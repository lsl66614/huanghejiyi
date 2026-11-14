// entry/src/main/ets/repository/SoftBusRdbTransport.ets —— F3 真机分布式传输（软总线 + 分布式 RDB）
// 与合并算法解耦：SyncScheduler 只认 ITransport；本类负责 deviceManager 选设备
// → remoteQuery 拉远端快照 → 合并落库 → notifyAfterSync PUSH 终态。
// 任一环节失败直接抛错，由 SyncPage 捕获并回落到 LoopbackAdapter 仿真，页面永不因此崩溃。
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import type { SyncRecord } from '../model/SyncModels';
import type { IDataRepository } from './IDataRepository';
import type { ITransport } from './ITransport';

const BUNDLE_NAME: string = 'com.example.huanghememory';

export class SoftBusRdbTransport implements ITransport {
  private repo: IDataRepository;
  private dm: distributedDeviceManager.DeviceManager | null = null;

  // context 仅用于与仿真构造形式对齐、未来挂组网回调；当前选设备/同步均走 repo
  constructor(_context: Object, repo: IDataRepository) {
    this.repo = repo;
  }

  // createDeviceManager 在 API 26 为同步签名，失败以异常抛出
  private deviceManager(): distributedDeviceManager.DeviceManager {
    if (this.dm === null) {
      this.dm = distributedDeviceManager.createDeviceManager(BUNDLE_NAME);
    }
    return this.dm;
  }

  // 选取第一台可信组网设备；无设备时给出可操作的错误信息
  private firstNetworkId(): string {
    let dm: distributedDeviceManager.DeviceManager;
    try {
      dm = this.deviceManager();
    } catch (e) {
      throw new Error(`设备管理初始化失败：${e instanceof Error ? e.message : String(e)}`);
    }
    let list: distributedDeviceManager.DeviceBasicInfo[] = [];
    try {
      list = dm.getAvailableDeviceListSync();
    } catch (e) {
      throw new Error(`设备列表获取失败：${e instanceof Error ? e.message : String(e)}`);
    }
    const first: distributedDeviceManager.DeviceBasicInfo | undefined = list[0];
    // networkId 在 DeviceBasicInfo 中为可选字段，逐层显式判空
    const rawId: string | undefined = first === undefined ? undefined : first.networkId;
    const networkId: string = rawId === undefined ? '' : rawId;
    if (networkId === '') {
      throw new Error('未发现在线可信设备：需两台真机登录同一华为账号、接入同一局域网并完成组网认证');
    }
    return networkId;
  }

  async exchange(_deviceId: string, _local: Map<string, SyncRecord[]>): Promise<Map<string, SyncRecord[]>> {
    await this.repo.enableDistributed();
    const networkId = this.firstNetworkId();
    // 先拉后推。若先 PUSH，本机旧值可能在对端 RDB 里覆盖较新的行，
    // 等 remoteQuery 再读时冲突已经被抹平，合并引擎只能看到一份“和平”的快照。
    // 正确顺序：拉远端快照 → runSync 合并落库 → notifyAfterSync 推终态。
    return this.repo.remoteSnapshot(networkId);
  }

  async notifyAfterSync(_deviceId: string, _finalTables: Map<string, SyncRecord[]>): Promise<void> {
    // 合并终态已 applyMerged 到本机库，再 PUSH 让对端收敛。
    // 注意：这是「拉 → 合并 → 推」三步，不是分布式事务。若对端在
    // remoteQuery 之后、PUSH 之前又写了新行，仍可能被这次 PUSH 覆盖。
    // 本版不做二次拉取或向量时钟，这是已知的窄窗口竞态。
    if (this.dm === null) { return; }
    const networkId = this.firstNetworkId();
    await this.repo.pushToDevices([networkId]);
  }
}
