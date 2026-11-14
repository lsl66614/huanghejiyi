// entry/src/main/ets/pages/RelicListPage.ets —— 文物图录：104 件器物的全局入口
//
// 之前文物只能从所属遗址进：用户想找「彩陶盆」必须先知道它出土于哪。
// 本页把 sites[].relics 压平成图录，支持年代 / 材质 / 遗址 / 关键词四维筛选。
//
// 图像诚实原则（见 common/ImagePolicy.ets）：有 real_ 实拍就铺实拍，
// 没有就用材质线稿并明确标「线稿」，不拿示意图冒充文物照片。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { ERAS, SiteInfo } from '../model/ContentModels';
import { ContentRepo } from '../repository/ContentRepo';
import { buildRelicIndex, relicHit, RelicEntry, RelicIndex } from '../service/content/RelicIndex';
import { BackLink } from '../common/BackLink';
import { eraColor, eraName, THEME_BG } from '../common/EraTheme';
import { StratumCrumb } from '../common/StratumCrumb';
import { materialKind, relicIconSrc } from '../common/RelicIcon';
import { firstRealImage } from '../common/ImagePolicy';
import {
  ACCENT, BODY, CHIP_H, CHIP_RADIUS, FONT_DISPLAY, FONT_SANS, FONT_SERIF,
  FS_CAPTION, FS_HEAD, FS_ITEM, FS_PAGE, FS_TITLE, HAIR, INK, LINE_HAIR,
  MAT_COLOR_BONE, MAT_COLOR_EARTH, MAT_COLOR_JADE, MAT_COLOR_METAL,
  MAT_COLOR_ORGANIC, MAT_COLOR_POTTERY, MAT_COLOR_STONE, PAGE_PAD_X,
  PRESS_SCALE, RADIUS_CARD_LG, ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SUB,
  SURFACE_CARD, SURFACE_RAISED, WT_DISPLAY
} from '../common/DesignTokens';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';
import { PressFade, PressScale } from '../common/PressScale';

const KINDS: string[] = ['陶', '金属', '土', '玉', '石', '骨', '有机', '未记'];

function kindColor(kind: string): string {
  if (kind === '陶') { return MAT_COLOR_POTTERY; }
  if (kind === '金属') { return MAT_COLOR_METAL; }
  if (kind === '土') { return MAT_COLOR_EARTH; }
  if (kind === '玉') { return MAT_COLOR_JADE; }
  if (kind === '石') { return MAT_COLOR_STONE; }
  if (kind === '骨') { return MAT_COLOR_BONE; }
  if (kind === '有机') { return MAT_COLOR_ORGANIC; }
  return SUB;
}

// 抽体（修复计划 阶段2）：首页「遗址 ⇄ 文物」分段的文物视图直接复用本组件，
// 路由 pages/RelicListPage 保留为兼容入口。
@Component
export struct RelicListBody {
  // true = 被首页「遗址 ⇄ 文物」分段嵌入：此时不挂返回键——
  // 分段不是新压的一页，返回键会指向首页自身，读作死链。
  @Prop embedded: boolean = false;
  @State entries: RelicEntry[] = [];
  @State shown: RelicEntry[] = [];
  @State siteIds: string[] = [];
  @State siteNames: string[] = [];
  @State era: string = '';
  @State kind: string = '';
  @State siteId: string = '';
  @State keyword: string = '';
  @State showFilters: boolean = false;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State realCount: number = 0;
  // 按下的文物 id：GridItem 宽度由网格给，不能套 PressScale（包装器
  // 的 Stack 按内容定宽，会把卡片缩成半格），故用手写三段式。
  @State pressedId: string = '';

  // 计数行：只在"有筛选"或"实拍不齐"时补充信息。
  // 原写法把「总数 / 有实拍数 / 当前数」三段都拼上，全量时三个数字一样，
  // 读作「104 件 · 104 件有实拍 · 当前 104 件」——重复且没有信息量。
  // 当前筛选的遗址名（面包屑最深一段用）。按 siteId 在 siteIds 里定位，
  // 两个数组同源构建、下标一一对应。
  private siteChipName(): string {
    const i: number = this.siteIds.indexOf(this.siteId);
    return i >= 0 && i < this.siteNames.length ? this.siteNames[i] : '';
  }

  private countLine(): string {
    const total: number = this.entries.length;
    const shown: number = this.shown.length;
    if (this.shown.length === this.entries.length) {
      // 无筛选：只说总量与实拍覆盖
      if (this.realCount >= total) {
        return `${total} 件 · 全部有实拍`;
      }
      return `${total} 件 · ${this.realCount} 件有实拍`;
    }
    // 有筛选：当前数 + 实拍覆盖
    const photo: string = this.realCount >= total ? '全部有实拍' : `${this.realCount} 件有实拍`;
    return `当前 ${shown} 件 / 共 ${total} 件 · ${photo}`;
  }

  aboutToAppear(): void {
    const p = router.getParams() as Record<string, string> | undefined;
    if (p !== undefined) {
      this.era = p['era'] ?? '';
      this.siteId = p['site'] ?? '';
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
      const idx: RelicIndex = buildRelicIndex(sites);
      idx.entries.sort((a: RelicEntry, b: RelicEntry): number => {
        const ea: number = ERAS.indexOf(a.era);
        const eb: number = ERAS.indexOf(b.era);
        if (ea !== eb) { return ea - eb; }
        if (a.siteName !== b.siteName) { return a.siteName < b.siteName ? -1 : 1; }
        return a.siteOrder - b.siteOrder;
      });
      this.entries = idx.entries;
      this.siteIds = idx.siteIds;
      this.siteNames = idx.siteNames;
      let real: number = 0;
      for (const e of idx.entries) {
        if (firstRealImage(e.images) !== '') { real++; }
      }
      this.realCount = real;
      this.loading = false;
      this.apply();
    }).catch((err: Object) => {
      this.loading = false;
      this.loadError = err instanceof Error ? err.message : String(err);
    });
  }

  apply(): void {
    const out: RelicEntry[] = [];
    for (const e of this.entries) {
      if (this.era !== '' && e.era !== this.era) { continue; }
      if (this.kind !== '' && materialKind(e.material) !== this.kind) { continue; }
      if (this.siteId !== '' && e.siteId !== this.siteId) { continue; }
      if (!relicHit(e, this.keyword)) { continue; }
      out.push(e);
    }
    this.shown = out;
  }

  clearAll(): void {
    this.era = '';
    this.kind = '';
    this.siteId = '';
    this.keyword = '';
    this.apply();
  }

  hasFilter(): boolean {
    return this.era !== '' || this.kind !== '' || this.siteId !== '' ||
      this.keyword.trim() !== '';
  }

  openRelic(e: RelicEntry): void {
    const prm: Record<string, string> = { 'site': e.siteId, 'relic': e.id };
    router.pushUrl({ url: 'pages/RelicPage', params: prm });
  }

  // 年代 chip：色点 + 名称，选中反白（与 ListPage 同一制式）。
  @Builder
  eraChip(e: string) {
    PressScale() {
      Row({ space: 6 }) {
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.era === e ? SURFACE_CARD : eraColor(e))
        Text(eraName(e))
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SANS)
          .fontColor(this.era === e ? SURFACE_CARD : INK)
      }
      .height(CHIP_H)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.era === e ? INK : SURFACE_CARD)
      .border({ width: HAIR, color: this.era === e ? INK : LINE_HAIR })
      .borderRadius(CHIP_RADIUS)
      .onClick(() => {
        this.era = this.era === e ? '' : e;
        this.apply();
      })
      .focusable(true)
      .focusBox(focusRing())
      .accessibilityText(`${eraName(e)}，${this.era === e ? '已选中' : '未选中'}`)
      .accessibilitySelected(this.era === e)
    }
  }

  // 材质 chip：色点即材质分类色，与 NetworkPage 的材质章同一套。
  @Builder
  kindChip(k: string) {
    PressScale() {
      Row({ space: 6 }) {
        Row()
          .width(8)
          .height(8)
          .borderRadius(4)
          .backgroundColor(this.kind === k ? SURFACE_CARD : kindColor(k))
        Text(k)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SANS)
          .fontColor(this.kind === k ? SURFACE_CARD : INK)
      }
      .height(CHIP_H)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.kind === k ? INK : SURFACE_CARD)
      .border({ width: HAIR, color: this.kind === k ? INK : LINE_HAIR })
      .borderRadius(CHIP_RADIUS)
      .onClick(() => {
        this.kind = this.kind === k ? '' : k;
        this.apply();
      })
      .focusable(true)
      .focusBox(focusRing())
      .accessibilityText(`材质${k}，${this.kind === k ? '已选中' : '未选中'}`)
      .accessibilitySelected(this.kind === k)
    }
  }

  @Builder
  siteChip(id: string, name: string) {
    PressScale() {
      Text(name)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(this.siteId === id ? SURFACE_CARD : BODY)
        .height(CHIP_H)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.siteId === id ? INK : SURFACE_CARD)
        .border({ width: HAIR, color: this.siteId === id ? INK : LINE_HAIR })
        .borderRadius(CHIP_RADIUS)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.siteId = this.siteId === id ? '' : id;
          this.apply();
        })
        .focusable(true)
        .focusBox(focusRing())
        .accessibilityText(`遗址${name}，${this.siteId === id ? '已选中' : '未选中'}`)
        .accessibilitySelected(this.siteId === id)
    }
  }

  @Builder
  relicCard(e: RelicEntry) {
    Column() {
        Stack({ alignContent: Alignment.TopEnd }) {
          if (firstRealImage(e.images) !== '') {
            Image($rawfile(firstRealImage(e.images)))
              .width('100%')
              .aspectRatio(1)
              .objectFit(ImageFit.Cover)
              .draggable(false)
          } else {
            Column() {
              Image($rawfile(relicIconSrc(e.material)))
                .width('58%')
                .height('58%')
                .objectFit(ImageFit.Contain)
                .draggable(false)
            }
            .width('100%')
            .aspectRatio(1)
            .backgroundColor(SURFACE_RAISED)
            .justifyContent(FlexAlign.Center)
          }

          // 角标只说事实：有 real_ 图就是实拍，否则是线稿。
          Text(firstRealImage(e.images) !== '' ? '实拍' : '线稿')
            .fontSize(FS_CAPTION)
            .fontColor(SURFACE_CARD)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor(INK)
            .borderRadius(4)
            .margin({ top: 8, right: 8 })
        }
        .width('100%')

        Column({ space: 4 }) {
          Text(e.name)
            .fontSize(FS_ITEM)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(`${eraName(e.era)} · ${e.siteName}`)
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontColor(SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(12)
      }
      .width('100%')
      .backgroundColor(SURFACE_CARD)
      .border({ width: HAIR, color: LINE_HAIR })
      .borderRadius(RADIUS_CARD_LG)
      .clip(true)
      .onClick(() => {
        this.openRelic(e);
      })
      .onTouch((ev: TouchEvent) => {
        if (ev.type === TouchType.Down) {
          this.pressedId = e.id;
        } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
          this.pressedId = '';
        }
      })
      .scale({
        x: this.pressedId === e.id ? PRESS_SCALE : 1,
        y: this.pressedId === e.id ? PRESS_SCALE : 1
      })
      .animation(pressAnim())
      .focusable(true)
      .focusBox(focusRing())
      .accessibilityText(`文物${e.name}，${eraName(e.era)}，${e.siteName}，` +
        `${firstRealImage(e.images) !== '' ? '实拍' : '线稿'}`)
  }

  build() {
    Column() {
      // ── 顶行（清单 §7.7）：嵌入首页「文物」分段时整行不渲染。
      // 之前只挡了返回键，Blank + 右端「馆藏总目」+ top:16 仍占一行，
      // 首页里就是一条空带顶着一个悬角小字——顶部大片空白的直接来源。
      if (!this.embedded) {
        Row({ space: 12 }) {
          BackLink()
          Blank()
          Text(this.hasFilter() ? '筛选结果' : '馆藏总目')
            .fontSize(FS_CAPTION)
            .letterSpacing(2)
            .fontColor(SUB)
        }
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16 })
      }

      if (this.embedded) {
        // 嵌入态：一行节头，无 30pt、无短杠——分段 tab 已经说明"这是文物线"
        Row({ space: 8 }) {
          Text('文物图录')
            .fontSize(FS_TITLE)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
          Text(this.countLine())
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontColor(SUB)
            .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Bottom)
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 8 })
      } else {
        // 层位面包屑（清单 C2）：地表 › 仰韶 [› 某遗址]
        Column() {
          if (this.era === '') {
            StratumCrumb({ era: '', eraLabel: '' })
          } else if (this.siteId === '') {
            StratumCrumb({ era: this.era, eraLabel: eraName(this.era) })
          } else {
            StratumCrumb({
              era: this.era,
              eraLabel: eraName(this.era),
              siteName: this.siteChipName()
            })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 6 })

        Column({ space: 6 }) {
          Text('文物图录')
            .fontSize(FS_PAGE)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
          Text(this.countLine())
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontColor(SUB)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 12 })
      }

      Row({ space: 12 }) {
        Text('搜')
          .fontSize(FS_CAPTION)
          .letterSpacing(1)
          .fontColor(SUB)
        TextInput({ placeholder: '文物名 / 遗址 / 材质', text: this.keyword })
          .accessibilityText('搜索文物：名称、遗址或材质')
          .layoutWeight(1)
          .fontSize(FS_CAPTION)
          .fontColor(INK)
          .placeholderColor(SUB)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .height(34)
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
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 6, bottom: 10 })
      .border({ width: { bottom: HAIR }, color: LINE_HAIR })

      // 三行筛选各自横向滚动：Row 不会换行，8 个材质胶囊在 360vp 上
      // 必然溢出，整页竖滚也不能把溢出的部分露出来。
      Column({ space: 8 }) {
        Scroll() {
          Row({ space: 4 }) {
            Text('年代')
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
              .margin({ right: 4 })
            ForEach(ERAS, (e: string) => {
              this.eraChip(e)
            }, (e: string) => `era_${e}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .align(Alignment.Start)

        Scroll() {
          Row({ space: 4 }) {
            Text('材质')
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
              .margin({ right: 4 })
            ForEach(KINDS, (k: string) => {
              this.kindChip(k)
            }, (k: string) => `kind_${k}`)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .align(Alignment.Start)

        Row({ space: 8 }) {
          PressFade() {
            Text(this.showFilters ? '收起遗址筛选' : '按遗址筛选')
              .fontSize(FS_CAPTION)
              .fontColor(ACCENT)
              .onClick(() => {
                this.showFilters = !this.showFilters;
              })
              .focusable(true)
              .focusBox(focusRing())
          }
          if (this.siteId !== '') {
            PressFade() {
              Text('清除遗址')
                .fontSize(FS_CAPTION)
                .fontColor(SUB)
                .onClick(() => {
                  this.siteId = '';
                  this.apply();
                })
                .focusable(true)
                .focusBox(focusRing())
            }
          }
          Blank()
          if (this.hasFilter()) {
            PressFade() {
              Text('清空筛选')
                .fontSize(FS_CAPTION)
                .fontColor(SUB)
                .onClick(() => {
                  this.clearAll();
                })
                .focusable(true)
                .focusBox(focusRing())
            }
          }
        }
        .width('100%')

        if (this.showFilters) {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.siteIds, (id: string, i: number) => {
                this.siteChip(id, this.siteNames[i])
              }, (id: string) => `site_${id}`)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .align(Alignment.Start)
        }
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 10, bottom: 10 })

      if (this.loading) {
        Text('正在整理馆藏…')
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 40 })
          .layoutWeight(1)
      } else if (this.loadError !== '') {
        Column({ space: 10 }) {
          Text('馆藏读取失败')
            .fontSize(FS_ITEM)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
          Text(this.loadError)
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontColor(SUB)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 40 })
        .layoutWeight(1)
      } else if (this.shown.length === 0) {
        Column({ space: 10 }) {
          Text('没有符合条件的文物')
            .fontSize(FS_ITEM)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
          Text('换个关键词，或把年代 / 材质 / 遗址放宽。')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontColor(SUB)
          PressFade() {
            Text('清空筛选')
              .fontSize(FS_CAPTION)
              .fontColor(SURFACE_CARD)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .backgroundColor(ACCENT)
              .borderRadius(CHIP_RADIUS)
              .onClick(() => {
                this.clearAll();
              })
              .focusable(true)
              .focusBox(focusRing())
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 40 })
        .layoutWeight(1)
      } else {
        Grid() {
          ForEach(this.shown, (e: RelicEntry) => {
            GridItem() {
              this.relicCard(e)
            }
          }, (e: RelicEntry) => e.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(12)
        .rowsGap(12)
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 24 })
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}

// ── 兼容入口（修复计划 阶段2）：路由 pages/RelicListPage 保留，
// 内容已抽成 RelicListBody，供首页「遗址 ⇄ 文物」分段复用。
@Entry
@Component
struct RelicListPage {
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
      RelicListBody()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}