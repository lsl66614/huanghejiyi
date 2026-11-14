// entry/src/main/ets/pages/DetailPage.ets
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PoemRef, RelicInfo, SiteEvent, SiteInfo, TourismInfo, ERAS } from '../model/ContentModels';
import type { FavoriteDO, ProgressDO, VisitDO } from '../model/UserDataModels';
import { ContentRepo } from '../repository/ContentRepo';
import { AttributionRepo } from '../repository/AttributionRepo';
import type { AttributionData, AttributionRecord } from '../service/content/Attribution';
import { creditsFor } from '../service/content/Attribution';
import { UserDataRepo } from '../repository/UserDataRepo';
import type { RecoRow } from '../service/recommend/RecoSource';
import { recoRowsFor } from '../service/recommend/RecoSource';
import { BackLink } from '../common/BackLink';
import { eraColor, eraName, THEME_BG } from '../common/EraTheme';
import {
  ACCENT, BODY, CARD_PAD, FONT_DISPLAY,
  FONT_MONO, FONT_SERIF, FS_BODY, FS_CAPTION,
  FS_ITEM, FS_LABEL, FS_META,
  FS_PAGE, FS_TAB, FS_TITLE, HAIR,
  HERO_IMAGE_H, INK, ITEM_GAP, LH_BODY,
  LH_CAPTION, LH_TITLE, LINE_HAIR, ON_IMAGE_TEXT,
  PAGE_PAD_X, PRESS_OPACITY, PRESS_SCALE, RADIUS_DOT_6, RADIUS_MD,
  RADIUS_SM, ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SCRIM,
  SCRIM_ALPHA_BADGE, SCRIM_ALPHA_EDGE, SCRIM_ALPHA_TEXT, SEAL_RED,
  SHADOW_CARD_COLOR_LIGHT, SHADOW_CARD_OFFSET, SHADOW_CARD_RADIUS, SUB,
  SURFACE_CARD, SURFACE_RAISED, WT_BOLD, WT_DISPLAY,
  WT_MEDIUM, WT_REGULAR, WT_SERIF
} from '../common/DesignTokens';
import { PressFade, PressScale } from '../common/PressScale';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut, durScrollTo, pressAnim } from '../common/Motion';
import { firstRealImage, isRealImage, realImagesExclude } from '../common/ImagePolicy';
import { AccessionPlate, layerCode } from '../common/AccessionPlate';
import { ImageViewer } from '../common/ImageViewer';
import { RevealOnScroll } from '../common/RevealOnScroll';
import { LayerBadge } from '../common/LayerBadge';
import { DepthRuler, RulerSeg } from '../common/DepthRuler';
import { RelatedNotes } from '../common/RelatedNotes';
import { cityName, typeName } from '../common/Labels';
import { itemTargetKey } from '../service/content/ItemTarget';

const DOMAIN = 0x0001;
const TAG = 'DetailPage';

interface TocItem {
  num: string;
  label: string;
}

const TOC: TocItem[] = [
  { num: '壹', label: '考古' },
  { num: '贰', label: '历史' },
  { num: '叁', label: '诗词' },
  { num: '肆', label: '文旅' },
  { num: '伍', label: '介绍' }
];

// 与 TOC 同序的 progress 段落键（LocalRdbImpl progress.section 取值）
const SEC_KEYS: string[] = ['arch', 'events', 'poems', 'tourism', 'intro'];

@Entry
@Component
struct DetailPage {
  @State site: SiteInfo | null = null;
  @State activeNum: string = '';
  @State favored: boolean = false;
  @State recoRows: RecoRow[] = [];
  @State openEvents: string[] = [];
  @State viewerOpen: boolean = false;
  @State viewerImages: string[] = [];
  @State viewerCredits: string[] = [];
  @State viewerIndex: number = 0;
  // 实拍署名表（rawfile/attribution.json）；灯箱图注按 path 查它
  @State attributions: AttributionRecord[] = [];
  // onError 兜底：real_ 图在 JSON 有引用、盘上缺文件时，$rawfile 不报错、
  // Image 渲染成永久空白；分别记头图 / 文物卡 / 图集的失败项，翻回制式占位。
  @State heroFailed: boolean = false;
  // 头图按压态：头图不能用 PressScale 包装器（LayerBadge 的 position
  // 定位基准会随包装层级改变），故就地手写同一套 onTouch 三段式。
  @State heroPressed: boolean = false;
  // 按下的文物卡 id：@Builder 产物是独立子树，按压态只能记在页面上。
  @State pressedRelic: string = '';
  // 按下的脉络推荐条目 id
  @State pressedReco: string = '';
  @State relicFailed: string[] = [];
  @State galleryFailed: string[] = [];
  // 已读段落集合（site:xxx|section）——导览尺的实色格来源
  @State readKeys: Set<string> = new Set();
  // 相关笔记的重读信号：从笔记页返回本页时 +1，RelatedNotes 用 @Watch 跟随。
  // 不用 aboutToAppear，因为组件不会随页面回到前台而重建。
  @State noteEpoch: number = 0;
  private shownOnce: boolean = false;
  private scroller: Scroller = new Scroller();
  private secY: number[] = [0, 0, 0, 0, 0];

  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }

  aboutToAppear(): void {
    const p = router.getParams() as Record<string, string> | undefined;
    const id: string = p !== undefined ? (p['id'] ?? '') : '';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 署名表与语料独立加载：读不到只是灯箱少一行图注，不影响页面主体
    AttributionRepo.load(ctx).then((d: AttributionData) => {
      this.attributions = d.images;
    }).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'attribution load fail: %{public}s', JSON.stringify(e));
    });
    ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
      for (const s of sites) {
        if (s.id === id) {
          this.site = s;
          break;
        }
      }
      if (this.site !== null) {
        const srcSite: SiteInfo = this.site;
        // F5：浏览埋点（60s 节流，失败不影响页面）
        UserDataRepo.trackVisit(ctx, `site:${srcSite.id}`).catch((e: Object) => {
          hilog.error(DOMAIN, TAG, 'trackVisit fail: %{public}s', JSON.stringify(e));
        });
        UserDataRepo.isFavored(ctx, `site:${srcSite.id}`).then((v: boolean) => {
          this.favored = v;
        });
        UserDataRepo.listFavoritesOf(ctx).then((favs: FavoriteDO[]) => {
          UserDataRepo.recentVisits(ctx, 20).then((visits: VisitDO[]) => {
            this.recoRows = recoRowsFor(srcSite, sites, favs, 3, visits);
          });
        });
        // 已读段落：导览尺按它决定哪几格实色
        UserDataRepo.allProgress(ctx).then((rows: ProgressDO[]) => {
          const keys: Set<string> = new Set();
          for (const p of rows) {
            if (p.done) { keys.add(`${p.targetKey}|${p.section}`); }
          }
          this.readKeys = keys;
        });
      }
    });
  }

  // 首次 onPageShow 紧跟 aboutToAppear，组件已经自己读过一次笔记；
  // 只有「再次回到前台」才需要新信号，否则每次进页都白读一遍。
  onPageShow(): void {
    if (this.shownOnce) {
      this.noteEpoch = this.noteEpoch + 1;
    }
    this.shownOnce = true;
  }

  toggleFav(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (this.site === null) { return; }
    UserDataRepo.toggleFavorite(ctx, `site:${this.site.id}`).then((now: boolean) => {
      this.favored = now;
    });
  }

  jumpTo(i: number): void {
    this.activeNum = TOC[i].num;
    this.scroller.scrollTo({
      yOffset: Math.max(0, this.secY[i] - 56),
      xOffset: 0,
      animation: { duration: durScrollTo(), curve: curveOut() }
    });
    // 这里不再顺带标记已读：设计稿 §4.2 的学习进度是每节底部的
    // 显式勾选。目录点击只是导航，替用户决定「读完了」是越权。
  }

  isRead(key: string): boolean {
    if (this.site === null) { return false; }
    return this.readKeys.has(`site:${this.site.id}|${key}`);
  }

  setRead(key: string, on: boolean): void {
    if (this.site === null) { return; }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const siteId: string = this.site.id;
    UserDataRepo.setSectionRead(ctx, `site:${siteId}`, key, on).then((): void => {
      const next: Set<string> = new Set<string>();
      this.readKeys.forEach((v: string) => { next.add(v); });
      const k: string = `site:${siteId}|${key}`;
      if (on) { next.add(k); } else { next.delete(k); }
      this.readKeys = next;
    }).catch((e: Object): void => {
      hilog.error(DOMAIN, TAG, 'setSectionRead fail: %{public}s', JSON.stringify(e));
    });
  }

  markSection(i: number, a: Area): void {
    this.secY[i] = (a.globalPosition.y as number) + this.scroller.currentOffset().yOffset;
  }

  openNote(targetSuffix: string, label: string): void {
    if (this.site === null) { return; }
    const prm: Record<string, string> = {
      'target': `site:${this.site.id}${targetSuffix}`,
      'title': `${this.site.name} · ${label}`
    };
    router.pushUrl({ url: 'pages/NotePage', params: prm });
  }

  // 单条内容条目（一首诗 / 一条事件 / 一张图）单独成档：赛题「任意内容条目」
  // 原来只覆盖到全篇与五段分节。序号从 0 起、编进 target_key，列表里才能分辨。
  openItemNote(kind: string, idx: number, secLabel: string, unit: string): void {
    if (this.site === null) { return; }
    const prm: Record<string, string> = {
      'target': itemTargetKey(this.site.id, kind, idx),
      'title': `${this.site.name} · ${secLabel} · 第${idx + 1}${unit}`
    };
    router.pushUrl({ url: 'pages/NotePage', params: prm });
  }

  // 事件展开态按 siteId+序号 记录：换站时不同条目互不影响
  eventKey(idx: number): string {
    const sid: string = this.site !== null ? this.site.id : '';
    return `${sid}#${idx}`;
  }

  // 时间线的起止年份：取首尾两条事件的 year 串（语料按时间倒序，
  // 故首条最新、末条最古）。取不到就返回空串，由调用方省掉这一句。
  eventSpan(): string {
    if (this.site === null || this.site.events.length === 0) { return ''; }
    const first: string = this.site.events[0].year;
    const last: string = this.site.events[this.site.events.length - 1].year;
    if (first === '' || last === '') { return ''; }
    return first === last ? first : `${first} — ${last}`;
  }

  isEventOpen(idx: number): boolean {
    return this.openEvents.includes(this.eventKey(idx));
  }

  toggleEvent(idx: number): void {
    const k = this.eventKey(idx);
    const next: string[] = this.openEvents.slice();
    const i = next.indexOf(k);
    if (i >= 0) {
      next.splice(i, 1);
    } else {
      next.push(k);
    }
    this.openEvents = next;
  }

  // 三联数据卡的格子（设计稿③）：键 11px SUB + 值 16px 宋体 semibold
  @Builder
  statCard(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(FS_LABEL)
        .fontColor(SUB)
      Text(value)
        .fontSize(FS_TITLE)
        .fontFamily(FONT_MONO)
        .fontWeight(WT_MEDIUM)
        .fontColor(INK)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(SURFACE_CARD)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(RADIUS_MD)
  }

  // 站点标签：设计稿③的 Tag Row 用站点自身 tags（前二个）。
  siteTags(): string[] {
    if (this.site === null) { return []; }
    return this.site.tags.slice(0, 2);
  }

  // 层号：站点年代的剖面序 + 1（L1–L6，与 Index 同口径）
  layerCode(): string {
    if (this.site === null) { return ''; }
    return `L${ERAS.indexOf(this.site.era) + 1}`;
  }

  // 五格导览尺的段数据：已读段落实色、未读发丝灰
  rulerSegs(): RulerSeg[] {
    const out: RulerSeg[] = [];
    for (let i = 0; i < TOC.length; i++) {
      const done = this.site !== null &&
        this.readKeys.has(`site:${this.site.id}|${SEC_KEYS[i]}`);
      out.push({ key: SEC_KEYS[i], label: TOC[i].label, done: done });
    }
    return out;
  }

  // 段落键 → TOC 下标
  secKeyIndex(key: string): number {
    return SEC_KEYS.indexOf(key);
  }

  @Builder
  sectionHead(num: string, label: string, key: string) {
    Row({ space: 12 }) {
      // 节标题：8vp 层色前置块 + 展示体（设计稿③）
      Row()
        .width(8)
        .height(18)
        .backgroundColor(this.eraColorOf())
        .borderRadius(RADIUS_SM)
      Text(label)
        .fontSize(FS_TITLE)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(INK)
      Blank()
      PressFade() {
        Text('✎ 笔记')
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
          .accessibilityText(`为「${label}」写笔记`)
          .onClick(() => {
            this.openNote(`:${key}`, label);
          })
          .focusable(true)
          .focusBox(focusRing())
      }
    }
    .width('100%')
    .padding({ top: 24, bottom: 12 })
  }

  // 当前站点的年代色（sectionHead 的前置块用）
  eraColorOf(): string {
    return this.site !== null ? eraColor(this.site.era) : INK;
  }

  // 每节底部的「已研读」勾选（设计稿 §4.2：学习进度是显式动作）。
  // 勾选写 progress 表（done=1），取消写 done=0——不是删行，见
  // UserDataRepo.setSectionRead 的说明。
  @Builder
  readToggle(key: string, label: string) {
    Row({ space: 10 }) {
      Checkbox()
        .select(this.isRead(key))
        .selectedColor(ACCENT)
        .width(22)
        .height(22)
        .onChange((on: boolean) => {
          this.setRead(key, on);
        })
      PressFade() {
        Text(this.isRead(key) ? `已研读「${label}」` : `标记「${label}」为已研读`)
          .fontSize(FS_CAPTION)
          .letterSpacing(1)
          .fontColor(this.isRead(key) ? ACCENT : SUB)
          .accessibilityText(`「${label}」研读状态，点按切换`)
          .onClick(() => {
            this.setRead(key, !this.isRead(key));
          })
          .focusable(true)
          .focusBox(focusRing())
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 4 })
    .margin({ top: 24 })
    .border({ width: { top: 1 }, color: LINE_HAIR })
  }

  @Builder
  para(text: string) {
    Text(text)
      .fontSize(FS_BODY)
      .lineHeight(LH_BODY)
      .fontColor(BODY)
      .width('100%')
  }

  // 拉起全屏看图。images 传入该图位的全部实拍路径，startIndex 指定初始张数下标。
  openViewer(images: string[], startIndex: number): void {
    if (images.length === 0) { return; }
    this.viewerImages = images;
    this.viewerCredits = creditsFor(images, this.attributions);
    this.viewerIndex = startIndex;
    this.viewerOpen = true;
  }

  // 遗址图集取全部实拍（头图在内），文物图集只取该文物自身实拍。
  siteRealImages(): string[] {
    if (this.site === null) { return []; }
    return this.site.images.filter((p: string): boolean => isRealImage(p));
  }

  // 事件层：发掘时间线。93 条事件全部带 background/process/impact 三段长文
  // （平均数百字，讲发掘过程与学术争议），是全 App 最深的内容层。
  // 版式：左侧年份轨 + 节点，右侧标题与摘要常显、三段深层按需展开。
  // 三层用「壹/贰/叁」编号 + 赭红小标，读起来是档案条目而不是折叠面板。
  @Builder
  eventCard(e: SiteEvent, idx: number) {
    Row({ space: 12 }) {
      // 年份轨：节点 + 竖线。线由 Column 的左侧描边实现，
      // 最后一项的线由外层 margin 收掉，见 events 列表容器。
      Column({ space: 4 }) {
        Row()
          .width(8)
          .height(8)
          .borderRadius(RADIUS_DOT_6)
          .backgroundColor(this.isEventOpen(idx) ? ACCENT : LINE_HAIR)
          .margin({ top: 6 })
        Column()
          .width(1)
          .backgroundColor(LINE_HAIR)
      }
      .width(8)

      Column({ space: 8 }) {
        Row({ space: 10 }) {
          if (e.year !== '') {
            Text(e.year)
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_MONO)
              .letterSpacing(1)
              .fontColor(SURFACE_CARD)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(ACCENT)
              .borderRadius(RADIUS_SM)
          }
          Text(e.title)
            .fontSize(FS_BODY)
            .fontWeight(WT_BOLD)
            .fontColor(INK)
            .layoutWeight(1)
          PressFade() {
            Text('✎')
              .fontSize(FS_CAPTION)
              .fontColor(ACCENT)
              .accessibilityText(`${e.title}，写笔记`)
              .accessibilityDescription(`为第${idx + 1}条历史事件写笔记`)
              .onClick(() => {
                this.openItemNote('events', idx, '历史', '条');
              })
              .focusable(true)
              .focusBox(focusRing())
          }
          PressFade() {
            Text(this.isEventOpen(idx) ? '收起 −' : '展开 ＋')
              .fontSize(FS_CAPTION)
              .fontColor(ACCENT)
              .accessibilityText(`${e.title}，${this.isEventOpen(idx) ? '已展开，点按收起' : '已折叠，点按展开'}`)
              .onClick(() => {
                this.toggleEvent(idx);
              })
              .focusable(true)
              .focusBox(focusRing())
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        this.para(e.summary)

        // 深层：三段各有编号，且注明是否可展开——用户一眼知道这里有货
        if (this.isEventOpen(idx)) {
          if (e.background !== '') {
            this.eventField('壹 · 背景', e.background)
          }
          if (e.process !== '') {
            this.eventField('贰 · 经过', e.process)
          }
          if (e.impact !== '') {
            this.eventField('叁 · 影响', e.impact)
          }
          if (e.figures.length > 0) {
            Column({ space: 4 }) {
              Text('相关人物')
                .fontSize(FS_CAPTION)
                .letterSpacing(2)
                .fontColor(SUB)
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(e.figures, (f: string) => {
                  Text(f)
                    .fontSize(FS_CAPTION)
                    .fontColor(BODY)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .border({ width: 1, color: LINE_HAIR })
                    .margin({ right: 6, bottom: 6 })
                }, (f: string) => f)
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
          }
          if (e.furtherReading !== '') {
            this.eventField('延伸阅读', e.furtherReading)
          }
        } else if (e.background !== '' || e.process !== '' || e.impact !== '') {
          // 折叠态给一条「内含三层」的提示，避免用户以为只有摘要一句话
          Text('含背景 / 经过 / 影响三层')
            .fontSize(FS_TAB)
            .fontColor(SUB)
            .letterSpacing(1)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ right: CARD_PAD, bottom: 12 })
  }

  @Builder
  eventField(label: string, body: string) {
    Column({ space: 3 }) {
      Text(label)
        .fontSize(FS_CAPTION)
        .fontWeight(WT_MEDIUM)
        .letterSpacing(2)
        .fontColor(ACCENT)
      Text(body)
        .fontSize(FS_BODY)
        .lineHeight(LH_BODY)
        .fontColor(BODY)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 8, bottom: 8 })
    .border({ width: { left: 2 }, color: LINE_HAIR })
    .padding({ left: 10 })
  }

  @Builder
  tourismBlock(t: TourismInfo) {
    this.para(t.overview)
    if (t.guide.hours !== '' || t.guide.tickets !== '' || t.guide.address !== '') {
      Column({ space: 6 }) {
        Text('参观指引')
          .fontSize(FS_CAPTION)
          .letterSpacing(2)
          .fontColor(ACCENT)
        if (t.guide.hours !== '') {
          this.guideRow('开放时间', t.guide.hours)
        }
        if (t.guide.tickets !== '') {
          this.guideRow('票务', t.guide.tickets)
        }
        if (t.guide.address !== '') {
          this.guideRow('地址', t.guide.address)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(12)
      .backgroundColor(SURFACE_CARD)
      .border({ width: 1, color: LINE_HAIR })
      .margin({ top: 12 })
    }
    if (t.itinerary !== '') {
      Column({ space: 4 }) {
        Text('行程建议')
          .fontSize(FS_CAPTION)
          .letterSpacing(2)
          .fontColor(ACCENT)
        Text(t.itinerary)
          .fontSize(FS_BODY)
          .lineHeight(LH_BODY)
          .fontColor(BODY)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ top: 12 })
    }
  }

  @Builder
  guideRow(label: string, value: string) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(FS_CAPTION)
        .fontColor(SUB)
        .width(52)
      Text(value)
        .fontSize(FS_CAPTION)
        .lineHeight(LH_CAPTION)
        .fontColor(BODY)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  poemBlock(poem: PoemRef, idx: number) {
    Column({ space: 8 }) {
      Text(`“${poem.text}”`)
        .fontSize(FS_TITLE)
        .lineHeight(LH_TITLE)
        .fontStyle(FontStyle.Italic)
        .fontColor(INK)
      Row() {
        Text(`${poem.author} · ${poem.source}`)
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
          .layoutWeight(1)
        PressFade() {
          Text('✎ 为这一首写笔记')
            .fontSize(FS_CAPTION)
            .fontColor(ACCENT)
            .accessibilityText(`第${idx + 1}首诗词，写笔记`)
            .accessibilityDescription(`为第${idx + 1}首诗词写笔记`)
            .onClick(() => {
              this.openItemNote('poems', idx, '诗词', '首');
            })
            .focusable(true)
            .focusBox(focusRing())
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .margin({ bottom: 16 })
  }

  // 文物卡（设计稿③ Relic Card）：白卡 8px 圆角 + 120vp 图位 +
  // L 层号小角标 + 名称 13px 展示体 + 材质。
  // 无实拍走藏品签制式（common/AccessionPlate.ets）——104 件文物 0 实拍，
  // 这块就是主画面，按博物馆编目做而不是留白。
  @Builder
  relicCard(r: RelicInfo) {
    Column({ space: 0 }) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (firstRealImage(r.images) !== '' && this.relicFailed.indexOf(r.id) < 0) {
          // 实拍卡沿用藏品签的版面：120 图 + 24 编号行，整格 144。
          // 只放 120 高的图会在 144 格底留一条白边（实测像图没加载完）。
          Column({ space: 0 }) {
            PressScale() {
              Image($rawfile(firstRealImage(r.images)))
                .width(120)
                .height(120)
                .objectFit(ImageFit.Cover)
                .draggable(false)
                .onError(() => {
                  this.relicFailed = this.relicFailed.concat([r.id]);
                })
                .onClick(() => {
                  const own: string[] = r.images.filter((p: string): boolean => isRealImage(p));
                  this.openViewer(own, 0);
                })
                .focusable(true)
                .focusBox(focusRing())
            }
            Text(this.relicCode(r))
              .width(120)
              .height(24)
              .textAlign(TextAlign.Center)
              .fontSize(FS_TAB)
              .fontFamily(FONT_MONO)
              .fontColor(SUB)
          }
          .width(120)
          .height(144)
        } else {
          // 藏品签制式（见 common/AccessionPlate.ets）：剪影 + 材质 + 编号。
          // 窄卡只保留剪影与编号，材质章与状态行由 plateSize 门槛关掉。
          AccessionPlate({
            plateSize: 120,
            era: r.era,
            material: r.material,
            relicId: r.id,
            siteRelicIds: this.siteRelicIds()
          })
        }
        // L 层号小角标（左上）
        Row({ space: 4 }) {
          Text(this.layerCodeOfEra(r.era))
            .fontSize(9)
            .fontFamily(FONT_MONO)
            .fontWeight(WT_MEDIUM)
            .fontColor(INK)
        }
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor(SURFACE_CARD)
        .borderRadius(RADIUS_SM)
        .margin({ left: 8, top: 8 })
      }
      // 图位高度 = 120 剪影 + 8 间距 + 编号行。藏品签在 120 档只画
      // 剪影与编号，编号排在剪影下方，所以图位要比剪影高，否则编号
      // 会溢出到卡片标题上（实测标题被「陶 / L2 · 001」压住）。
      .width(120)
      .height(144)

      Column({ space: 4 }) {
        Text(r.name)
          .fontSize(FS_META)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(INK)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(120)
        Text(r.material)
          .fontSize(FS_TAB)
          .fontColor(SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(120)
      }
      .alignItems(HorizontalAlign.Start)
      .width(120)
      .padding({ left: 8, right: 8, top: 8, bottom: 10 })
    }
    .alignItems(HorizontalAlign.Start)
    .width(120)
    .backgroundColor(SURFACE_CARD)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(RADIUS_MD)
    .onClick(() => {
      const prm: Record<string, string> = { 'site': r.siteId, 'relic': r.id };
      router.pushUrl({ url: 'pages/RelicPage', params: prm });
    })
    // 按压反馈写在 @Builder 内部：@Builder 的调用方看不到内部结构，
    // 套包装器只能包住「this.relicCard(r)」这一句调用，而 Builder 的
    // 产物是独立子树，包装器里的 scale 落在调用点而非卡片自身。
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressedRelic = r.id;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedRelic = '';
      }
    })
    .scale({ x: this.pressedRelic === r.id ? PRESS_SCALE : 1, y: this.pressedRelic === r.id ? PRESS_SCALE : 1 })
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`${r.name}，${r.material}`)
    .accessibilityLevel('yes')
  }

  // 年代键 → 层号（L1–L6）
  layerCodeOfEra(era: string): string {
    return layerCode(era);
  }

  // 藏品签序号来源：本遗址所有文物 id（保持 relics 数组序）
  siteRelicIds(): string[] {
    if (this.site === null) { return []; }
    const out: string[] = [];
    for (const r of this.site.relics) { out.push(r.id); }
    return out;
  }

  // 实拍卡的编号行，与 AccessionPlate 的「L2 · 002」同一口径：
  // 层号 + 该文物在本遗址 relics 数组中的位次。
  relicCode(r: RelicInfo): string {
    const ids: string[] = this.siteRelicIds();
    const idx: number = ids.indexOf(r.id);
    const n: number = idx >= 0 ? idx + 1 : 1;
    const seq: string = n < 10 ? `00${n}` : (n < 100 ? `0${n}` : `${n}`);
    return `${this.layerCodeOfEra(r.era)} · ${seq}`;
  }

  build() {
    Column() {
      Scroll(this.scroller) {
        Column() {
          // 遗址头图：320vp（设计稿③ HERO_IMAGE_H）。
          // 仅显示真实照片（real_ 前缀）；无实拍时层色整块 + 层号章 +
          // 「待实拍入仓」——占位态必须比真实态更克制，它是在说
          // "这里将有一张图"，不能用花哨图案伪装成内容。
          Stack({ alignContent: Alignment.BottomStart }) {
            if (this.site !== null && firstRealImage(this.site.images) !== '' && !this.heroFailed) {
              Image($rawfile(firstRealImage(this.site.images)))
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .draggable(false)
                .onError(() => {
                  this.heroFailed = true;
                })
              // 底→上 scrim：保护信息行。实端 alpha 走 SCRIM_ALPHA_EDGE，
              // 文字只允许落在 ≥ 阈值的那一段（见 DesignTokens 的 scrim 注释）。
              Row()
                .width('100%')
                .height('100%')
                .linearGradient({
                  direction: GradientDirection.Top,
                  colors: [
                    [SCRIM + '00', 0],
                    [SCRIM + '8C', 0.55],
                    [SCRIM + 'AE', 1]
                  ]
                })
              // 实拍不挂「示意图」角标：这一分支只渲染 real_ 前缀的实拍图，
              // 角标属于 AI 示意图；挂在实拍上等于把真图说成假图（P3 实测）。
            } else {
              // 占位态：层色整块。同样要铺 scrim——层色虽过 eraInk 对比度，
              // 但仰韶赭红上叠 90% 白的标题字实测偏灰（装机截图可见），
              // 加一层 SCRIM_ALPHA_TEXT 的暗底把白字托住。
              Stack({ alignContent: Alignment.Center }) {
                Column()
                  .width('100%')
                  .height('100%')
                  .backgroundColor(this.site !== null ? eraColor(this.site.era) : eraColor(''))
                Row()
                  .width('100%')
                  .height('100%')
                  .backgroundColor(SCRIM)
                  .opacity(SCRIM_ALPHA_TEXT)
                // 占位态中央：说明文字
                Column({ space: 10 }) {
                  Text('图像整备中')
                    .fontSize(FS_TITLE)
                    .fontFamily(FONT_DISPLAY)
                    .fontWeight(WT_DISPLAY)
                    .fontColor(ON_IMAGE_TEXT)
                  Text('待实拍入仓 · REAL PHOTO PENDING')
                    .fontSize(FS_CAPTION)
                    .fontFamily(FONT_MONO)
                    .letterSpacing(1)
                    .fontColor(ON_IMAGE_TEXT)
                    .opacity(0.85)
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
              }
              .width('100%')
              .height('100%')
            }
            // 层号章：头图左下（设计稿③）。替代旧制的竖排层名——
            // 章是标签不是装饰，只回答"第几层、什么年代"。
            LayerBadge({
              layerCode: this.layerCode(),
              era: this.site !== null ? this.site.era : '',
              eraLabel: this.site !== null ? eraName(this.site.era) : ''
            })
            .position({ left: 20, bottom: 76 })
            Column({ space: 10 }) {
              Row() {
                BackLink({ onImage: true })
                Blank()
                PressFade() {
                  Text('✎ 笔记')
                    .fontSize(FS_CAPTION)
                    .fontColor(ON_IMAGE_TEXT)
                    .margin({ right: 16 })
                    .accessibilityText('为本遗址写笔记')
                    .onClick(() => {
                      this.openNote('', '全篇');
                    })
                    .focusable(true)
                    .focusBox(focusRing())
                }
                PressFade() {
                  Text(this.favored ? '★ 已收藏' : '☆ 收藏')
                    .fontSize(FS_CAPTION)
                    .fontColor(ON_IMAGE_TEXT)
                    .accessibilityText(this.favored ? '已收藏，点按取消' : '收藏本遗址')
                    .accessibilitySelected(this.favored)
                    .onClick(() => {
                      this.toggleFav();
                    })
                    .focusable(true)
                    .focusBox(focusRing())
                }
              }
              .width('100%')
              Blank()
              // 站名与副题**不在头图上再写一遍**（2026-11-05 实测截图）：
              // 它们紧贴在下方 30pt 处已经是这一屏的主标题，头图上那层白字
              // 既重复、又落在展签的浅灰底上读不出（白字压 #C8C8C8）。
              // 头图只保留三件操作（返回/笔记/收藏）与左下角层号章。
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .height(HERO_IMAGE_H)
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 24 })
          }
          .width('100%')
          .height(HERO_IMAGE_H)
          // 灯箱入口挂在头图 Stack（最外层）上：命中测试自上而下，
          // 顶层 info Column（默认命中模式）会挡住下层 Image 的 onClick，
          // 渐变 Row 同理。挂到祖先上后，无 handler 的空档点击沿冒泡链
          // 必然到达；带自己的 onClick 的返回/笔记/收藏按钮仍在更深层，
          // 事件停在它们身上，不会误触发灯箱。
          .onClick(() => {
            this.openViewer(this.siteRealImages(), 0);
          })
          .accessibilityText(this.site !== null ? `${this.site.name}头图，点按放大细观` : '头图')
          .accessibilityTextHint('共 ' + (this.site !== null ? this.siteRealImages().length : 0) + ' 张')
          .focusable(true)
          .focusBox(focusRing())
          // 头图是「有底色的整块」：按 PressScale 的几何型反馈走。这里
          // 不能套 PressScale() 包装器——Stack 内的 LayerBadge 用 position
          // 绝对定位，包一层 Column 会改掉定位基准（父级由 Stack 变 Column）。
          // 故直接复用同一套 onTouch 三段式，反馈形态与包装器逐字一致。
          .onTouch((e: TouchEvent) => {
            if (e.type === TouchType.Down) {
              this.heroPressed = true;
            } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
              this.heroPressed = false;
            }
          })
          .scale({ x: this.heroPressed ? PRESS_SCALE : 1, y: this.heroPressed ? PRESS_SCALE : 1 })
          .animation(pressAnim())

          // 站点信息区：标签行 + 站点名 + meta + 三联数据卡（设计稿③）
          Column({ space: 8 }) {
            // 标签行：站点自身 tags（前二）
            if (this.site !== null) {
              Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                ForEach(this.siteTags(), (t: string) => {
                  Text(t)
                    .fontSize(FS_LABEL)
                    .fontColor(BODY)
                    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                    .backgroundColor(SURFACE_RAISED)
                    .borderRadius(RADIUS_SM)
                    .margin({ right: 8, bottom: 4 })
                }, (t: string) => t)
              }
              .width('100%')
            }
            // 站点名 + meta（设计稿③ Content 区）
            if (this.site !== null) {
              Text(this.site.name)
                .fontSize(FS_PAGE)
                .fontFamily(FONT_DISPLAY)
                .fontWeight(WT_DISPLAY)
                .fontColor(INK)
                .width('100%')
              Text(`${eraName(this.site.era)}文化 · ${cityName(this.site.city)} · ${typeName(this.site.siteType)}`)
                .fontSize(FS_META)
                .fontColor(SUB)
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16 })

          // Stats Row 三联数据卡（设计稿③）
          // 数据取自站点自身字段——不编探方面积/文化层厚（schema 里没有），
          // 用三个真实计数：代表文物 / 诗词 / 史事。
          if (this.site !== null) {
            Row({ space: 12 }) {
              this.statCard('代表文物', `${this.site.relics.length}`)
              this.statCard('诗词', `${this.site.poems.length}`)
              this.statCard('史事', `${this.site.events.length}`)
            }
            .width('100%')
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12 })
          }

          // 我的笔记：同一处遗址的笔记排前，其次是共享标签的笔记。
          // 没有笔记时组件自身不占高度，不会留下一块只有标题的空白。
          if (this.site !== null) {
            Column() {
              RelatedNotes({
                targetKey: `site:${this.site.id}`,
                selfTitle: this.site.name,
                dark: false,
                epoch: this.noteEpoch
              })
            }
            .width('100%')
            .padding({ top: 16 })
          }

          // 本篇导览：DepthRuler 五格尺（设计稿③ TOC）
          Column({ space: 12 }) {
            Row({ space: 8 }) {
              Row()
                .width(8)
                .height(18)
                .backgroundColor(this.site !== null ? eraColor(this.site.era) : INK)
                .borderRadius(RADIUS_SM)
              Text('本篇导览')
                .fontSize(FS_TITLE)
                .fontFamily(FONT_DISPLAY)
                .fontWeight(WT_DISPLAY)
                .fontColor(INK)
            }
            .width('100%')

            DepthRuler({
              segs: this.rulerSegs(),
              era: this.site !== null ? this.site.era : '',
              onSegTap: (key: string) => {
                const i = this.secKeyIndex(key);
                if (i >= 0) {
                  this.jumpTo(i);
                }
              }
            })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 8 })

          Row()
            .width('100%')
            .height(1)
            .backgroundColor(LINE_HAIR)

          // 遗址图集：真实照片（除头图外）。点击任一张拉起看图，初始张数对齐被点的那张。
          if (this.site !== null && realImagesExclude(this.site.images, firstRealImage(this.site.images)).length > 0) {
            Scroll() {
              Row({ space: 12 }) {
                ForEach(realImagesExclude(this.site.images, firstRealImage(this.site.images)),
                  (img: string, idx: number) => {
                    Column({ space: 6 }) {
                      if (this.galleryFailed.indexOf(img) < 0) {
                        PressScale() {
                          Image($rawfile(img))
                            .width(220)
                            .height(150)
                            .objectFit(ImageFit.Cover)
                            .draggable(false)
                            .onError(() => {
                              this.galleryFailed = this.galleryFailed.concat([img]);
                            })
                            .onClick(() => {
                              this.openViewer(this.siteRealImages(), this.siteRealImages().indexOf(img));
                            })
                            .focusable(true)
                            .focusBox(focusRing())
                        }
                      } else {
                        // 解码失败占位：点击仍进灯箱，灯箱内是同款「解码中/未入仓」卡
                        PressFade() {
                          Column()
                            .width(220)
                            .height(150)
                            .backgroundColor(SURFACE_RAISED)
                            .onClick(() => {
                              this.openViewer(this.siteRealImages(), this.siteRealImages().indexOf(img));
                            })
                            .focusable(true)
                            .focusBox(focusRing())
                        }
                      }
                      PressFade() {
                        Text('✎ 为这张写笔记')
                          .fontSize(FS_CAPTION)
                          .fontColor(ACCENT)
                          .accessibilityText(`为第${idx + 1}张实拍写笔记`)
                          .onClick(() => {
                            this.openItemNote('images', idx, '图集', '张');
                          })
                          .focusable(true)
                          .focusBox(focusRing())
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .width(220)
                  }, (img: string) => img)
              }
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .align(Alignment.Start)
            .width('100%')
            .padding({ top: 16 })
          }

          if (this.site !== null) {
            RevealOnScroll() {
              Column() {
                this.sectionHead('壹', '考古', 'arch')
                this.para(this.site.archaeology)
                this.readToggle('arch', '考古')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 24 })
              .backgroundColor(THEME_BG)
              .onAreaChange((_o: Area, a: Area) => {
                this.markSection(0, a);
              })
            }

            RevealOnScroll() {
              Column() {
                this.sectionHead('贰', '历史', 'events')
                // 发掘时间线的起止范围：93 条事件横跨「发掘当年」到「史前」，
                // 把范围念出来，用户才知道这条轴有多长。
                if (this.site.events.length > 0) {
                  Text(`发掘时间线 ${this.site.events.length} 条 · ${this.eventSpan()}`)
                    .fontSize(FS_CAPTION)
                    .fontColor(SUB)
                    .letterSpacing(1)
                    .width('100%')
                    .padding({ left: PAGE_PAD_X, bottom: 12 })
                }
                ForEach(this.site.events, (e: SiteEvent, idx: number) => {
                  this.eventCard(e, idx)
                }, (e: SiteEvent, idx: number) => this.eventKey(idx))
                this.readToggle('events', '历史')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 24 })
              .backgroundColor(SURFACE_RAISED)
              .onAreaChange((_o: Area, a: Area) => {
                this.markSection(1, a);
              })
            }

            RevealOnScroll() {
              Column() {
                this.sectionHead('叁', '诗词', 'poems')
                if (this.site.poems.length === 0) {
                  // 诗词空态：绢底竖排 + 朱印（方志留白制式）
                  Row({ space: 12 }) {
                    Column({ space: 4 }) {
                      Text('暂').fontSize(FS_BODY).fontColor(SUB)
                      Text('无').fontSize(FS_BODY).fontColor(SUB)
                      Text('传').fontSize(FS_BODY).fontColor(SUB)
                      Text('世').fontSize(FS_BODY).fontColor(SUB)
                      Text('诗').fontSize(FS_BODY).fontColor(SUB)
                      Text('词').fontSize(FS_BODY).fontColor(SUB)
                    }
                    .alignItems(HorizontalAlign.Center)
                    Column({ space: 3 }) {
                      Text('黄').fontSize(9).fontColor(SURFACE_CARD)
                      Text('河').fontSize(9).fontColor(SURFACE_CARD)
                      Text('志').fontSize(9).fontColor(SURFACE_CARD)
                    }
                    .alignItems(HorizontalAlign.Center)
                    .backgroundColor(SEAL_RED)
                    .padding({ top: 6, bottom: 6, left: 3, right: 3 })
                  }
                  .width('100%')
                  .justifyContent(FlexAlign.Center)
                  .padding({ top: 24, bottom: 24 })
                  .border({ width: { top: 1, bottom: 1 }, color: LINE_HAIR })
                } else {
                  ForEach(this.site.poems, (poem: PoemRef, idx: number) => {
                    this.poemBlock(poem, idx)
                  }, (poem: PoemRef) => poem.text)
                }
                this.readToggle('poems', '诗词')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 24 })
              .backgroundColor(THEME_BG)
              .onAreaChange((_o: Area, a: Area) => {
                this.markSection(2, a);
              })
            }

            RevealOnScroll() {
              Column() {
                this.sectionHead('肆', '文旅', 'tourism')
                this.tourismBlock(this.site.tourism)
                Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                  ForEach(this.site.tags, (t: string) => {
                    Text(t)
                      .fontSize(FS_CAPTION)
                      .fontColor(SUB)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .border({ width: 1, color: LINE_HAIR })
                      .margin({ right: 8, bottom: 8 })
                  }, (t: string) => t)
                }
                .width('100%')
                .margin({ top: 12 })
                this.readToggle('tourism', '文旅')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 24 })
              .backgroundColor(SURFACE_RAISED)
              .onAreaChange((_o: Area, a: Area) => {
                this.markSection(3, a);
              })
            }

            RevealOnScroll() {
              Column() {
                this.sectionHead('伍', '介绍', 'intro')
                this.para(this.site.intro)
                if (this.site.relics.length > 0) {
                  Text('代表文物')
                    .fontSize(FS_CAPTION)
                    .letterSpacing(3)
                    .fontColor(SUB)
                    .margin({ top: 24, bottom: 12 })
                  Scroll() {
                    Row({ space: 16 }) {
                      ForEach(this.site.relics, (r: RelicInfo) => {
                        this.relicCard(r)
                      }, (r: RelicInfo) => r.id)
                    }
                    // 外层 Column 已经有 PAGE_PAD_X，这里只留右侧余量：
                    // 再补一份左边距会把第一张卡推离「代表文物」一个 pad。
                    .padding({ right: PAGE_PAD_X })
                  }
                  .scrollable(ScrollDirection.Horizontal)
                  .scrollBar(BarState.Off)
                  .align(Alignment.Start)
                  .width('100%')
                }
                this.readToggle('intro', '介绍')
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 40 })
              .backgroundColor(THEME_BG)
              .onAreaChange((_o: Area, a: Area) => {
                this.markSection(4, a);
              })
            }

            RevealOnScroll() {
              Column() {
                Row({ space: 10 }) {
                  Text('脉络推荐')
                    .fontSize(FS_TITLE)
                    .fontFamily(FONT_DISPLAY)
                    .fontWeight(WT_DISPLAY)
                    .fontColor(INK)
                  Blank()
                  PressFade() {
                    Text('全部 ›')
                      .fontSize(FS_CAPTION)
                      .fontColor(ACCENT)
                      .onClick(() => {
                        if (this.site === null) { return; }
                        const prm: Record<string, string> = { 'from': this.site.id };
                        router.pushUrl({ url: 'pages/RecommendPage', params: prm });
                      })
                      .focusable(true)
                      .focusBox(focusRing())
                  }
                }
                .width('100%')
                .padding({ top: 24, bottom: 12 })

                ForEach(this.recoRows, (row: RecoRow) => {
                  // 不用 PressFade 包装器：这一行 width('100%') 且内含
                  // layoutWeight(1)，套进包装器后百分比按包装器算、权重
                  // 分配也落在包装器里，标题会被压扁。按压态就地写。
                  Column({ space: 6 }) {
                    Row({ space: 10 }) {
                      Text(row.rank)
                        .fontSize(FS_CAPTION)
                        .fontColor(ACCENT)
                      Text(row.name)
                        .fontSize(FS_TITLE)
                        .fontWeight(WT_BOLD)
                        .fontColor(INK)
                        .layoutWeight(1)
                      Text(row.score)
                        .fontSize(FS_CAPTION)
                        .fontColor(SUB)
                    }
                    .width('100%')
                    Text(row.reasons.join(' · '))
                      .fontSize(FS_CAPTION)
                      .fontColor(SUB)
                      .width('100%')
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .padding({ top: 12, bottom: 12 })
                  .border({ width: { bottom: 1 }, color: LINE_HAIR })
                  .onClick(() => {
                    const prm: Record<string, string> = { 'id': row.id };
                    router.pushUrl({ url: 'pages/DetailPage', params: prm });
                  })
                  .onTouch((e: TouchEvent) => {
                    if (e.type === TouchType.Down) {
                      this.pressedReco = row.id;
                    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                      this.pressedReco = '';
                    }
                  })
                  .opacity(this.pressedReco === row.id ? PRESS_OPACITY : 1)
                  .animation(pressAnim())
                  .focusable(true)
                  .focusBox(focusRing())
                }, (row: RecoRow) => row.id)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 40 })
              .backgroundColor(SURFACE_RAISED)
            }
          }
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
    // 全屏看图：页面级遮罩，不受内层 Scroll 裁剪与滚动影响
    .bindContentCover(this.viewerOpen, this.viewerCover(), {
      onDisappear: () => {
        this.viewerOpen = false;
      }
    })
  }

  @Builder
  viewerCover() {
    ImageViewer({
      images: this.viewerImages,
      credits: this.viewerCredits,
      startIndex: this.viewerIndex,
      onClose: () => {
        this.viewerOpen = false;
      }
    })
  }
}

