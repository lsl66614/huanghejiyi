// entry/src/main/ets/repository/IDataRepository.ets —— 纯类型，禁 @kit
import type { SyncRecord } from '../model/SyncModels';
import type { FavoriteDO, FavoriteTagDO, NoteDO, NoteView, TagDO, ProgressDO, VisitDO, RecoFeedbackDO } from '../model/UserDataModels';

export interface IDataRepository {
  init(context: ESObject): Promise<void>;
  // 本次写入应使用的时间戳（单调逻辑时钟，见 service/merge/LogicalClock）。
  // 所有会进入同步域的写操作都必须取这里的时间，不能直接用 Date.now()：
  // 同一毫秒内连写两次会拿到相同时间戳，LWW 平局改按 deviceId 字典序裁决，
  // 与「谁后写」的因果无关；设备时钟被回拨时，该设备之后的编辑会全部输给对端。
  nextWriteTime(): Promise<number>;
  // 把外部来源（同步合并、档案导入）见过的最大版本号吸收进本机单调时钟：
  // 本机时钟若慢于外部，吸收后自己的下一笔写入仍严格大于外部内容，
  // 不会一写就输。见 LocalRdbImpl.observeSyncedTime 与档案导入（ExportPage）。
  observeExternalTime(updateTime: number): Promise<void>;
  // F3 真机分布式：注册同步域表 / PUSH 推送 / 远端快照查询（模拟器上会失败，调用方必须回落）
  enableDistributed(): Promise<void>;
  /** 注册「对端推送来了变更」的通知；注入方负责节流，实现方只负责转发 */
  setRemoteChangeHook(hook: () => void): void;
  pushToDevices(networkIds: string[]): Promise<void>;
  remoteSnapshot(networkId: string): Promise<Map<string, SyncRecord[]>>;
  snapshotSyncTables(): Promise<Map<string, SyncRecord[]>>;
  applyMerged(table: string, records: SyncRecord[]): Promise<void>;
  getMeta(key: string): Promise<string>;
  setMeta(key: string, value: string): Promise<void>;
  upsertFavorite(fav: FavoriteDO): Promise<void>;
  deleteFavorite(targetKey: string, deviceId: string, now: number): Promise<void>;
  listFavorites(): Promise<FavoriteDO[]>;
  // 最近删除（30 天回收站）：只读墓碑行，恢复时把 isDeleted 翻回 0。
  listDeletedFavorites(since: number): Promise<FavoriteDO[]>;
  listDeletedNotes(since: number): Promise<NoteView[]>;
  restoreFavorite(targetKey: string, deviceId: string, now: number): Promise<void>;
  restoreNote(noteId: string, deviceId: string, now: number): Promise<void>;
  // 收藏-标签分类（赛题 F2：按标签管理收藏内容；纳入同步域）
  setFavoriteTags(targetKey: string, tagIds: string[], now: number, deviceId: string): Promise<void>;
  listFavoriteTags(targetKey: string): Promise<string[]>;
  listFavoriteTagRows(): Promise<FavoriteTagDO[]>;
  // 学习进度（首页年代完成度环用）
  listProgress(): Promise<ProgressDO[]>;
  // 浏览行为（仅本机缓存，不进同步域）
  upsertVisit(targetKey: string, now: number): Promise<void>;
  listRecentVisits(limit: number): Promise<VisitDO[]>;
  // 推荐负反馈（仅本机缓存，不进同步域、不进快照）
  upsertRecoFeedback(fb: RecoFeedbackDO): Promise<void>;
  listRecoFeedback(): Promise<RecoFeedbackDO[]>;
  upsertNote(note: NoteDO): Promise<void>;
  listNotesOf(targetKey: string): Promise<NoteView[]>;
  listAllNotes(): Promise<NoteView[]>;
  deleteNote(noteId: string, deviceId: string, now: number): Promise<void>;
  listTags(): Promise<TagDO[]>;
  setNoteTags(noteId: string, tagIds: string[], now: number, deviceId: string): Promise<void>;
  upsertTag(tag: TagDO): Promise<void>;
  upsertProgress(p: ProgressDO): Promise<void>;
}
