// entry/src/main/ets/pages/RouteListPage.ets —— 主题路线：人工排过序的遗址清单
//
// 这一页回答的不是「还有哪些遗址没看」，而是「先看哪、后看哪」。
// 列表按年代排序（语料顺序），每条线给一句副题和完成度；
// 完成度与首页年代卡同口径：五段全读完才算一站，避免「点开过」冒充「读过」。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { RouteInfo, SiteInfo } from '../model/ContentModels';
import { ProgressDO, SECTIONS } from '../model/UserDataModels';
import { ContentRepo } from '../repository/ContentRepo';
import { RouteRepo } from '../repository/RouteRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import { pruneRoutes, routeDoneCount, routePercent } from '../service/content/RouteParse';
import { BackLink } from '../common/BackLink';
import { eraColor, eraName, THEME_BG, THEME_INK } from '../common/EraTheme';
import {
  ACCENT, BLOCK_GAP, CHIP_RADIUS, FONT_DISPLAY, FONT_SERIF, FS_BODY, FS_CAPTION,
  FS_DISPLAY, FS_ITEM, HAIR, LH_BODY, LH_CAPTION, LH_DISPLAY, LINE_HAIR,
  PAGE_PAD_X, PRESS_OPACITY, RADIUS_CARD_LG, RADIUS_TRACK_3,
  ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SUB, SURFACE_CARD, SURFACE_RAISED,
  WT_DISPLAY
} from '../common/DesignTokens';
import { focusRing } from '../common/Accessibility';
import { PressFade } from '../common/PressScale';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';

class RouteRow {
  id: string = '';
  title: string = '';
  subtitle: string = '';
  era: string = '';
  duration: string = '';
  stops: number = 0;
  done: number = 0;
  percent: number = 0;
}

@Entry
@Component
struct RouteListPage {
  @State rows: RouteRow[] = [];
  @State loading: boolean = true;
  @State failed: boolean = false;
  @State pressed: string = '';
  private routes: RouteInfo[] = [];
  private sites: SiteInfo[] = [];

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
    ContentRepo.load(ctx)
      .then((sites: SiteInfo[]): Promise<RouteInfo[]> => {
        this.sites = sites;
        return RouteRepo.load(ctx);
      })
      .then((routes: RouteInfo[]): Promise<ProgressDO[]> => {
        this.routes = routes;
        return UserDataRepo.allProgress(ctx);
      })
      .then((prog: ProgressDO[]) => {
        this.buildRows(prog);
        this.loading = false;
      })
      .catch((_e: Object) => {
        this.failed = true;
        this.loading = false;
      });
  }

  // 完成度只认「五段全读完」，口径写在这里一次，两个页面共用。
  private readSiteIds(prog: ProgressDO[]): string[] {
    const counts: Map<string, number> = new Map();
    for (const p of prog) {
      if (!p.done) { continue; }
      const parts: string[] = p.targetKey.split(':');
      if (parts[0] !== 'site') { continue; }
      const n = counts.get(parts[1]);
      counts.set(parts[1], n === undefined ? 1 : n + 1);
    }
    const out: string[] = [];
    for (const s of this.sites) {
      const n = counts.get(s.id);
      if (n !== undefined && n >= SECTIONS.length) { out.push(s.id); }
    }
    return out;
  }

  private buildRows(prog: ProgressDO[]): void {
    const ids: string[] = [];
    for (const s of this.sites) { ids.push(s.id); }
    const read = this.readSiteIds(prog);
    const out: RouteRow[] = [];
    for (const r of pruneRoutes(this.routes, ids)) {
      const row = new RouteRow();
      row.id = r.id;
      row.title = r.title;
      row.subtitle = r.subtitle;
      row.era = r.era;
      row.duration = r.duration;
      row.stops = r.stops.length;
      row.done = routeDoneCount(r, read);
      row.percent = routePercent(r, read);
      out.push(row);
    }
    this.rows = out;
  }

  private open(r: RouteRow): void {
    const prm: Record<string, string> = { 'id': r.id };
    router.pushUrl({ url: 'pages/RoutePage', params: prm });
  }

  @Builder
  routeCard(r: RouteRow) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Row()
          .width(6)
          .height(56)
          .backgroundColor(eraColor(r.era))
        Column({ space: 4 }) {
          Text(r.title)
            .fontSize(FS_ITEM)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .letterSpacing(1)
            .fontColor(THEME_INK)
          Text(r.subtitle)
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .lineHeight(LH_CAPTION)
            .fontColor(SUB)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Text('›')
          .fontSize(FS_ITEM)
          .fontColor(SUB)
      }
      .width('100%')

      Row({ space: 8 }) {
        Text(`${eraName(r.era)} · ${r.duration} · ${r.stops} 站`)
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
          .layoutWeight(1)
        Text(r.done === 0 ? '未开始' : `已读 ${r.done}/${r.stops}`)
          .fontSize(FS_CAPTION)
          .fontColor(r.done === r.stops ? ACCENT : SUB)
      }
      .width('100%')

      Row() {
        Row()
          .width(`${r.percent}%`)
          .height(3)
          .backgroundColor(eraColor(r.era))
          .borderRadius(RADIUS_TRACK_3)
      }
      .width('100%')
      .height(3)
      .backgroundColor(SURFACE_RAISED)
      .borderRadius(RADIUS_TRACK_3)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(SURFACE_CARD)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(RADIUS_CARD_LG)
    .onClick(() => {
      this.open(r);
    })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.pressed = r.id;
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.pressed = '';
      }
    })
    .opacity(this.pressed === r.id ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`路线${r.title}，${r.subtitle}，${r.stops}站，已读${r.done}站`)
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        BackLink()
        Blank()
        Text('主题路线')
          .fontSize(FS_CAPTION)
          .letterSpacing(3)
          .fontColor(SUB)
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16 })

      Column({ space: 6 }) {
        Text('沿一条线看下去')
          .fontSize(FS_DISPLAY)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .lineHeight(LH_DISPLAY)
          .fontColor(THEME_INK)
        Text('每条线按顺序串起几处遗址，说明这一站为什么接在上一站后面。进度按「五段全部读完」计。')
          .fontSize(FS_BODY)
          .fontFamily(FONT_SERIF)
          .lineHeight(LH_BODY)
          .fontColor(SUB)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 12 })

      if (this.loading) {
        Text('正在展开路线…')
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SERIF)
          .fontColor(SUB)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 40 })
          .layoutWeight(1)
      } else if (this.failed) {
        Text('路线读取失败。返回后重试。')
          .fontSize(FS_BODY)
          .fontFamily(FONT_SERIF)
          .fontColor(SUB)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 40 })
          .layoutWeight(1)
      } else if (this.rows.length === 0) {
        Column({ space: 8 }) {
          Text('暂时没有可走的路线')
            .fontSize(FS_ITEM)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(THEME_INK)
          Text('路线表里至少要有两处能对上语料的遗址才会显示。先去全部遗址里看看。')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .lineHeight(LH_CAPTION)
            .fontColor(SUB)
          PressFade() {
            Text('去全部遗址')
              .fontSize(FS_CAPTION)
              .fontColor(SURFACE_CARD)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor(ACCENT)
              .borderRadius(CHIP_RADIUS)
              .margin({ top: 8 })
              .onClick(() => {
                // push 不是 replace：replace 会把路线列表页吞掉。
                router.pushUrl({ url: 'pages/ListPage' });
              })
              .focusable(true)
              .focusBox(focusRing())
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 32 })
        .layoutWeight(1)
      } else {
        Scroll() {
          Column({ space: BLOCK_GAP }) {
            ForEach(this.rows, (r: RouteRow) => {
              this.routeCard(r)
            }, (r: RouteRow) => `${r.id}_${r.done}`)
          }
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 40 })
        }
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}
