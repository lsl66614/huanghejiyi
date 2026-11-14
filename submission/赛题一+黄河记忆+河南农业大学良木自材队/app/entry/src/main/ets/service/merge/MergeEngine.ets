// entry/src/main/ets/service/merge/MergeEngine.ets —— 纯函数，禁 @kit
import type { SyncRecord, ConflictVersion, ConflictEntry, MergeResult } from '../../model/SyncModels';

function toVersion(r: SyncRecord): ConflictVersion {
  const v: ConflictVersion = {
    updateTime: r.updateTime, deviceId: r.deviceId,
    isDeleted: r.isDeleted, payload: r.payload
  };
  return v;
}

export function mergeElementSets(local: SyncRecord[], remote: SyncRecord[],
  table: string = ''): MergeResult {
  const localMap: Map<string, SyncRecord> = new Map();
  for (const r of local) { localMap.set(r.key, r); }
  const remoteMap: Map<string, SyncRecord> = new Map();
  for (const r of remote) { remoteMap.set(r.key, r); }
  const finals: SyncRecord[] = [];
  const conflicts: ConflictEntry[] = [];
  const keys: Set<string> = new Set();
  localMap.forEach((_v: SyncRecord, k: string) => { keys.add(k); });
  remoteMap.forEach((_v: SyncRecord, k: string) => { keys.add(k); });
  keys.forEach((k: string) => {
    const a: SyncRecord | undefined = localMap.get(k);
    const b: SyncRecord | undefined = remoteMap.get(k);
    if (a === undefined) {
      if (b !== undefined) { finals.push(b); }
      return;
    }
    if (b === undefined) { finals.push(a); return; }
    if (a.updateTime === b.updateTime && a.deviceId === b.deviceId && a.isDeleted === b.isDeleted) {
      finals.push(a); return;
    }
    let winner: SyncRecord = a;
    let reason: string = 'updateTime';
    if (a.updateTime === b.updateTime) {
      winner = a.deviceId > b.deviceId ? a : b;
      reason = 'tie_break_deviceId';
    } else {
      winner = a.updateTime > b.updateTime ? a : b;
    }
    const loser: SyncRecord = winner === a ? b : a;
    finals.push(winner);
    const entry: ConflictEntry = { key: k, table: table, winner: toVersion(winner), loser: toVersion(loser), reason: reason };
    conflicts.push(entry);
  });
  finals.sort((m: SyncRecord, n: SyncRecord): number => m.key < n.key ? -1 : (m.key > n.key ? 1 : 0));
  const result: MergeResult = { finalRecords: finals, conflicts: conflicts };
  return result;
}

export function appendConflictLog(existingJson: string, entries: ConflictEntry[], cap: number): string {
  let log: ConflictEntry[] = [];
  try {
    const parsed: ConflictEntry[] | null = JSON.parse(existingJson) as ConflictEntry[] | null;
    if (Array.isArray(parsed)) { log = parsed; } // 非数组（如 '{}'、'"str"'）按空日志处理
  } catch (e) {
    log = [];
  }
  for (const x of entries) { log.push(x); }
  if (log.length > cap) { log = log.slice(log.length - cap); }
  return JSON.stringify(log);
}
