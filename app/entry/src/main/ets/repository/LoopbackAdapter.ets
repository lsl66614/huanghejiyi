// entry/src/main/ets/repository/LoopbackAdapter.ets —— 单机双档案仿真，禁 @kit
// 仿真语义（设计方案 §4.3）：两个身份各自持有独立档案（各一个 RDBStore，见
// UserDataRepo 的 simRepoOf），互不知晓对方写入；同步时才交换快照，交由同一个
// MergeEngine 裁决。
//
// 早期版本把合并结果同时写回两份 profile 袋，导致两侧永远一致——首次冲突能
// 演示，之后同一冲突不再产生记录。现改为「袋只由对方 exchange 时带进来的
// local 播种」，notifyAfterSync 只写对方一份。
import type { SyncRecord } from '../model/SyncModels';
import type { ITransport } from './ITransport';

function cloneTables(t: Map<string, SyncRecord[]>): Map<string, SyncRecord[]> {
  const out: Map<string, SyncRecord[]> = new Map();
  t.forEach((recs: SyncRecord[], name: string) => {
    const copy: SyncRecord[] = [];
    for (const r of recs) {
      const c: SyncRecord = { key: r.key, updateTime: r.updateTime, deviceId: r.deviceId,
        isDeleted: r.isDeleted, payload: r.payload };
      copy.push(c);
    }
    out.set(name, copy);
  });
  return out;
}

export class LoopbackAdapter implements ITransport {
  // profiles[X]：X 的对端（=对方身份）在上一轮同步时的档案快照。
  // 只在对方 exchange 时写入（播种）或 notifyAfterSync 后收敛，从不被本机覆写。
  private profiles: Map<string, Map<string, SyncRecord[]>> = new Map();

  private static peerOf(deviceId: string): string {
    return deviceId === 'deviceA' ? 'deviceB' : 'deviceA';
  }

  // 该身份是否已和对端交换过档案（首轮同步前为 false，UI 可据此提示先各改一次）
  hasPeerProfile(deviceId: string): boolean {
    return this.profiles.has(deviceId);
  }

  async exchange(deviceId: string, local: Map<string, SyncRecord[]>): Promise<Map<string, SyncRecord[]>> {
    // 先把本机当前档案留给对端：对端下一轮同步时，exchange 取到的就是它
    this.profiles.set(LoopbackAdapter.peerOf(deviceId), cloneTables(local));
    const theirs = this.profiles.get(deviceId);
    if (theirs === undefined) {
      // 首次同步：对端档案尚未建立，按空档案合并（本机数据全量保留）
      const empty: Map<string, SyncRecord[]> = new Map();
      local.forEach((_v: SyncRecord[], name: string) => { empty.set(name, []); });
      return empty;
    }
    return cloneTables(theirs);
  }

  async notifyAfterSync(deviceId: string, finalTables: Map<string, SyncRecord[]>): Promise<void> {
    // 只写对方：本机档案由 runSync 的 applyMerged 落库，此处不再覆写本机袋。
    // 若也写本机袋，本机下次 sync 会取到「已收敛的自己」，冲突记录不再产生。
    this.profiles.set(LoopbackAdapter.peerOf(deviceId), cloneTables(finalTables));
  }

  // 重置仿真档案（退出演示 / 切换模式时调用），避免跨轮次残留旧快照
  reset(): void {
    this.profiles.clear();
  }
}

// 演示期常驻单例：跨页面保留双档案，避免返回再进就丢对端快照
export const LOOPBACK: LoopbackAdapter = new LoopbackAdapter();
