// entry/src/main/ets/service/sync/AutoSyncGate.ets —— 自动同步的唯一闸门，纯函数，禁 @kit
//
// 为什么要拆出来：AutoSync.ets import 了 NetworkKit（网络监听是它躲不开的
// 系统 API），因此进不了 tools/merge-tests 的转译体系——它里面的节流/幂等
// 判定此前完全没有任何测试碰到。把「该不该跑」抽成纯函数放这里，
// 「怎么跑」（NetworkKit 注册、runSync 调用）留在 AutoSync.ets，
// 判定逻辑就能被 Node 单测逐分支验证。
//
// 判定顺序与 AutoSync.checkNow 的原有行为一致（网抖连续触发 netAvailable、
// 启动/回前台/切模式三入口共用），重构只搬逻辑不改语义：
//   realMode 关 → 不跑（仿真是单机演示，没有"另一台设备"）；
//   in-flight → 不跑（避免并发跑多次合并）；
//   冷却窗内 → 不跑（30 秒只自动同步一次）；
//   离线 → 不跑，且要把状态条标成 offline（这是唯一的副作用标记）；
//   其余 → 跑。
export const AUTO_SYNC_COOLDOWN_MS: number = 30000;

export class AutoSyncGateInput {
  realMode: boolean = false;
  running: boolean = false;
  // 上次自动同步开始时刻（毫秒）。0 = 从未跑过。
  lastAt: number = 0;
  // 当前墙钟（毫秒）。由调用方传入，纯函数不取 Date.now()。
  now: number = 0;
  online: boolean = false;
}

export class AutoSyncDecision {
  run: boolean = false;
  // 判定为离线时置 true：AutoSync 据此调 SyncStatus.markOffline()。
  // 闸门函数只给结论，不碰状态条——那是页面层的副作用。
  markOffline: boolean = false;
  // 'mode' | 'inflight' | 'cooldown' | 'offline' | 'go'，给日志与单测断言用
  reason: string = '';
}

function decided(run: boolean, markOffline: boolean, reason: string): AutoSyncDecision {
  const d = new AutoSyncDecision();
  d.run = run;
  d.markOffline = markOffline;
  d.reason = reason;
  return d;
}

export function decideAutoSync(i: AutoSyncGateInput): AutoSyncDecision {
  if (!i.realMode) { return decided(false, false, 'mode'); }
  if (i.running) { return decided(false, false, 'inflight'); }
  // lastAt=0（从未跑过）时 now - lastAt 必然远大于冷却窗，自然放行
  if (i.now - i.lastAt < AUTO_SYNC_COOLDOWN_MS) { return decided(false, false, 'cooldown'); }
  if (!i.online) { return decided(false, true, 'offline'); }
  return decided(true, false, 'go');
}
