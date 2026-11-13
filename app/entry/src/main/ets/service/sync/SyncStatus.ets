// entry/src/main/ets/service/sync/SyncStatus.ets —— 全局同步状态的唯一事实源
//
// 为什么单独一层：同步发生在三个地方——SyncPage 手动、AutoSync 网络恢复、
// 启动/回前台补同步。状态如果各自记在页面 @State 里，用户在不同页面会看到
// 互相矛盾的三份结论（面板说失败、首页说已同步）。
//
// 这里只存内存快照，不落库：真正的 lastSyncTime / 冲突日志仍在 RDB meta，
// 本模块是「这一次运行到现在」的展示状态。进程重启后由启动补同步重新建立。
export class SyncSnapshot {
  // idle | syncing | synced | failed | offline | auth | no_peer
  state: string = 'idle';
  lastSyncTime: number = 0;
  lastError: string = '';
  conflictCount: number = 0;
}

let current: SyncSnapshot = new SyncSnapshot();

// 底栏「同步」格角标的数据源（修复计划 §6.2 矛盾二）：
// SyncStatus 是普通类，刷不了 @Component；底栏要跟着冲突数变，
// 只能把「冲突数」这一件事镜像到 AppStorage，由 AppNavBar 用
// @StorageProp 订阅。快照本身仍是唯一事实源，这里只做单向镜像。
export const SYNC_BADGE_KEY: string = 'syncConflictBadge';

function publishBadge(): void {
  AppStorage.setOrCreate(SYNC_BADGE_KEY, current.conflictCount);
}

function copyOf(): SyncSnapshot {
  const c = new SyncSnapshot();
  c.state = current.state;
  c.lastSyncTime = current.lastSyncTime;
  c.lastError = current.lastError;
  c.conflictCount = current.conflictCount;
  return c;
}

// 把底层异常翻译成用户能理解的三类。SDK 的报错文案不稳定，
// 只能按关键字归类；归不进去的一律算传输失败，至少不会误报“已授权”。
export function classifySyncError(msg: string): string {
  const m = msg.toLowerCase();
  if (m.includes('permission') || m.includes('unauthorized') ||
    m.includes('201') || m.includes('401') || m.includes('权限')) {
    return 'auth';
  }
  if (m.includes('peer') || m.includes('no device') || m.includes('not found') ||
    m.includes('offline') || m.includes('device') ||
    m.includes('未发现') || m.includes('可信设备') || m.includes('组网')) {
    return 'no_peer';
  }
  return 'failed';
}

export class SyncStatus {
  static snapshot(): SyncSnapshot {
    return copyOf();
  }

  static markIdle(): void {
    current.state = 'idle';
    current.lastError = '';
  }

  static markSyncing(): void {
    current.state = 'syncing';
    current.lastError = '';
  }

  static markSynced(at: number, conflicts: number): void {
    current.state = 'synced';
    current.lastSyncTime = at;
    current.lastError = '';
    current.conflictCount = conflicts;
    publishBadge();
  }

  static markOffline(): void {
    current.state = 'offline';
    current.lastError = '';
  }

  // kind 由 classifySyncError 给出；auth / no_peer 直接成为状态，
  // 状态条据此给不同文案，而不是把三种失败都写成“同步失败”。
  static markFailure(kind: string, msg: string): void {
    current.lastError = msg;
    if (kind === 'auth' || kind === 'no_peer' || kind === 'offline') {
      current.state = kind;
    } else {
      current.state = 'failed';
    }
  }

  // 从已落库的冲突日志恢复红点数量；不改 state。
  static setConflictCount(n: number): void {
    current.conflictCount = n;
    publishBadge();
  }
}
