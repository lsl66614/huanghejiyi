// entry/src/main/ets/service/sync/AutoSync.ets
// 赛题条款「全部图文预置本地、离线可编辑、**恢复后自动同步**」的落地实现。
//
// 设计要点：
//   1. 监听网络可用事件（@ohos.net.connection 的 netAvailable）；
//   2. 仅在**真机分布式模式**下触发一次自动同步——仿真模式（Loopback）
//      是单机演示，没有"另一台设备"，自动跑它没有意义且会干扰面板演示；
//   3. 全程 try/catch + 幂等节流：网络抖动会连续触发 netAvailable，
//      用时间窗 + in-flight 标志去重，避免并发跑多次合并；
//   4. 同步失败只记日志，不弹窗、不崩溃——后台自动任务不该打断用户。
//
// 与 SyncPage 的关系：SyncPage 仍是手动同步的主入口；本模块是"兜底通道"，
// 两者共用同一个 SyncScheduler.runSync 与同一个 ITransport 实现。
import { connection } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import type { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { UserDataRepo } from '../../repository/UserDataRepo';
import { SoftBusRdbTransport } from '../../repository/SoftBusRdbTransport';
import { runSync } from './SyncScheduler';
import { SyncStatus, classifySyncError } from './SyncStatus';
import { AutoSyncGateInput, decideAutoSync } from './AutoSyncGate';
import { releaseBootGate } from './BootGate';
import type { IDataRepository } from '../../repository/IDataRepository';

const DOMAIN = 0x0000;
const TAG = 'AutoSync';

// 恢复同步模式的等待上限。它要读 sync_meta，也就是必须先打开 RDB
// （老库还要跑迁移）。正常情况几十毫秒；一旦卡住，这里按默认口径
// （主库、不自动同步）放行，不把数据库访问无限期挂着。
// 首屏已经先行渲染，这个上限影响的是首页数据出现的时刻，不是白屏时长。
const MODE_RESTORE_TIMEOUT_MS: number = 1500;

// 模块级状态。ArkTS 不允许在类外访问类的 private 静态字段，
// 所以这些状态放在模块作用域，类方法只做转发。
let registered: boolean = false;
let running: boolean = false;
let lastAt: number = 0;
let realMode: boolean = false;
let appContext: common.UIAbilityContext | null = null;
let netConn: connection.NetConnection | null = null;

function onNetAvailable(_handle: connection.NetHandle): void {
  if (!realMode) {
    hilog.info(DOMAIN, TAG, 'net available but real mode off, skip auto sync');
    return;
  }
  AutoSync.checkNow('network');
}

function onNetLost(_handle: connection.NetHandle): void {
  if (realMode) { SyncStatus.markOffline(); }
}

function onNetUnavailable(): void {
  if (realMode) { SyncStatus.markOffline(); }
}

// 真机 + 在线 + 未在跑 + 过了冷却窗，才开一次。
// 启动和回前台也走这里，避免三个入口各写一套判断。
function isOnline(): boolean {
  try {
    const handle: connection.NetHandle = connection.getDefaultNetSync();
    return handle.netId !== 0;
  } catch (e) {
    return false;
  }
}

// 真正跑合并
async function triggerSync(): Promise<void> {
  const ctx: common.UIAbilityContext | null = appContext;
  if (ctx === null) {
    running = false;
    SyncStatus.markIdle();
    return;
  }
  SyncStatus.markSyncing();
  try {
    const repo: IDataRepository = await UserDataRepo.get(ctx);
    const dev: string = await UserDataRepo.deviceIdOf(ctx);
    const transport: SoftBusRdbTransport = new SoftBusRdbTransport(ctx, repo);
    const conflicts = await runSync(dev, repo, transport);
    SyncStatus.markSynced(Date.now(), conflicts.length);
    hilog.info(DOMAIN, TAG, 'auto sync done, conflicts=%{public}d', conflicts.length);
  } catch (e) {
    // 后台自动同步失败只记日志：可能没有配对设备、可能权限未授予，
    // 都不该打断用户操作，更不该让 App 崩。状态条负责把原因说出来。
    const msg: string = e instanceof Error ? e.message : String(e);
    SyncStatus.markFailure(classifySyncError(msg), msg);
    hilog.warn(DOMAIN, TAG, 'auto sync failed (ignored): %{public}s', msg);
  } finally {
    running = false;
  }
}

export class AutoSync {
  // 冷启动：恢复上次的同步模式，再决定是否补一次同步。
  //
  // 这一步不再卡在 loadContent 之前（首屏先出，见 EntryAbility）。顺序要求
  // 移交给了 BootGate：prepare 结束时放行闸门，UserDataRepo.get() 在闸门
  // 后等待，因此页面拿不到「模式尚未恢复」的库。
  static async prepare(context: common.UIAbilityContext): Promise<void> {
    appContext = context;
    // 不 await：网络监听注册失败/回调迟迟不来时，不能把首屏一起拖住。
    // start 内部自己 catch，注册成功后 netAvailable 仍会正常触发。
    AutoSync.start(context);
    // 对端推送变更 → 跑一次合并。节流交给 checkNow 的冷却窗与 in-flight 判定：
    // dataChange 在抖动时会连着来，不能每次都真跑。
    UserDataRepo.installRemoteChangeHook(context, () => {
      AutoSync.checkNow('remote-change');
    }).catch((_e: Object): void => {
      hilog.warn(DOMAIN, TAG, 'install remote change hook failed');
    });
    try {
      const modePromise: Promise<string> = UserDataRepo.readSyncMode(context)
        .catch((_e: Object): string => '');
      const timeoutPromise: Promise<string> = new Promise<string>(
        (resolve: (v: string) => void): void => {
          setTimeout(() => { resolve(''); }, MODE_RESTORE_TIMEOUT_MS);
        });
      const mode: string = await Promise.race([modePromise, timeoutPromise]);
      if (mode === 'real') {
        realMode = true;
        await UserDataRepo.setSimMode(context, false);
      } else if (mode === 'sim') {
        realMode = false;
        await UserDataRepo.setSimMode(context, true);
      } else {
        // 从未选过模式：保持旧默认（主库、不自动同步），
        // 避免升级后把老用户的主库数据藏起来。
        realMode = false;
      }
      hilog.info(DOMAIN, TAG, 'prepare mode=%{public}s real=%{public}s',
        mode === '' ? 'unset' : mode, String(realMode));
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'prepare mode restore failed: %{public}s', msg);
    }
    // 放行闸门必须早于 checkNow：checkNow → triggerSync 会走 UserDataRepo.get()，
    // 而 get() 在等这道闸门。放行放在 finally 之外、checkNow 之前，
    // 顺序上一目了然。
    releaseBootGate();
    AutoSync.checkNow('startup');
  }

  // 回前台补一次：可能后台期间网络恢复了，而 netAvailable 没派发。
  static onForeground(): void {
    AutoSync.checkNow('foreground');
  }

  // 所有自动同步入口的唯一闸门。
  // 判定本身在 AutoSyncGate.decideAutoSync（纯函数、有单测）；这里只做
  // 判定结果的执行：日志按原措辞、离线标状态条、放行才置 running/lastAt。
  static checkNow(reason: string): void {
    const gate = new AutoSyncGateInput();
    gate.realMode = realMode;
    gate.running = running;
    gate.lastAt = lastAt;
    gate.now = Date.now();
    gate.online = isOnline();
    const d = decideAutoSync(gate);
    if (d.reason === 'mode') {
      hilog.info(DOMAIN, TAG, '%{public}s: real mode off, skip', reason);
      return;
    }
    if (d.reason === 'inflight') {
      hilog.info(DOMAIN, TAG, '%{public}s: already running, skip', reason);
      return;
    }
    if (d.reason === 'cooldown') {
      hilog.info(DOMAIN, TAG, '%{public}s: cooling down, skip', reason);
      return;
    }
    if (d.reason === 'offline') {
      SyncStatus.markOffline();
      hilog.info(DOMAIN, TAG, '%{public}s: offline, skip', reason);
      return;
    }
    running = true;
    lastAt = gate.now;
    hilog.info(DOMAIN, TAG, '%{public}s: auto sync start', reason);
    triggerSync();
  }

  // 注册网络监听。幂等：重复调用不会重复注册。
  static async start(context: common.UIAbilityContext): Promise<void> {
    appContext = context;
    if (registered) {
      return;
    }
    try {
      const conn: connection.NetConnection = connection.createNetConnection();
      conn.on('netAvailable', onNetAvailable);
      conn.on('netLost', onNetLost);
      conn.on('netUnavailable', onNetUnavailable);
      // register 是回调式的（register(callback)），不是 Promise——
      // 写成 await conn.register() 会报 "Expected 1 arguments, but got 0"。
      // 回调参数**成功时是 undefined、失败时才是 BusinessError**：直接读
      // err.code 会在成功路径上抛 TypeError 并把整个进程打死
      // （2026-11-06 实测：补 GET_NETWORK_INFO 后首次走到成功分支，
      //  报 "Cannot read property code of undefined"，AppKit 判 JS_ERROR 杀进程）。
      await new Promise<void>((resolve: () => void, reject: (e: Object) => void): void => {
        conn.register((err: Object | undefined) => {
          const code: number = err === undefined ? 0 : ((err as BusinessError).code ?? 0);
          if (code !== 0) {
            reject(new Error('register failed code=' + code));
            return;
          }
          resolve();
        });
      });
      netConn = conn;
      registered = true;
      hilog.info(DOMAIN, TAG, 'network listener registered');
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'register network listener failed: %{public}s', msg);
    }
  }

  // 注销监听（Ability 销毁时调用）
  static stop(): void {
    if (!registered || netConn === null) {
      return;
    }
    const conn: connection.NetConnection = netConn;
    netConn = null;
    registered = false;
    try {
      // unregister 必须带回调，SDK 签名不收零参
      conn.unregister((err) => {
        if (err.code) {
          hilog.warn(DOMAIN, TAG, 'unregister network listener failed. code=%{public}d', err.code);
        }
      });
    } catch (e) {
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(DOMAIN, TAG, 'unregister network listener threw: %{public}s', msg);
    }
    hilog.info(DOMAIN, TAG, 'network listener unregistered');
  }

  // SyncPage 切换模式时同步过来：只有真机分布式模式才自动同步。
  static setRealMode(on: boolean): void {
    realMode = on;
    hilog.info(DOMAIN, TAG, 'real mode = %{public}s', on);
  }
}
