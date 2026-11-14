// entry/src/main/ets/service/sync/BootGate.ets —— 禁 @kit
//
// 冷启动的第一屏不该等数据库。
//
// 原实现里 EntryAbility 等 AutoSync.prepare() 完成（它要先打开 RDB、老库
// 还要跑迁移、再按 syncMode 切档案）才 loadContent，于是首页的骨架、语料
// 这些完全不依赖数据库的东西也被一起按住。现在改成先 loadContent、再后台
// 恢复模式；但「先恢复模式」这个顺序本身是有理由的——首页若先读主库，
// 等模式切到仿真档案后又不重读，用户会看到「数据少了一半」。
//
// 所以把顺序约束下沉成一道闸门：
//   · 页面侧所有数据库访问都排在 UserDataRepo.get() 之后，get() 先等闸门；
//   · prepare() 走完（成功、失败或超时）一定会放行。
// 结果是可以安全并行的：界面与语料立刻渲染，数据库读写等模式就绪再说。
// 闸门另带超时兜底：即使 prepare 从未被调用，页面也不会被吊死。
const GATE_TIMEOUT_MS: number = 3000;

let released: boolean = false;
let openGate: (() => void) | null = null;

const gate: Promise<void> = new Promise<void>((resolve: () => void): void => {
  openGate = resolve;
});

// 放行。多次调用是安全的：只有第一次生效。
export function releaseBootGate(): void {
  if (released) { return; }
  released = true;
  const open: (() => void) | null = openGate;
  openGate = null;
  if (open !== null) { open(); }
}

// 等闸门。超时视为放行（降级为「按默认口径继续」），
// 调用方无需区分「已恢复模式」与「等太久了」——两者都必须往下走。
export async function whenBootGate(): Promise<void> {
  if (released) { return; }
  const fallback: Promise<void> = new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => { resolve(); }, GATE_TIMEOUT_MS);
  });
  await Promise.race([gate, fallback]);
}
