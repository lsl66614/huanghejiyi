// entry/src/main/ets/pages/RelicPage.ets
// 文物展柜（设计稿④）：全 App 唯一的深色区。
//
// 明暗对照的两极：Index 是白盒地表，这里是展柜深井。这个对比是
// 真实存在的两屏（EntryAbility 锁浅色，没有深色模式），不是合成的
// 展示图——所以「展柜感」只能靠这一页自己的材质建立。
//
// 三条硬约束（全部来自 check_contrast 实测）：
//   1. 交互色走 ON_DARK_GOLD（7.82:1 @ PANEL），**不得退回 ACCENT**——
//      #9C4A2F 在 #1C1A18 上只有 2.84:1。
//   2. 文物名用 eraTextDark(era)（ERA_TEXT_DARK 提亮变体），
//      原块色在深底上最低只有 1.29:1（龙山）。
//   3. 剪影占位的「待入藏」是诚实的占位，别改成好看的空壳——
//      104 件里仍有多数没有实拍，占位态就是这些器物的主画面。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RelicInfo, SiteInfo } from '../model/ContentModels';
import type { FavoriteDO, VisitDO } from '../model/UserDataModels';
import { ContentRepo } from '../repository/ContentRepo';
import { AttributionRepo } from '../repository/AttributionRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import type { AttributionData, AttributionRecord } from '../service/content/Attribution';
import { creditsFor } from '../service/content/Attribution';
import { RecoRow, recoRowsFor, relicRecoFor } from '../service/recommend/RecoSource';
import { eraColor, eraGlow, eraName, eraTextDark } from '../common/EraTheme';
import {
  ACCENT, BODY, CAPSULE_H, CAPSULE_RADIUS,
  CARD_PAD, FONT_DISPLAY, FONT_MONO, FONT_SANS,
  FONT_SERIF, FS_BODY, FS_CAPTION, FS_DISPLAY,
  FS_LABEL, FS_META, FS_PAGE, FS_ITEM,
  FS_TITLE, HAIR, ICON_BTN_H, ICON_BTN_RADIUS,
  INK, ITEM_GAP, LH_BODY, LH_PAGE, LINE_HAIR,
  ON_DARK_ACCENT, ON_DARK_BG, ON_DARK_GOLD, ON_DARK_LINE,
  ON_DARK_PANEL, ON_DARK_RAISED, ON_DARK_SUB, ON_DARK_TEXT,
  ON_DARK_TEXT_ALT, PAGE_PAD_X, PRESS_OPACITY, PRESS_SCALE,
  RADIUS_MD, RADIUS_SM, RADIUS_TRACK_3,
  ROUTE_FADE_MIN, ROUTE_SHIFT_VP, ROW_GAP,
  SUB, SURFACE_CARD, TAB_H, TAB_RADIUS,
  TRANSPARENT, WT_BOLD, WT_DISPLAY, WT_MEDIUM
} from '../common/DesignTokens';
import { AccessionPlate, layerName } from '../common/AccessionPlate';
import { materialKind } from '../common/RelicIcon';
import { firstRealImage, isRealImage, realImagesExclude } from '../common/ImagePolicy';
import { cityName } from '../common/Labels';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';
import { PressScale } from '../common/PressScale';
import { RelatedNotes } from '../common/RelatedNotes';
import { ImageViewer } from '../common/ImageViewer';

const DOMAIN = 0x0001;
const TAG = 'RelicPage';

interface AttrRow {
  k: string;
  v: string;
}

// 相关文物要带上它所属的遗址：RelicPage 的路由参数是 site+relic 二元组，
// 只有 RelicInfo 无法跳转。
class RelicRef {
  id: string = '';
  name: string = '';
  era: string = '';
  material: string = '';
  images: string[] = [];
  siteId: string = '';
  siteName: string = '';
}

class RelatedGroup {
  label: string = '';
  items: RelicRef[] = [];
}

// 主视觉高：整幅实拍铺满，留白由照片自己承担，不再用 210 小图 + 340 黑框。
const MEDIA_H: number = 340;

@Entry
@Component
struct RelicPage {
  @State relic: RelicInfo | null = null;
  @State site: SiteInfo | null = null;
  @State favored: boolean = false;
  // onError 兜底：real_ 图缺文件时 $rawfile 只渲染空白，翻回剪影占位。
  @State imgFailed: boolean = false;
  // 底部笔记胶囊的按压态（Button 用 layoutWeight，不能套包装器）
  @State notePressed: boolean = false;
  // 展柜内标签页（设计稿④ 三枚胶囊 tab）
  @State viewTab: number = 0;

  // P1-2：图集 / 相关文物 / 遗址回流 / 推荐
  @State attributions: AttributionRecord[] = [];
  @State recoRows: RecoRow[] = [];
  // 基于收藏/浏览行为的「相似文物」推荐（赛题第 5 条的"或文物"）。
  // 与 recoRows 并存：那个推遗址，这个推器物。
  @State relicRows: RecoRow[] = [];
  @State relicRecoPressed: string = '';
  @State viewerOpen: boolean = false;
  @State viewerImages: string[] = [];
  @State viewerCredits: string[] = [];
  @State viewerIndex: number = 0;
  // 主视觉按下去要看得见：Stack 是整幅点击区，不能套 PressScale
  // （包装器按内容定宽，会把 100% 宽的图收窄），故手写三段式。
  @State mediaPressed: boolean = false;
  @State sitePressed: boolean = false;
  @State recoPressed: string = '';
  // 相关笔记的重读信号：从笔记页返回展柜时 +1（组件不随页面回前台重建）。
  @State noteEpoch: number = 0;
  private shownOnce: boolean = false;
  // 全量语料：同年代 / 同材质的相关文物要跨遗址查，不能只看本遗址。
  private allSites: SiteInfo[] = [];

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
    const siteId: string = p !== undefined ? (p['site'] ?? '') : '';
    const relicId: string = p !== undefined ? (p['relic'] ?? '') : '';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 署名表与语料独立加载：读不到只是图注少一行，不影响展柜主体。
    AttributionRepo.load(ctx).then((d: AttributionData) => {
      this.attributions = d.images;
    }).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'attribution load fail: %{public}s', JSON.stringify(e));
    });
    ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
      this.allSites = sites;
      let seed: SiteInfo | null = null;
      for (const s of sites) {
        if (s.id !== siteId) { continue; }
        seed = s;
        this.site = s;
        for (const r of s.relics) {
          if (r.id === relicId) {
            this.relic = r;
            break;
          }
        }
        break;
      }
      // 推荐以“所属遗址”为种子：推荐服务目前只吃 SiteInfo。
      // 结果按“同年代 / 同城 / 共享标签”给理由，理由在卡片上可见。
      if (seed !== null) {
        const src: SiteInfo = seed;
        const selfRelic: RelicInfo | null = this.relic;
        UserDataRepo.listFavoritesOf(ctx).then((favs: FavoriteDO[]) => {
          UserDataRepo.recentVisits(ctx, 20).then((visits: VisitDO[]) => {
            this.recoRows = recoRowsFor(src, sites, favs, 3, visits);
            // 文物级推荐（赛题第 5 条的"或文物"）：以当前这件为种子，
            // 用收藏/浏览过的文物做行为加权。与上面的遗址推荐并存——
            // 一个是"顺着遗址再看"，一个是"相似文物"。
            if (selfRelic !== null) {
              this.relicRows = relicRecoFor(selfRelic, sites, favs, 3, visits);
            }
          }).catch((e: Object): void => {
            this.recoRows = recoRowsFor(src, sites, favs, 3, []);
            if (selfRelic !== null) {
              this.relicRows = relicRecoFor(selfRelic, sites, favs, 3, []);
            }
            hilog.error(DOMAIN, TAG, 'visits load fail: %{public}s', JSON.stringify(e));
          });
        }).catch((e: Object): void => {
          hilog.error(DOMAIN, TAG, 'favorites load fail: %{public}s', JSON.stringify(e));
        });
      }
      if (this.relic !== null) {
        // F5：文物浏览埋点；同时记一条所属遗址，供全局推荐吸收
        UserDataRepo.trackVisit(ctx, `relic:${this.relic.id}`).catch((e: Object) => {
          hilog.error(DOMAIN, TAG, 'trackVisit fail: %{public}s', JSON.stringify(e));
        });
        UserDataRepo.trackVisit(ctx, `site:${siteId}`).catch((e: Object) => {
          hilog.error(DOMAIN, TAG, 'trackVisit fail: %{public}s', JSON.stringify(e));
        });
        UserDataRepo.isFavored(ctx, `relic:${this.relic.id}`).then((v: boolean) => {
          this.favored = v;
        });
      }
    });
  }

  // 首次 onPageShow 紧跟 aboutToAppear，组件已自读过一次；只有再次回到
  // 前台（例如从笔记页返回）才递增信号，避免每次进页白读一遍全量笔记。
  onPageShow(): void {
    if (this.shownOnce) {
      this.noteEpoch = this.noteEpoch + 1;
    }
    this.shownOnce = true;
  }

  toggleFav(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (this.relic === null) { return; }
    UserDataRepo.toggleFavorite(ctx, `relic:${this.relic.id}`).then((now: boolean) => {
      this.favored = now;
    });
  }

  openNote(): void {
    if (this.relic === null) { return; }
    const prm: Record<string, string> = {
      'target': `relic:${this.relic.id}`,
      'title': this.relic.name
    };
    router.pushUrl({ url: 'pages/NotePage', params: prm });
  }

  // 入藏序号：本文物在所属遗址 relic 列表中的下标（0-based）。
  // 展签编号「042/104」的前半段——104 是全库文物总数，见 ContentRepo。
  relicIndex(): number {
    if (this.relic === null || this.site === null) { return 0; }
    for (let i = 0; i < this.site.relics.length; i++) {
      if (this.site.relics[i].id === this.relic.id) {
        return i;
      }
    }
    return 0;
  }

  // 展签编号：出土地层 + 年代共同决定（设计稿④「层色即展签色标」）
  plateCode(): string {
    if (this.relic === null) { return ''; }
    const era = this.relic.era;
    return `RELIC · ${era.toUpperCase()} · ${this.relic.id.toUpperCase()}`;
  }

  // 出土层标签：「出土层 · 龙山」制式
  layerLabel(): string {
    if (this.relic === null) { return ''; }
    return `出土层 · ${eraName(this.relic.era)}`;
  }

  // 藏品签的序号来源：本遗址下所有文物 id（保持 relics 数组序）
  siteRelicIds(): string[] {
    if (this.site === null) { return []; }
    const out: string[] = [];
    for (const r of this.site.relics) { out.push(r.id); }
    return out;
  }

  // 有可用实拍（且未解码失败）时才铺大图；否则回藏品签。
  hasRealPhoto(): boolean {
    if (this.relic === null || this.imgFailed) { return false; }
    return firstRealImage(this.relic.images) !== '';
  }

  // 该文物的全部实拍。图条与灯箱都按这个顺序走，
  // 与“第一张 = 主视觉”保持同一口径。
  realImages(): string[] {
    if (this.relic === null) { return []; }
    const out: string[] = [];
    for (const p of this.relic.images) {
      if (isRealImage(p)) { out.push(p); }
    }
    return out;
  }

  // 主视觉已占用的那张之外，还剩几张可看。
  extraImages(): string[] {
    if (this.relic === null) { return []; }
    return realImagesExclude(this.relic.images, firstRealImage(this.relic.images));
  }

  // 当前主视觉的图注（作者 · 许可）。没有署名记录就返回空串，
  // 页面不补“佚名”之类的假信息。
  photoCredit(): string {
    const imgs = this.realImages();
    if (imgs.length === 0) { return ''; }
    const one: string[] = [imgs[0]];
    const lines: string[] = creditsFor(one, this.attributions);
    return lines.length > 0 ? lines[0] : '';
  }

  openViewer(images: string[], startIndex: number): void {
    if (images.length === 0) { return; }
    this.viewerImages = images;
    this.viewerCredits = creditsFor(images, this.attributions);
    this.viewerIndex = startIndex;
    this.viewerOpen = true;
  }

  // 三组相关文物：同遗址 / 同年代 / 同材质，各上限 4 件。
  // 同遗址限制在本地，另两组必须跨全库查——只看本遗址会漏掉
  // “同在仰韶、但出土于另一处”的对照器物。
  relatedGroups(): RelatedGroup[] {
    const out: RelatedGroup[] = [];
    if (this.relic === null) { return out; }
    const selfId: string = this.relic.id;
    const selfEra: string = this.relic.era;
    // 「未记」不是一类材质。不排除它的话，所有材质字段缺失的器物会被
    // 归成一组“同材质”，比不给推荐更误导。
    const rawKind: string = this.relic.material === '' ? '' : materialKind(this.relic.material);
    const selfKind: string = rawKind === '未记' ? '' : rawKind;

    const siteGroup = new RelatedGroup();
    siteGroup.label = '同遗址';
    const srcSite: SiteInfo | null = this.site;
    if (srcSite !== null) {
      for (const r of srcSite.relics) {
        if (r.id === selfId || siteGroup.items.length >= 4) { continue; }
        siteGroup.items.push(this.toRef(r, srcSite.id, srcSite.name));
      }
    }
    if (siteGroup.items.length > 0) { out.push(siteGroup); }

    const eraGroup = new RelatedGroup();
    eraGroup.label = '同年代';
    const kindGroup = new RelatedGroup();
    kindGroup.label = '同材质';
    for (const s of this.allSites) {
      for (const r of s.relics) {
        if (r.id === selfId) { continue; }
        if (r.era === selfEra && eraGroup.items.length < 4) {
          eraGroup.items.push(this.toRef(r, s.id, s.name));
        }
        if (selfKind !== '' && r.material !== '' &&
          materialKind(r.material) === selfKind && kindGroup.items.length < 4) {
          kindGroup.items.push(this.toRef(r, s.id, s.name));
        }
      }
    }
    if (eraGroup.items.length > 0) { out.push(eraGroup); }
    if (kindGroup.items.length > 0) { out.push(kindGroup); }
    return out;
  }

  toRef(r: RelicInfo, siteId: string, siteName: string): RelicRef {
    const ref = new RelicRef();
    ref.id = r.id;
    ref.name = r.name;
    ref.era = r.era;
    ref.material = r.material;
    ref.images = r.images;
    ref.siteId = siteId;
    ref.siteName = siteName;
    return ref;
  }

  openRelic(ref: RelicRef): void {
    if (ref.id === (this.relic !== null ? this.relic.id : '')) { return; }
    const prm: Record<string, string> = { 'site': ref.siteId, 'relic': ref.id };
    router.pushUrl({ url: 'pages/RelicPage', params: prm });
  }

  openSite(): void {
    if (this.site === null) { return; }
    const prm: Record<string, string> = { 'id': this.site.id };
    router.pushUrl({ url: 'pages/DetailPage', params: prm });
  }

  // 推荐行点击：行本身就是一处遗址，直接进它的详情，
  // 不要绕到推荐页再让用户找一遍。
  openReco(row: RecoRow): void {
    const prm: Record<string, string> = { 'id': row.id };
    router.pushUrl({ url: 'pages/DetailPage', params: prm });
  }

  // 「相似文物」行：row.id 是 'relic:{id}'，RelicPage 要 site+relic 二元组。
  // 文物 id 全局唯一，反查所属遗址即可，不需要在行里多塞一个字段。
  openRelicReco(row: RecoRow): void {
    const rid: string = row.id.startsWith('relic:') ? row.id.substring('relic:'.length) : row.id;
    for (const s of this.allSites) {
      for (const r of s.relics) {
        if (r.id !== rid) { continue; }
        const prm: Record<string, string> = { 'site': s.id, 'relic': r.id };
        router.pushUrl({ url: 'pages/RelicPage', params: prm });
        return;
      }
    }
  }

  // 展签序位的文字与图形口径见 relicPosLabel() / posMarks()：
  // 序位是「第几件」，不是百分比，所以这里不再提供 depthPercent()。
  relicPosLabel(): string {
    if (this.relic === null || this.site === null) { return '—'; }
    const total: number = this.site.relics.length;
    if (total <= 0) { return '—'; }
    return `${this.relicIndex() + 1} / ${total}`;
  }

  // 展签序位的分段标记：本遗址共几件器物就画几格，只点亮当前那一格。
  // 刻意不用连续进度条——「第 1 件 / 共 2 件」是序位，不是完成度；
  // 画成填充条会被读成「这一仓收到一半了」，那才是假数据。
  posMarks(): number[] {
    const out: number[] = [];
    if (this.site === null) { return out; }
    const total: number = this.site.relics.length;
    for (let i = 0; i < total; i++) {
      out.push(i);
    }
    return out;
  }

  // 出土信息只陈述数据里有的三件事；不写"出土时已残、经缀合复原"
  // 这类没有出处的修复史（内容纪律：不确定就留空，不编造）。
  originLine(): string {
    if (this.relic === null || this.site === null) { return ''; }
    const era: string = eraName(this.relic.era);
    const m: string = this.relic.material;
    if (m === '') {
      return `该器出自${this.site.name}，年代属${era}。`;
    }
    return `该器出自${this.site.name}，年代属${era}，材质为${m}。`;
  }

  @Builder
  attrRow(row: AttrRow) {
    Row() {
      Text(row.k)
        .fontSize(FS_CAPTION)
        .letterSpacing(2)
        .fontColor(ON_DARK_SUB)
      Blank()
      Text(row.v)
        .fontSize(FS_BODY)
        .fontColor(ON_DARK_TEXT_ALT)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: 1 }, color: ON_DARK_LINE })
  }

  // 三联 Facts 卡（设计稿④）：文化年代 / 出土地点 / 材质（均有数据来源）
  // 列内不再自加 padding：容器已给 CARD_PAD，列再叠一层会把首列文字推到
  // 距屏幕 52vp（页边距 20 + 容器 20 + 列 12），整张卡看着空心。
  @Builder
  factCard(k: string, v: string) {
    Column({ space: 4 }) {
      Text(k)
        .fontSize(FS_CAPTION)
        .fontColor(ON_DARK_SUB)
        .width('100%')
        .textAlign(TextAlign.Center)
      Text(v)
        .fontSize(FS_BODY)
        .fontFamily(FONT_SERIF)
        .fontColor(ON_DARK_TEXT)
        .width('100%')
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  // 展柜内标签页胶囊（设计稿④）
  @Builder
  viewTabCapsule(label: string, idx: number) {
    PressScale() {
      Text(label)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(this.viewTab === idx ? ON_DARK_TEXT : ON_DARK_SUB)
        .height(TAB_H)
        .padding({ left: 16, right: 16 })
        .backgroundColor(this.viewTab === idx ? ON_DARK_RAISED : TRANSPARENT)
        .border({ width: HAIR, color: this.viewTab === idx ? ON_DARK_RAISED : ON_DARK_LINE })
        .borderRadius(TAB_RADIUS)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.viewTab = idx;
        })
        .focusable(true)
        .focusBox(focusRing())
        .accessibilityText(`${label}，${this.viewTab === idx ? '当前视图' : '切换视图'}`)
        .accessibilityLevel('yes')
        .accessibilitySelected(this.viewTab === idx)
    }
  }

  // 所属遗址回流卡：文物页的“上一层”是遗址，不是首页。
  // 点击回 DetailPage（tab 状态会丢，但至少落在正确条目上）。
  @Builder
  siteCard() {
    // 整行 100% 宽，不能套 PressScale（包装器按内容定宽会把卡收窄），
    // 按压态就地写 @State + onTouch。
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text('所属遗址')
          .fontSize(FS_CAPTION)
          .fontColor(ON_DARK_SUB)
        Text(this.site !== null ? this.site.name : '')
          .fontSize(FS_BODY)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(ON_DARK_TEXT)
        Text(this.site !== null
          ? `${eraName(this.site.era)} · ${cityName(this.site.city)}`
          : '')
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SERIF)
          .fontColor(ON_DARK_SUB)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(FS_TITLE)
        .fontColor(ON_DARK_SUB)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ON_DARK_RAISED)
    .border({ width: HAIR, color: ON_DARK_LINE })
    .borderRadius(RADIUS_MD)
    .onClick(() => {
      this.openSite();
    })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.sitePressed = true;
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.sitePressed = false;
      }
    })
    .opacity(this.sitePressed ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(this.site !== null ? `所属遗址 ${this.site.name}，查看遗址详情` : '所属遗址')
  }

  // 相关文物卡：同遗址 / 同年代 / 同材质三组共用一种卡。
  @Builder
  relatedCard(ref: RelicRef) {
    PressScale() {
      Column({ space: 6 }) {
        if (firstRealImage(ref.images) !== '') {
          Image($rawfile(firstRealImage(ref.images)))
            .width(88)
            .height(88)
            .objectFit(ImageFit.Cover)
            .borderRadius(RADIUS_SM)
            .draggable(false)
        } else {
          AccessionPlate({
            plateSize: 88,
            era: ref.era,
            material: ref.material,
            relicId: ref.id,
            siteRelicIds: [],
            onDark: true
          })
        }
        Text(ref.name)
          .fontSize(FS_CAPTION)
          .fontColor(ON_DARK_TEXT_ALT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(88)
        Text(ref.siteName)
          .fontSize(FS_CAPTION)
          .fontColor(ON_DARK_SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(88)
      }
      .width(88)
      .onClick(() => {
        this.openRelic(ref);
      })
      .focusable(true)
      .focusBox(focusRing())
      .accessibilityText(`相关文物 ${ref.name}，${ref.siteName}`)
    }
  }

  @Builder
  relatedBlock() {
    // 单一根节点：@Builder 里直接以 ForEach 开头在部分 API 版本上
    // 会被当成“无根”，外面仍需一层 Column 承接宽度与组间距。
    Column({ space: 12 }) {
      ForEach(this.relatedGroups(), (g: RelatedGroup) => {
        Column({ space: 8 }) {
          Text(`${g.label} · ${g.items.length} 件`)
            .fontSize(FS_CAPTION)
            .fontColor(ON_DARK_SUB)
            .width('100%')
          Scroll() {
            Row({ space: 12 }) {
              ForEach(g.items, (ref: RelicRef) => {
                this.relatedCard(ref)
              }, (ref: RelicRef) => `${g.label}_${ref.id}`)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .align(Alignment.Start)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }, (g: RelatedGroup) => g.label)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  // 推荐行：种子是所属遗址，理由是服务算出来的，不写死。
  @Builder
  recoRow(row: RecoRow) {
    Row({ space: 12 }) {
      Text(row.rank)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_MONO)
        .fontColor(ON_DARK_GOLD)
      Column({ space: 4 }) {
        Text(row.name)
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(ON_DARK_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(row.reasons.join(' · '))
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SERIF)
          .fontColor(ON_DARK_SUB)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(row.score)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_MONO)
        .fontColor(ON_DARK_SUB)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: HAIR }, color: ON_DARK_LINE })
    .onClick(() => {
      this.openReco(row);
    })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.recoPressed = row.id;
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.recoPressed = '';
      }
    })
    .opacity(this.recoPressed === row.id ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`${row.name}，推荐理由 ${row.reasons.join('，')}`)
  }

  // 「相似文物」行：与 recoRow 同版式，但点击进文物页而不是遗址页。
  // 不共用一个 Builder 加布尔参数——@Builder 按值传参只保留首帧，
  // 两组共用一个 Builder 会让点击目标在状态更新后串台。
  @Builder
  relicRecoRow(row: RecoRow) {
    Row({ space: 12 }) {
      Text(row.rank)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_MONO)
        .fontColor(ON_DARK_GOLD)
      Column({ space: 4 }) {
        Text(row.name)
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(ON_DARK_TEXT)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(row.reasons.join(' · '))
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SERIF)
          .fontColor(ON_DARK_SUB)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(row.score)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_MONO)
        .fontColor(ON_DARK_SUB)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
    .border({ width: { bottom: HAIR }, color: ON_DARK_LINE })
    .onClick(() => {
      this.openRelicReco(row);
    })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.relicRecoPressed = row.id;
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.relicRecoPressed = '';
      }
    })
    .opacity(this.relicRecoPressed === row.id ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`${row.name}，推荐理由 ${row.reasons.join('，')}`)
  }

  build() {
    Column() {
      // 顶栏（设计稿④ Actions）：40×40 圆形返回 / 40×40 圆形分享 /
      // 金胶囊收藏（40px 高）+ 右侧页题。
      Row({ space: 10 }) {
        // 圆形返回按钮
        PressScale() {
          Row() {
            Text('‹')
              .fontSize(FS_TITLE)
              .fontColor(ON_DARK_TEXT_ALT)
          }
          .width(ICON_BTN_H)
          .height(ICON_BTN_H)
          .backgroundColor(ON_DARK_PANEL)
          .border({ width: HAIR, color: ON_DARK_LINE })
          .borderRadius(ICON_BTN_RADIUS)
          .justifyContent(FlexAlign.Center)
          .accessibilityText('返回上一页')
          .onClick(() => {
            router.back();
          })
          .focusable(true)
          .focusBox(focusRing())
        }

        Blank()

        Text('文物')
          .fontSize(FS_CAPTION)
          .letterSpacing(3)
          .fontColor(ON_DARK_SUB)

        // 金胶囊收藏（已收藏态）
        PressScale() {
          Row({ space: 8 }) {
            Text(this.favored ? '★' : '☆')
              .fontSize(FS_META)
              .fontColor(this.favored ? ON_DARK_BG : ON_DARK_GOLD)
            Text(this.favored ? '已入展柜' : '收藏')
              .fontSize(FS_META)
              .fontFamily(FONT_DISPLAY)
              .fontWeight(WT_DISPLAY)
              .fontColor(this.favored ? ON_DARK_BG : ON_DARK_GOLD)
          }
          .height(ICON_BTN_H)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.favored ? ON_DARK_GOLD : TRANSPARENT)
          .border({ width: HAIR, color: ON_DARK_GOLD })
          .borderRadius(ICON_BTN_RADIUS)
          .justifyContent(FlexAlign.Center)
          .accessibilityText(this.favored ? '已入展柜，点按取消' : '收藏此文物')
          .accessibilitySelected(this.favored)
          .onClick(() => {
            this.toggleFav();
          })
          .focusable(true)
          .focusBox(focusRing())
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16 })

      // 整页内容一起滚：原先标题/主视觉/Facts/tab 正文全塞在固定高度里，
      // 中间靠 Blank(layoutWeight) 撑开，tab 正文被压成 0 高——点标签页
      // 屏上什么也不出来。改为单一滚动区，底部笔记胶囊仍常驻。
      Scroll() {
        Column() {

      // 文物名。年代与出土地点由下方 Facts 三联卡给，标题下不再重复
      // 一行「仰韶文化 · 开封先民聚落遗存（仰韶时期聚合档案）」——
      // 那条既与 Facts 重复，聚合档案的长名还会顶到屏幕右缘。
      Column({ space: 4 }) {
        Text(this.relic !== null ? this.relic.name : '…')
          .fontSize(FS_PAGE)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(ON_DARK_TEXT)
          .lineHeight(LH_PAGE)
          // 长器物名（「唐三彩釉陶残片与马俑」）在 30pt 下会顶出右缘被切字，
          // 必须允许折到两行并省略号收尾，不能靠单行裁切。
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 12 })

      // 主视觉：有实拍就整幅铺满（不再把 210×210 的小图悬在一大片黑里），
      // 没有实拍才用藏品签居中。层章压在大图左上，深浅底都带描边可读。
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height(MEDIA_H)
          .backgroundColor(ON_DARK_PANEL)
          .radialGradient({
            center: ['50%', '50%'],
            radius: '50%',
            colors: [[this.relic !== null ? this.glowColor() : TRANSPARENT, 0], [TRANSPARENT, 1]]
          })
        if (this.hasRealPhoto()) {
          Image($rawfile(firstRealImage(this.relic !== null ? this.relic.images : [])))
            .width('100%')
            .height(MEDIA_H)
            .objectFit(ImageFit.Cover)
            .draggable(false)
            .onError(() => {
              this.imgFailed = true;
            })
        } else {
          // 藏品签制式：剪影 + 材质章 + 藏编号 + 状态行。
          // 没有实拍的器物，这块就是主画面——按博物馆编目做的，
          // 不是「没做完」的占位（见 common/AccessionPlate.ets）。
          AccessionPlate({
            plateSize: 210,
            era: this.relic !== null ? this.relic.era : '',
            material: this.relic !== null ? this.relic.material : '',
            relicId: this.relic !== null ? this.relic.id : '',
            siteRelicIds: this.siteRelicIds(),
            onDark: true
          })
        }
        // 出土层章（左上）：深底版 LayerBadge 制式
        Row({ space: 8 }) {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.relic !== null
              ? eraTextDark(this.relic.era) : ON_DARK_SUB)
          Text(this.layerLabel())
            .fontSize(FS_CAPTION)
            .fontColor(ON_DARK_TEXT_ALT)
        }
        .position({ left: 16, top: 16 })
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(ON_DARK_PANEL)
        .border({ width: HAIR, color: ON_DARK_LINE })
        .borderRadius(RADIUS_SM)

        // 有实拍才给“点按看大图”的可见提示；藏品签不是可点对象。
        if (this.hasRealPhoto()) {
          Text('点按看大图')
            .fontSize(FS_CAPTION)
            .fontColor(ON_DARK_TEXT_ALT)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(ON_DARK_PANEL)
            .border({ width: HAIR, color: ON_DARK_LINE })
            .borderRadius(RADIUS_SM)
            // 图上角标统一在右上（与 DetailPage 的「示意图」同一制式）；
            // 左上是出土层章，两角各表一职，不再对角散落。
            .position({ right: 16, top: 16 })
        }
      }
      .width('100%')
      .height(MEDIA_H)
      .onClick(() => {
        if (this.hasRealPhoto()) {
          this.openViewer(this.realImages(), 0);
        }
      })
      .onTouch((ev: TouchEvent) => {
        if (ev.type === TouchType.Down) {
          this.mediaPressed = true;
        } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
          this.mediaPressed = false;
        }
      })
      .opacity(this.hasRealPhoto() && this.mediaPressed ? PRESS_OPACITY : 1)
      .animation(pressAnim())
      .focusable(this.hasRealPhoto())
      .focusBox(focusRing())
      .accessibilityText(this.hasRealPhoto()
        ? `${this.relic !== null ? this.relic.name : ''}，实拍 ${this.realImages().length} 张，点按查看大图`
        : `${this.relic !== null ? this.relic.name : ''}，暂无实拍`)
      .accessibilityLevel(this.hasRealPhoto() ? 'yes' : 'no')

      // 实拍图条：主图之外还有几张就列几张，点开灯箱从该张开始。
      // 主图解不出来（rawfile 缺文件）时整条收起，别让用户点进空灯箱。
      if (this.realImages().length > 0 && !this.imgFailed) {
        Row({ space: 8 }) {
          // 分隔符不可省：原来"实拍 · 1 张"与后面的"作者 · 许可"直接相接，
          // 连读成"实拍 · 1 张 Windmemories · CC BY-SA 4.0"，量词与作者
          // 之间没有分隔，语义断裂。
          Text(`实拍 ${this.realImages().length} 张`)
            .fontSize(FS_CAPTION)
            .fontColor(ON_DARK_SUB)
          if (this.photoCredit() !== '') {
            Text('·')
              .fontSize(FS_CAPTION)
              .fontColor(ON_DARK_SUB)
            Text(this.photoCredit())
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(ON_DARK_SUB)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          } else {
            Blank()
          }
          PressScale() {
            Text('图片版权 ›')
              .fontSize(FS_CAPTION)
              .fontColor(ON_DARK_GOLD)
              .accessibilityText('打开图片版权与来源')
              .onClick(() => {
                router.pushUrl({ url: 'pages/CreditsPage' });
              })
              .focusable(true)
              .focusBox(focusRing())
          }
        }
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 10, bottom: 6 })

        if (this.extraImages().length > 0) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.extraImages(), (p: string, i: number) => {
                PressScale() {
                  Image($rawfile(p))
                    .width(84)
                    .height(84)
                    .objectFit(ImageFit.Cover)
                    .borderRadius(RADIUS_SM)
                    .draggable(false)
                    .accessibilityText(`查看第 ${i + 2} 张实拍`)
                    .onClick(() => {
                      this.openViewer(this.realImages(), i + 1);
                    })
                    .focusable(true)
                    .focusBox(focusRing())
                }
              }, (p: string) => p)
            }
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .align(Alignment.Start)
          .padding({ bottom: 8 })
        }
      }

      // 展签序位：分段标记（每件一格，只点亮当前格）
      Row({ space: 10 }) {
        Text('展签序位')
          .fontSize(FS_CAPTION)
          .fontColor(ON_DARK_SUB)
        Text(this.relicPosLabel())
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_MONO)
          .fontColor(ON_DARK_TEXT)
        Row({ space: 4 }) {
          ForEach(this.posMarks(), (i: number) => {
            Row()
              .layoutWeight(1)
              .height(4)
              .borderRadius(RADIUS_TRACK_3)
              .backgroundColor(i === this.relicIndex() ? ON_DARK_GOLD : ON_DARK_RAISED)
          }, (i: number) => `${i}`)
        }
        .layoutWeight(1)
        .height(4)
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 16 })

      // 三联 Facts 卡：三列等宽居中，靠留白分隔。
      // 竖分隔线已删——三列内容长短悬殊（「陶」只有一字），固定 32vp 的线
      // 在行里上下都露缝，把「等宽」强调成了三道栅栏，反而更乱。
      Row({ space: 0 }) {
        if (this.relic !== null && this.site !== null) {
          this.factCard('文化年代', eraName(this.relic.era))
          this.factCard('出土地点', this.site.name)
          this.factCard('材质', this.relic.material === '' ? '未记' : materialKind(this.relic.material))
        }
      }
      .width('100%')
      // 页边距只在这一层给：margin 负责离屏幕，padding 负责卡内留白。
      // 原先两层都用 PAGE_PAD_X，文字被推到距屏幕 40vp，卡心全空。
      // 四边统一 CARD_PAD(16)：14 不在间距档位上，会被 lint_tokens 拦。
      .padding(CARD_PAD)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(ON_DARK_RAISED)
      // 深底上 RAISED(#262320) 与 BG(#121110) 只差 4 个色阶，不描边就是一片
      // 看不清边界的重影；补 ON_DARK_LINE 发丝把卡的轮廓交还出来。
      .border({ width: HAIR, color: ON_DARK_LINE })
      .borderRadius(RADIUS_MD)
      .margin({ left: PAGE_PAD_X, right: PAGE_PAD_X })

      // 展柜内标签页（三枚胶囊）
      Row({ space: 8 }) {
        this.viewTabCapsule('展品说明', 0)
        this.viewTabCapsule('出土信息', 1)
        this.viewTabCapsule('关系图谱', 2)
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16 })

      // 内容区：按 tab 切换（随整页滚动，不再套一层可压缩的 Scroll）
      Column({ space: 12 }) {
          if (this.viewTab === 0) {
            // 展品说明
            Text(this.relic !== null ? this.relic.summary : '')
              .fontSize(FS_BODY)
              .lineHeight(LH_BODY)
              .fontColor(ON_DARK_TEXT_ALT)
              .width('100%')
            if (this.relic !== null && this.site !== null) {
              this.attrRow({ k: '年代', v: eraName(this.relic.era) })
              this.attrRow({ k: '材质', v: this.relic.material })
              this.attrRow({ k: '出土', v: this.site.name })
              this.attrRow({ k: '产地', v: cityName(this.site.city) })
            }
            // 相似文物：以当前这件为种子，用收藏/浏览过的文物做行为加权。
            // 与上方「顺着这处遗址再看」并列——一个是邻站，一个是相似器物。
            if (this.relicRows.length > 0) {
              Column({ space: 4 }) {
                Text('相似文物')
                  .fontSize(FS_CAPTION)
                  .fontColor(ON_DARK_SUB)
                  .width('100%')
                Text('以这件器物为种子，按年代 / 材质 / 出土地算，并参考你收藏与浏览过的器物。')
                  .fontSize(FS_CAPTION)
                  .fontFamily(FONT_SERIF)
                  .fontColor(ON_DARK_SUB)
                  .width('100%')
                ForEach(this.relicRows, (row: RecoRow) => {
                  this.relicRecoRow(row)
                }, (row: RecoRow) => `relic_${row.id}`)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ top: 8 })
            }
            // 推荐：种子 = 所属遗址。理由直接铺在行里，不做“猜你喜欢”的黑箱。
            if (this.recoRows.length > 0) {
              Column({ space: 4 }) {
                Text('顺着这处遗址再看')
                  .fontSize(FS_CAPTION)
                  .fontColor(ON_DARK_SUB)
                  .width('100%')
                Text(this.site !== null ? `以「${this.site.name}」为种子，按年代 / 地域 / 标签算出的邻站。` : '')
                  .fontSize(FS_CAPTION)
                  .fontFamily(FONT_SERIF)
                  .fontColor(ON_DARK_SUB)
                  .width('100%')
                ForEach(this.recoRows, (row: RecoRow) => {
                  this.recoRow(row)
                }, (row: RecoRow) => `reco_${row.id}`)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ top: 8 })
            }
            // 我关于这件器物写的笔记：同一件器物的排前，其次是共享标签的。
            // 没有笔记时组件不占高度，展柜里不会多出一块空白。
            if (this.relic !== null) {
              Column() {
                RelatedNotes({
                  targetKey: `relic:${this.relic.id}`,
                  selfTitle: this.relic.name,
                  dark: true,
                  padX: false,
                  epoch: this.noteEpoch
                })
              }
              .width('100%')
              // 父列本身有 12 的间距，这里只补到 16，与上方推荐的呼吸一致。
              .padding({ top: 4 })
            }
          } else if (this.viewTab === 1) {
            // 出土信息
            Text(this.originLine())
              .fontSize(FS_BODY)
              .lineHeight(LH_BODY)
              .fontColor(ON_DARK_TEXT_ALT)
              .width('100%')
            // 所属遗址：把“回上一层”放在出土信息里，符合检索路径。
            if (this.site !== null) {
              this.siteCard()
            }
            // 共出器物：本站其他文物横滚
            if (this.site !== null && this.site.relics.length > 1) {
              Text('共出器物 ' + (this.site.relics.length - 1) + ' 件')
                .fontSize(FS_CAPTION)
                .fontColor(ON_DARK_SUB)
                .width('100%')
              Scroll() {
                Row({ space: 12 }) {
                  ForEach(this.site.relics, (r: RelicInfo) => {
                    // 跳过当前文物自身：ForEach 里不能写裸 return，
                    // 用 if 包住整块内容，非目标项渲染成空白占位。
                    if (r.id !== (this.relic !== null ? this.relic.id : '')) {
                      PressScale() {
                        Column({ space: 6 }) {
                          AccessionPlate({
                            plateSize: 64,
                            era: r.era,
                            material: r.material,
                            relicId: r.id,
                            siteRelicIds: this.siteRelicIds()
                          })
                          Text(r.name)
                            .fontSize(9)
                            .fontColor(ON_DARK_SUB)
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                            .width(64)
                        }
                        .onClick(() => {
                          const prm: Record<string, string> = {
                            'site': this.site !== null ? this.site.id : '',
                            'relic': r.id
                          };
                          router.pushUrl({ url: 'pages/RelicPage', params: prm });
                        })
                        .focusable(true)
                        .focusBox(focusRing())
                        .accessibilityText(r.name)
                        .accessibilityLevel('yes')
                      }
                    }
                  }, (r: RelicInfo) => r.id)
                }
                .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })
              }
              .scrollable(ScrollDirection.Horizontal)
              .scrollBar(BarState.Off)
              .align(Alignment.Start)
              .width('100%')
            }
          } else {
            // 关系图谱：用三组真实的相关文物替掉原来的“整备中”占位。
            // 组内是语料里查得到的同遗址 / 同年代 / 同材质，不是示意关系。
            Text('与这件器物同处一层的其他藏品')
              .fontSize(FS_BODY)
              .fontFamily(FONT_SERIF)
              .lineHeight(LH_BODY)
              .fontColor(ON_DARK_TEXT_ALT)
              .width('100%')
            if (this.relatedGroups().length === 0) {
              Text('语料中暂时没有可对照的其他器物。')
                .fontSize(FS_CAPTION)
                .fontFamily(FONT_SERIF)
                .fontColor(ON_DARK_SUB)
                .width('100%')
            } else {
              this.relatedBlock()
            }
            PressScale() {
              Text('打开主题网络图 ›')
                .fontSize(FS_CAPTION)
                .fontColor(ON_DARK_GOLD)
                .accessibilityText('打开主题网络图')
                .onClick(() => {
                  router.pushUrl({ url: 'pages/NetworkPage' });
                })
                .focusable(true)
                .focusBox(focusRing())
            }
          }
        }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 24 })

        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')

      // 底部操作：笔记胶囊（收藏已移至顶部 Actions 金胶囊）
      Row({ space: 12 }) {
        // 按钮用 layoutWeight(1)，包装器多出的一层会把权重分配吃掉，
        // 故按压态就地写 onTouch 三段式。
        Button('✎ 笔记')
          .fontSize(FS_BODY)
          .fontColor(ON_DARK_TEXT_ALT)
          .backgroundColor(ON_DARK_PANEL)
          .border({ width: HAIR, color: ON_DARK_LINE })
          .borderRadius(CAPSULE_RADIUS)
          .height(CAPSULE_H)
          .layoutWeight(1)
          .accessibilityText('为这件文物写笔记')
          .focusBox(focusRing())
          .onClick(() => {
            this.openNote();
          })
          .onTouch((e: TouchEvent) => {
            if (e.type === TouchType.Down) {
              this.notePressed = true;
            } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
              this.notePressed = false;
            }
          })
          .scale({ x: this.notePressed ? PRESS_SCALE : 1, y: this.notePressed ? PRESS_SCALE : 1 })
          .animation(pressAnim())
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 12 })

      // 详情页不挂底部导航：与 P3 / P5–P10 一致，统一用「返回」。
      // 原先这里另起一套「地表 / 选层 / 展柜 / 我的」，
      // 与 P1 的「年代 / 收藏 / 笔记 / 我的」并存，是全站两套导航的源头。
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ON_DARK_BG)
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

  glowColor(): string {
    return eraGlow(this.relic !== null ? this.relic.era : '');
  }
}
