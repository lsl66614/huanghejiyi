// entry/src/main/ets/pages/NoteCenterPage.ets —— 全部笔记：随手 / 遗址 / 文物
//
// 与 NotePage 的分工：
//   NoteCenterPage 只做“找得到、分得清、能关联”，不改正文；
//   NotePage 仍是单 target 的编辑器，从本页点“改写”进入。
// 这样既保留原有编辑体验，也不再把 notebook:inbox 误当成“全部笔记”。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import type { NoteView } from '../model/UserDataModels';
import type { SiteInfo } from '../model/ContentModels';
import { ContentRepo } from '../repository/ContentRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import { BackLink } from '../common/BackLink';
import { THEME_BG } from '../common/EraTheme';
import {
  ACCENT, FONT_MONO, FONT_SERIF, FS_BODY, FS_CAPTION, FS_LABEL, FS_TITLE,
  HAIR, INK, LH_BODY, LINE_HAIR, PAGE_PAD_X, ROW_GAP,
  ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SUB
} from '../common/DesignTokens';
import { SectionTitle } from '../common/SectionTitle';
import { SegmentTab, SegmentItem } from '../common/SegmentTab';
import { IconMenu, MenuEntry } from '../common/IconMenu';
import { PillButton } from '../common/PillButton';
import { EmptyState } from '../common/EmptyState';
import {
  DAY_MS, REVIEW_KEEP_DAYS, dailyReviewNote, dayEnd, dayKeyOf, dismissedIds, withDismissed
} from '../service/notes/NoteReview';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut } from '../common/Motion';
import { PressFade } from '../common/PressScale';
import { itemLabel } from '../service/content/ItemTarget';

const SCOPE_ALL: string = 'all';
const SCOPE_INBOX: string = 'inbox';
const SCOPE_SITE: string = 'site';
const SCOPE_RELIC: string = 'relic';

function sectionLabel(sec: string): string {
  if (sec === 'intro') { return '介绍'; }
  if (sec === 'arch') { return '考古'; }
  if (sec === 'events') { return '历史'; }
  if (sec === 'poems') { return '诗词'; }
  if (sec === 'tourism') { return '文旅'; }
  return sec;
}

function targetKind(key: string): string {
  if (key === 'notebook:inbox') { return SCOPE_INBOX; }
  if (key.startsWith('site:')) { return SCOPE_SITE; }
  if (key.startsWith('relic:')) { return SCOPE_RELIC; }
  return 'other';
}

// target_key → 可读标题。语料加载完成前退化为原始 key，不让列表空白。
class TargetIndex {
  private siteNames: Map<string, string> = new Map();
  private relicNames: Map<string, string> = new Map();

  build(sites: SiteInfo[]): void {
    for (const s of sites) {
      this.siteNames.set(s.id, s.name);
      for (const r of s.relics) {
        this.relicNames.set(r.id, r.name);
      }
    }
  }

  label(key: string): string {
    if (key === 'notebook:inbox') { return '随手笔记'; }
    const parts: string[] = key.split(':');
    if (parts[0] === 'site') {
      const raw = this.siteNames.get(parts[1]);
      const site = raw === undefined ? parts[1] : raw;
      const item: string = itemLabel(key, site);
      if (item !== '') { return item; }
      if (parts.length >= 3 && parts[2] !== '') {
        return `${site} · ${sectionLabel(parts[2])}`;
      }
      return site;
    }
    if (parts[0] === 'relic') {
      const raw = this.relicNames.get(parts[1]);
      return raw === undefined ? parts[1] : raw;
    }
    return key;
  }
}

class ScopeRow {
  key: string = '';
  label: string = '';
  count: number = 0;
}
// 一个自然日的一组笔记（修复计划 §7.14 时间流）。
class NoteDayGroup {
  day: string = '';
  entries: NoteView[] = [];
}

// 抽体（修复计划 §7.13）：本 struct 只由 pages/NoteCenterPage 承载——
// 它原先还被档案页内嵌成分段，那会在同一屏叠出「档案 30pt + 笔记」两个大标题。
// 数据加载挂在 aboutToAppear：本页是路由推送出来的独立页，每次进入都是新挂载。
@Component
export struct NoteCenterBody {
  @State notes: NoteView[] = [];
  @State shown: NoteView[] = [];
  // 时间流按自然日成组；shown 变了就重建（apply 里）。
  @State dayGroups: NoteDayGroup[] = [];
  // 列表最新一条的 id：回顾条若正好就是它，就不重复渲染（见 apply）。
  @State newestId: string = '';
  @State tags: string[] = [];
  @State scope: string = SCOPE_ALL;
  @State tag: string = '';
  @State keyword: string = '';
  @State counts: number[] = [0, 0, 0, 0];
  @State ready: boolean = false;
  // 今日回顾。拆成标量而不是留一个 NoteView | null：null 收窄在
  // @Builder 的按值拷贝里不可靠，拆开之后「有没有卡片」是一个明确的布尔。
  @State hasReview: boolean = false;
  @State reviewId: string = '';
  @State reviewText: string = '';
  @State reviewKey: string = '';
  @State reviewTime: number = 0;
  @State reviewHint: string = '';

  private index: TargetIndex = new TargetIndex();

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
      this.index.build(sites);
      this.ready = true;
      this.apply();
    }).catch((_e: Object) => {
      // 语料失败不阻塞笔记列表：标题退化为 target key，正文仍可读。
      this.ready = true;
      this.apply();
    });
    this.reload(ctx);
  }

  // 推送页的刷新桥（修复计划 §7.14）：onPageShow 只在 @Entry 上触发，
  // 本 body 是 @Entry 壳的子组件，写在这里永远不会响——从编辑器/关联页
  // 返回时列表停在旧数据上（实测：写了 4 条笔记，回来仍显示「共 0 条」）。
  // 壳页把 onPageShow 记成 pageTick，这里 @Watch 它。
  @Prop @Watch('onPageTick') pageTick: number = 0;
  private loadedOnce: boolean = false;

  onPageTick(): void {
    if (!this.loadedOnce) {
      // 首帧的加载已由 aboutToAppear 做过，这次 onPageShow 不重复拉。
      this.loadedOnce = true;
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.reload(ctx);
  }

  reload(ctx: common.UIAbilityContext): void {
    this.reviewHint = '';
    UserDataRepo.allNotes(ctx).then((list: NoteView[]) => {
      this.notes = list;
      let inbox = 0;
      let site = 0;
      let relic = 0;
      for (const n of list) {
        const k = targetKind(n.targetKey);
        if (k === SCOPE_INBOX) { inbox++; }
        else if (k === SCOPE_SITE) { site++; }
        else if (k === SCOPE_RELIC) { relic++; }
      }
      this.counts = [list.length, inbox, site, relic];
      this.apply();
      this.rebuildReview(ctx, list);
    });
    UserDataRepo.allTags(ctx).then((t: string[]) => {
      this.tags = t;
    });
  }

  scopeRows(): ScopeRow[] {
    const out: ScopeRow[] = [];
    const labels: string[] = ['全部', '随手', '遗址', '文物'];
    const keys: string[] = [SCOPE_ALL, SCOPE_INBOX, SCOPE_SITE, SCOPE_RELIC];
    for (let i = 0; i < keys.length; i++) {
      const r = new ScopeRow();
      r.key = keys[i];
      r.label = labels[i];
      r.count = this.counts[i];
      out.push(r);
    }
    return out;
  }

  // 范围切换收进图标菜单（清单 §7.11）：菜单项带计数，
  // 选中后按钮上的无障碍名会念出当前是哪一类。
  scopeMenuItems(): MenuEntry[] {
    const out: MenuEntry[] = [];
    for (const r of this.scopeRows()) {
      const e = new MenuEntry();
      e.key = r.key;
      e.label = `${r.label} ${r.count}`;
      out.push(e);
    }
    return out;
  }

  // 当前范围的人话标签（给按钮的无障碍名用）。
  scopeLabel(): string {
    for (const r of this.scopeRows()) {
      if (r.key === this.scope) { return `${r.label} ${r.count} 条`; }
    }
    return '全部';
  }

  // 下拉胶囊上显示的字：只留范围名，不带条数。
  // 条数在菜单项里已经有（「遗址 3」），按钮上再写一遍就是同一行两个数字。
  scopeName(): string {
    for (const r of this.scopeRows()) {
      if (r.key === this.scope) { return r.label; }
    }
    return '全部';
  }

  labelOf(key: string): string {
    if (!this.ready) { return key; }
    return this.index.label(key);
  }

  apply(): void {
    const kw = this.keyword.trim().toLowerCase();
    const out: NoteView[] = [];
    for (const n of this.notes) {
      if (this.scope !== SCOPE_ALL && targetKind(n.targetKey) !== this.scope) { continue; }
      if (this.tag !== '' && !n.tagIds.includes(this.tag)) { continue; }
      if (kw !== '') {
        const label = this.labelOf(n.targetKey).toLowerCase();
        const inText = n.text.toLowerCase().includes(kw);
        const inTag = n.tagIds.some((t: string): boolean => t.toLowerCase().includes(kw));
        if (!inText && !inTag && !label.includes(kw)) { continue; }
      }
      out.push(n);
    }
    this.shown = out;
    this.buildDayGroups();
    // 回顾条要躲开最新一条：它的作用是翻出「今天之前写的那条」，
    // 而当页只有今天的笔记时它会选中列表第一行，纸面上就出现两行一样的字。
    this.newestId = out.length === 0 ? '' : out[0].noteId;
  }

  // 时间流分组：shown 已按 updateTime 倒序（allNotes 的排序），
  // 这里只按自然日切段，不重排——重排会把「同一天」拆散。
  buildDayGroups(): void {
    const out: NoteDayGroup[] = [];
    for (const n of this.shown) {
      const label = dayKeyOf(n.updateTime);
      let hit: NoteDayGroup | null = null;
      for (const g of out) {
        if (g.day === label) { hit = g; break; }
      }
      if (hit === null) {
        const g = new NoteDayGroup();
        g.day = label;
        out.push(g);
        hit = g;
      }
      hit.entries.push(n);
    }
    this.dayGroups = out;
  }

  // 日期栏两行：日号 + 月。同一天只有首条给完整日期，后续条给时刻——
  // 重复写日期是噪音，但「这天里的哪一条」值得留。
  dayNum(ts: number): string {
    const d = new Date(ts);
    return d.getDate().toString().padStart(2, '0');
  }

  dayMon(ts: number): string {
    const d = new Date(ts);
    return `${d.getMonth() + 1}月`;
  }

  dayTime(ts: number): string {
    const d = new Date(ts);
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
  }

  // 一条笔记的三个动作收进一颗 ⋯：原先每行摊「关联 / 改写」两颗文字按钮，
  // 十行就是二十颗，页面读起来全是可点的东西。删除此前只能在编辑器里做。
  noteMenu(n: NoteView): MenuElement[] {
    const link: MenuElement = {
      value: '关联到遗址 / 文物',
      action: (): void => {
        this.openPicker(n);
      }
    };
    const edit: MenuElement = {
      value: '改写',
      action: (): void => {
        this.openEditor(n);
      }
    };
    const del: MenuElement = {
      value: '删除',
      action: (): void => {
        this.erase(n);
      }
    };
    return [link, edit, del];
  }

  erase(n: NoteView): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    UserDataRepo.removeNote(ctx, n.noteId).then(() => {
      this.reload(ctx);
    });
  }

  setScope(k: string): void {
    this.scope = k;
    this.apply();
  }

  setTag(t: string): void {
    this.tag = this.tag === t ? '' : t;
    this.apply();
  }

  // 今日回顾：哈希只吃日期键，所以同一自然日刷新多少次都是同一条。
  private rebuildReview(ctx: common.UIAbilityContext, list: NoteView[]): void {
    const now = Date.now();
    UserDataRepo.readReviewState(ctx).then((raw: string) => {
      const pick: NoteView | null =
        dailyReviewNote(list, dayKeyOf(now), now, dismissedIds(raw, now));
      if (pick === null) {
        this.hasReview = false;
        return;
      }
      this.reviewId = pick.noteId;
      this.reviewText = pick.text;
      this.reviewKey = pick.targetKey;
      this.reviewTime = pick.updateTime;
      this.hasReview = true;
    }).catch((_e: Object) => {
      // 读不到搁置记录就不放这张卡：宁可今天没有回顾，
      // 也不要每次回到本页都翻出同一条「新」笔记。
      this.hasReview = false;
    });
  }

  // keep = true 是「记住了」（一个月内不再翻到），false 是「下次再说」（到今晚为止）。
  private dismissReview(keep: boolean): void {
    if (this.reviewId === '') { return; }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const now = Date.now();
    const id = this.reviewId;
    const until = keep ? now + REVIEW_KEEP_DAYS * DAY_MS : dayEnd(now);
    UserDataRepo.readReviewState(ctx).then((raw: string) => {
      UserDataRepo.writeReviewState(ctx, withDismissed(raw, id, until, now)).then(() => {
        this.hasReview = false;
        this.reviewHint = keep ? '记住了，一个月内不再翻到这条。' : '明天再翻一条。';
      }).catch((_e: Object) => {
        this.reviewHint = '没记下，稍后再试。';
      });
    }).catch((_e: Object) => {
      this.reviewHint = '没记下，稍后再试。';
    });
  }

  private openReviewNote(): void {
    if (this.reviewKey === '') { return; }
    const prm: Record<string, string> = {
      'target': this.reviewKey,
      'title': this.labelOf(this.reviewKey)
    };
    router.pushUrl({ url: 'pages/NotePage', params: prm });
  }

  openEditor(n: NoteView): void {
    const prm: Record<string, string> = {
      'target': n.targetKey,
      'title': this.labelOf(n.targetKey)
    };
    router.pushUrl({ url: 'pages/NotePage', params: prm });
  }

  openPicker(n: NoteView): void {
    const prm: Record<string, string> = {
      'noteId': n.noteId,
      'target': n.targetKey,
      'title': this.labelOf(n.targetKey)
    };
    router.pushUrl({ url: 'pages/TargetPickerPage', params: prm });
  }

  newNote(): void {
    const prm: Record<string, string> = {
      'target': 'notebook:inbox',
      'title': '随手笔记'
    };
    router.pushUrl({ url: 'pages/NotePage', params: prm });
  }

  // 标签筛选的数据源。此前标签行「未选即 ACCENT 描边 / 选中 ACCENT 实底」
  // （清单 N3/N10），与范围行是两套语法；现两处都走 SegmentTab
  // （未选白底发丝、选中 INK 实底）。
  //
  // 范围行不在这儿：它已收进图标菜单（清单 §7.11），见 scopeMenuItems。
  // 标签行补一个「全部标签」项：tag 为空即未过滤，原先没有可见的"全部"态，
  // 用户只能靠"再点一次已选中的标签"退出筛选。
  tagItems(): SegmentItem[] {
    const out: SegmentItem[] = [];
    const all = new SegmentItem();
    all.key = '';
    all.label = '全部标签';
    all.count = -1;
    out.push(all);
    for (const t of this.tags) {
      const it = new SegmentItem();
      it.key = t;
      it.label = t;
      it.count = -1;
      out.push(it);
    }
    return out;
  }

  // 时间流的一行（修复计划 §7.14）：左日期栏 + 右正文，行尾一条发丝。
  // 不再是卡片——田野笔记本是一条条写下来的，不是一个个装进盒子的；
  // 这一屏的母题因此和展厅的图墙、剖面的竖图各自分开。
  @Builder
  noteFlow(n: NoteView, showDay: boolean) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        if (showDay) {
          Text(this.dayNum(n.updateTime))
            .fontSize(FS_TITLE)
            .fontFamily(FONT_MONO)
            .fontColor(INK)
          Text(this.dayMon(n.updateTime))
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_MONO)
            .fontColor(SUB)
        } else {
          // 同一天只有首条给完整日期，后续条给时刻：重复日期是噪音，
          // 但「这天里的哪一条」值得留。
          Text(this.dayTime(n.updateTime))
            .fontSize(FS_LABEL)
            .fontFamily(FONT_MONO)
            .fontColor(SUB)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width(56)

      Column({ space: 6 }) {
        PressFade() {
          Text(n.text)
            .fontSize(FS_BODY)
            .fontFamily(FONT_SERIF)
            .lineHeight(LH_BODY)
            .fontColor(INK)
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .accessibilityText(`改写这条笔记，${n.text}`)
            .onClick(() => {
              this.openEditor(n);
            })
            .focusable(true)
            .focusBox(focusRing())
        }

        Row({ space: 8 }) {
          Text(this.labelOf(n.targetKey))
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontColor(SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (n.tagIds.length > 0) {
            Text(n.tagIds.join(' · '))
              .fontSize(FS_LABEL)
              .fontColor(SUB)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          Blank()
          // 三个动作收进一颗 ⋯：原先每行摊「关联 / 改写」两颗文字按钮，
          // 十行就是二十颗，整页读起来全是可点的东西。
          // 删除此前只能进编辑器才能做，现在在这里也够得着。
          Text('⋯')
            .fontSize(FS_TITLE)
            .fontColor(SUB)
            .padding({ left: 8, right: 4 })
            .bindMenu(this.noteMenu(n))
            .focusable(true)
            .focusBox(focusRing())
            .accessibilityText(`这条笔记的操作，${n.text}`)
            .accessibilityLevel('yes')
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 16, bottom: 16 })
    .border({ width: { bottom: HAIR }, color: LINE_HAIR })
  }

  // 今日回顾：从一张白卡降成纸面上的第一行——左栏写「今天」，
  // 正文点开就是那条笔记，「记住了 / 下次再说」收进同一颗 ⋯。
  @Builder
  reviewFlow() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text('今天')
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_MONO)
          .fontColor(ACCENT)
        Text(this.dayTime(this.reviewTime))
          .fontSize(FS_LABEL)
          .fontFamily(FONT_MONO)
          .fontColor(SUB)
      }
      .alignItems(HorizontalAlign.Start)
      .width(56)

      Column({ space: 6 }) {
        PressFade() {
          Text(this.reviewText)
            .fontSize(FS_BODY)
            .fontFamily(FONT_SERIF)
            .lineHeight(LH_BODY)
            .fontColor(INK)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .accessibilityText('打开这条笔记')
            .onClick(() => {
              this.openReviewNote();
            })
            .focusable(true)
            .focusBox(focusRing())
        }

        Row({ space: 8 }) {
          Text(this.labelOf(this.reviewKey))
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontColor(SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Text('⋯')
            .fontSize(FS_TITLE)
            .fontColor(SUB)
            .padding({ left: 8, right: 4 })
            .bindMenu(this.reviewMenu())
            .focusable(true)
            .focusBox(focusRing())
            .accessibilityText('今日回顾的操作')
            .accessibilityLevel('yes')
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 16, bottom: 16 })
    .border({ width: { bottom: HAIR }, color: LINE_HAIR })
  }

  reviewMenu(): MenuElement[] {
    const got: MenuElement = {
      value: '记住了，一个月不再翻',
      action: (): void => {
        this.dismissReview(true);
      }
    };
    const later: MenuElement = {
      value: '下次再说',
      action: (): void => {
        this.dismissReview(false);
      }
    };
    return [got, later];
  }
  build() {
    Column() {
      // ── 顶栏（修复计划 §7.13）：本页由档案落地页的「笔记」卡 push 进来，
      // 只给返回键；「最近删除」放顶栏右端，标题行留给 30pt 页名与主按钮。
      Row({ space: ROW_GAP }) {
        BackLink({ backToParent: true })
        Blank()
        PressFade() {
          Text('最近删除')
            .fontSize(FS_CAPTION)
            .fontColor(SUB)
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .accessibilityText('最近删除的收藏与笔记')
            .onClick(() => {
              router.pushUrl({ url: 'pages/RecyclePage' });
            })
            .focusable(true)
            .focusBox(focusRing())
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16 })

      // ── 页头（清单 N4/N8）：30pt SectionTitle 与全站同族；
      //    实心主按钮全页只剩「＋ 写一条」一个。
      //    本页原先还被档案页内嵌成分段，那会同屏叠出「档案 + 笔记」两个大标题；
      //    独立成页后一屏只有一个标题。
      Row({ space: ROW_GAP }) {
        SectionTitle({ title: '笔记', caption: `共 ${this.counts[0]} 条` })
        Blank()
        PillButton({
          label: '＋ 写一条',
          onPress: () => {
            this.newNote();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 4 })

      // ── 搜索框（清单 N1）：去掉全站唯一直角填充块，改图录同款「透明底 + 下沿发丝」
      // padding(0) 不能省：ArkUI 的 TextInput 默认自带内边距与圆角，
      // 只写 backgroundColor(Transparent) 清不掉——渲染出来仍是一个
      // 圆角描边盒，与 ListPage / SearchPage 的「眉标 + 无框输入 + 下沿发丝」
      // 制式不一致（实测截图）。外层 Row 挂发丝，TextInput 自身保持透明。
      Row({ space: ROW_GAP }) {
        Text('搜')
          .fontSize(FS_CAPTION)
          .letterSpacing(1)
          .fontColor(SUB)
        TextInput({ text: this.keyword, placeholder: '正文、标签或所属条目' })
          .accessibilityText('搜索笔记：正文、标签或所属条目')
          .layoutWeight(1)
          .fontSize(FS_BODY)
          .fontColor(INK)
          .placeholderColor(SUB)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .height(38)
          .onChange((v: string) => {
            this.keyword = v;
            this.apply();
          })
        if (this.keyword !== '') {
          PressFade() {
            Text('清空')
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
              .onClick(() => {
                this.keyword = '';
                this.apply();
              })
              .focusable(true)
              .focusBox(focusRing())
          }
        }
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 4, bottom: 4 })
      .border({ width: { bottom: HAIR }, color: LINE_HAIR })

      // 筛选两层并成一行（spec §3.8 / 清单 §7.12）：
      //   「范围」＝看哪一类笔记（全部/随手/遗址/文物）→ 一枚带当前值的下拉胶囊；
      //   「标签」＝按什么标签筛 → 胶囊组，横向滚动。
      // 为什么并：范围自占一行时，那一行只有「眉标 + 一个小控件」，
      // 右边整条空白（实测截图），读起来像没做完；而它和标签行又都是圆角控件，
      // 上下两排并排就又回到「分不清哪排管什么」。并成一行后
      // 只剩一条筛选带，且范围胶囊自带「范围」二字与 ⌄ 箭头，与胶囊组语法不同。
      Row({ space: 10 }) {
        IconMenu({
          text: `范围 ${this.scopeName()}`,
          label: `范围，当前${this.scopeLabel()}`,
          items: this.scopeMenuItems(),
          selected: this.scope,
          onPick: (k: string): void => {
            this.setScope(k);
          }
        })
        if (this.tags.length > 0) {
          Scroll() {
            Column() {
              SegmentTab({
                items: this.tagItems(),
                selected: this.tag,
                onPick: (k: string): void => {
                  this.setTag(k);
                }
              })
            }
            .alignItems(HorizontalAlign.Start)
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .align(Alignment.Start)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 必须用 padding 而不是 margin：这一行是 width('100%')，
      // ArkUI 下百分比宽度 + 横向 margin 时 margin 被吞（实测眉标落在 x=60，
      // 而搜索行/页头/空态都在 x=120，左缘断成两列）。搜索行用 padding 就是对的。
      //
      // 上方留 12：搜索行的下沿发丝是「输入区」的底界，胶囊紧贴它读作
      // 胶囊属于输入框（实测截图）。发丝下要有一段空白，胶囊才是另一层。
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 12 })

      Scroll() {
        Column() {
          // 今日回顾：放在列表最上面、跟着列表滚走，不做常驻卡。
          // 筛选或搜索时收起——那时用户在找一条确定的笔记，
          // 再推一条「今天翻到」只会挡路。
          if (this.hasReview && this.scope === SCOPE_ALL && this.tag === '' &&
            this.reviewId !== this.newestId && this.keyword.trim() === '') {
            this.reviewFlow()
          }

          if (this.reviewHint !== '') {
            Text(this.reviewHint)
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
              .width('100%')
              .margin({ bottom: 12 })
          }

          if (this.shown.length === 0) {
            // 空态（清单 N6 / §7.6）：走全站唯一 EmptyState。
            // actionLabel 置空——页头已有实心「＋ 写一条」，空态再放一个就是同页两个主按钮。
            Column() {
              EmptyState({
                headline: this.notes.length === 0 ? '田野笔记尚无记录' : '这个筛选下没有笔记',
                desc: this.notes.length === 0
                  ? '用右上角「＋ 写一条」先记一句，之后再关联到遗址或文物。'
                  : '换个筛选，或清空搜索词。',
                actionLabel: '',
                onAction: (): void => {}
              })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ top: 40 })
          } else {
            ForEach(this.dayGroups, (g: NoteDayGroup) => {
              Column() {
                ForEach(g.entries, (n: NoteView, i: number) => {
                  this.noteFlow(n, i === 0)
                }, (n: NoteView) => `${n.noteId}:${n.updateTime}`)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }, (g: NoteDayGroup) => `${g.day}|` +
              `${g.entries.map((n: NoteView): string => n.noteId).join(',')}`)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: PAGE_PAD_X })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
    }
    .width('100%')
    // 独立频道页：自己撑满整屏。底栏不挂——它是档案频道的下级页，
    // 顶栏的「‹ 返回」回到档案页。
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}

// ── 页面入口（修复计划 §7.13）：从档案落地页的「笔记」卡 pushUrl 进来。
// 底栏不挂——它是档案频道的下级页，返回键回到档案页。
@Entry
@Component
struct NoteCenterPage {
  // 页面可见性桥：onPageShow 只在 @Entry 上触发，把它记成一个自增数，
  // 交给 body 的 @Watch——否则从编辑器返回时列表停在旧数据上。
  @State pageTick: number = 0;

  onPageShow(): void {
    this.pageTick += 1;
  }

  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }

  build() {
    Column() {
      NoteCenterBody({ pageTick: this.pageTick })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}