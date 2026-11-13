// entry/src/main/ets/service/sync/SyncScheduler.ets —— 禁 @kit
//
// 本文件在 tools/merge-tests 下会被转译成 .ts 由 Node 直接执行（scheduler.test.mjs），
// 所以不能 import @kit：日志一律不在这里打，进度经 onProgress 回调交给页面。
// 早先这里有一串 console.info('P8 ...') 的调试输出，既不进 hilog 体系，
// release 包里也无法按模块关闭，已删除。
import type { SyncRecord, ConflictEntry } from '../../model/SyncModels';
import { SYNC_TABLES } from '../../model/SyncModels';
import { mergeElementSets, appendConflictLog } from '../merge/MergeEngine';
import type { IDataRepository } from '../../repository/IDataRepository';
import type { ITransport } from '../../repository/ITransport';

export type ProgressCallback = (table: string, done: number, total: number) => void;

// paceMs：每张表之间额外停顿的毫秒数，**只给演示用**。
// 同步面板要让人看清进度条一格一格推进，所以手动同步会传 260ms；
// 自动同步（网络恢复后后台补跑）传 0 或省略——让用户等 1.5 秒空转没有意义。
export async function runSync(deviceId: string, repo: IDataRepository,
  transport: ITransport, onProgress?: ProgressCallback,
  paceMs?: number): Promise<ConflictEntry[]> {
  const pace: number = paceMs === undefined ? 0 : Math.max(0, paceMs);
  const local = await repo.snapshotSyncTables();
  const remote = await transport.exchange(deviceId, local);
  let allConflicts: ConflictEntry[] = [];
  const finalTables: Map<string, SyncRecord[]> = new Map();
  let done = 0;
  for (const name of SYNC_TABLES) {
    const a: SyncRecord[] = local.get(name) ?? [];
    const b: SyncRecord[] = remote.get(name) ?? [];
    const merged = mergeElementSets(a, b, name);
    allConflicts = allConflicts.concat(merged.conflicts);
    finalTables.set(name, merged.finalRecords);
    await repo.applyMerged(name, merged.finalRecords);
    done = done + 1;
    if (onProgress !== undefined) { onProgress(name, done, SYNC_TABLES.length); }
    // 分表节奏停顿：仅演示模式下非 0（设计方案 §4.3「分批 yield 驱动进度动画」）
    if (pace > 0) {
      await new Promise<void>((resolve: () => void) => setTimeout(resolve, pace));
    }
  }
  await transport.notifyAfterSync(deviceId, finalTables);
  if (allConflicts.length > 0) {
    const oldLog: string = await repo.getMeta('conflictLogJson');
    await repo.setMeta('conflictLogJson', appendConflictLog(oldLog, allConflicts, 50));
  }
  await repo.setMeta('lastSyncTime', String(Date.now()));
  return allConflicts;
}
