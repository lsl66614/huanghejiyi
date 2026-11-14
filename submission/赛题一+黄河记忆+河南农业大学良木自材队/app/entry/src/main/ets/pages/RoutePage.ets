// entry/src/main/ets/pages/RoutePage.ets —— 一条路线的纵轴
//
// 每一站说明「为什么接在上一站后面」，而不是只报站名。进度不新建表：
// 全站只有 progress 一处记录「读过哪一段」，路线完成度由它派生。
// 收藏状态同理，只读 favorites，不在这一页提供收藏动作——
// 收藏的判断发生在遗址详情页，这里重复一个按钮只会制造两处真相。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { RouteInfo, SiteInfo } from '../model/ContentModels';
import { FavoriteDO, ProgressDO, SECTIONS } from '../model/UserDataModels';
import { ContentRepo } from '../repository/ContentRepo';
import { RouteRepo } from '../repository/RouteRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import {
  nextStopId, pruneRoutes, routeDoneCount, routePercent
} from '../service/content/RouteParse';
import { BackLink } from '../common/BackLink';
import { eraColor, eraName, THEME_BG, THEME_INK } from '../common/EraTheme';
import { cityName, typeName } from '../common/Labels';
import {
  ACCENT, BODY, CHIP_RADIUS, FONT_DISPLAY, FONT_MONO, FONT_SERIF, FS_BODY,
  FS_CAPTION, FS_DISPLAY, FS_ITEM, FS_TITLE, HAIR, LH_BODY, LH_CAPTION, LH_DISPLAY,
  LINE_HAIR, PAGE_PAD_X, PRESS_OPACITY, RADIUS_CARD_LG, RADIUS_TRACK_3,
  ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SUB, SURFACE_CARD, SURFACE_RAISED,
  WT_DISPLAY
} from '../common/DesignTokens';
import { focusRing } from '../common/Accessibility';
import { PressFade } from '../common/PressScale';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';

class StopRow {
  siteId: string = '';
  index: string = '';
  name: string = '';
  meta: string = '';
  note: string = '';
  sections: number = 0;
  done: boolean = false;
  favored: boolean = false;
  next: boolean = false;
}

@Entry
@Component
struct RoutePage {
  @State title: string = '';
  @State subtitle: string = '';
  @State era: string = '';
  @State duration: string = '';
  @State stops: StopRow[] = [];
  @State doneCount: number = 0;
  @State percent: number = 0;
  @State nextId: string = '';
  @State ready: boolean = false;
  @State missing: boolean = false;
  @State failed: boolean = false;
  @State pressedStop: string = '';
  private routeId: string = '';
  private route: RouteInfo | null = null;
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
    const p = router.getParams() as Record<string, string> | undefined;
    this.routeId = p !== undefined ? (p['id'] ?? '') : '';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ContentRepo.load(ctx)
      .then((sites: SiteInfo[]): Promise<RouteInfo[]> => {
        this.sites = sites;
        return RouteRepo.load(ctx);
      })
      .then((routes: RouteInfo[]) => {
        let found: RouteInfo | null = null;
        for (const r of routes) {
          if (r.id === this.routeId) { found = r; break; }
        }
        if (found === null) {
          this.missing = true;
          this.ready = true;
          return;
        }
        const ids: string[] = [];
        for (const s of this.sites) { ids.push(s.id); }
        const pruned = pruneRoutes([found], ids);
        if (pruned.length === 0) {
          this.missing = true;
          this.ready = true;
          return;
        }
        const r = pruned[0];
        this.route = r;
        this.title = r.title;
        this.subtitle = r.subtitle;
        this.era = r.era;
        this.duration = r.duration;
        this.loadStatus(ctx);
      })
      .catch((_e: Object) => {
        this.failed = true;
        this.ready = true;
      });
  }

  // 从详情页返回时重读进度：用户刚在里面勾了「已研读」，
  // 这一页的站点状态必须跟着变，否则会显示成没读。
  onPageShow(): void {
    if (!this.ready || this.route === null) { return; }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loadStatus(ctx);
  }

  private loadStatus(ctx: common.UIAbilityContext): void {
    UserDataRepo.allProgress(ctx)
      .then((prog: ProgressDO[]) => {
        UserDataRepo.listFavoritesOf(ctx)
          .then((favs: FavoriteDO[]) => {
            this.applyStatus(prog, favs);
            this.ready = true;
          })
          .catch((_e: Object) => {
            this.applyStatus(prog, []);
            this.ready = true;
          });
      })
      .catch((_e: Object) => {
        this.failed = true;
        this.ready = true;
      });
  }

  private applyStatus(prog: ProgressDO[], favs: FavoriteDO[]): void {
    const route = this.route;
    if (route === null) { return; }
    const counts: Map<string, number> = new Map();
    for (const p of prog) {
      if (!p.done) { continue; }
      const parts: string[] = p.targetKey.split(':');
      if (parts[0] !== 'site') { continue; }
      const n = counts.get(parts[1]);
      counts.set(parts[1], n === undefined ? 1 : n + 1);
    }
    const favIds: string[] = [];
    for (const f of favs) {
      const parts: string[] = f.targetKey.split(':');
      if (parts[0] === 'site' && !favIds.includes(parts[1])) { favIds.push(parts[1]); }
    }

    const rows: StopRow[] = [];
    const readIds: string[] = [];
    for (let i = 0; i < route.stops.length; i++) {
      const st = route.stops[i];
      let site: SiteInfo | null = null;
      for (const s of this.sites) {
        if (s.id === st.siteId) { site = s; break; }
      }
      if (site === null) { continue; }
      const n = counts.get(st.siteId);
      const sec = n === undefined ? 0 : n;
      const row = new StopRow();
      row.siteId = site.id;
      row.index = i < 9 ? `0${i + 1}` : `${i + 1}`;
      row.name = site.name;
      row.meta = `${eraName(site.era)} · ${cityName(site.city)} · ${typeName(site.siteType)}`;
      row.note = st.note;
      row.sections = sec;
      row.done = sec >= SECTIONS.length;
      row.favored = favIds.includes(site.id);
      rows.push(row);
      if (row.done) { readIds.push(site.id); }
    }

    const nid = nextStopId(route, readIds);
    for (const row of rows) { row.next = nid !== '' && row.siteId === nid; }
    this.nextId = nid;
    this.doneCount = routeDoneCount(route, readIds);
    this.percent = routePercent(route, readIds);
    this.stops = rows;
  }

  private readLabel(s: StopRow): string {
    return s.done ? '五段已读完' : `已读 ${s.sections}/${SECTIONS.length} 节`;
  }

  private openStop(id: string): void {
    if (id === '') { return; }
    const prm: Record<string, string> = { 'id': id };
    router.pushUrl({ url: 'pages/DetailPage', params: prm });
  }

  // 「下一站」优先；整条线读完了就从第一站再来一遍——
  // 按钮文案同步改成「再走一遍」，不假装还有下一站。
  private openNext(): void {
    let id = this.nextId;
    if (id === '' && this.stops.length > 0) { id = this.stops[0].siteId; }
    this.openStop(id);
  }

  @Builder
  statusChip(label: string, filled: boolean) {
    Text(label)
      .fontSize(FS_CAPTION)
      .fontColor(filled ? SURFACE_CARD : SUB)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(filled ? ACCENT : SURFACE_RAISED)
      .borderRadius(CHIP_RADIUS)
  }

  @Builder
  stopItem(s: StopRow) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(s.index)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_MONO)
          .fontColor(ACCENT)
        Text(s.name)
          .fontSize(FS_TITLE)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(THEME_INK)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (s.done) {
          this.statusChip('已读', false)
        } else if (s.next) {
          this.statusChip('下一站', true)
        }
      }
      .width('100%')

      Text(s.meta)
        .fontSize(FS_CAPTION)
        .fontColor(SUB)

      if (s.note !== '') {
        Text(s.note)
          .fontSize(FS_BODY)
          .fontFamily(FONT_SERIF)
          .lineHeight(LH_BODY)
          .fontColor(BODY)
      }

      Row({ space: 8 }) {
        Text(this.readLabel(s))
          .fontSize(FS_CAPTION)
          .fontColor(s.done ? ACCENT : SUB)
        if (s.favored) {
          Text('已收藏')
            .fontSize(FS_CAPTION)
            .fontColor(SUB)
        }
        Blank()
        Text('›')
          .fontSize(FS_ITEM)
          .fontColor(SUB)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 12, right: 12, top: 16, bottom: 16 })
    .border({ width: { bottom: HAIR }, color: LINE_HAIR })
    .onClick(() => {
      this.openStop(s.siteId);
    })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.pressedStop = s.siteId;
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.pressedStop = '';
      }
    })
    .opacity(this.pressedStop === s.siteId ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`${s.index} ${s.name}，${s.meta}，` +
      `${this.readLabel(s)}${s.favored ? '，已收藏' : ''}`)
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
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 8 })

      if (!this.ready) {
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
      } else if (this.missing) {
        Column({ space: 8 }) {
          Text('这条路线不存在')
            .fontSize(FS_ITEM)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(THEME_INK)
          Text('路线表可能更新过，站点对不上语料。回去看看还有哪些线。')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .lineHeight(LH_CAPTION)
            .fontColor(SUB)
          PressFade() {
            Text('看看其他路线')
              .fontSize(FS_CAPTION)
              .fontColor(SURFACE_CARD)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor(ACCENT)
              .borderRadius(CHIP_RADIUS)
              .margin({ top: 8 })
              .onClick(() => {
                // 路线失效回列表：本页只从 RouteListPage push 进来，
                // back 正好回到列表；replace 会在栈里叠出两层列表页。
                router.back();
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
          Column() {
            Column({ space: 6 }) {
              Text(this.title)
                .fontSize(FS_DISPLAY)
                .fontFamily(FONT_DISPLAY)
                .fontWeight(WT_DISPLAY)
                .lineHeight(LH_DISPLAY)
                .fontColor(THEME_INK)
              Text(this.subtitle)
                .fontSize(FS_BODY)
                .fontFamily(FONT_SERIF)
                .lineHeight(LH_BODY)
                .fontColor(SUB)
              Text(`${eraName(this.era)} · ${this.duration} · ${this.stops.length} 站`)
                .fontSize(FS_CAPTION)
                .letterSpacing(1)
                .fontColor(SUB)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .margin({ bottom: 16 })

            // 进度卡：数字、条、下一步动作放在一处，
            // 用户不必先自己找「我读到哪了」再找入口。
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text(`已读 ${this.doneCount}/${this.stops.length} 站`)
                  .fontSize(FS_CAPTION)
                  .fontColor(THEME_INK)
                  .layoutWeight(1)
                Text(`${this.percent}%`)
                  .fontSize(FS_CAPTION)
                  .fontFamily(FONT_MONO)
                  .fontColor(ACCENT)
              }
              .width('100%')
              Row() {
                Row()
                  .width(`${this.percent}%`)
                  .height(3)
                  .backgroundColor(eraColor(this.era))
                  .borderRadius(RADIUS_TRACK_3)
              }
              .width('100%')
              .height(3)
              .backgroundColor(SURFACE_RAISED)
              .borderRadius(RADIUS_TRACK_3)
              Row() {
                PressFade() {
                  Text(this.nextId === '' ? '再走一遍' : '从下一站开始')
                    .fontSize(FS_CAPTION)
                    .fontColor(ACCENT)
                    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    .backgroundColor(SURFACE_RAISED)
                    .borderRadius(CHIP_RADIUS)
                    .onClick(() => {
                      this.openNext();
                    })
                    .focusable(true)
                    .focusBox(focusRing())
                    .accessibilityText(this.nextId === '' ? '从第一站重新走一遍' : '打开下一站')
                }
                Blank()
              }
              .width('100%')
              .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(16)
            .backgroundColor(SURFACE_CARD)
            .border({ width: HAIR, color: LINE_HAIR })
            .borderRadius(RADIUS_CARD_LG)
            .margin({ bottom: 16 })

            // 纵轴：左侧年代色实线由每一站的左边框接成，中间不断开。
            Column() {
              ForEach(this.stops, (s: StopRow) => {
                this.stopItem(s)
              }, (s: StopRow) => `${s.siteId}_${s.sections}_${s.favored}`)
            }
            .width('100%')
            .border({ width: { left: 2 }, color: eraColor(this.era) })

            Text('进度与收藏来自本机的研读记录与收藏夹 · 不需要联网')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .margin({ top: 24 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 8, bottom: 40 })
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
