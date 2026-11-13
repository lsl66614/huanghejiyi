// entry/src/main/ets/pages/SearchPage.ets —— 全局搜索：遗址 / 文物 / 笔记
//
// 之前三块内容是三条互不相通的入口：遗址在年代卡里，文物在图录里，
// 笔记在笔记中心里。用户记得“彩陶”两个字，却不知道该去哪一页找。
// 本页把三类条目放进同一个结果集，分组展示、关键词高亮、直达详情。
//
// 不做的事：不做模糊纠错、不做拼音、不做全文分词。语料只有 42+104+笔记，
// 子串匹配足够，也不会把“没匹配”伪装成“相关”。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SiteInfo } from '../model/ContentModels';
import type { NoteView } from '../model/UserDataModels';
import { ContentRepo } from '../repository/ContentRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import { BackLink } from '../common/BackLink';
import { eraName, THEME_BG } from '../common/EraTheme';
import { cityName, typeName } from '../common/Labels';
import {
  ACCENT, CARD_PAD, CHIP_RADIUS, FONT_DISPLAY, FONT_SERIF, FS_BODY, FS_CAPTION, FS_ITEM,
  FS_PAGE, HAIR, INK, LH_BODY, LH_CAPTION, LINE_HAIR, PAGE_PAD_X, PRESS_OPACITY,
  RADIUS_CARD_LG, ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SUB, SURFACE_CARD,
  SURFACE_RAISED, WT_DISPLAY
} from '../common/DesignTokens';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';
import { PressFade } from '../common/PressScale';
import { itemLabel } from '../service/content/ItemTarget';

const DOMAIN = 0x0001;
const TAG = 'SearchPage';

const KIND_SITE: string = 'site';
const KIND_RELIC: string = 'relic';
const KIND_NOTE: string = 'note';
const RECENT_KEY: string = 'recentSearch';
const RECENT_MAX: number = 5;

class Hit {
  kind: string = '';
  title: string = '';
  sub: string = '';
  siteId: string = '';
  relicId: string = '';
  noteId: string = '';
  targetKey: string = '';
}

@Entry
@Component
struct SearchPage {
  @State keyword: string = '';
  @State siteHits: Hit[] = [];
  @State relicHits: Hit[] = [];
  @State noteHits: Hit[] = [];
  @State recent: string[] = [];
  @State ready: boolean = false;
  @State failed: boolean = false;
  @State siteAll: boolean = false;
  @State relicAll: boolean = false;
  @State noteAll: boolean = false;
  // 整行结果不能套 Press* 包装器（会按内容定宽），按压态就地写。
  @State pressedKey: string = '';

  private sites: SiteInfo[] = [];
  private notes: NoteView[] = [];
  private siteNames: Map<string, string> = new Map();
  private relicNames: Map<string, string> = new Map();

  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadRecent(ctx);
    ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
      this.sites = sites;
      for (const s of sites) {
        this.siteNames.set(s.id, s.name);
        for (const r of s.relics) {
          this.relicNames.set(r.id, r.name);
        }
      }
      UserDataRepo.allNotes(ctx).then((list: NoteView[]) => {
        this.notes = list;
        this.ready = true;
        this.apply();
      }).catch((_e: Object) => {
        this.ready = true;
        this.apply();
      });
    }).catch((_e: Object) => {
      this.ready = true;
      this.failed = true;
    });
  }

  loadRecent(ctx: common.UIAbilityContext): void {
    UserDataRepo.get(ctx).then((repo) => {
      repo.getMeta(RECENT_KEY).then((json: string) => {
        this.recent = this.parseRecent(json);
      }).catch((_e: Object) => {
        this.recent = [];
      });
    }).catch((_e: Object) => {
      this.recent = [];
    });
  }

  parseRecent(json: string): string[] {
    const out: string[] = [];
    if (json === '') { return out; }
    let arr: string[] | null = null;
    try {
      arr = JSON.parse(json) as string[] | null;
    } catch (_e) {
      arr = null;
    }
    if (arr === null || !Array.isArray(arr)) { return out; }
    for (const w of arr) {
      if (typeof w === 'string' && w !== '' && out.length < RECENT_MAX) {
        out.push(w);
      }
    }
    return out;
  }

  // 搜索词只记 5 条，重复词提到最前，不做“搜索历史云”。
  remember(): void {
    const w: string = this.keyword.trim();
    if (w === '') { return; }
    const out: string[] = [w];
    for (const r of this.recent) {
      if (r !== w && out.length < RECENT_MAX) { out.push(r); }
    }
    this.recent = out;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    UserDataRepo.get(ctx).then((repo) => {
      repo.setMeta(RECENT_KEY, JSON.stringify(out)).catch((e: Object) => {
        hilog.error(DOMAIN, TAG, 'recentSearch save fail: %{public}s', JSON.stringify(e));
      });
    }).catch((_e: Object) => {});
  }

  apply(): void {
    const kw: string = this.keyword.trim().toLowerCase();
    if (kw === '') {
      this.siteHits = [];
      this.relicHits = [];
      this.noteHits = [];
      return;
    }
    const sitesOut: Hit[] = [];
    const relicsOut: Hit[] = [];
    const notesOut: Hit[] = [];

    for (const s of this.sites) {
      if (this.siteMatch(s, kw)) {
        const h = new Hit();
        h.kind = KIND_SITE;
        h.title = s.name;
        h.sub = `${eraName(s.era)} · ${cityName(s.city)} · ${typeName(s.siteType)}`;
        h.siteId = s.id;
        sitesOut.push(h);
      }
      for (const r of s.relics) {
        if (this.relicMatch(r.name, r.material, r.summary, s.name, kw)) {
          const h = new Hit();
          h.kind = KIND_RELIC;
          h.title = r.name;
          h.sub = `${eraName(r.era)} · ${s.name}${r.material === '' ? '' : ' · ' + r.material}`;
          h.siteId = s.id;
          h.relicId = r.id;
          relicsOut.push(h);
        }
      }
    }

    for (const n of this.notes) {
      const label: string = this.labelOf(n.targetKey);
      let tagText: string = '';
      for (const t of n.tagIds) { tagText += t + ' '; }
      if (n.text.toLowerCase().includes(kw) ||
        label.toLowerCase().includes(kw) ||
        tagText.toLowerCase().includes(kw)) {
        const h = new Hit();
        h.kind = KIND_NOTE;
        // 正文为空、只靠标签命中的笔记，行标题不能留白。
        h.title = n.text.trim() !== '' ? n.text : '（空笔记）';
        h.sub = label === '' ? '未关联' : label;
        h.noteId = n.noteId;
        h.targetKey = n.targetKey;
        notesOut.push(h);
      }
    }

    this.siteHits = sitesOut;
    this.relicHits = relicsOut;
    this.noteHits = notesOut;
    // 结果变少时收起“查看全部”，否则会出现“展开一个只有 2 条的组”。
    if (this.siteHits.length <= 3) { this.siteAll = false; }
    if (this.relicHits.length <= 3) { this.relicAll = false; }
    if (this.noteHits.length <= 3) { this.noteAll = false; }
  }

  siteMatch(s: SiteInfo, kw: string): boolean {
    if (s.name.toLowerCase().includes(kw) || s.summary.toLowerCase().includes(kw) ||
      eraName(s.era).toLowerCase().includes(kw) ||
      cityName(s.city).toLowerCase().includes(kw) ||
      typeName(s.siteType).toLowerCase().includes(kw)) {
      return true;
    }
    for (const t of s.tags) {
      if (t.toLowerCase().includes(kw)) { return true; }
    }
    return false;
  }

  relicMatch(name: string, material: string, summary: string, siteName: string,
    kw: string): boolean {
    return name.toLowerCase().includes(kw) ||
      material.toLowerCase().includes(kw) ||
      summary.toLowerCase().includes(kw) ||
      siteName.toLowerCase().includes(kw);
  }

  labelOf(key: string): string {
    if (key === 'notebook:inbox') { return '随手笔记'; }
    const parts: string[] = key.split(':');
    if (parts[0] === 'site') {
      const n = this.siteNames.get(parts[1]);
      if (n !== undefined) {
        const item: string = itemLabel(key, n);
        return item !== '' ? item : n;
      }
    }
    if (parts[0] === 'relic') {
      const n = this.relicNames.get(parts[1]);
      if (n !== undefined) { return n; }
    }
    return key;
  }

  totalOf(kind: string): number {
    if (kind === KIND_SITE) { return this.siteHits.length; }
    if (kind === KIND_RELIC) { return this.relicHits.length; }
    return this.noteHits.length;
  }

  allOf(kind: string): boolean {
    if (kind === KIND_SITE) { return this.siteAll; }
    if (kind === KIND_RELIC) { return this.relicAll; }
    return this.noteAll;
  }

  shownOf(kind: string): Hit[] {
    if (kind === KIND_SITE) {
      return this.siteAll ? this.siteHits : this.siteHits.slice(0, 3);
    }
    if (kind === KIND_RELIC) {
      return this.relicAll ? this.relicHits : this.relicHits.slice(0, 3);
    }
    return this.noteAll ? this.noteHits : this.noteHits.slice(0, 3);
  }

  toggle(kind: string): void {
    if (kind === KIND_SITE) {
      this.siteAll = !this.siteAll;
    } else if (kind === KIND_RELIC) {
      this.relicAll = !this.relicAll;
    } else {
      this.noteAll = !this.noteAll;
    }
  }

  groupLabel(kind: string): string {
    if (kind === KIND_SITE) { return '遗址'; }
    if (kind === KIND_RELIC) { return '文物'; }
    return '笔记';
  }

  hitKey(h: Hit): string {
    return `${h.kind}_${h.siteId}_${h.relicId}_${h.noteId}`;
  }

  openHit(h: Hit): void {
    this.remember();
    if (h.kind === KIND_SITE) {
      const prm: Record<string, string> = { 'id': h.siteId };
      router.pushUrl({ url: 'pages/DetailPage', params: prm });
      return;
    }
    if (h.kind === KIND_RELIC) {
      const prm: Record<string, string> = { 'site': h.siteId, 'relic': h.relicId };
      router.pushUrl({ url: 'pages/RelicPage', params: prm });
      return;
    }
    const prm: Record<string, string> = {
      'target': h.targetKey,
      'title': h.sub === '未关联' ? '随手笔记' : h.sub
    };
    router.pushUrl({ url: 'pages/NotePage', params: prm });
  }

  hitIndex(text: string): number {
    const kw: string = this.keyword.trim().toLowerCase();
    if (kw === '') { return -1; }
    return text.toLowerCase().indexOf(kw);
  }

  kwLen(): number {
    return this.keyword.trim().length;
  }

  hlBefore(text: string): string {
    const i: number = this.hitIndex(text);
    return i < 0 ? text : text.slice(0, i);
  }

  hlMid(text: string): string {
    const i: number = this.hitIndex(text);
    return i < 0 ? '' : text.slice(i, i + this.kwLen());
  }

  hlAfter(text: string): string {
    const i: number = this.hitIndex(text);
    return i < 0 ? '' : text.slice(i + this.kwLen());
  }

  totalHits(): number {
    return this.siteHits.length + this.relicHits.length + this.noteHits.length;
  }

  useWord(w: string): void {
    this.keyword = w;
    this.apply();
  }

  @Builder
  hlText(text: string) {
    Text() {
      Span(this.hlBefore(text))
      Span(this.hlMid(text))
        .fontColor(ACCENT)
      Span(this.hlAfter(text))
    }
    .fontSize(FS_ITEM)
    .fontFamily(FONT_DISPLAY)
    .fontWeight(WT_DISPLAY)
    .fontColor(INK)
    .width('100%')
    .maxLines(2)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  recentChip(w: string) {
    PressFade() {
      Text(w)
        .fontSize(FS_CAPTION)
        .fontColor(INK)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(SURFACE_CARD)
        .border({ width: HAIR, color: LINE_HAIR })
        .borderRadius(CHIP_RADIUS)
        .onClick(() => {
          this.useWord(w);
        })
        .focusable(true)
        .focusBox(focusRing())
        .accessibilityText(`搜索 ${w}`)
    }
  }

  @Builder
  hitRow(h: Hit) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        this.hlText(h.title)
        Text(h.sub)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SERIF)
          .fontColor(SUB)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(FS_ITEM)
        .fontColor(SUB)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: HAIR }, color: LINE_HAIR })
    .onClick(() => {
      this.openHit(h);
    })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.pressedKey = this.hitKey(h);
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .opacity(this.pressedKey === this.hitKey(h) ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`${this.groupLabel(h.kind)}，${h.title}`)
    .accessibilityTextHint(h.sub)
  }

  @Builder
  group(kind: string) {
    if (this.totalOf(kind) > 0) {
      Column({ space: 0 }) {
        Row() {
          Text(this.groupLabel(kind))
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
          Text(` ${this.totalOf(kind)}`)
            .fontSize(FS_CAPTION)
            .fontColor(SUB)
          Blank()
          if (this.totalOf(kind) > 3) {
            PressFade() {
              Text(this.allOf(kind) ? '收起' : `查看全部 ${this.totalOf(kind)} 条`)
                .fontSize(FS_CAPTION)
                .fontColor(ACCENT)
                .onClick(() => {
                  this.toggle(kind);
                })
                .focusable(true)
                .focusBox(focusRing())
            }
          }
        }
        .width('100%')
        .padding({ top: 16, bottom: 4 })
        ForEach(this.shownOf(kind), (h: Hit) => {
          this.hitRow(h)
        }, (h: Hit) => this.hitKey(h))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        BackLink()
        Blank()
        Text('搜索')
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .letterSpacing(2)
          .fontColor(INK)
        Blank()
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 8 })

      Text('遗址、文物、笔记一起搜')
        .fontSize(FS_PAGE)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(INK)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 12 })

      Row({ space: 8 }) {
        Text('搜')
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
        TextInput({ text: this.keyword, placeholder: '仰韶 / 彩陶 / 半坡' })
          .accessibilityText('搜索关键词')
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
          .onSubmit(() => {
            this.remember();
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
      // 页边距只由外层 margin 给，卡内留白用 CARD_PAD。
      // 原先 padding 与 margin 都用 PAGE_PAD_X(20)，输入框内文字
      // 距屏幕 40vp，整条搜索框看着往中间缩。
      .padding({ left: CARD_PAD, right: CARD_PAD })
      .height(44)
      .backgroundColor(SURFACE_CARD)
      .border({ width: HAIR, color: LINE_HAIR })
      .borderRadius(CHIP_RADIUS)
      .margin({ left: PAGE_PAD_X, right: PAGE_PAD_X })

      Scroll() {
        Column() {
          if (!this.ready) {
            Text('正在打开目录…')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .width('100%')
              .padding({ top: 40 })
          } else if (this.failed) {
            Text('语料读取失败，只能搜笔记；请返回后重试。')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .width('100%')
              .padding({ top: 40 })
          } else if (this.keyword.trim() === '') {
            if (this.recent.length > 0) {
              Text('最近搜索')
                .fontSize(FS_CAPTION)
                .letterSpacing(1)
                .fontColor(SUB)
                .width('100%')
                .padding({ top: 24, bottom: 8 })
              Scroll() {
                Row({ space: 8 }) {
                  ForEach(this.recent, (w: string) => {
                    this.recentChip(w)
                  }, (w: string) => `recent_${w}`)
                }
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .width('100%')
              .align(Alignment.Start)
            }
            Text('试试这些词')
              .fontSize(FS_CAPTION)
              .letterSpacing(1)
              .fontColor(SUB)
              .width('100%')
              .padding({ top: 24, bottom: 8 })
            Row({ space: 8 }) {
              this.recentChip('仰韶')
              this.recentChip('彩陶')
              this.recentChip('半坡')
            }
            .width('100%')
            Text('搜索会同时查遗址名与摘要、文物的名称与材质、笔记正文与标签。')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .lineHeight(LH_CAPTION)
              .fontColor(SUB)
              .width('100%')
              .padding({ top: 16 })
          } else if (this.totalHits() === 0) {
            Column({ space: 8 }) {
              Text('没有找到')
                .fontSize(FS_ITEM)
                .fontFamily(FONT_DISPLAY)
                .fontWeight(WT_DISPLAY)
                .fontColor(INK)
              Text(`“${this.keyword.trim()}”没有匹配的遗址、文物或笔记。换个词，或去文物图录按年代 / 材质筛。`)
                .fontSize(FS_CAPTION)
                .fontFamily(FONT_SERIF)
                .lineHeight(LH_CAPTION)
                .fontColor(SUB)
              PressFade() {
                Text('打开文物图录')
                  .fontSize(FS_CAPTION)
                  .fontColor(SURFACE_CARD)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(ACCENT)
                  .borderRadius(CHIP_RADIUS)
                  .onClick(() => {
                    router.pushUrl({ url: 'pages/RelicListPage' });
                  })
                  .focusable(true)
                  .focusBox(focusRing())
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ top: 40 })
          } else {
            Text(`共 ${this.totalHits()} 条：遗址 ${this.siteHits.length} · 文物 ${this.relicHits.length} · 笔记 ${this.noteHits.length}`)
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
              .width('100%')
              .padding({ top: 16 })
            this.group(KIND_SITE)
            this.group(KIND_RELIC)
            this.group(KIND_NOTE)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 24 })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}
