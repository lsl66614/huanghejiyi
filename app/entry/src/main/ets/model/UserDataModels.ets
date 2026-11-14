// entry/src/main/ets/model/UserDataModels.ets
export class FavoriteDO {
  targetKey: string = '';   // 'site:{id}' | 'relic:{id}'
  createTime: number = 0;
  updateTime: number = 0;
  deviceId: string = '';
  isDeleted: boolean = false;
}

export class NoteDO {
  noteId: string = '';
  targetKey: string = '';   // 'site:{id}:intro' | 'site:{id}' | 'relic:{id}' …
  text: string = '';
  createTime: number = 0;
  updateTime: number = 0;
  deviceId: string = '';
  isDeleted: boolean = false;
}

export class TagDO {
  tagId: string = '';
  name: string = '';
  isPreset: boolean = false;
  updateTime: number = 0;
  isDeleted: boolean = false;
  deviceId: string = '';
}

export class ProgressDO {
  targetKey: string = '';
  section: string = '';     // 'intro'|'arch'|'events'|'poems'|'tourism'
  done: boolean = false;
  updateTime: number = 0;
  deviceId: string = '';
}

// 收藏-标签关系行（tag_id 沿用 note_tag 约定：直接存标签名）
export class FavoriteTagDO {
  targetKey: string = '';
  tagId: string = '';
  updateTime: number = 0;
}

// 浏览行为（本机缓存，不进同步域）：同条目重复浏览刷新 createTime 并置顶
export class VisitDO {
  targetKey: string = '';
  createTime: number = 0;
}

// 推荐负反馈（本机缓存，不进同步域）。
// key 是被抑制的对象：'site:{id}' 为单条，'era:{id}' / 'type:{id}' 为整类；
// reason 记原因（seen / dislike / era / type），供以后调权重时区分。
export class RecoFeedbackDO {
  key: string = '';
  reason: string = '';
  createTime: number = 0;
}

// 笔记视图：note 行 + note_tag 关联标签，供编辑器与列表一次取回
export class NoteView {
  noteId: string = '';
  targetKey: string = '';
  text: string = '';
  createTime: number = 0;
  updateTime: number = 0;
  tagIds: string[] = [];
}

export const PRESET_TAGS: string[] = ['待实地探访', '已去过', '研究资料'];
export const SECTIONS: string[] = ['intro', 'arch', 'events', 'poems', 'tourism'];
