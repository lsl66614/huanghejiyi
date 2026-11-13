// entry/src/main/ets/pages/FavoritesPage.ets
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { ERAS, SiteInfo } from '../model/ContentModels';
import { FavoriteDO, FavoriteTagDO, PRESET_TAGS } from '../model/UserDataModels';
import { ContentRepo } from '../repository/ContentRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import { BackLink } from '../common/BackLink';
import { eraColor, eraName, THEME_BG, THEME_INK } from '../common/EraTheme';
import {
  ACCENT, BODY, FONT_DISPLAY, FONT_MONO, FONT_SERIF, FS_BODY,
  FS_CAPTION, FS_DISPLAY, FS_HERO, FS_LABEL, FS_MICRO,
  FS_TITLE, HAIR, INK, ITEM_GAP, LINE_HAIR, ON_DARK_TEXT, PAGE_PAD_X, PRESS_SCALE,
  RADIUS_MD, RADIUS_SM, ROW_GAP,
  ROUTE_FADE_MIN, ROUTE_SHIFT_VP,
  SUB, SURFACE_CARD, WT_BOLD,
  WT_DISPLAY, WT_REGULAR, WT_SERIF
} from '../common/DesignTokens';
import { AccessionPlate } from '../common/AccessionPlate';
import { cityName, typeName } from '../common/Labels';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut } from '../common/Motion';
import { PressFade, PressScale } from '../common/PressScale';
import { pressAnim } from '../common/Motion';
import { SectionTitle } from '../common/SectionTitle';
import { IconMenu, MenuEntry } from '../common/IconMenu';
import { SegmentTab, SegmentItem } from '../common/SegmentTab';
import { EmptyState } from '../common/EmptyState';
import { firstRealImage } from '../common/ImagePolicy';
import { LayerBadge } from '../common/LayerBadge';

// 视图切换的两个键（清单 C3）：与 IconMenu 的 onPick 同口径
// 三种视图（修复计划 §7.14）：展厅的分组轴。
// 年代＝挂在第几层；标签＝按标签看时组头就是标签；时间＝按收下的日子排。
const VIEW_LAYER: string = 'layer';
const VIEW_TAG: string = 'tag';
const VIEW_TIME: string = 'time';

// 图块宽高比：3:2 横图。图录（RelicListPage）用的是 1:1 方块——
// 展厅挂的是"场景"，图录摆的是"器物"，两个网格必须一眼分得开。
const WALL_ASPECT: number = 1.5;

class FavEntry {
  key: string = '';
  kind: string = '';      // 'site' | 'relic'
  title: string = '';
  meta: string = '';
  era: string = '';
  material: string = '';
  time: number = 0;
  siteId: string = '';
  relicId: string = '';
  tags: string[] = [];
  // 该条目的首张实拍（rawfile 相对路径）。站点与文物的实拍都已进仓，
  // 卡片缩略直接用它；空串才落到年代色块占位。
  img: string = '';
  // 站点所在城市（图块 meta 用；文物留空，用 material）
  short: string = '';
}

// 贴标签弹窗：复用预置三标签 + 笔记里建过的用户标签，并可就地新建
@CustomDialog
struct TagPickerDialog {
  title: string = '';
  tags: string[] = [];
  selected: string[] = [];
  controller: CustomDialogController;
  onConfirm: (picked: string[]) => void = () => {};
  onCreateTag: (name: string) => void = () => {};
  @State picked: string[] = [];
  @State draft: string = '';

  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }

  aboutToAppear(): void {
    this.picked = this.selected.slice();
  }

  isPicked(t: string): boolean {
    return this.picked.includes(t);
  }

  createTag(): void {
    const name = this.draft.trim();
    if (name === '') { return; }
    if (!this.tags.includes(name)) {
      this.onCreateTag(name);
      if (!this.picked.includes(name)) {
        this.picked = this.picked.concat([name]);
      }
    }
    this.draft = '';
  }

  toggle(t: string, on: boolean): void {
    const next: string[] = this.picked.slice();
    if (on) {
      if (!next.includes(t)) { next.push(t); }
    } else {
      const idx = next.indexOf(t);
      if (idx >= 0) { next.splice(idx, 1); }
    }
    this.picked = next;
  }

  build() {
    Column({ space: 12 }) {
      Text(`为《${this.title}》贴标签`)
        .fontSize(FS_TITLE)
        .fontWeight(WT_BOLD)
        .fontColor(THEME_INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Column({ space: 4 }) {
        ForEach(this.tags, (t: string) => {
          Row() {
            Text(t)
              .fontSize(FS_BODY)
              .fontColor(THEME_INK)
              .layoutWeight(1)
            Checkbox()
              .select(this.isPicked(t))
              .selectedColor(ACCENT)
              .onChange((on: boolean) => {
                this.toggle(t, on);
              })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
        }, (t: string) => t)
      }
      .width('100%')

      Row({ space: 10 }) {
        TextInput({ text: this.draft, placeholder: '新标签，如 彩陶 / 都邑' })
          .accessibilityText('新标签名称')
          .fontSize(FS_BODY)
          .fontColor(THEME_INK)
          .placeholderColor(SUB)
          .backgroundColor(Color.Transparent)
          .border({ width: { bottom: HAIR }, color: { bottom: LINE_HAIR }, style: BorderStyle.Solid })
          .height(36)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.draft = v;
          })
          .onSubmit(() => {
            this.createTag();
          })
        PressScale() {
          Text('新建')
            .fontSize(FS_BODY)
            .fontColor(ON_DARK_TEXT)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(ACCENT)
            .onClick(() => {
              this.createTag();
            })
            .focusable(true)
            .focusBox(focusRing())
        }
      }
      .width('100%')

      Row({ space: 16 }) {
        PressFade() {
          Text('取消')
            .fontSize(FS_BODY)
            .fontColor(SUB)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .onClick(() => {
              this.controller.close();
            })
            .focusable(true)
            .focusBox(focusRing())
        }
        PressScale() {
          Text('保存')
            .fontSize(FS_BODY)
            .fontColor(ON_DARK_TEXT)
            .letterSpacing(2)
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 8, bottom: 8 })
            .backgroundColor(ACCENT)
            .onClick(() => {
              this.onConfirm(this.picked.slice());
              this.controller.close();
            })
            .focusable(true)
            .focusBox(focusRing())
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('86%')
    .padding(24)
    .backgroundColor(THEME_BG)
    // 弹层轮廓用发丝，不用 ACCENT：赭红留给选中态与主按钮（清单 §1.1）
    .border({ width: HAIR, color: LINE_HAIR })
  }
}

class DayGroup {
  day: string = '';
  entries: FavEntry[] = [];
}

// 按标签分组的一组。同一条收藏有多个标签时会出现在多个组里——
// 这就是「按标签看」该有的语义，不做「只归入主标签」的取舍。
class TagGroup {
  tag: string = '';
  entries: FavEntry[] = [];
}
// 图墙的一组（修复计划 §7.14）：三种视图共用同一个结构，渲染层只认它。
// badge 只有年代视图给（L1–L6），标签/时间视图留空走另一种层头。
class WallGroup {
  badge: string = '';
  era: string = '';
  label: string = '';
  count: number = 0;
  entries: FavEntry[] = [];
}

// 抽体（修复计划 §7.13）：本 struct 只由 pages/FavoritesPage 承载——
// 它原先还被档案页内嵌成分段，那会在同一屏叠出「档案 30pt + 收藏」两个大标题。
// 现在档案页改为四张入口卡、点进来是独立一页，一屏只有一个标题。
@Component
export struct FavoritesBody {
  @State entries: FavEntry[] = [];     // 全量
  @State shown: FavEntry[] = [];       // 当前标签筛选后
  // 视图（分组轴）：年代 / 标签 / 时间（§7.14）
  @State view: string = VIEW_LAYER;
  @State tag: string = '全部';
  @State tagChips: string[] = ['全部'].concat(PRESET_TAGS);
  // 图墙分组：view 变了就重建，渲染层只认这一个结构
  @State wallGroups: WallGroup[] = [];
  // 按下的收藏条目 key：@Builder 产物是独立子树，按压态只能记在页面上。
  @State pressedEntry: string = '';
  // 缩略实拍加载失败的 key：失败一次就回落年代色块，不再重试。
  @State thumbFailed: string[] = [];
  private ctx: common.UIAbilityContext | null = null;
  private tagDialog: CustomDialogController | null = null;

  aboutToAppear(): void {
    this.ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.reload();
    const ctx = this.ctx;
    UserDataRepo.allTags(ctx).then((tags: string[]) => {
      const chips: string[] = ['全部'];
      for (const t of tags) {
        if (!chips.includes(t)) { chips.push(t); }
      }
      this.tagChips = chips;
    });
  }

  // 推送页的刷新桥（修复计划 §7.14）：本 body 不是 @Entry，onPageShow
  // 写在这里不会触发；壳页把可见性记成 pageTick，这里 @Watch 它。
  @Prop @Watch('onPageTick') pageTick: number = 0;
  private loadedOnce: boolean = false;

  onPageTick(): void {
    if (!this.loadedOnce) {
      // 首帧已由 aboutToAppear 拉过，这次进入不重复读库。
      this.loadedOnce = true;
      return;
    }
    if (this.ctx !== null) { this.reload(); }
  }

  reload(): void {
    const ctx = this.ctx;
    if (ctx === null) { return; }
    UserDataRepo.listFavoritesOf(ctx).then((favs: FavoriteDO[]) => {
      UserDataRepo.favoriteTagRows(ctx).then((rows: FavoriteTagDO[]) => {
        ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
          this.entries = this.resolve(favs, sites, rows);
          this.applyFilter();
        });
      });
    });
  }

  resolve(favs: FavoriteDO[], sites: SiteInfo[], rows: FavoriteTagDO[]): FavEntry[] {
    const tagMap: Map<string, string[]> = new Map();
    for (const r of rows) {
      const arr = tagMap.get(r.targetKey);
      if (arr === undefined) {
        tagMap.set(r.targetKey, [r.tagId]);
      } else {
        arr.push(r.tagId);
      }
    }
    const out: FavEntry[] = [];
    for (const f of favs) {
      const parts: string[] = f.targetKey.split(':');
      const kind = parts[0];
      const id = parts[1];
      for (const s of sites) {
        if (kind === 'site' && s.id === id) {
          const e = new FavEntry();
          e.key = f.targetKey; e.kind = 'site'; e.title = s.name;
          e.meta = `${eraName(s.era)} · ${cityName(s.city)} · ${typeName(s.siteType)}`;
          e.era = s.era; e.time = f.updateTime; e.siteId = s.id; e.relicId = '';
          e.img = firstRealImage(s.images);
          e.short = cityName(s.city);
          const tagsHere = tagMap.get(f.targetKey);
          e.tags = tagsHere === undefined ? [] : tagsHere;
          out.push(e);
          break;
        }
        if (kind === 'relic') {
          for (const r of s.relics) {
            if (r.id === id) {
              const e = new FavEntry();
              e.key = f.targetKey; e.kind = 'relic'; e.title = r.name;
              e.meta = `${eraName(r.era)} · ${r.material} · 出自${s.name}`;
              e.era = r.era; e.material = r.material; e.time = f.updateTime; e.siteId = s.id; e.relicId = r.id;
              e.img = firstRealImage(r.images);
              const tagsHere2 = tagMap.get(f.targetKey);
              e.tags = tagsHere2 === undefined ? [] : tagsHere2;
              out.push(e);
              break;
            }
          }
        }
      }
    }
    return out;
  }

  applyFilter(): void {
    if (this.tag === '全部') {
      this.shown = this.entries;
    } else {
      this.shown = this.entries.filter((e: FavEntry): boolean => e.tags.includes(this.tag));
    }
    this.buildWall();
  }

  // 图墙分组。年代视图按 ERAS 序，空层不渲染——展厅只挂手里有的东西，
  // 不画六格空位（那是在说「这里本该有展品」，而它只是没收到过）。
  buildWall(): void {
    const out: WallGroup[] = [];
    if (this.view === VIEW_LAYER) {
      for (const era of ERAS) {
        const list: FavEntry[] = this.shown.filter((e: FavEntry): boolean => e.era === era);
        if (list.length === 0) { continue; }
        const g = new WallGroup();
        g.badge = `L${ERAS.indexOf(era) + 1}`;
        g.era = era;
        g.label = eraName(era);
        g.count = list.length;
        g.entries = list;
        out.push(g);
      }
    } else if (this.view === VIEW_TAG) {
      for (const t of this.buildTagGroups()) {
        const g = new WallGroup();
        g.label = t.tag;
        g.count = t.entries.length;
        g.entries = t.entries;
        out.push(g);
      }
    } else {
      for (const d of this.buildDays()) {
        const g = new WallGroup();
        g.label = d.day;
        g.count = d.entries.length;
        g.entries = d.entries;
        out.push(g);
      }
    }
    this.wallGroups = out;
  }

  viewName(): string {
    if (this.view === VIEW_LAYER) { return '年代'; }
    return this.view === VIEW_TAG ? '标签' : '时间';
  }

  // meta 行回答「这一格在当前视图里还缺什么」：按年代看时层头已经说了
  // 年代，meta 给地点/材质；另外两种视图没有年代轴，meta 就把年代补回来。
  tileMeta(e: FavEntry): string {
    const kind: string = e.kind === 'site' ? '遗址' : '文物';
    if (this.view === VIEW_LAYER) {
      return e.kind === 'site' ? `${kind} · ${e.short}` : `${kind} · ${e.material}`;
    }
    return `${eraName(e.era)} · ${kind}`;
  }

  // 按标签分组（设计稿 §4.2）。同一条收藏有多个标签时会出现在多个组里——
  // 这就是「按标签看」该有的语义，不做「只归入主标签」的取舍。
  // 顺序：预置标签在前（按 PRESET_TAGS 序），用户标签按字母序在后，
  // 无标签的统一收进末尾「未分类」——不让它们凭空消失。
  buildTagGroups(): TagGroup[] {
    const ordered: TagGroup[] = [];
    const byTag: Map<string, TagGroup> = new Map();
    const untagged: TagGroup = new TagGroup();
    untagged.tag = '未分类';

    for (const e of this.shown) {
      if (e.tags.length === 0) {
        untagged.entries.push(e);
        continue;
      }
      for (const t of e.tags) {
        // 已按某个标签筛选时只建这一组：否则同一条目会以它的另一个
        // 标签再出现一次，用户筛「研究资料」却看到「待实地探访」组，
        // 与顶部「1/3 条」也对不上。
        if (this.tag !== '全部' && t !== this.tag) { continue; }
        let g = byTag.get(t);
        if (g === undefined) {
          g = new TagGroup();
          g.tag = t;
          byTag.set(t, g);
          ordered.push(g);
        }
        g.entries.push(e);
      }
    }

    const presetOrder: Map<string, number> = new Map();
    for (let i = 0; i < PRESET_TAGS.length; i++) { presetOrder.set(PRESET_TAGS[i], i); }
    ordered.sort((a: TagGroup, b: TagGroup): number => {
      const pa = presetOrder.get(a.tag);
      const pb = presetOrder.get(b.tag);
      if (pa !== undefined && pb !== undefined) { return pa - pb; }
      if (pa !== undefined) { return -1; }
      if (pb !== undefined) { return 1; }
      return a.tag < b.tag ? -1 : (a.tag > b.tag ? 1 : 0);
    });

    if (untagged.entries.length > 0) { ordered.push(untagged); }
    return ordered;
  }
  openTagPicker(e: FavEntry): void {
    const ctx = this.ctx;
    if (ctx === null) { return; }
    const opts: string[] = this.tagChips.filter((t: string): boolean => t !== '全部');
    this.tagDialog = new CustomDialogController({
      builder: TagPickerDialog({
        title: e.title,
        tags: opts,
        selected: e.tags,
        onCreateTag: (name: string) => {
          const ctx = this.ctx;
          if (ctx === null) { return; }
          UserDataRepo.ensureTag(ctx, name).then(() => {
            this.reload();
          });
        },
        onConfirm: (picked: string[]) => {
          this.confirmTags(e.key, picked);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.tagDialog.open();
  }

  confirmTags(key: string, picked: string[]): void {
    const ctx = this.ctx;
    if (ctx === null) { return; }
    UserDataRepo.assignFavoriteTags(ctx, key, picked).then(() => {
      this.reload();
    });
  }

  buildDays(): DayGroup[] {
    const groups: DayGroup[] = [];
    for (const e of this.shown) {
      const d = new Date(e.time);
      const label = `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`;
      let hit: DayGroup | null = null;
      for (const g of groups) {
        if (g.day === label) { hit = g; break; }
      }
      if (hit === null) {
        const g = new DayGroup();
        g.day = label;
        groups.push(g);
        hit = g;
      }
      hit.entries.push(e);
    }
    return groups;
  }
  erase(key: string): void {
    const ctx = this.ctx;
    if (ctx === null) { return; }
    UserDataRepo.toggleFavorite(ctx, key).then(() => {
      this.reload();
    });
  }

  openEntry(e: FavEntry): void {
    if (e.kind === 'site') {
      const prm: Record<string, string> = { 'id': e.siteId };
      router.pushUrl({ url: 'pages/DetailPage', params: prm });
    } else {
      const prm: Record<string, string> = { 'site': e.siteId, 'relic': e.relicId };
      router.pushUrl({ url: 'pages/RelicPage', params: prm });
    }
  }

  // 层头（§7.14）：横跨两列。年代视图给 LayerBadge（L 号 + 层色点 + 年代名），
  // 标签/时间视图给 INK 方点 + 名字——同一行同一制式，只是章不同。
  @Builder
  wallHead(g: WallGroup) {
    Row({ space: 10 }) {
      if (g.badge !== '') {
        LayerBadge({ layerCode: g.badge, era: g.era, eraLabel: g.label })
      } else {
        Row()
          .width(8)
          .height(8)
          .borderRadius(RADIUS_SM)
          .backgroundColor(INK)
        Text(g.label)
          .fontSize(FS_BODY)
          .fontWeight(WT_BOLD)
          .letterSpacing(2)
          .fontColor(THEME_INK)
      }
      Text(`${g.count} 件`)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_MONO)
        .fontColor(SUB)
      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 16, bottom: 8 })
  }

  // 图块：3:2 图 + 名 + meta + 一颗溢出菜单。
  // 可点区只含「图 + 名」，动作行留在外面——ArkUI 的 click 会冒泡，
  // 整块可点时点「⋯」会连详情页一起推开，嵌套点击只能靠两块独立来分。
  @Builder
  wallTile(e: FavEntry) {
    Column({ space: 6 }) {
      Column({ space: 6 }) {
        // 图块优先实拍；缺图走占位态（文物＝剪影牌，遗址＝层色整块）。
        Stack({ alignContent: Alignment.Center }) {
          if (e.img !== '' && this.thumbFailed.indexOf(e.key) < 0) {
            Image($rawfile(e.img))
              .width('100%')
              .aspectRatio(WALL_ASPECT)
              .objectFit(ImageFit.Cover)
              .draggable(false)
              .onError(() => {
                this.thumbFailed = this.thumbFailed.concat([e.key]);
              })
          } else if (e.kind === 'relic') {
            Column() {
              AccessionPlate({ plateSize: 88, era: e.era, material: e.material })
            }
            .width('100%')
            .aspectRatio(WALL_ASPECT)
            .backgroundColor(eraColor(e.era))
            .justifyContent(FlexAlign.Center)
          } else {
            Column() {
              Text('图像整备中')
                .fontSize(FS_MICRO)
                .fontColor(SURFACE_CARD)
                .opacity(0.85)
            }
            .width('100%')
            .aspectRatio(WALL_ASPECT)
            .backgroundColor(eraColor(e.era))
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .borderRadius(RADIUS_MD)
        .clip(true)

        Text(e.title)
          .fontSize(FS_BODY)
          .fontWeight(WT_BOLD)
          .fontColor(THEME_INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .onClick(() => {
        this.openEntry(e);
      })
      .onTouch((ev: TouchEvent) => {
        if (ev.type === TouchType.Down) {
          this.pressedEntry = e.key;
        } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
          this.pressedEntry = '';
        }
      })
      .scale({
        x: this.pressedEntry === e.key ? PRESS_SCALE : 1,
        y: this.pressedEntry === e.key ? PRESS_SCALE : 1
      })
      .animation(pressAnim())
      .focusable(true)
      .focusBox(focusRing())
      .accessibilityText(`${e.title}，${this.tileMeta(e)}`)
      .accessibilityLevel('yes')

      Row({ space: 6 }) {
        Column({ space: 3 }) {
          Text(this.tileMeta(e))
            .fontSize(FS_CAPTION)
            .fontColor(SUB)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          // 标签只在它不是分组轴的视图里露出来：按标签看时组头就是标签，
          // 每块再挂一遍是重复。
          if (this.view !== VIEW_TAG && e.tags.length > 0) {
            Text(e.tags.join(' / '))
              .fontSize(FS_LABEL)
              .fontColor(SUB)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('⋯')
          .fontSize(FS_TITLE)
          .fontColor(SUB)
          .padding({ left: 8, right: 4 })
          .bindMenu(this.tileMenu(e))
          .focusable(true)
          .focusBox(focusRing())
          .accessibilityText(`更多操作，${e.title}`)
          .accessibilityLevel('yes')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  // 图块的溢出菜单：原先靠 ListItem 左滑（贴标签）/ 右滑（移除），
  // 网格里没有 swipeAction，两个动作收进这一颗 ⋯。
  tileMenu(e: FavEntry): MenuElement[] {
    const tagItem: MenuElement = {
      value: e.tags.length > 0 ? '改标签' : '贴标签',
      action: (): void => {
        this.openTagPicker(e);
      }
    };
    const eraseItem: MenuElement = {
      value: '从收藏移除',
      action: (): void => {
        this.erase(e.key);
      }
    };
    return [tagItem, eraseItem];
  }
  // 视图切换器数据（清单 C3）：不带计数——三种视图看的是同一批收藏，
  // 报三个一样的数字没有信息量。
  viewItems(): MenuEntry[] {
    const defs: string[] = [VIEW_LAYER, VIEW_TAG, VIEW_TIME];
    const labels: string[] = ['按年代分层', '按标签分组', '按收下时间'];
    const out: MenuEntry[] = [];
    for (let i = 0; i < defs.length; i++) {
      const it = new MenuEntry();
      it.key = defs[i];
      it.label = labels[i];
      out.push(it);
    }
    return out;
  }
  // 标签筛选项：tagChips 首项已是「全部」（空过滤），其余是预置标签 + 用户自建标签。
  // count 一律 -1：标签筛选用不着条数，占位只会挤掉胶囊里的中文。
  tagItems(): SegmentItem[] {
    const out: SegmentItem[] = [];
    for (const t of this.tagChips) {
      const it = new SegmentItem();
      it.key = t;
      it.label = t;
      it.count = -1;
      out.push(it);
    }
    return out;
  }

  build() {
    Column() {
      // ── 顶栏（修复计划 §7.13）：本页由档案落地页 push 进来，只给返回键。
      // 「最近删除」放在顶栏右端：标题行要留给 30pt 页名与视图切换，
      // 三个动作挤同一行会把主按钮的分量吃掉。
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

      // ── 页头：30pt「我的收藏」+ 计数 + 视图切换，一屏只有这一个大标题。
      // 此前它是档案页的内嵌分段，档案页的 30pt「档案」与本页标题叠在一起，
      // 用户读作「标题乱了」；独立成页后嵌套消失。
      // 视图切换用图标菜单而不是第二排胶囊（清单 §7.11）：它与下面「筛选」
      // 胶囊同形时是两排一样的圆角控件，读者分不出哪排管什么。
      Row({ space: ROW_GAP }) {
        SectionTitle({
          title: '我的收藏',
          caption: `已收 ${this.entries.length} 条，当前显示 ${this.shown.length} 条`
        })
        Blank()
        // 与笔记页的「范围」下拉同一形态：值露在胶囊上，
        // 图标菜单那种不带读数的 ☷/☰ 会让当前视图只能点开才知道。
        IconMenu({
          text: `视图 ${this.viewName()}`,
          label: `视图，当前${this.viewName()}`,
          items: this.viewItems(),
          selected: this.view,
          onPick: (k: string): void => {
            this.view = k;
            // 分组轴一换，墙就得重建：wallGroups 是渲染的唯一依据，
            // 只在筛选时重算会让胶囊文案变了、层头还是老的分法（实测过）。
            this.buildWall();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 16 })

      // 数据筛选（标签）：嵌入态时视图切换已折进页头并收进图标菜单，
      // 这里只留「看哪些」。眉标「筛选」把语义钉死，避免与页签、胶囊混为一谈。
      // 走 SegmentTab：与笔记页的标签筛选同一套实现与同一套制式
      // （选中 INK 实底、未选白底发丝、高 CHIP_H），不再各写一遍 chip。
      Row({ space: 10 }) {
        Text('筛选')
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
          .padding({ left: PAGE_PAD_X })
        Scroll() {
          Column() {
            SegmentTab({
              items: this.tagItems(),
              selected: this.tag,
              onPick: (k: string): void => {
                this.tag = k;
                this.applyFilter();
              }
            })
          }
          .alignItems(HorizontalAlign.Start)
          .padding({ right: PAGE_PAD_X })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.entries.length === 0) {
        // 空态走全站唯一 EmptyState（8vp 色点 + FS_TITLE 22 + 左对齐）。
        // 原先这里自写了一套：FS_DISPLAY 28 巨字、无色点——与笔记页/路线页
        // /网络图页/回收站页的空态语法都不一致（清单 §0）。
        Column() {
          EmptyState({
            dotColor: INK,
            headline: '还没有收藏。',
            desc: '翻到感兴趣的遗址或文物，点收藏即可在此集结。',
            actionLabel: '',
            onAction: (): void => {}
          })
        }
        .width('100%')
        .padding({ top: 80, left: PAGE_PAD_X, right: PAGE_PAD_X })
        .alignItems(HorizontalAlign.Start)
        // 空态也要占满剩余高度，否则底栏会被顶到内容下方而不是页底。
        .layoutWeight(1)
      } else if (this.shown.length === 0) {
        Column() {
          EmptyState({
            dotColor: INK,
            headline: `「${this.tag}」下暂无收藏。`,
            desc: '向右滑动条目，即可为收藏贴标签分类。',
            actionLabel: '',
            onAction: (): void => {}
          })
        }
        .width('100%')
        .padding({ top: 80, left: PAGE_PAD_X, right: PAGE_PAD_X })
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      } else {
        // 图墙：双列 3:2 图块，层头横跨两列（columnStart/columnEnd）。
        // GridItem 的宽度由网格给，不能套 PressScale 包装器——那会多一层
        // 布局节点把列宽算歪；按压态记在页面 @State 上（同 RelicListPage）。
        Grid() {
          ForEach(this.wallGroups, (g: WallGroup) => {
            GridItem() {
              this.wallHead(g)
            }
            .columnStart(0)
            .columnEnd(1)

            ForEach(g.entries, (e: FavEntry) => {
              GridItem() {
                this.wallTile(e)
              }
            }, (e: FavEntry) => `${e.key}|${e.tags.join(',')}`)
          }, (g: WallGroup) => `${g.badge}|${g.label}|${g.count}|` +
            `${g.entries.map((e: FavEntry): string => e.key).join(',')}`)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(ITEM_GAP)
        .rowsGap(ITEM_GAP)
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 24 })
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }

}

// ── 页面入口（修复计划 §7.13）：从档案落地页的「收藏」卡 pushUrl 进来。
// 底栏不挂——它是档案频道的下级页，返回键回到档案页。
@Entry
@Component
struct FavoritesPage {
  // 页面可见性桥：onPageShow 只在 @Entry 上触发，把它记成一个自增数，
  // 交给 body 的 @Watch——否则在详情页收了藏再返回，展厅还是旧的。
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
      FavoritesBody({ pageTick: this.pageTick })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}