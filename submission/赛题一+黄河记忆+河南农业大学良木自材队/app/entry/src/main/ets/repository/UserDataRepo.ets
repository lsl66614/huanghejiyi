// entry/src/main/ets/repository/UserDataRepo.ets
import { common } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { FavoriteDO, FavoriteTagDO, NoteDO, NoteView, ProgressDO, TagDO, VisitDO, RecoFeedbackDO, PRESET_TAGS } from '../model/UserDataModels';
import { LocalRdbImpl } from './LocalRdbImpl';
import { whenBootGate } from '../service/sync/BootGate';
import type { IDataRepository } from './IDataRepository';

export class UserDataRepo {
  private static impl: IDataRepository | null = null;
  private static deviceId: string = '';
  private static lastVisitAt: Map<string, number> = new Map();
  private static readonly VISIT_THROTTLE_MS: number = 60000;
  // init 进行中的共享 Promise：首页与「我的」页会并发调 get()，
  // 而 impl 只在 init 完成后才赋值。两边都往下走会各自 new 一个 LocalRdbImpl，
  // 两个实例同时对同一批表跑迁移/建表 —— 实测表现为 hilog 里 db ready 打两遍，
  // 且其中一个实例的 DROP TABLE 把另一个刚搬完的数据删掉（2026-10-11 真机踩到）。
  private static pending: Promise<IDataRepository> | null = null;
  // 仿真模式：两个身份各自的独立档案（各一个 RDBStore，数据真正分离）。
  // simActive 为 true 时，所有读写都走 simRepos[currentSim]，主库 impl 不再被访问。
  private static simActive: boolean = false;
  private static currentSim: string = 'deviceA';
  private static simRepos: Map<string, IDataRepository> = new Map();
  private static simPending: Map<string, Promise<IDataRepository>> = new Map();

  static async get(context: common.UIAbilityContext): Promise<IDataRepository> {
    // 首屏不再等数据库初始化，同步模式改在后台恢复（见 BootGate）。
    // 页面所有读写都要经过这里，所以闸门放在最前面：模式没就绪就不给库，
    // 避免「先读主库、模式切到仿真档案后又没重读」的数据错配。
    await whenBootGate();
    if (UserDataRepo.simActive) { return await UserDataRepo.simRepoOf(context, UserDataRepo.currentSim); }
    if (UserDataRepo.impl !== null) { return UserDataRepo.impl; }
    if (UserDataRepo.pending !== null) { return UserDataRepo.pending; }
    UserDataRepo.pending = UserDataRepo.createRepo(context);
    try {
      return await UserDataRepo.pending;
    } finally {
      UserDataRepo.pending = null;
    }
  }

  private static async createRepo(context: common.UIAbilityContext): Promise<IDataRepository> {
    const rdb = new LocalRdbImpl();
    await rdb.init(context);
    UserDataRepo.impl = rdb;
    return rdb;
  }

  // 仿真档案：按身份 lazy 建独立库，建过一次就复用，避免重复跑迁移。
  private static async simRepoOf(context: common.UIAbilityContext,
    deviceId: string): Promise<IDataRepository> {
    const done = UserDataRepo.simRepos.get(deviceId);
    if (done !== undefined) { return done; }
    const inflight = UserDataRepo.simPending.get(deviceId);
    if (inflight !== undefined) { return inflight; }
    const p = (async (): Promise<IDataRepository> => {
      const rdb = new LocalRdbImpl();
      await rdb.initAs(context, LocalRdbImpl.simStoreName(deviceId));
      UserDataRepo.simRepos.set(deviceId, rdb);
      return rdb;
    })();
    UserDataRepo.simPending.set(deviceId, p);
    try {
      return await p;
    } finally {
      UserDataRepo.simPending.delete(deviceId);
    }
  }

  // 进入/退出仿真模式。进入时当前身份固定为 deviceA；
  // 退出时读写的都是主库（真机档案），与仿真库互不干扰。
  static async setSimMode(context: common.UIAbilityContext, on: boolean): Promise<void> {
    if (on) {
      UserDataRepo.currentSim = 'deviceA';
      UserDataRepo.simActive = true;
      await UserDataRepo.simRepoOf(context, 'deviceA');
      return;
    }
    UserDataRepo.simActive = false;
  }

  // 仿真身份切换：只切当前库，不写任何元数据——两份档案本就该各自独立。
  static async switchSimIdentity(context: common.UIAbilityContext, deviceId: string): Promise<void> {
    if (!UserDataRepo.simActive) { return; }
    await UserDataRepo.simRepoOf(context, deviceId);
    UserDataRepo.currentSim = deviceId;
    UserDataRepo.deviceId = deviceId;
  }

  // 同步模式的元数据必须存在主库：仿真模式打开后 get() 会返回仿真档案，
  // 如果照着 get() 写，模式会落到当前仿真身份里，重启读主库时又变回默认值。
  // 所以这里绕开 simActive，显式拿主库。
  private static async mainRepo(context: common.UIAbilityContext): Promise<IDataRepository> {
    if (UserDataRepo.impl !== null) { return UserDataRepo.impl; }
    if (UserDataRepo.pending !== null) { return UserDataRepo.pending; }
    UserDataRepo.pending = UserDataRepo.createRepo(context);
    try {
      return await UserDataRepo.pending;
    } finally {
      UserDataRepo.pending = null;
    }
  }

  // '' = 用户从未选过（保持旧行为：冷启动读主库、自动同步关闭）
  static async readSyncMode(context: common.UIAbilityContext): Promise<string> {
    const repo = await UserDataRepo.mainRepo(context);
    const m = await repo.getMeta('syncMode');
    if (m === 'real' || m === 'sim') { return m; }
    return '';
  }

  static async writeSyncMode(context: common.UIAbilityContext, mode: string): Promise<void> {
    const repo = await UserDataRepo.mainRepo(context);
    await repo.setMeta('syncMode', mode === 'real' ? 'real' : 'sim');
  }

  // 真机分布式下，对端推来变更 → 驱动一次合并。
  // 必须走 mainRepo：get() 会等 BootGate 放行，而 prepare 阶段闸门还没开，
  // 用 get() 就成了自锁（见 AutoSync.prepare 的顺序说明）。
  static async installRemoteChangeHook(context: common.UIAbilityContext,
    hook: () => void): Promise<void> {
    const repo = await UserDataRepo.mainRepo(context);
    repo.setRemoteChangeHook(hook);
  }

  // 设备面板：当前真正在读写的库文件。仿真下是某一身份的那一份，真机下是主库。
  static storeName(): string {
    if (UserDataRepo.simActive) {
      return LocalRdbImpl.simStoreName(UserDataRepo.currentSim);
    }
    return LocalRdbImpl.mainStoreName();
  }

  // 设备名与系统版本：两台真机并排演示时，用户要能确认「这一台是哪一台」。
  // 市场名不是所有设备都有，取不到就退到设备类型，不把面板留成空白。
  static deviceProfile(): string {
    try {
      const m: string = deviceInfo.marketName;
      if (m !== '' && m !== 'Unknown') { return m; }
    } catch (_e) {
      // 取不到市场名不算异常：继续往下退。
    }
    try {
      return deviceInfo.deviceType;
    } catch (_e) {
      return '鸿蒙设备';
    }
  }

  static systemProfile(): string {
    try {
      return `${deviceInfo.osFullName} · API ${deviceInfo.sdkApiVersion}`;
    } catch (_e) {
      return '';
    }
  }

  static async deviceIdOf(context: common.UIAbilityContext): Promise<string> {    if (UserDataRepo.simActive) { return UserDataRepo.currentSim; }
    if (UserDataRepo.deviceId !== '') { return UserDataRepo.deviceId; }
    const repo = await UserDataRepo.get(context);
    let saved = await repo.getMeta('deviceId');
    if (saved === '') {
      let raw = '';
      try {
        raw = deviceInfo.ODID;
      } catch (e) {
        raw = '';
      }
      saved = raw !== '' ? `oh-${raw.substring(0, 8)}` : 'deviceA';
      await repo.setMeta('deviceId', saved);
    }
    UserDataRepo.deviceId = saved;
    return saved;
  }

  static async toggleFavorite(context: common.UIAbilityContext, targetKey: string): Promise<boolean> {
    const repo = await UserDataRepo.get(context);
    // 版本号走存储层的单调时钟：同一毫秒内「取消收藏 → 再收藏」若取到相同
    // 时间戳，LWW 会退到 deviceId 字典序，可能让墓碑赢，用户看到的是点了没反应。
    const now = await repo.nextWriteTime();
    const dev = await UserDataRepo.deviceIdOf(context);
    const list = await repo.listFavorites();
    const exists = list.some((f: FavoriteDO): boolean => f.targetKey === targetKey);
    if (exists) {
      await repo.deleteFavorite(targetKey, dev, now);
      return false;
    }
    const fav = new FavoriteDO();
    fav.targetKey = targetKey;
    fav.createTime = now;
    fav.updateTime = now;
    fav.deviceId = dev;
    fav.isDeleted = false;
    await repo.upsertFavorite(fav);
    return true;
  }

  static async isFavored(context: common.UIAbilityContext, targetKey: string): Promise<boolean> {
    const repo = await UserDataRepo.get(context);
    const list = await repo.listFavorites();
    return list.some((f: FavoriteDO): boolean => f.targetKey === targetKey);
  }

  static async listFavoritesOf(context: common.UIAbilityContext): Promise<FavoriteDO[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listFavorites();
  }

  // 最近删除：只取 30 天内的墓碑行。窗口由调用方传 since（毫秒），
  // 与页面上的“保留 30 天”文案同源，避免两处各写一个常量。
  static async deletedFavorites(context: common.UIAbilityContext,
    since: number): Promise<FavoriteDO[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listDeletedFavorites(since);
  }

  static async restoreFavorite(context: common.UIAbilityContext, targetKey: string): Promise<void> {
    const repo = await UserDataRepo.get(context);
    const dev = await UserDataRepo.deviceIdOf(context);
    await repo.restoreFavorite(targetKey, dev, await repo.nextWriteTime());
  }

  static async restoreNote(context: common.UIAbilityContext, noteId: string): Promise<void> {
    const repo = await UserDataRepo.get(context);
    const dev = await UserDataRepo.deviceIdOf(context);
    await repo.restoreNote(noteId, dev, await repo.nextWriteTime());
  }

  // F2：给收藏条目贴标签（全量覆盖该条目的标签集合）
  static async assignFavoriteTags(context: common.UIAbilityContext, targetKey: string,
    tagIds: string[]): Promise<void> {
    const repo = await UserDataRepo.get(context);
    const dev = await UserDataRepo.deviceIdOf(context);
    await repo.setFavoriteTags(targetKey, tagIds, await repo.nextWriteTime(), dev);
  }

  static async tagsOfFavorite(context: common.UIAbilityContext, targetKey: string): Promise<string[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listFavoriteTags(targetKey);
  }

  static async favoriteTagRows(context: common.UIAbilityContext): Promise<FavoriteTagDO[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listFavoriteTagRows();
  }

  // 导出用：标签定义整行（含版本号），不只是名字。名字清单 (allTags) 不足以
  // 在另一台设备上按原版本重建，LWW 会被重新盖章盖乱。
  static async allTagRows(context: common.UIAbilityContext): Promise<TagDO[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listTags();
  }

  // F1：学习进度全量（首页年代完成度环）
  static async allProgress(context: common.UIAbilityContext): Promise<ProgressDO[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listProgress();
  }

  // F5：浏览埋点（同条目 60s 节流）；仅本机缓存，不进同步域
  static async trackVisit(context: common.UIAbilityContext, targetKey: string): Promise<void> {
    const now = Date.now();
    const last = UserDataRepo.lastVisitAt.get(targetKey);
    if (last !== undefined && now - last < UserDataRepo.VISIT_THROTTLE_MS) { return; }
    UserDataRepo.lastVisitAt.set(targetKey, now);
    const repo = await UserDataRepo.get(context);
    await repo.upsertVisit(targetKey, now);
  }

  static async recentVisits(context: common.UIAbilityContext, limit: number): Promise<VisitDO[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listRecentVisits(limit);
  }

  // 冷启动偏好存 meta：它是一段小 JSON，不参与同步，也不值得单开一张表。
  static async readRecoPrefs(context: common.UIAbilityContext): Promise<string> {
    const repo = await UserDataRepo.get(context);
    return repo.getMeta('recoPrefs');
  }

  static async writeRecoPrefs(context: common.UIAbilityContext, json: string): Promise<void> {
    const repo = await UserDataRepo.get(context);
    await repo.setMeta('recoPrefs', json);
  }

  // 回顾搁置记录（id|until 纯文本行）。与 recoPrefs 同样只存本机 meta：
  // 它是「我今天不想看这条」的临时态度，不该随笔记一起同步到另一台设备。
  static async readReviewState(context: common.UIAbilityContext): Promise<string> {
    const repo = await UserDataRepo.get(context);
    return repo.getMeta('reviewDismissed');
  }

  static async writeReviewState(context: common.UIAbilityContext, raw: string): Promise<void> {
    const repo = await UserDataRepo.get(context);
    await repo.setMeta('reviewDismissed', raw);
  }

  // 负反馈只写本地库。仿真模式下 get() 会落到当前仿真档案——
  // 两份演示档案各自有各自的口味，这是预期行为。
  static async addRecoFeedback(context: common.UIAbilityContext, key: string,
    reason: string): Promise<void> {
    const repo = await UserDataRepo.get(context);
    const fb = new RecoFeedbackDO();
    fb.key = key;
    fb.reason = reason;
    fb.createTime = Date.now();
    await repo.upsertRecoFeedback(fb);
  }

  static async recoFeedback(context: common.UIAbilityContext): Promise<RecoFeedbackDO[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listRecoFeedback();
  }

  // 演示模式切换身份：仿真下切到另一份独立档案；真机下只改本机 deviceId 标签
  static async setDeviceId(context: common.UIAbilityContext, deviceId: string): Promise<void> {
    if (UserDataRepo.simActive) {
      await UserDataRepo.switchSimIdentity(context, deviceId);
      return;
    }
    const repo = await UserDataRepo.get(context);
    await repo.setMeta('deviceId', deviceId);
    UserDataRepo.deviceId = deviceId;
  }

  static async notesOf(context: common.UIAbilityContext, targetKey: string): Promise<NoteView[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listNotesOf(targetKey);
  }

  static async allNotes(context: common.UIAbilityContext): Promise<NoteView[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listAllNotes();
  }

  static async deletedNotes(context: common.UIAbilityContext, since: number): Promise<NoteView[]> {
    const repo = await UserDataRepo.get(context);
    return repo.listDeletedNotes(since);
  }

  // 标签全集 = 预置三标签 + 用户自建（tag 表）
  static async allTags(context: common.UIAbilityContext): Promise<string[]> {
    const repo = await UserDataRepo.get(context);
    const out: string[] = PRESET_TAGS.slice();
    const tags = await repo.listTags();
    for (const t of tags) {
      if (!out.includes(t.name)) { out.push(t.name); }
    }
    return out;
  }

  // 自建标签即时落库：写 tag 表并纳入同步域，避免仅存在于页面内存、重启即失。
  // tag 表同样有 deviceId：时间戳平局时按设备号字典序裁决，不能缺列。
  static async ensureTag(context: common.UIAbilityContext, name: string): Promise<void> {
    const label = name.trim();
    if (label === '') { return; }
    const repo = await UserDataRepo.get(context);
    const existing = await repo.listTags();
    if (existing.some((t: TagDO): boolean => t.name === label)) { return; }
    const dev = await UserDataRepo.deviceIdOf(context);
    const tag = new TagDO();
    tag.tagId = label;
    tag.name = label;
    tag.isPreset = PRESET_TAGS.includes(label);
    tag.updateTime = await repo.nextWriteTime();
    tag.isDeleted = false;
    tag.deviceId = dev;
    await repo.upsertTag(tag);
  }

  // 「已研读」勾选落库。设计稿 §4.2 是显式勾选，故必须支持取消：
  // 取消写 done=0 而不是删行——删行会让对端把它当成「从未标记」，
  // 同步时无法表达「我刚刚把已读改回未读」这次编辑。
  static async setSectionRead(context: common.UIAbilityContext, targetKey: string,
    section: string, done: boolean): Promise<void> {
    const repo = await UserDataRepo.get(context);
    const dev = await UserDataRepo.deviceIdOf(context);
    const p = new ProgressDO();
    p.targetKey = targetKey;
    p.section = section;
    p.done = done;
    p.updateTime = await repo.nextWriteTime();
    p.deviceId = dev;
    await repo.upsertProgress(p);
  }

  // noteId 为空 → 新建；否则改写（保留 createTime，刷新 updateTime）
  static async saveNote(context: common.UIAbilityContext, targetKey: string, text: string,
    tagIds: string[], noteId: string): Promise<string> {
    const repo = await UserDataRepo.get(context);
    const now = await repo.nextWriteTime();
    const dev = await UserDataRepo.deviceIdOf(context);
    const id = noteId !== '' ? noteId
      : `n${now.toString(36)}${Math.floor(Math.random() * 1e4).toString(36)}`;
    let createTime = now;
    if (noteId !== '') {
      const old = await repo.listNotesOf(targetKey);
      for (const o of old) {
        if (o.noteId === noteId) { createTime = o.createTime; break; }
      }
    }
    const note = new NoteDO();
    note.noteId = id;
    note.targetKey = targetKey;
    note.text = text;
    note.createTime = createTime;
    note.updateTime = now;
    note.deviceId = dev;
    note.isDeleted = false;
    await repo.upsertNote(note);
    await repo.setNoteTags(id, tagIds, now, dev);
    return id;
  }

  // 把一条笔记从当前 target 移到另一个遗址/文物。
  // note_id 不变，只改 target_key；同步仍按行收敛，不会多出一条。
  // 不重写 note_tag：标签关联挂在 note_id 上，与 target 无关。
  static async moveNote(context: common.UIAbilityContext, noteId: string,
    targetKey: string): Promise<void> {
    const repo = await UserDataRepo.get(context);
    const all = await repo.listAllNotes();
    let old: NoteView | null = null;
    for (const n of all) {
      if (n.noteId === noteId) {
        old = n;
        break;
      }
    }
    if (old === null || old.targetKey === targetKey || targetKey === '') { return; }
    const dev = await UserDataRepo.deviceIdOf(context);
    const note = new NoteDO();
    note.noteId = old.noteId;
    note.targetKey = targetKey;
    note.text = old.text;
    note.createTime = old.createTime;
    note.updateTime = await repo.nextWriteTime();
    note.deviceId = dev;
    note.isDeleted = false;
    await repo.upsertNote(note);
  }

  static async removeNote(context: common.UIAbilityContext, noteId: string): Promise<void> {
    const repo = await UserDataRepo.get(context);
    const dev = await UserDataRepo.deviceIdOf(context);
    await repo.deleteNote(noteId, dev, await repo.nextWriteTime());
  }
}
