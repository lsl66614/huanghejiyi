// entry/src/ohosTest/ets/test/MergeEngine.test.ets —— T8：MergeEngine 纯函数用例
// 对应 Node 侧 tools/merge-tests/merge_engine.test.mjs 的核心断言，保证 ArkTS 侧语义一致
import { describe, it, expect } from '@ohos/hypium';
import { mergeElementSets, appendConflictLog } from '../../main/ets/service/merge/MergeEngine';
import type { SyncRecord, ConflictVersion } from '../../main/ets/model/SyncModels';

function rec(key: string, t: number, dev: string, del: boolean): SyncRecord {
  const payload: Record<string, string | number | boolean> = { text: 'v' };
  const r: SyncRecord = { key: key, updateTime: t, deviceId: dev, isDeleted: del, payload: payload };
  return r;
}

export default function mergeEngineTest() {
  describe('MergeEngine', () => {
    it('single_side_included_no_conflict', 0, () => {
      const local: SyncRecord[] = [rec('note:1', 100, 'devA', false)];
      const remote: SyncRecord[] = [rec('note:2', 200, 'devB', false)];
      const result = mergeElementSets(local, remote);
      expect(result.finalRecords.length).assertEqual(2);
      expect(result.conflicts.length).assertEqual(0);
    })

    it('newer_updateTime_wins_and_conflict_logged', 0, () => {
      const local: SyncRecord[] = [rec('note:1', 100, 'devA', false)];
      const remote: SyncRecord[] = [rec('note:1', 200, 'devB', false)];
      const result = mergeElementSets(local, remote);
      expect(result.finalRecords.length).assertEqual(1);
      expect(result.finalRecords[0].updateTime).assertEqual(200);
      expect(result.conflicts.length).assertEqual(1);
      expect(result.conflicts[0].reason).assertEqual('updateTime');
      // 败方版本快照可见（设计方案 §6.2：保留败方版本供回看）
      const loser: ConflictVersion = result.conflicts[0].loser;
      expect(loser.updateTime).assertEqual(100);
      expect(loser.deviceId).assertEqual('devA');
    })

    it('tie_break_by_deviceId_lexicographic', 0, () => {
      const local: SyncRecord[] = [rec('note:1', 100, 'devB', false)];
      const remote: SyncRecord[] = [rec('note:1', 100, 'devA', false)];
      const result = mergeElementSets(local, remote);
      expect(result.finalRecords[0].deviceId).assertEqual('devB');
      expect(result.conflicts[0].reason).assertEqual('tie_break_deviceId');
    })

    it('identical_records_no_conflict', 0, () => {
      const local: SyncRecord[] = [rec('note:1', 100, 'devA', false)];
      const remote: SyncRecord[] = [rec('note:1', 100, 'devA', false)];
      const result = mergeElementSets(local, remote);
      expect(result.finalRecords.length).assertEqual(1);
      expect(result.conflicts.length).assertEqual(0);
    })

    it('tombstone_vs_older_alive_tombstone_wins', 0, () => {
      // 设计方案 §6.2：单方墓碑(isDeleted=1) 而对方为存活 → 仍按时间戳裁决（删除是最后一次编辑）
      const local: SyncRecord[] = [rec('note:1', 300, 'devA', true)];
      const remote: SyncRecord[] = [rec('note:1', 100, 'devB', false)];
      const result = mergeElementSets(local, remote);
      expect(result.finalRecords[0].isDeleted).assertTrue();
      expect(result.conflicts.length).assertEqual(1);
    })

    it('finals_sorted_by_key', 0, () => {
      const local: SyncRecord[] = [rec('note:2', 100, 'devA', false), rec('note:1', 100, 'devA', false)];
      const remote: SyncRecord[] = [];
      const result = mergeElementSets(local, remote);
      expect(result.finalRecords[0].key).assertEqual('note:1');
      expect(result.finalRecords[1].key).assertEqual('note:2');
    })

    it('appendConflictLog_caps_and_keeps_latest', 0, () => {
      let log: string = '[]';
      for (let i = 1; i <= 5; i++) {
        const entry = mergeElementSets(
          [rec(`note:${i}`, 100, 'devA', false)],
          [rec(`note:${i}`, 200, 'devB', false)]
        );
        log = appendConflictLog(log, entry.conflicts, 3);
      }
      const arr = JSON.parse(log) as Array<Record<string, string>>;
      expect(Array.isArray(arr)).assertTrue();
      expect(arr.length).assertEqual(3);
      // 滚动窗口保留最新 3 条：note:3/4/5
      expect(arr[0]['key'] as string).assertEqual('note:3');
    })

    it('appendConflictLog_bad_json_starts_empty', 0, () => {
      const entry = mergeElementSets(
        [rec('note:1', 100, 'devA', false)],
        [rec('note:1', 200, 'devB', false)]
      );
      const log: string = appendConflictLog('not-json{{', entry.conflicts, 50);
      const arr = JSON.parse(log) as Array<Record<string, string>>;
      expect(Array.isArray(arr)).assertTrue();
      expect(arr.length).assertEqual(1);
    })
  })
}