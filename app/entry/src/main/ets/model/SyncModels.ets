// entry/src/main/ets/model/SyncModels.ets —— 纯类型，禁止 @kit 导入
export interface SyncRecord {
  key: string;
  updateTime: number;
  deviceId: string;
  isDeleted: boolean;
  payload: Record<string, string | number | boolean>;
}

export interface ConflictVersion {
  updateTime: number;
  deviceId: string;
  isDeleted: boolean;
  payload: Record<string, string | number | boolean>;
}

export interface ConflictEntry {
  key: string;
  // 冲突发生在哪张表。合并引擎逐表跑，不带表名的话六张表的冲突
  // 混在一起，用户看到「同一个 key 冲突了」却不知道是笔记还是标签。
  table: string;
  winner: ConflictVersion;
  loser: ConflictVersion;
  reason: string; // 'updateTime' | 'tie_break_deviceId'
}

export interface MergeResult {
  finalRecords: SyncRecord[];
  conflicts: ConflictEntry[];
}

// 同步域：本地合并引擎与官方分布式通道共同覆盖的表。
// 判定键是「每行的逻辑身份」。六张表的主键都已是单列
// （三张关联表用 row_id = 两个业务列以 ␟ 拼接，见 LocalRdbImpl 的 DDL），
// 因此既能被合并引擎逐表 LWW 合流，也满足官方对分布式表的单列主键要求。
//
// 删除语义：favorite / note / tag 与 note_tag / favorite_tag 都用 isDeleted
// 墓碑；progress 用 done=0 表达“取消已读”，不删行，故不需要墓碑。
export const SYNC_TABLES: string[] = ['favorite', 'favorite_tag', 'note', 'note_tag', 'tag', 'progress'];

// 可注册为**官方分布式表**的表集。
//
// 官方硬约束（openharmony/docs zh-cn/application-dev/database/
// data-sync-of-rdb-store.md「约束限制」）：**不支持将含有复合键的表设置为
// 分布式表**。SDK 的 setDistributedTables 声明里没有这句，只读 .d.ts 发现不了。
//
// 本项目原先踩过这个坑：note_tag / favorite_tag / progress 三张表都是复合主键，
// 曾被剔出本列表。现已改为单列 row_id 主键（见 LocalRdbImpl 的 DDL 与 migrateJoinTables），
// 六表重新全部可注册。
//
// 注意：schema 文件只有**单版本表模式**需要，多设备协同表模式
// 「不支持设置schema，默认不读取schema文件」——所以这里用的是默认模式，无需落地
// sync_schema.json。若日后切单版本表模式，才必须补 uuid 全局唯一列 + schema 声明解冲突列。
export const DISTRIBUTED_TABLES: string[] = SYNC_TABLES;
