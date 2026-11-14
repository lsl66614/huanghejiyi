// entry/src/main/ets/repository/LocalRdbImpl.ets
import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { SyncRecord } from '../model/SyncModels';
import { SYNC_TABLES, DISTRIBUTED_TABLES } from '../model/SyncModels';
import { FavoriteDO, FavoriteTagDO, NoteView, TagDO, ProgressDO, VisitDO, RecoFeedbackDO } from '../model/UserDataModels';
import type { NoteDO } from '../model/UserDataModels';
import { monotonicNow } from '../service/merge/LogicalClock';
import type { IDataRepository } from './IDataRepository';

const DOMAIN = 0x0001;
const TAG = 'HuangheRdb';

const DDL: string[] = [
  `CREATE TABLE IF NOT EXISTS favorite (
  target_key TEXT PRIMARY KEY,
  createTime INTEGER, updateTime INTEGER,
  deviceId TEXT, isDeleted INTEGER DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS note (
  note_id TEXT PRIMARY KEY,
  target_key TEXT, text TEXT, createTime INTEGER, updateTime INTEGER,
  deviceId TEXT, isDeleted INTEGER DEFAULT 0)`,
  // 三张关联表的 row_id 是单列主键，满足官方「不支持将含有复合键的表设置为分布式表」。
  // 取值 = 两个业务列用 ␟ 拼接，即合并引擎认的逻辑身份，故同步行天然收敛到同一行。
  // deviceId 必填：合并引擎的时间戳平局决胜按 deviceId 字典序，没有这一列
  // 时三张表恒判「远端胜」，冲突日志里的 tie_break_deviceId 名不副实。
  `CREATE TABLE IF NOT EXISTS note_tag (row_id TEXT PRIMARY KEY,
  note_id TEXT, tag_id TEXT, updateTime INTEGER, deviceId TEXT,
  isDeleted INTEGER DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS favorite_tag (row_id TEXT PRIMARY KEY,
  target_key TEXT, tag_id TEXT, updateTime INTEGER, deviceId TEXT,
  isDeleted INTEGER DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS visit (target_key TEXT PRIMARY KEY, createTime INTEGER)`,
  // 推荐负反馈：只在本机生效，故意不进 DISTRIBUTED_TABLES / SYNC_TABLES。
  // 一台设备上“不想看这个”是本地口味，同步到另一台会把对方的推荐也改掉。
  // feedback_key 用 'site:{id}' / 'era:{id}' / 'type:{id}' 三种前缀，
  // 一张表同时装“这条别看”和“这类少看”。
  `CREATE TABLE IF NOT EXISTS reco_feedback (
  feedback_key TEXT PRIMARY KEY, reason TEXT, createTime INTEGER)`,
  `CREATE TABLE IF NOT EXISTS tag (
  tag_id TEXT PRIMARY KEY, name TEXT, isPreset INTEGER,
  updateTime INTEGER, isDeleted INTEGER, deviceId TEXT)`,
  `CREATE TABLE IF NOT EXISTS progress (row_id TEXT PRIMARY KEY,
  target_key TEXT, section TEXT,
  done INTEGER, updateTime INTEGER, deviceId TEXT)`,
  `CREATE TABLE IF NOT EXISTS sync_meta (k TEXT PRIMARY KEY, v TEXT)`
];

// 业务列上的唯一性索引：row_id 唯一是它的推论，但建出来让查询能用上，
// 也让「同一笔记重复挂同一标签」在 DB 层直接被拒，而不是靠调用方自觉。
const DDL_INDEX: string[] = [
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_note_tag_pair ON note_tag(note_id, tag_id)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_favorite_tag_pair ON favorite_tag(target_key, tag_id)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_progress_pair ON progress(target_key, section)',
  // 笔记列表按 target_key 反查（listNotesOf）；没有这个索引时，
  // 每打开一次遗址详情页就对 note 全表扫一遍。
  'CREATE INDEX IF NOT EXISTS idx_note_target ON note(target_key, updateTime)'
];

// 表元数据：主键列名 + 同步域四列在各表中的列名映射
class TableMeta {
  pk: string = '';
  keyCols: string[] = [];        // 拼 key 的列（= 主键列；三张关联表已改为单列 row_id）
  updateTimeCol: string = 'updateTime';
  deviceCol: string = 'deviceId'; // 无 deviceId 列的表 → ''
  deleteCol: string = 'isDeleted';// 无墓碑列的表 → ''
}

const TABLE_META: Map<string, TableMeta> = new Map();

function meta(pk: string, deviceCol: string, deleteCol: string): TableMeta {
  const m = new TableMeta();
  m.pk = pk;
  m.keyCols = [pk];
  m.deviceCol = deviceCol;
  m.deleteCol = deleteCol;
  return m;
}

// row_id = 两个业务列用 ␟ 拼接（与 mergeElementSets 的逻辑身份一致）
const PAIR_SEP: string = '\u001f';

function pairRowId(a: string, b: string): string {
  return `${a}${PAIR_SEP}${b}`;
}

TABLE_META.set('favorite', meta('target_key', 'deviceId', 'isDeleted'));
TABLE_META.set('note', meta('note_id', 'deviceId', 'isDeleted'));
TABLE_META.set('tag', meta('tag_id', 'deviceId', 'isDeleted'));
TABLE_META.set('note_tag', meta('row_id', 'deviceId', 'isDeleted'));
TABLE_META.set('favorite_tag', meta('row_id', 'deviceId', 'isDeleted'));
TABLE_META.set('progress', meta('row_id', 'deviceId', ''));

// 主库：真机/单机模式的唯一档案。
const STORE_NAME: string = 'huanghe_memory.db';
// 仿真库后缀：单机双档案演示时，两个身份各用一个独立库，数据真正分离。
const SIM_STORE_SUFFIX: string = '.sim';

function storeConfigFor(name: string): relationalStore.StoreConfig {
  return { name: name, securityLevel: relationalStore.SecurityLevel.S1 };
}

// I-2：合法列名白名单（正则取标识符形状、大小写不敏感——本表 DDL 含 createTime/isPreset 等驼前列，
// 纯小写正则会误伤合法载荷列；仍严格排除引号/空格/分号等一切注入字符）
const SAFE_COLUMN: RegExp = /^[a-z_][a-z0-9_]*$/i;

// 迁移用：从 pragma_table_info 读实际列名与列类型，不把 DDL 里写的当事实。
// ⚠️ 表名必须内联进 SQL，不能用占位符：实测 `pragma_table_info(?)` 传绑定参数
// 返回**零行且不报错**，迁移会被静默跳过（2026-10-11 真机验证）。
// 表名只来自本文件的 DDL 常量，不含外部输入，内联无注入面。
async function tableColumns(st: relationalStore.RdbStore, table: string): Promise<ColumnSpec[]> {
  const rs = await st.querySql(`SELECT name, type FROM pragma_table_info('${table}')`);
  const out: ColumnSpec[] = [];
  while (rs.goToNextRow()) {
    const c = new ColumnSpec();
    c.name = rs.getString(0);
    c.type = rs.getString(1);
    out.push(c);
  }
  rs.close();
  return out;
}

// 重建表时要把类型一起带上：新表若全用无类型列，SQLite 给的是 NONE 亲和性，
// 与原 DDL 声明的 TEXT/INTEGER 不一致。
function columnDefs(cols: ColumnSpec[]): string {
  return cols.map((c: ColumnSpec): string => `${c.name} ${c.type}`).join(', ');
}

function columnList(cols: ColumnSpec[]): string {
  return cols.map((c: ColumnSpec): string => c.name).join(', ');
}

class ColumnSpec {
  name: string = '';
  type: string = '';
}

class JoinTableSpec {
  name: string = '';
  pk: string[] = [];
}

// 标签关联行：软删差集要同时拿到 row_id（定位）与 tag_id（判断是否保留）
class TagPairRow {
  rowId: string = '';
  tagId: string = '';
}

export class LocalRdbImpl implements IDataRepository {
  private store: relationalStore.RdbStore | null = null;
  private distributedReady: boolean = false;
  // 对端推来变更时的通知钩子。由上层（AutoSync）在启动时注入，
  // 这里不 import service 层——repository 反向依赖 service 会成环。
  // 不注入时退化为只打日志，仿真/单机模式下本来就没有远端变更。
  private remoteChangeHook: (() => void) | null = null;
  // 实际可注册的分布式表：init 时按迁移结果算出，未 init 前退回常量
  private distributedTables: string[] = DISTRIBUTED_TABLES;
  // 单调逻辑时钟的高水位（持久化在 sync_meta.lastWrite）。
  // 每份档案各一份：真机主库一份、仿真 deviceA/B 各一份，互不干扰。
  // lastWriteLoaded 用「是否已从库里读过」而不是「值是否非 0」——
  // 首次写入的合法高水位本来就是 0，用值判断会每次都重读。
  private lastWrite: number = 0;
  private lastWriteLoaded: boolean = false;
  // nextWriteTime 的串行队列：见该方法上的注释。
  private writeChain: Promise<number> | null = null;

  private distributedTableList(): string[] {
    return this.distributedTables;
  }

  // 仿真库名：单机双档案时两个身份各用一个库（huanghe_memory.db.sim.deviceA）。
  // 库名只来自本文件的固定后缀与调用方给定的身份串，不含外部输入。
  static simStoreName(deviceId: string): string {
    return STORE_NAME + SIM_STORE_SUFFIX + '.' + deviceId;
  }

  // 主库名（真机档案）。设备面板要显示「这一台现在读写的是哪个库」，
  // 名字只在最近的地方给出去，不要在页面上再抄一份字符串。
  static mainStoreName(): string {
    return STORE_NAME;
  }

  // 以指定库名初始化。仿真适配器据此为两个身份各建一份独立档案。
  async initAs(context: ESObject, name: string): Promise<void> {
    const st = await relationalStore.getRdbStore(context as common.UIAbilityContext, storeConfigFor(name));
    this.store = st;
    // 旧库先迁：老版本三张关联表是复合主键，新 DDL 的 CREATE TABLE IF NOT EXISTS
    // 对已存在的表不会改结构，必须显式重建，否则 row_id 列永远不存在。
    const blocked = await this.migrateJoinTables(st);
    for (const sql of DDL) {
      await st.executeSql(sql);
    }
    for (const sql of DDL_INDEX) {
      await st.executeSql(sql);
    }
    // 迁移失败的表仍是复合主键，不能进分布式通道——按实际 schema 状态收窄，
    // 而不是照抄常量列表，否则迁移一失败就退回违规配置。
    const tables: string[] = [];
    for (const name of DISTRIBUTED_TABLES) {
      if (!blocked.has(name)) { tables.push(name); }
    }
    this.distributedTables = tables;
    hilog.info(DOMAIN, TAG, `db ready (${name}), distributed tables: ${tables.join(',')}`);
  }

  // 主库初始化：真机与单机模式共用同一份档案
  async init(context: ESObject): Promise<void> {
    await this.initAs(context, STORE_NAME);
  }

  // 复合主键 → 单列 row_id 的就地迁移。
  // SQLite 无法直接改主键，只能「建新表 → 搬数据 → 删旧表 → 改名」。
  // 幂等：row_id 已存在说明迁过了，直接跳过。
  // 返回未能迁移的表名集合（迁移失败时旧表原样保留，功能不受影响）。
  private async migrateJoinTables(st: relationalStore.RdbStore): Promise<Set<string>> {
    const blocked: Set<string> = new Set();
    const specs: JoinTableSpec[] = [
      { name: 'note_tag', pk: ['note_id', 'tag_id'] },
      { name: 'favorite_tag', pk: ['target_key', 'tag_id'] },
      { name: 'progress', pk: ['target_key', 'section'] }
    ];
    for (const spec of specs) {
      const cols = await tableColumns(st, spec.name);
      if (cols.length === 0) { continue; }          // 表还不存在，交给 DDL 建
      let migrated: boolean = false;
      for (const c of cols) { if (c.name === 'row_id') { migrated = true; break; } }
      if (migrated) { continue; }                    // 已迁过
      const defsSql = columnDefs(cols);
      const namesSql = columnList(cols);
      const expr = `${spec.pk[0]} || char(31) || ${spec.pk[1]}`;
      st.beginTransaction();
      try {
        // 先清残留：上一轮若在别处失败，__new 会留在库里，而下面的 CREATE 没有
        // IF NOT EXISTS，会直接撞「table already exists」把整轮迁移判死。
        // 结果是首轮失败后每次启动都失败，旧表永远迁不掉（2026-10-11 真机踩到）。
        await st.executeSql(`DROP TABLE IF EXISTS ${spec.name}__new`);
        await st.executeSql(
          `CREATE TABLE ${spec.name}__new (row_id TEXT PRIMARY KEY, ${defsSql})`);
        await st.executeSql(
          `INSERT INTO ${spec.name}__new (row_id, ${namesSql}) ` +
          `SELECT ${expr}, ${namesSql} FROM ${spec.name}`);
        await st.executeSql(`DROP TABLE ${spec.name}`);
        await st.executeSql(`ALTER TABLE ${spec.name}__new RENAME TO ${spec.name}`);
        st.commit();
        hilog.info(DOMAIN, TAG, `migrated ${spec.name} to single-column pk`);
      } catch (e) {
        st.rollBack();
        // 迁移失败不阻断启动：旧表还在，功能照常，只是该表不能设分布式表
        blocked.add(spec.name);
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, `migrate ${spec.name} skipped: ${msg}`);
      }
    }
    // 补 deviceId 列：合并引擎的平局决胜按 deviceId 字典序，缺列时三张关联表
    // 恒判「远端胜」，冲突日志的 tie_break_deviceId 名不副实。
    // ALTER TABLE ADD COLUMN 是 SQLite 原生支持的原位操作，不需要重建表。
    // 默认值给 ''：旧行补列后直接是空串，getString 读出来可比较。
    for (const t of ['note_tag', 'favorite_tag', 'tag']) {
      await this.addColumnIfMissing(st, t, 'deviceId', 'TEXT');
    }
    // 关联表墓碑列：老库没有 isDeleted 时，取消标签只能物理删行，
    // 而同步并集会把对端那一行原样带回来（删除无法表达）。
    for (const t of ['note_tag', 'favorite_tag']) {
      await this.addColumnIfMissing(st, t, 'isDeleted', 'INTEGER', '0');
    }
    return blocked;
  }

  private async addColumnIfMissing(st: relationalStore.RdbStore, table: string,
    column: string, type: string, defaultSql: string = "''"): Promise<void> {
    const cols = await tableColumns(st, table);
    if (cols.length === 0) { return; }        // 表还不存在，交给 DDL 建
    for (const c of cols) {
      if (c.name === column) { return; }      // 已有该列
    }
    try {
      await st.executeSql(`ALTER TABLE ${table} ADD COLUMN ${column} ${type} DEFAULT ${defaultSql}`);
      hilog.info(DOMAIN, TAG, `added ${table}.${column}`);
    } catch (e) {
      // 补列失败不阻断启动：该表仍可用，只是同步平局裁决退化为远端胜
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, `add ${table}.${column} skipped: ${msg}`);
    }
  }

  // 注册分布式同步域（模拟器不支持分布式数据对象，此调用必失败，属预期，须由调用方回落）
  // 注册「对端有变更」通知。AutoSync 在 prepare 时注入一次；
  // 注入的回调自己负责节流（AutoSyncGate 的冷却窗 + in-flight），
  // 这里只管把事件转出去——dataChange 在抖动时会连着来很多次。
  setRemoteChangeHook(hook: () => void): void {
    this.remoteChangeHook = hook;
  }

  async enableDistributed(): Promise<void> {
    if (this.distributedReady) { return; }
    const st = this.s();
    try {
      await st.setDistributedTables(this.distributedTableList());
      // 订阅对端推来的变更。赛题原文要求"任一设备新增/编辑后，其他设备
      // 实时获取更新"，所以这里必须真的驱动一次合并，不能只记日志：
      // 回调 → AutoSync.checkNow('remote-change') → runSync 拉取合并。
      st.on('dataChange', relationalStore.SubscribeType.SUBSCRIBE_TYPE_REMOTE, (devices: Array<string>) => {
        hilog.info(DOMAIN, TAG, `remote dataChange from ${devices.length} device(s)`);
        const hook = this.remoteChangeHook;
        if (hook !== null) { hook(); }
      });
      this.distributedReady = true;
      hilog.info(DOMAIN, TAG, 'distributed tables registered');
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, `setDistributedTables failed (expected on emulator): ${msg}`);
      throw new Error(`distributed unavailable: ${msg}`);
    }
  }

  async pushToDevices(networkIds: string[]): Promise<void> {
    const st = this.s();
    // 只推实际已注册为分布式表的那些：迁移失败的表未注册，推了也无处落地
    for (const name of this.distributedTableList()) {
      const predicates = new relationalStore.RdbPredicates(name);
      predicates.inDevices(networkIds);
      // SYNC_MODE_PUSH：本机终态推到对端分布式库
      await st.sync(relationalStore.SyncMode.SYNC_MODE_PUSH, predicates);
    }
  }

  // 把结果集的行读成合并引擎认的记录。
  //
  // remoteSnapshot 与 snapshotSyncTables 原先各抄了一份完全相同的读行逻辑，
  // 只差数据来源。两份实现最危险的地方不是重复，而是"改一边忘另一边"——
  // 例如只给远端快照补 deviceId、漏了本机快照，冲突日志就会一边有设备号
  // 一边没有，且不会有人发现。列名由调用方先查一次空结果集拿到：
  // 远端查询必须提前把列清单交给 remoteQuery，本机查询跟着同一口径走。
  private readRecords(rs: relationalStore.ResultSet, m: TableMeta,
    columns: string[]): SyncRecord[] {
    const rows: SyncRecord[] = [];
    while (rs.goToNextRow()) {
      const payload: Record<string, string | number | boolean> = {};
      for (const col of columns) {
        if (col === m.updateTimeCol) { continue; }
        payload[col] = rs.getString(rs.getColumnIndex(col));
      }
      const keyParts: string[] = [];
      for (const kc of m.keyCols) {
        keyParts.push(rs.getString(rs.getColumnIndex(kc)));
      }
      const rec: SyncRecord = {
        key: keyParts.join('\u001f'),
        updateTime: rs.getLong(rs.getColumnIndex(m.updateTimeCol)),
        // 补列前的旧行 deviceId 可能是 NULL：读成空串，交给合并引擎按
        // 字典序正常决胜，而不是把 null 传进比较
        deviceId: m.deviceCol === '' ? '' : (rs.getString(rs.getColumnIndex(m.deviceCol)) ?? ''),
        isDeleted: m.deleteCol === '' ? false : rs.getLong(rs.getColumnIndex(m.deleteCol)) === 1,
        payload: payload
      };
      rows.push(rec);
    }
    return rows;
  }

  async remoteSnapshot(networkId: string): Promise<Map<string, SyncRecord[]>> {
    const st = this.s();
    const out: Map<string, SyncRecord[]> = new Map();
    // 只查已注册为分布式表的那些。未注册的表 remoteQuery 拿不到对端数据，
    // 合并时按「仅本机有」处理（保留本机版本，不丢数据）。
    for (const name of this.distributedTableList()) {
      const m = TABLE_META.get(name);
      if (m === undefined) { continue; }
      // 列清单取本地同表结构（远端由同应用安装，schema 一致）
      const probe = await st.querySql(`SELECT * FROM ${name} LIMIT 0`);
      const columns: string[] = probe.columnNames;
      probe.close();
      const predicates = new relationalStore.RdbPredicates(name);
      const rs = await st.remoteQuery(networkId, name, predicates, columns);
      const rows: SyncRecord[] = this.readRecords(rs, m, columns);
      rs.close();
      out.set(name, rows);
    }
    return out;
  }

  private s(): relationalStore.RdbStore {
    const st = this.store;
    if (st === null) {
      throw new Error('rdb not init');
    }
    return st;
  }

  async snapshotSyncTables(): Promise<Map<string, SyncRecord[]>> {
    const st = this.s();
    const out: Map<string, SyncRecord[]> = new Map();
    for (const name of SYNC_TABLES) {
      const m = TABLE_META.get(name);
      if (m === undefined) { continue; } // arkts-no-non-null-assertion：显式 undefined 守卫
      // 与 remoteSnapshot 同一口径取列名（见 readRecords 的注释）
      const probe = await st.querySql(`SELECT * FROM ${name} LIMIT 0`);
      const columns: string[] = probe.columnNames;
      probe.close();
      const rs = await st.querySql(`SELECT * FROM ${name}`);
      const rows: SyncRecord[] = this.readRecords(rs, m, columns);
      rs.close();
      out.set(name, rows);
    }
    return out;
  }

  async applyMerged(table: string, records: SyncRecord[]): Promise<void> {
    const m = TABLE_META.get(table);
    if (m === undefined) { return; }
    const store = this.s();
    // 先把高水位读起来：下面要吸收远端时间戳，没读过就会把「本机已有更大值」
    // 当成 0，合并完反而让本地时钟倒退。
    await this.loadLastWrite();
    // 只 upsert 合并终态，不删「合并结果里没有」的本地行。
    //
    // 合并是 local ∪ remote：快照时已经存在的每个 key 必然出现在终态里；
    // 终态里没有的 key，只可能是快照拍完之后、落库之前新写入的行。
    // 原先的删除循环恰好会把这些“同步期间的新写入”静默删掉——
    // 谓词复用只是把问题从“删第一条”放大成“删多条”。删除语义已经由
    // favorite/note/tag/note_tag/favorite_tag 的 isDeleted 墓碑和
    // progress 的 done=0 表达，不需要物理删行。
    store.beginTransaction();
    try {
      for (const r of records) {
        this.observeSyncedTime(r.updateTime);
        const cols = Object.keys(r.payload);
        const keyVals: string[] = r.key.split('\u001f');
        const allCols: string[] = [];
        const bucket: relationalStore.ValuesBucket = {};
        for (let i = 0; i < m.keyCols.length; i++) {
          allCols.push(m.keyCols[i]);
          bucket[m.keyCols[i]] = keyVals[i];
        }
        for (const c of cols) {
          if (!SAFE_COLUMN.test(c)) { continue; } // I-2：远端 payload 键须过列名白名单，杜绝列名注入
          if (m.keyCols.includes(c) || c === m.updateTimeCol || c === m.deviceCol || c === m.deleteCol) {
            continue;
          }
          allCols.push(c);
          bucket[c] = r.payload[c];
        }
        allCols.push(m.updateTimeCol);
        bucket[m.updateTimeCol] = r.updateTime;
        if (m.deviceCol !== '') {
          allCols.push(m.deviceCol);
          bucket[m.deviceCol] = r.deviceId;
        }
        if (m.deleteCol !== '') {
          allCols.push(m.deleteCol);
          bucket[m.deleteCol] = r.isDeleted ? 1 : 0;
        }
        const placeholders = allCols.map((_c: string): string => '?').join(',');
        const values: relationalStore.ValueType[] = allCols.map((c: string): relationalStore.ValueType => bucket[c]);
        await store.executeSql(`INSERT OR REPLACE INTO ${table} (${allCols.join(',')}) VALUES (${placeholders})`, values);
      }
      store.commit();
    } catch (e) {
      store.rollBack();
      // arkts-limited-throw：catch 量为任意类型，须包成 Error 再抛
      const msg: string = e instanceof Error ? e.message : 'unknown rdb error';
      throw new Error(`applyMerged(${table}) rolled back: ${msg}`);
    }
  }

  // ---- 单调逻辑时钟 -------------------------------------------------------
  // 设计依据见 service/merge/LogicalClock.ets。这里只负责持久化：
  // 高水位存 sync_meta.lastWrite，跟着档案走（仿真两份档案各自独立）。
  //
  // 为什么放在存储层而不是 UserDataRepo：读高水位 → 算新值 → 回写是一个
  // 需要原子感的序列。放在门面层时，两次并发写（页面初始化与用户点击）会在
  // await 之间交错，各自读到同一个 last，仍然产出并列时间戳。
  private async loadLastWrite(): Promise<void> {
    if (this.lastWriteLoaded) { return; }
    const raw = await this.getMeta('lastWrite');
    // 并发兜底：两个调用同时进到这里时，先返回的那个已经把高水位装好了，
    // 后返回的若照旧写入，就会把它刚推进的值覆盖回旧值，两条并发写拿到
    // 同一个时间戳——正是这个类要消灭的情形。
    if (this.lastWriteLoaded) { return; }
    if (raw === '') {
      this.lastWrite = 0;
    } else {
      const n = Number(raw);
      this.lastWrite = Number.isFinite(n) && n > 0 ? n : 0;
    }
    this.lastWriteLoaded = true;
  }

  // 外来到的版本号也要抬高本地高水位：本机时钟若慢于对端，合并进来的记录
  // updateTime 会明显大于本机 lastWrite，此时再写 6/7 会立刻输给那条记录。
  // 把见过的最大值吸收进来，本地后续写入才能继续递增。
  private observeSyncedTime(updateTime: number): void {
    if (updateTime > this.lastWrite) { this.lastWrite = updateTime; }
  }

  // 读高水位 → 算新值 → 回写，三步之间都有 await。两个并发写若交错，
  // 后一个会读到前一个尚未回写的旧高水位，各自算出同一个时间戳——
  // 这正是本类要消灭的并列。这里把调用排成一队：前一个彻底落库后，
  // 后一个才开始读数。
  async nextWriteTime(): Promise<number> {
    const run = async (): Promise<number> => {
      await this.loadLastWrite();
      const t = monotonicNow(this.lastWrite, Date.now());
      this.lastWrite = t;
      await this.setMeta('lastWrite', String(t));
      return t;
    };
    const prev: Promise<number> | null = this.writeChain;
    const next: Promise<number> = prev === null ? run() : prev.then(run);
    // 队列本身不能因为某一次失败就断掉：吞掉结果，只保留时序
    this.writeChain = next.catch((_e: Object): number => this.lastWrite);
    return next;
  }

  // IDataRepository.observeExternalTime：档案导入的版本号来自导出档案，
  // 可能大于本机高水位（导出设备的时钟更快，或导入的是很久之后翻出来的旧档）。
  // 不吸收的话，导入完本机下一笔写入的版本号会小于导入内容，LWW 立刻输。
  // 语义与 observeSyncedTime 相同，只是作为公开入口供门面层调用。
  async observeExternalTime(updateTime: number): Promise<void> {
    await this.loadLastWrite();
    if (updateTime > this.lastWrite) {
      this.lastWrite = updateTime;
      await this.setMeta('lastWrite', String(updateTime));
    }
  }

  async getMeta(key: string): Promise<string> {
    const rs = await this.s().querySql('SELECT v FROM sync_meta WHERE k = ?', [key]);
    let v = '';
    if (rs.goToNextRow()) {
      v = rs.getString(0);
    }
    rs.close();
    return v;
  }

  async setMeta(key: string, value: string): Promise<void> {
    await this.s().executeSql('INSERT OR REPLACE INTO sync_meta (k, v) VALUES (?, ?)', [key, value]);
  }

  async upsertFavorite(fav: FavoriteDO): Promise<void> {
    // INSERT OR REPLACE 语义：重复保存（UI 计划 P5/P6）不再触发 PK 冲突异常
    await this.s().executeSql(
      'INSERT OR REPLACE INTO favorite (target_key, createTime, updateTime, deviceId, isDeleted) VALUES (?, ?, ?, ?, ?)',
      [fav.targetKey, fav.createTime, fav.updateTime, fav.deviceId, fav.isDeleted ? 1 : 0]);
  }

  async deleteFavorite(targetKey: string, deviceId: string, now: number): Promise<void> {
    // 墓碑更新（§4.2）：不物理删除
    const bucket: relationalStore.ValuesBucket = { updateTime: now, deviceId: deviceId, isDeleted: 1 };
    const p = new relationalStore.RdbPredicates('favorite');
    p.equalTo('target_key', targetKey);
    await this.s().update(bucket, p);
  }

  async listFavorites(): Promise<FavoriteDO[]> {
    const rs = await this.s().querySql(
      'SELECT target_key, createTime, updateTime, deviceId, isDeleted FROM favorite WHERE isDeleted = 0 ORDER BY updateTime DESC');
    const out: FavoriteDO[] = [];
    while (rs.goToNextRow()) {
      const f = new FavoriteDO();
      f.targetKey = rs.getString(0);
      f.createTime = rs.getLong(1);
      f.updateTime = rs.getLong(2);
      f.deviceId = rs.getString(3);
      f.isDeleted = rs.getLong(4) === 1;
      out.push(f);
    }
    rs.close();
    return out;
  }

  // 回收站只查墓碑行，且以 updateTime 作为“删除时间”。
  // 30 天窗口由调用方算好传进来；这里不再写死时间常量。
  async listDeletedFavorites(since: number): Promise<FavoriteDO[]> {
    const rs = await this.s().querySql(
      'SELECT target_key, createTime, updateTime, deviceId, isDeleted FROM favorite ' +
      'WHERE isDeleted = 1 AND updateTime >= ? ORDER BY updateTime DESC', [since]);
    const out: FavoriteDO[] = [];
    while (rs.goToNextRow()) {
      const f = new FavoriteDO();
      f.targetKey = rs.getString(0);
      f.createTime = rs.getLong(1);
      f.updateTime = rs.getLong(2);
      f.deviceId = rs.getString(3);
      f.isDeleted = rs.getLong(4) === 1;
      out.push(f);
    }
    rs.close();
    return out;
  }

  // 恢复不是“重新收藏”：保留 createTime，只把墓碑翻回 0 并刷新版本，
  // 这样同步对端按 LWW 采信这次恢复，而不是把它当成一条新收藏。
  async restoreFavorite(targetKey: string, deviceId: string, now: number): Promise<void> {
    const bucket: relationalStore.ValuesBucket = { updateTime: now, deviceId: deviceId, isDeleted: 0 };
    const p = new relationalStore.RdbPredicates('favorite');
    p.equalTo('target_key', targetKey);
    await this.s().update(bucket, p);
  }

  // 读出某主体当前仍然存活的标签关联行，供软删差集使用。
  // 已墓碑的行不再重复更新——否则每次保存都会刷新旧墓碑的 updateTime，
  // 在同步里制造无意义的“新删除”。表名/列名只来自本文件常量。
  private async tagPairs(table: string, keyCol: string, keyVal: string): Promise<TagPairRow[]> {
    const rs = await this.s().querySql(
      `SELECT row_id, tag_id FROM ${table} WHERE ${keyCol} = ? AND isDeleted = 0`, [keyVal]);
    const out: TagPairRow[] = [];
    while (rs.goToNextRow()) {
      const r = new TagPairRow();
      r.rowId = rs.getString(0);
      r.tagId = rs.getString(1);
      out.push(r);
    }
    rs.close();
    return out;
  }

  async setFavoriteTags(targetKey: string, tagIds: string[], now: number, deviceId: string): Promise<void> {
    const keep: Set<string> = new Set();
    for (const t of tagIds) { keep.add(t); }
    const current = await this.tagPairs('favorite_tag', 'target_key', targetKey);
    for (const row of current) {
      if (keep.has(row.tagId)) { continue; }
      // 关联表只有 row_id 可定位；打墓碑而不是物理删，否则下次同步
      // 对端仍持有这一行，并集会把它复活。
      await this.s().executeSql(
        'UPDATE favorite_tag SET isDeleted = 1, updateTime = ?, deviceId = ? WHERE row_id = ?',
        [now, deviceId, row.rowId]);
    }
    for (const t of tagIds) {
      // 同一 target 的同一标签只可能一行；REPLACE 让重复调用幂等，
      // 同时把曾经墓碑的行重新置为 0。
      await this.s().executeSql(
        'INSERT OR REPLACE INTO favorite_tag (row_id, target_key, tag_id, updateTime, deviceId, isDeleted) VALUES (?, ?, ?, ?, ?, 0)',
        [pairRowId(targetKey, t), targetKey, t, now, deviceId]);
      // 字典自动补全（与 setNoteTags 同约定）
      await this.s().executeSql(
        'INSERT OR IGNORE INTO tag (tag_id, name, isPreset, updateTime, isDeleted, deviceId) VALUES (?, ?, 0, ?, 0, ?)',
        [t, t, now, deviceId]);
    }
  }

  async listFavoriteTags(targetKey: string): Promise<string[]> {
    const rs = await this.s().querySql(
      'SELECT tag_id FROM favorite_tag WHERE target_key = ? AND isDeleted = 0 ORDER BY updateTime ASC', [targetKey]);
    const out: string[] = [];
    while (rs.goToNextRow()) { out.push(rs.getString(0)); }
    rs.close();
    return out;
  }

  async listFavoriteTagRows(): Promise<FavoriteTagDO[]> {
    const rs = await this.s().querySql(
      'SELECT target_key, tag_id, updateTime FROM favorite_tag WHERE isDeleted = 0');
    const out: FavoriteTagDO[] = [];
    while (rs.goToNextRow()) {
      const r = new FavoriteTagDO();
      r.targetKey = rs.getString(0);
      r.tagId = rs.getString(1);
      r.updateTime = rs.getLong(2);
      out.push(r);
    }
    rs.close();
    return out;
  }

  async listProgress(): Promise<ProgressDO[]> {
    const rs = await this.s().querySql(
      'SELECT target_key, section, done, updateTime, deviceId FROM progress');
    const out: ProgressDO[] = [];
    while (rs.goToNextRow()) {
      const p = new ProgressDO();
      p.targetKey = rs.getString(0);
      p.section = rs.getString(1);
      p.done = rs.getLong(2) === 1;
      p.updateTime = rs.getLong(3);
      p.deviceId = rs.getString(4);
      out.push(p);
    }
    rs.close();
    return out;
  }

  async upsertVisit(targetKey: string, now: number): Promise<void> {
    await this.s().executeSql(
      'INSERT OR REPLACE INTO visit (target_key, createTime) VALUES (?, ?)', [targetKey, now]);
  }

  async listRecentVisits(limit: number): Promise<VisitDO[]> {
    // limit 为调用方给定的整数，不拼接用户输入
    const n: number = limit > 0 ? Math.floor(limit) : 50;
    const rs = await this.s().querySql(
      `SELECT target_key, createTime FROM visit ORDER BY createTime DESC LIMIT ${n}`);
    const out: VisitDO[] = [];
    while (rs.goToNextRow()) {
      const v = new VisitDO();
      v.targetKey = rs.getString(0);
      v.createTime = rs.getLong(1);
      out.push(v);
    }
    rs.close();
    return out;
  }

  // REPLACE 语义：同一对象再点一次“不感兴趣”只刷新原因与时间，
  // 不会因为主键冲突把整次点击判失败。
  async upsertRecoFeedback(fb: RecoFeedbackDO): Promise<void> {
    await this.s().executeSql(
      'INSERT OR REPLACE INTO reco_feedback (feedback_key, reason, createTime) VALUES (?, ?, ?)',
      [fb.key, fb.reason, fb.createTime]);
  }

  async listRecoFeedback(): Promise<RecoFeedbackDO[]> {
    const rs = await this.s().querySql(
      'SELECT feedback_key, reason, createTime FROM reco_feedback ORDER BY createTime DESC');
    const out: RecoFeedbackDO[] = [];
    while (rs.goToNextRow()) {
      const f = new RecoFeedbackDO();
      f.key = rs.getString(0);
      f.reason = rs.getString(1);
      f.createTime = rs.getLong(2);
      out.push(f);
    }
    rs.close();
    return out;
  }

  async upsertNote(note: NoteDO): Promise<void> {
    await this.s().executeSql(
      'INSERT OR REPLACE INTO note (note_id, target_key, text, createTime, updateTime, deviceId, isDeleted) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [note.noteId, note.targetKey, note.text, note.createTime, note.updateTime, note.deviceId, note.isDeleted ? 1 : 0]);
  }

  async listNotesOf(targetKey: string): Promise<NoteView[]> {
    const rs = await this.s().querySql(
      'SELECT note_id, target_key, text, createTime, updateTime FROM note ' +
      'WHERE target_key = ? AND isDeleted = 0 ORDER BY updateTime DESC', [targetKey]);
    return await this.readNotes(rs);
  }

  async listAllNotes(): Promise<NoteView[]> {
    const rs = await this.s().querySql(
      'SELECT note_id, target_key, text, createTime, updateTime FROM note ' +
      'WHERE isDeleted = 0 ORDER BY updateTime DESC');
    return await this.readNotes(rs);
  }

  async listDeletedNotes(since: number): Promise<NoteView[]> {
    const rs = await this.s().querySql(
      'SELECT note_id, target_key, text, createTime, updateTime FROM note ' +
      'WHERE isDeleted = 1 AND updateTime >= ? ORDER BY updateTime DESC', [since]);
    return await this.readNotes(rs);
  }

  private async readNotes(rs: relationalStore.ResultSet): Promise<NoteView[]> {
    const out: NoteView[] = [];
    while (rs.goToNextRow()) {
      const n = new NoteView();
      n.noteId = rs.getString(0);
      n.targetKey = rs.getString(1);
      n.text = rs.getString(2);
      n.createTime = rs.getLong(3);
      n.updateTime = rs.getLong(4);
      out.push(n);
    }
    rs.close();
    if (out.length === 0) { return out; }
    // 一条 SQL 取回全部关联标签，按 note_id 在内存里归组：
    // 逐笔记各查一次 note_tag 是 N+1，笔记一多详情页就要发 N 次查询。
    // 用 Map 而不是依赖 out 有序——调用方要的是 updateTime 倒序，
    // 与 note_id 的字典序没有关系。
    const byId: Map<string, NoteView> = new Map();
    for (const n of out) { byId.set(n.noteId, n); }
    const trs = await this.s().querySql('SELECT note_id, tag_id FROM note_tag WHERE isDeleted = 0');
    while (trs.goToNextRow()) {
      const n = byId.get(trs.getString(0));
      if (n !== undefined) { n.tagIds.push(trs.getString(1)); }
    }
    trs.close();
    return out;
  }

  async deleteNote(noteId: string, deviceId: string, now: number): Promise<void> {
    // 墓碑更新：笔记删除同样不物理删行，保留同步版本语义
    const bucket: relationalStore.ValuesBucket = { updateTime: now, deviceId: deviceId, isDeleted: 1 };
    const p = new relationalStore.RdbPredicates('note');
    p.equalTo('note_id', noteId);
    await this.s().update(bucket, p);
  }

  // 恢复笔记：正文、createTime、note_id 都不变，只翻墓碑并刷新版本。
  // note_tag 若在删除时未被打墓碑，会随之重新可见；若已墓碑，则恢复后
  // 只是“无标签”，不会丢正文。
  async restoreNote(noteId: string, deviceId: string, now: number): Promise<void> {
    const bucket: relationalStore.ValuesBucket = { updateTime: now, deviceId: deviceId, isDeleted: 0 };
    const p = new relationalStore.RdbPredicates('note');
    p.equalTo('note_id', noteId);
    await this.s().update(bucket, p);
  }

  async listTags(): Promise<TagDO[]> {
    const rs = await this.s().querySql(
      'SELECT tag_id, name, isPreset FROM tag WHERE isDeleted = 0 ORDER BY isPreset DESC, updateTime ASC');
    const out: TagDO[] = [];
    while (rs.goToNextRow()) {
      const t = new TagDO();
      t.tagId = rs.getString(0);
      t.name = rs.getString(1);
      t.isPreset = rs.getLong(2) === 1;
      t.isDeleted = false;
      out.push(t);
    }
    rs.close();
    return out;
  }

  async setNoteTags(noteId: string, tagIds: string[], now: number, deviceId: string): Promise<void> {
    const keep: Set<string> = new Set();
    for (const t of tagIds) { keep.add(t); }
    const current = await this.tagPairs('note_tag', 'note_id', noteId);
    for (const row of current) {
      if (keep.has(row.tagId)) { continue; }
      await this.s().executeSql(
        'UPDATE note_tag SET isDeleted = 1, updateTime = ?, deviceId = ? WHERE row_id = ?',
        [now, deviceId, row.rowId]);
    }
    for (const t of tagIds) {
      // 同一笔记的同一标签只可能一行；REPLACE 让重复调用幂等，
      // 同时把曾经墓碑的行重新置为 0。
      await this.s().executeSql(
        'INSERT OR REPLACE INTO note_tag (row_id, note_id, tag_id, updateTime, deviceId, isDeleted) VALUES (?, ?, ?, ?, ?, 0)',
        [pairRowId(noteId, t), noteId, t, now, deviceId]);
    }
    for (const t of tagIds) {
      // 字典自动补全：INSERT OR IGNORE 语义（PK 冲突时静默跳过）
      await this.s().executeSql(
        'INSERT OR IGNORE INTO tag (tag_id, name, isPreset, updateTime, isDeleted, deviceId) VALUES (?, ?, 0, ?, 0, ?)',
        [t, t, now, deviceId]);
    }
  }

  async upsertTag(tag: TagDO): Promise<void> {
    await this.s().executeSql(
      'INSERT OR REPLACE INTO tag (tag_id, name, isPreset, updateTime, isDeleted, deviceId) VALUES (?, ?, ?, ?, ?, ?)',
      [tag.tagId, tag.name, tag.isPreset ? 1 : 0, tag.updateTime, tag.isDeleted ? 1 : 0, tag.deviceId]);
  }

  async upsertProgress(p: ProgressDO): Promise<void> {
    await this.s().executeSql(
      'INSERT OR REPLACE INTO progress (row_id, target_key, section, done, updateTime, deviceId) VALUES (?, ?, ?, ?, ?, ?)',
      [pairRowId(p.targetKey, p.section), p.targetKey, p.section, p.done ? 1 : 0, p.updateTime, p.deviceId]);
  }
}
