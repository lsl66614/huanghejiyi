// entry/src/main/ets/pages/SyncPage.ets —— P8 同步面板（风格A 米白纸底·卷宗制式）
// 2026-10-04 弃用双暗柜黑金配色：同步是操作流程页，不离开纸面世界（暗柜仅保留给 P4 文物展签）。
// 设备 A/B 隐喻改为两份卷宗；按钮回归 §7 制式（赭红实心主按钮 / 描边次按钮）。
import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import type { PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import type { ConflictEntry, SyncRecord } from '../model/SyncModels';
import type { NoteView } from '../model/UserDataModels';
import { UserDataRepo } from '../repository/UserDataRepo';
import { LOOPBACK } from '../repository/LoopbackAdapter';
import { SoftBusRdbTransport } from '../repository/SoftBusRdbTransport';
import type { ITransport } from '../repository/ITransport';
import { runSync } from '../service/sync/SyncScheduler';
import { conflictTitle, conflictContent } from '../service/merge/ConflictLabel';
import { AutoSync } from '../service/sync/AutoSync';
import { SyncStatus, classifySyncError } from '../service/sync/SyncStatus';
import type { IDataRepository } from '../repository/IDataRepository';
import { stampSec, stampShort } from '../common/Time';
import { PressFade } from '../common/PressScale';
import { THEME_BG, THEME_INK } from '../common/EraTheme';
import {
  ACCENT, BLOCK_GAP, CARD_PAD, FONT_DISPLAY, FONT_MONO, FONT_SERIF,
  FS_BODY, FS_CAPTION, FS_ITEM,
  HAIR, INK, LH_BODY, LH_CAPTION, LINE_HAIR,
  PAGE_PAD_X, PRESS_OPACITY, RADIUS_CARD_LG, RADIUS_DOT_6,
  ROUTE_FADE_MIN,
  ROUTE_SHIFT_VP, SUB, SURFACE_CARD, WT_DISPLAY
} from '../common/DesignTokens';
import { SectionTitle } from '../common/SectionTitle';
import { StatStrip, StatItem } from '../common/StatStrip';
import { UnderlineTabs, TabItem } from '../common/UnderlineTabs';
import { PillButton } from '../common/PillButton';
import { AppNavBar } from '../common/AppNavBar';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, curveInOut, durRouteIn, durRouteOut, durSlow, pressAnim } from '../common/Motion';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0001;
const TAG = 'SyncPage';
const PERM_DATASYNC: Permissions = 'ohos.permission.DISTRIBUTED_DATASYNC';
const PERM_GRANTED: number = 0;

// 冲突历史折叠态：默认只看最近 2 条
const FOLD_COUNT: number = 2;

// 手动同步时每张表之间停一下，纯粹为了让面板上的进度条看得清。
// 自动同步走 AutoSync → runSync(...) 不传这个值，那里不需要等人看。
const SYNC_PACE_MS: number = 260;

class ConflictRow {
  key: string = '';
  content: string = '';
  reason: string = '';
  win: string = '';
  lose: string = '';
}

// 卷宗对：本机与对端各一格。
//
// 为什么压到 104 高、且内容左对齐（2026-11-05 视觉整改）：
// 原先是 150 高的两个方框，里面只挂一个 8px 状态点和两行字，垂直居中后
// 读作「两张空海报」——框比内容重，眼睛先看见边框再看见字。
// 改成：状态点与标题同一行、内容左对齐、框高收到刚好容下两行。
// 于是「哪一格是我」变成一行就能读完的事：赭红点 + 赭红标题。
//
// 层级仍由「赭红描边 + 赭红状态点 + 赭红标题」承担，底色不参与层级
// （非选中卡用白底 + 发丝；浅发丝短杠 + 灰字的写法读作「这块渲染坏了」）。
@Component
struct CabinetCell {
  @Prop label: string = '';
  @Prop sub: string = '';
  @Prop active: boolean = false;
  build() {
    Column({ space: 6 }) {
      // 状态点：选中=赭红实点，对端=发丝灰点。
      // 灰点是「这一格是另一台设备/对端」的标记，不是状态灯。
      Row({ space: 6 }) {
        Row()
          .width(6)
          .height(6)
          .borderRadius(RADIUS_DOT_6)
          .backgroundColor(this.active ? ACCENT : LINE_HAIR)
        Text(this.label)
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(this.active ? ACCENT : INK)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.sub)
        .fontSize(FS_CAPTION)
        .lineHeight(LH_CAPTION)
        .fontColor(SUB)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .height(104)
    .justifyContent(FlexAlign.Center)
    .padding({ left: CARD_PAD, right: CARD_PAD })
    .backgroundColor(SURFACE_CARD)
    .border({ width: this.active ? 1.5 : HAIR, color: this.active ? ACCENT : LINE_HAIR })
    .borderRadius(RADIUS_CARD_LG)
  }
}

// 设备面板的一行：键 + 值。值会在页面加载完成后异步补上，
// 所以同样必须是 @Component 而不是 @Builder（理由见上方 MetricCell）。
@Component
struct DeviceLine {
  @Prop k: string = '';
  @Prop v: string = '';
  build() {
    Row({ space: 12 }) {
      Text(this.k)
        .fontSize(FS_CAPTION)
        .fontColor(SUB)
        .width(56)
      Text(this.v)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_MONO)
        .fontColor(THEME_INK)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

@Entry
@Component
struct SyncPage {
  @State dev: string = 'deviceA';
  // 「展开全部」行的按压态
  @State expandPressed: boolean = false;
  @State syncing: boolean = false;
  @State progress: number = 0;
  @State lastSync: string = '';
  @State rows: ConflictRow[] = [];
  // 冲突日志原文（读出来留着：笔记正文表晚一步到，拿到后要重新解析）
  private conflictJson: string = '';
  // note_id → 笔记正文：把冲突逻辑身份里的 note_id 翻成人话
  private noteTexts: Map<string, string> = new Map();
  @State localCount: number = 0;
  @State sweep: number = 0;
  @State expanded: boolean = false;
  // 'sim' 单机双档案仿真；'real' 软总线真机分布式（失败不崩，可随时切回仿真）
  @State mode: string = 'sim';
  @State hint: string = '';
  // 三要素下方的方向行（"手机 → 平板 已收敛"）。只在本次同步成功后写入；
  // 失败或重新进页时清空，避免拿上一次的成功冒充这一次。
  @State doneLine: string = '';
  // 设备面板：这一台是哪一台、现在读写哪个库。两项都在切换身份/模式后重取。
  @State devName: string = '';
  @State sysName: string = '';
  @State storeName: string = '';

  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 先恢复上次选的模式，再建库读数：否则从真机模式返回/重启后，
    // 面板会先按仿真档案显示一遍条数，用户以为数据丢了。
    // 没存过模式时仍落回仿真（与旧版默认一致）。
    UserDataRepo.readSyncMode(ctx).then((m: string) => {
      this.mode = m === 'real' ? 'real' : 'sim';
      AutoSync.setRealMode(this.mode === 'real');
      return UserDataRepo.setSimMode(ctx, this.mode === 'sim');
    }).then(() => {
      return UserDataRepo.deviceIdOf(ctx);
    }).then((d: string) => {
      this.dev = d;
      this.readDevice();
      this.refresh(ctx);
    }).catch((e: Object): void => {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'aboutToAppear rejected: %{public}s', msg);
      this.hint = `档案初始化失败：${msg}`;
    });
  }

  // 设备名/系统版本是常量，读一次即可；库文件名会随身份与模式变，必须重取。
  private readDevice(): void {
    this.storeName = UserDataRepo.storeName();
    this.devName = UserDataRepo.deviceProfile();
    this.sysName = UserDataRepo.systemProfile();
  }

  private archiveLine(): string {
    // 清单 S7：内部标识 deviceA/deviceB 不外露，这里只给读者人话；
    // 原始标识挪到下方「设备与档案」技术区一行。
    // 设备类型词与赛题原文对齐：原文写的是"个人数据在手机、平板等多设备间
    // 自动同步""展示'手机→平板'的同步进度"。仿真里两份卷宗固定映射
    // deviceA=手机、deviceB=平板，屏上才能逐字对得上原文。
    if (this.mode !== 'sim') { return '本机'; }
    return this.dev === 'deviceA' ? '手机' : '平板';
  }

  // 同步方向：在哪个身份上同步，就是把本机档案推向对端。
  private peerType(): string {
    return this.dev === 'deviceA' ? '平板' : '手机';
  }

  private syncDoneText(): string {
    return `仿真同步完成 · ${this.archiveLine()} → ${this.peerType()} 已收敛`;
  }

  // 模式的人话名：刊头副题与按钮标签都用它，避免同页两种写法。
  private modeName(): string {
    return this.mode === 'sim' ? '单机仿真' : '真机分布式';
  }

  // 模式切换器数据：走 UnderlineTabs（页签制式）。
  //
  // 为什么不用 SegmentTab 的黑底胶囊（2026-11-05 视觉整改）：
  // 这一行是「页面级模式切换」，不是「同一份数据的视图切换」。
  // 胶囊（INK 实底）在一个满屏赭红强调的页面上读作另一个产品的控件，
  // 且它与下方那个赭红实心主按钮形状相同、颜色却相反，读者会先点错。
  // 页签（墨色字 + 下划线）没有色块，不与任何按钮撞形。
  modeItems(): TabItem[] {
    const a = new TabItem();
    a.key = 'sim';
    a.label = '单机仿真';
    const b = new TabItem();
    b.key = 'real';
    b.label = '真机分布式';
    const out: TabItem[] = [a, b];
    return out;
  }

  // 三要素：同步进度 / 最后同步 / 冲突记录。
  // 第一格挂进度线（StatStrip 的 progress 三件套）——原先那条线通栏
  // 横贯屏幕，读作把屏幕切成两半的划痕。
  statItems(): StatItem[] {
    return [
      new StatItem('同步进度', `${this.progress}%`, this.progress),
      new StatItem('最后同步', this.lastSync === '' ? '—' : this.lastSync),
      new StatItem('冲突记录', `${this.rows.length}`)
    ];
  }

  private deviceLineText(): string {
    if (this.sysName === '') { return this.devName; }
    return `${this.devName} · ${this.sysName}`;
  }

  refresh(ctx: common.UIAbilityContext): void {
    UserDataRepo.get(ctx).then((repo: IDataRepository): void => {
      repo.getMeta('lastSyncTime').then((v: string) => {
        const t: number = Number(v);
        this.lastSync = stampShort(t);
        // 进度只在本次滚动同步时从 0 涨到 100；重新进页面时它归零，
        // 于是「最后同步 12:45 + 同步进度 0%」自相矛盾。有上次同步记录
        // 就按「已完成」显示 100%，与本页三要素的口径一致。
        if (t > 0 && !this.syncing) { this.progress = 100; }
      });
      repo.getMeta('conflictLogJson').then((j: string) => {
        this.conflictJson = j;
        this.rows = this.parseConflicts(j);
        SyncStatus.setConflictCount(this.rows.length);
      });
      // note_id → 笔记正文：冲突的逻辑身份里带 note_id，
      // 不翻译的话用户看到的是一串随机 id（nmvn75i6l5ql）。
      repo.listAllNotes().then((notes: NoteView[]) => {
        const map: Map<string, string> = new Map();
        for (const n of notes) { map.set(n.noteId, n.text); }
        this.noteTexts = map;
        this.rows = this.parseConflicts(this.conflictJson);
      });
      repo.snapshotSyncTables().then((t: Map<string, SyncRecord[]>) => {
        let n = 0;
        t.forEach((recs: SyncRecord[]) => { n += recs.length; });
        this.localCount = n;
      });
    });
  }

  parseConflicts(json: string): ConflictRow[] {
    const out: ConflictRow[] = [];
    if (json === '') { return out; }
    let log: ConflictEntry[] | null = null;
    try {
      log = JSON.parse(json) as ConflictEntry[] | null;
    } catch (e) {
      log = null;
    }
    if (log === null || !Array.isArray(log)) { return out; }
    for (let i = log.length - 1; i >= 0; i--) {
      const c = log[i];
      const r = new ConflictRow();
      // 显示可读标题而非原始逻辑身份：关联表的 key 是 note_id␟tag_id，
      // ␟ 是不可见控制符，直接显示用户看到的是「乱码 + 标签名」。
      r.key = conflictTitle(c, this.noteTexts);
      r.content = conflictContent(c);
      r.reason = c.reason === 'tie_break_deviceId' ? '同时间戳 · 按设备号裁决' : '时间戳更新者采信';
      r.win = `${stampSec(c.winner.updateTime)} · ${c.winner.deviceId}`;
      r.lose = `${stampSec(c.loser.updateTime)} · ${c.loser.deviceId}`;
      out.push(r);
    }
    return out;
  }

  visibleRows(): ConflictRow[] {
    if (this.expanded || this.rows.length <= 2) {
      return this.rows;
    }
    return this.rows.slice(0, 2);
  }

  switchDevice(): void {
    hilog.info(DOMAIN, TAG, 'switchDevice tap, dev=%{public}s', this.dev);
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const next = this.dev === 'deviceA' ? 'deviceB' : 'deviceA';
    UserDataRepo.setDeviceId(ctx, next).then(() => {
      hilog.info(DOMAIN, TAG, 'switchDevice ok -> %{public}s', next);
      this.dev = next;
      this.progress = 0;
      this.readDevice();
      // 切到另一份档案：记录条数与冲突历史都跟着换成该身份视角
      this.refresh(ctx);
    }).catch((e: object): void => {
      hilog.error(DOMAIN, TAG, 'switchDevice rejected: %{public}s', JSON.stringify(e));
    });
  }

  startSweep(): void {
    const to: number = this.dev === 'deviceA' ? 1 : -1;
    this.sweep = -to;
    this.getUIContext().animateTo({ duration: durSlow(), curve: curveInOut() }, () => {
      this.sweep = to;
    });
  }

  // 同步执行核心：传输层由调用方注入（仿真 LOOPBACK / 真机 SoftBusRdbTransport）
  runWith(ctx: common.UIAbilityContext, repo: IDataRepository, transport: ITransport,
    deviceId: string, okText: string): void {
    hilog.info(DOMAIN, TAG, 'runWith start dev=%{public}s', deviceId);
    SyncStatus.markSyncing();
    runSync(deviceId, repo, transport, (_table: string, done: number, total: number): void => {
      this.progress = Math.round(done * 100 / total);
    }, SYNC_PACE_MS).then((conflicts: ConflictEntry[]): Promise<void> => {
      hilog.info(DOMAIN, TAG, 'runSync ok conflicts=%{public}d', conflicts.length);
      return repo.getMeta('conflictLogJson').then((j: string) => {
        this.rows = this.parseConflicts(j);
        this.lastSync = stampShort(Date.now());
        this.syncing = false;
        this.hint = okText;
        this.doneLine = this.syncDoneText();
        SyncStatus.markSynced(Date.now(), conflicts.length);
        this.refresh(ctx);
      });
    }).catch((e: Object): void => {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'runSync rejected: %{public}s', msg);
      this.syncing = false;
      this.progress = 0;
      this.doneLine = '';
      SyncStatus.markFailure(classifySyncError(msg), msg);
      if (this.mode === 'real') {
        this.hint = `真机同步未完成：${msg}。可切回「单机仿真」继续演示合并裁决。`;
      } else {
        this.hint = `同步失败：${msg}`;
      }
    });
  }

  doSync(): void {
    if (this.syncing) { return; }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.syncing = true;
    this.progress = 0;
    this.hint = '';
    this.doneLine = '';
    this.startSweep();
    if (this.mode === 'sim') {
      UserDataRepo.get(ctx).then((repo: IDataRepository): void => {
        this.runWith(ctx, repo, LOOPBACK, this.dev, '仿真同步完成 · 两份卷宗已收敛');
      }).catch((e: Object): void => {
        hilog.error(DOMAIN, TAG, 'repo get failed: %{public}s', e instanceof Error ? e.message : String(e));
        this.syncing = false;
      });
      return;
    }
    // 真机模式：user_grant 权限在点击时运行时申请（UIAbilityContext 无此方法，须走 AtManager）
    const atManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(ctx, [PERM_DATASYNC])
      .then((res: PermissionRequestResult): void => {
        const results: number[] = res.authResults;
        let granted = false;
        for (const r of results) {
          if (r === 0) { granted = true; break; }
        }
        if (!granted) {
          this.syncing = false;
          this.progress = 0;
          this.hint = '未授予分布式数据权限，无法进行真机同步；可切回「单机仿真」。';
          SyncStatus.markFailure('auth', '未授予分布式数据权限');
          return;
        }
        UserDataRepo.get(ctx).then((repo: IDataRepository): void => {
          const transport = new SoftBusRdbTransport(ctx, repo);
          this.runWith(ctx, repo, transport, this.dev, '真机分布式同步完成');
        });
      }).catch((e: Object): void => {
        this.syncing = false;
        this.progress = 0;
        const msg: string = e instanceof Error ? e.message : String(e);
        this.hint = `权限申请失败：${msg}`;
        SyncStatus.markFailure('auth', msg);
      });
  }

  switchMode(m: string): void {
    if (this.syncing || m === this.mode) { return; }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 仿真模式切到双档案库（两身份各自一份数据），真机模式回到主库。
    // 必须在读任何数据前切完，否则 localCount 仍是另一份档案的数。
    UserDataRepo.setSimMode(ctx, m === 'sim').then(() => {
      this.mode = m;
      this.progress = 0;
      this.hint = m === 'real'
        ? '真机模式：两台设备登录同一华为账号、同一局域网并完成可信组网后点击同步。'
        : '仿真模式：两份卷宗各自独立存档。先在一个身份下改一条笔记或收藏，同步一次；再切到另一身份改同一条，同步一次即可看到冲突裁决。';
      // 把模式告诉自动同步器：只有真机分布式模式才在网络恢复后自动跑合并。
      // 仿真模式是单机演示，没有对端设备，自动跑它没有意义。
      AutoSync.setRealMode(m === 'real');
      // 模式落主库 meta：杀进程重启后仍是这个模式（见 AutoSync.prepare）。
      // 写失败不影响本次切换，只是下次启动回落到旧模式。
      UserDataRepo.writeSyncMode(ctx, m).catch((e: Object): void => {
        const msg = e instanceof Error ? e.message : String(e);
        hilog.error(DOMAIN, TAG, 'writeSyncMode failed: %{public}s', msg);
      });
      // 换了一份档案，上一份的“已同步”不再代表当前数据。
      SyncStatus.markIdle();
      this.readDevice();
      this.refresh(ctx);
    }).catch((e: Object): void => {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'switchMode rejected: %{public}s', msg);
      this.hint = `模式切换失败：${msg}`;
    });
  }

  build() {
    Column() {
      Scroll() {
        Column() {
        // 频道页（修复计划 阶段2）：同步从「我的」子页升为底栏第 3 格，
        // 因此不再挂返回键——底栏切频道是清栈替换，栈里只有本页。

        // 刊头：走 SectionTitle 与全站同族。
        //
        // 副题放「当前模式 + 记录条数」——原先这两句散在页面上方（模式）
        // 与中部（记录数），中间夹着统计卡与两个大方框，读者要上下扫两遍
        // 才拼得出「现在是什么模式、有多少数据」。并进副题后，刊头一行
        // 说清「这是哪一页 + 现在处于什么状态」。
        Column() {
          SectionTitle({
            title: '同步面板',
            caption: `${this.modeName()} · 本机六表 ${this.localCount} 条`
          })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16 })

        // 传输模式切换：同一合并引擎，两种 ITransport。
        // 走 UnderlineTabs（页签）而非 SegmentTab（黑底胶囊）——
        // 理由见 modeItems() 上的注释。
        Column() {
          UnderlineTabs({
            items: this.modeItems(),
            selected: this.mode,
            // 不画行下沿发丝：页签下划线已经标出当前项，
            // 再加一条通栏发丝就成了两条横线密集。
            hairline: false,
            onPick: (k: string): void => {
              this.switchMode(k);
            }
          })
        }
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })
        .margin({ top: 16 })

        // 三要素条：StatStrip——四边发丝 + 圆角 + 页边留边。
        // 进度轨挂在「同步进度」那一格数字下方，不再通栏横贯屏幕。
        Column() {
          StatStrip({ items: this.statItems() })
        }
        .width('100%')
        .margin({ top: BLOCK_GAP })

        // 方向行：赛题原文要"清晰展示「手机→平板」的同步进度"，
        // 原来那句完成提示排在「设备与档案」卡之后、首屏之外，要上滑才看得见。
        // 挪到三要素正下方：看完进度自然看到方向，不用找。
        // 只在本次真的同步成功后出现——没同步就写"已收敛"是假话；
        // 失败走下方 hint，不在这里冒充成功。
        if (this.doneLine !== '') {
          Text(this.doneLine)
            .fontSize(FS_CAPTION)
            .lineHeight(LH_CAPTION)
            .fontFamily(FONT_MONO)
            .fontColor(ACCENT)
            .width('100%')
            .textAlign(TextAlign.Start)
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })
            .margin({ top: 10 })
        }

        Stack() {
          Row() {
            if (this.mode === 'sim') {
              CabinetCell({
                label: '手机',
                sub: this.dev === 'deviceA' ? '当前身份 · 本机档案' : '仿真对端',
                active: this.dev === 'deviceA'
              })
              CabinetCell({
                label: '平板',
                sub: this.dev === 'deviceB' ? '当前身份 · 本机档案' : '仿真对端',
                active: this.dev === 'deviceB'
              })
            } else {
              CabinetCell({
                label: '本机',
                // 清单 S7：deviceA 这类内部标识不外露，原始键在下方技术区一行
                sub: '本机档案',
                active: true
              })
              // 清单 S6：灰底不能"空着像坏了"——给状态点之外的可操作提示
              CabinetCell({ label: '可信对端', sub: '未组网 · 需同账号同局域网', active: false })
            }
          }
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })

          // 同步时的扫描光条：贴在两格卷宗之间，从左扫到右。
          // 原先它与通栏进度条叠在一起，两个细线在同一处出现，
          // 读作「屏幕上划了一道」。现在通栏那条已收进统计卡，
          // 只留这一条表示「正在搬数据」。
          //
          // 空闲态必须完全隐去（2026-11-05 实测）：留着 0.12 的残影，
          // 它停在设备 B 卡内右侧，读作卡片上多了一道没对齐的分隔线。
          Row()
            .width(2)
            .height(104)
            .linearGradient({ angle: 180, colors: [['#00' + ACCENT.slice(1), 0], [ACCENT, 0.5], ['#00' + ACCENT.slice(1), 1]] })
            .translate({ x: this.sweep * 150 })
            .opacity(this.syncing ? 1 : 0)
        }
        .width('100%')
        .margin({ top: 24 })

        // 卷宗说明：原先两句灰字各自占一段、位置又散（上方一句模式、
        // 下方一句技术栈），中间隔着按钮，读作四段互不相干的注释。
        // 合成一句、跟在卷宗对下面：一句说清「这些数据怎么走」。
        Text(this.mode === 'sim'
          ? '两份卷宗在本机合并，冲突按时间戳裁决'
          : '经软总线与对端交换，冲突按时间戳裁决')
          .fontSize(FS_CAPTION)
          .lineHeight(LH_CAPTION)
          .fontColor(SUB)
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })
          .margin({ top: 12, bottom: 16 })

        Row({ space: 12 }) {
          // 禁用态（清单 S5 / §3.4）：走 PillButton 的 disabled 布尔——
          // 系统 .enabled(false) 会把自定义底色/描边盖成灰斑。
          // fill 平分：自定义组件链 layoutWeight 不生效，宽度在组件内撑满。
          Column() {
            PillButton({
              label: this.mode === 'sim' ? '切换身份' : '身份自动识别',
              secondary: true,
              fill: true,
              disabled: !(this.mode === 'sim' && !this.syncing),
              onPress: () => {
                this.switchDevice();
              }
            })
          }
          .layoutWeight(1)

          Column() {
            PillButton({
              label: this.syncing ? '同步中…' : (this.mode === 'sim' ? '组网同步' : '真机同步'),
              fill: true,
              disabled: this.syncing,
              onPress: () => {
                this.doSync();
              }
            })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })

        // 技术区（设备与档案 + 传输方式）：原先是按钮下方一句灰字、
        // 页面底部一个小标题加四行键值，两块内容隔着冲突历史，
        // 且都只是「补充说明」，却各占一段版面，读作散落。
        // 合成一张卡放在按钮之后：技术信息归技术信息，与正文分区。
        Column({ space: 6 }) {
          Text('设备与档案')
            .fontSize(FS_CAPTION)
            .letterSpacing(3)
            .fontColor(SUB)
            .width('100%')
          DeviceLine({ k: '档案', v: this.archiveLine() })
          DeviceLine({ k: '本机', v: this.deviceLineText() })
          DeviceLine({ k: '库文件', v: this.storeName === '' ? '—' : this.storeName })
          // 清单 S7：deviceA/deviceB 从界面文案收进这里——技术区仍可见、可核对
          DeviceLine({ k: '标识', v: this.dev === '' ? '—' : this.dev })
          DeviceLine({
            k: '传输',
            v: this.mode === 'sim' ? '单机仿真 · 纯本机' : '分布式 RDB · 软总线'
          })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: CARD_PAD, right: CARD_PAD, top: CARD_PAD, bottom: CARD_PAD })
        .margin({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 24 })
        .backgroundColor(SURFACE_CARD)
        .border({ width: HAIR, color: LINE_HAIR })
        .borderRadius(RADIUS_CARD_LG)

        if (this.hint !== '') {
          Text(this.hint)
            .fontSize(FS_CAPTION)
            .lineHeight(LH_CAPTION)
            .fontColor(ACCENT)
            .width('100%')
            .textAlign(TextAlign.Start)
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })
            .margin({ top: 10 })
        }

        Text('冲突历史')
          .fontSize(FS_CAPTION)
          .letterSpacing(3)
          .fontColor(SUB)
          .width('100%')
          .padding({ left: PAGE_PAD_X, top: 32, bottom: 10 })

        List({ space: 0 }) {
          ForEach(this.visibleRows(), (r: ConflictRow) => {
            ListItem() {
              Column({ space: 8 }) {
                Row() {
                  Text(r.key)
                    .fontSize(FS_CAPTION)
                    .fontFamily(FONT_MONO)
                    .fontColor(THEME_INK)
                  Blank()
                  Text(r.reason)
                    .fontSize(FS_CAPTION)
                    .fontColor(SUB)
                }
                .width('100%')
                if (r.content !== '') {
                  Text(r.content)
                    .fontSize(FS_CAPTION)
                    .fontFamily(FONT_SERIF)
                    .fontColor(THEME_INK)
                    .width('100%')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                Text(`落选 ${r.lose}`)
                  .fontSize(FS_CAPTION)
                  .fontFamily(FONT_MONO)
                  .fontColor(SUB)
                  .decoration({ type: TextDecorationType.LineThrough, color: SUB })
                Text(`采信 ${r.win}`)
                  .fontSize(FS_CAPTION)
                  .fontFamily(FONT_MONO)
                  .fontColor(ACCENT)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 12 })
              .border({ width: { bottom: 1 }, color: LINE_HAIR })
            }
          }, (r: ConflictRow, i: number) => `${r.key}:${i}`)

          if (this.rows.length > 2) {
            ListItem() {
              // 不用 PressFade 包装器：这一行 width('100%')，套进包装器后
              // 百分比会按包装器算，撑不满 ListItem。按压态就地写。
              Row({ space: 6 }) {
                Text(this.expanded ? '收起' : `展开全部 ${this.rows.length} 条`)
                  .fontSize(FS_CAPTION)
                  .letterSpacing(2)
                  .fontColor(ACCENT)
                Text(this.expanded ? '▴' : '▾')
                  .fontSize(FS_CAPTION)
                  .fontColor(ACCENT)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 12, bottom: 12 })
              .onClick(() => {
                this.expanded = !this.expanded;
              })
              .onTouch((e: TouchEvent) => {
                if (e.type === TouchType.Down) {
                  this.expandPressed = true;
                } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                  this.expandPressed = false;
                }
              })
              .opacity(this.expandPressed ? PRESS_OPACITY : 1)
              .animation(pressAnim())
              .focusable(true)
              .focusBox(focusRing())
            }
          }

          if (this.rows.length === 0) {
            ListItem() {
              // 29 字的成句空态，不是眉标：按正文 14pt 排。
              // 原为 FS_CAPTION(12) + lineHeight 19，是全站唯一一处
              // 需要读者读懂句意的 FS_CAPTION，归档时按语义提档。
              Text('尚无冲突。先在两个身份下分别改写同一条笔记或收藏，再各同步一次。')
                .fontSize(FS_BODY)
                .lineHeight(LH_BODY)
                .fontColor(SUB)
                .width('100%')
                .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 6, bottom: 24 })
            }
          }
        }
        .scrollBar(BarState.Off)
        .width('100%')
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // 频道页底栏（修复计划 阶段2）：同步是底栏第 3 格（active: 2）。
      // 必须在正文 Scroll 之外——放进 Scroll 里会被正文顶出视口（装机实测）。
      AppNavBar({ active: 2 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}
