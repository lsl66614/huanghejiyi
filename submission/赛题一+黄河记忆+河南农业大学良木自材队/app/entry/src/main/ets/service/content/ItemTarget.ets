// service/content/ItemTarget.ets —— 单条内容条目的笔记 target_key
//
// 赛题主要功能第 2 条：「对任意内容条目添加自定义笔记」。原先笔记只能挂在
// 全篇 site:{id}、五段分节 site:{id}:{sec}、文物 relic:{id}、随手 inbox 四种粒度；
// 单条诗词、单条事件、单张图挂不上。这里给出第五种：site:{id}:{kind}:i{n}。
//
// 为什么序号要编进键：同一遗址下多首诗词的笔记必须在列表里可分辨，
// 而笔记的同步身份就是 target_key，用展示标题当键会在改名/换语料后错位。
// 纯函数、禁 @kit，可进 Node 单测；不新增同步表（仍写现有 note 表）。
//
// i{n} 里的 i 是前缀而不是纯数字：这样 label() 一眼能区分「条目键」与
// 「五段分节键」，不会把 site:x:poems:2 误读成段落名。

export type ItemKind = 'poems' | 'events' | 'images';

const KIND_META: Record<string, string> = {
  'poems': '诗词|首',
  'events': '历史|条',
  'images': '图集|张'
};

export function itemTargetKey(siteId: string, kind: string, index: number): string {
  return `site:${siteId}:${kind}:i${index}`;
}

/** 非条目键返回空串，交回调用方原来的段落/文物映射。 */
export function itemLabel(key: string, siteName: string): string {
  const parts: string[] = key.split(':');
  if (parts.length !== 4 || parts[0] !== 'site' || parts[2] === '' || parts[3] === '') {
    return '';
  }
  const meta: string | undefined = KIND_META[parts[2]];
  if (meta === undefined || parts[3].charAt(0) !== 'i') {
    return '';
  }
  const n: number = Number(parts[3].substring(1));
  if (!Number.isInteger(n) || n < 0) {
    return '';
  }
  const words: string[] = meta.split('|');
  return `${siteName} · ${words[0]} · 第${n + 1}${words[1]}`;
}
