// entry/src/main/ets/repository/ITransport.ets —— 纯类型，禁 @kit
import type { SyncRecord } from '../model/SyncModels';

export interface ITransport {
  // 返回对端（或对方设备档案）的五表快照
  exchange(deviceId: string, local: Map<string, SyncRecord[]>): Promise<Map<string, SyncRecord[]>>;
  // 合并完成后回写，使下一轮对端能看到本轮终态（收敛语义）
  notifyAfterSync(deviceId: string, finalTables: Map<string, SyncRecord[]>): Promise<void>;
}
