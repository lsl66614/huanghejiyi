// entry/src/main/ets/pages/ArchivePage.ets —— 「档案」频道落地页
//
// 为什么有这个页（修复计划 阶段2 / §6.1 六层模型的第 4 层）：
// 赛题点名的「三类个人数据」（收藏 / 笔记 / 研读进度）此前散在底栏两格
// （收藏、笔记）与一个已删组件（剖面完整度）里，学习进度甚至没有家。
// 本页把三类数据收成一个频道，底栏第 2 格直达；导出改为页右上的溢出操作。
//
// 这一屏只有标题与入口，没有内容（修复计划 §7.13）：
// 原先四段（收藏 / 笔记 / 研读 / 网络图）内嵌在本页的分段里，同一屏会叠出
// 「档案 30pt + 收藏 30pt」两个大标题，页头还要再加一排页签，读作标题打架。
// 现在本页是四张横向入口卡，点哪张 pushUrl 进哪一页——每张卡自己撑起一整屏、
// 只有一个标题，返回键回到这里。
//
// 页头常驻当前身份（§6.2 矛盾三）：档案页的主语是「哪一份档案」，
// 切换动作在同步页，这里只做显式提示，不重复实现切换。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import type { FavoriteDO, NoteView, ProgressDO } from '../model/UserDataModels';
import { UserDataRepo } from '../repository/UserDataRepo';
import { THEME_BG } from '../common/EraTheme';
import {
  ACCENT, BLOCK_GAP, CARD_PAD, CHIP_RADIUS, FONT_DISPLAY, FONT_MONO, FONT_SANS, FONT_SERIF,
  FS_BODY, FS_CAPTION, FS_DISPLAY, FS_MICRO, FS_PAGE, FS_TITLE, HAIR, INK,
  LINE_HAIR, PAGE_PAD_X, PRESS_SCALE, RADIUS_CARD_LG, ROUTE_FADE_MIN, ROUTE_SHIFT_VP,
  ROW_GAP, SUB, SURFACE_CARD, WT_DISPLAY
} from '../common/DesignTokens';
import { AppNavBar } from '../common/AppNavBar';
import { SyncStatus } from '../service/sync/SyncStatus';
import { IconButton } from '../common/IconButton';
import { PressFade } from '../common/PressScale';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';

@Entry
@Component
struct ArchivePage {
  // 三张卡的计数。网络图卡的节点数由 buildGraph（收藏 + 笔记 + 年代 / 标签节点）
  // 决定，本页不复算，所以那张卡不给数字——宁可少一个数，不说一个可能假的数。
  @State favCount: number = 0;
  @State noteCount: number = 0;
  @State studiedSections: number = 0;
  // 身份：设备 A / 设备 B / 本机
  @State dev: string = '';

  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }

  aboutToAppear(): void {
    this.reload();
  }

  // 从子页返回、或从同步页切回身份后要重算——否则会把上一份档案的计数挂着。
  onPageShow(): void {
    this.reload();
  }

  private identityText(): string {
    if (this.dev === 'deviceA') { return '手机'; }
    if (this.dev === 'deviceB') { return '平板'; }
    return this.dev === '' ? '本机' : this.dev;
  }

  // 页头右侧的同步时刻（设计稿：「2 分钟前已同步」）。
  // 口径与 SyncStatusBar 一致：读最近一次同步时间戳，按分钟/小时/天前。
  // 快照只存在于本次运行，所以没同步过时说的是"尚未同步"，不是"0 分钟前"。
  private syncNote(): string {
    const t: number = SyncStatus.snapshot().lastSyncTime;
    if (t <= 0) { return '尚未同步'; }
    const diff: number = Date.now() - t;
    if (diff < 60000) { return '刚刚已同步'; }
    if (diff < 3600000) { return `${Math.floor(diff / 60000)} 分钟前已同步`; }
    if (diff < 86400000) { return `${Math.floor(diff / 3600000)} 小时前已同步`; }
    return `${Math.floor(diff / 86400000)} 天前已同步`;
  }

  reload(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    UserDataRepo.deviceIdOf(ctx).then((d: string) => {
      this.dev = d;
    });
    UserDataRepo.listFavoritesOf(ctx).then((f: FavoriteDO[]) => {
      this.favCount = f.length;
    });
    UserDataRepo.allNotes(ctx).then((n: NoteView[]) => {
      this.noteCount = n.length;
    });
    UserDataRepo.allProgress(ctx).then((p: ProgressDO[]) => {
      let done: number = 0;
      for (const row of p) {
        if (row.done) { done += 1; }
      }
      this.studiedSections = done;
    });
  }

  // 入口卡改独立组件（ArchiveEntryCard，文件末尾）：@Builder 按值传参，
  // 计数只会停在首帧——hilog 实测 promise 已带回 favs 9，卡上还是「0 条」。

  build() {
    Column() {
      // ── 页头（2026-11-04 设计稿「档案」页理想布局，主题色不变）：
      //   眉标「田野记录 · 个人档案」+ 30pt 衬线大标题「档案」；
      //   右上四个 36 圆形图标按钮：搜索 / 网络图 / 导出 / 更多；
      //   第二行：身份胶囊（赭红点 + 设备名 + chevron）+ 右侧「N 分钟前已同步」。
      Column({ space: 16 }) {
        Row() {
          Column({ space: 4 }) {
            Text('田野记录 · 个人档案')
              .fontSize(FS_MICRO)
              .fontFamily(FONT_SANS)
              .fontColor(SUB)
              .letterSpacing(1.6)
            Text('档案')
              .fontSize(FS_PAGE)
              .fontFamily(FONT_DISPLAY)
              .fontWeight(WT_DISPLAY)
              .fontColor(INK)
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Row({ space: 8 }) {
            IconButton({
              icon: 'search',
              label: '搜索',
              hint: '打开全局搜索',
              onPress: () => {
                router.pushUrl({ url: 'pages/SearchPage' });
              }
            })
            // 网络图不再在这里放第二入口：第四张卡就是它，
            // 同一屏两个 affordance 指向同一页只会让人怀疑是两个东西。
            IconButton({
              icon: 'download',
              label: '导出我的档案',
              hint: '打开导出页，可选 Markdown 或 JSON',
              onPress: () => {
                router.pushUrl({ url: 'pages/ExportPage' });
              }
            })
            IconButton({
              icon: 'more',
              label: '更多入口',
              hint: '打开图片版权与来源',
              onPress: () => {
                router.pushUrl({ url: 'pages/CreditsPage' });
              }
            })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          // 身份胶囊：白底 + 发丝描边 + 赭红点 + 设备名 + 下拉箭头。
          // 点它去同步页换身份（切换动作在同步页，这里只做入口）。
          PressFade() {
            Row({ space: 6 }) {
              Row()
                .width(6)
                .height(6)
                .borderRadius(4)
                .backgroundColor(ACCENT)
              Text(this.identityText())
                .fontSize(FS_CAPTION)
                .fontFamily(FONT_SANS)
                .fontColor(INK)
              Text('⌄')
                .fontSize(FS_CAPTION)
                .fontColor(SUB)
            }
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .backgroundColor(SURFACE_CARD)
            .border({ width: HAIR, color: LINE_HAIR })
            .borderRadius(CHIP_RADIUS)
            // 这颗胶囊此前只有 accessibilityText 写着「点击去同步页切换」、
            // 还画了 ⌄，但没有 onClick——承诺了却按不动。补上真正的入口。
            .onClick(() => {
              router.pushUrl({ url: 'pages/SyncPage' });
            })
            .focusable(true)
            .focusBox(focusRing())
            .accessibilityText(`当前档案：${this.identityText()}，点击去同步页切换`)
          }

          Blank()

          Text(this.syncNote())
            .fontSize(FS_MICRO)
            .fontFamily(FONT_SANS)
            .fontColor(SUB)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 10 })

      // ── 四张横向入口卡（收藏 / 笔记 / 研读 / 网络图）
      //
      // 左右内衬由这一层的 padding 给出，卡片不各写横向 margin：
      // ArkUI 里 .width('100%') 会把横向 margin 吞掉，只有 padding 生效
      // （笔记页两行筛选实测过这个坑）。
      //
      // Scroll 只在短屏上让第四张卡够得着。卡片自身不滚动，点进去的子页
      // 各带自己的滚动容器——分段内嵌时代那套「外层只分高 / 内层滚」的
      // 高度分配（§7.10）整条不再需要。
      // 这一层仍要挂 layoutWeight(1)：否则按内容高度撑开，把同级的
      // AppNavBar 挤出行外（档案页一度看不见底部四格导航）。
      Scroll() {
        Column({ space: BLOCK_GAP }) {
          ArchiveEntryCard({ glyph: '藏', title: '收藏', count: `${this.favCount} 条`,
            desc: '收下的遗址与器物，按标签分看', route: 'pages/FavoritesPage' })
          ArchiveEntryCard({ glyph: '记', title: '笔记', count: `${this.noteCount} 条`,
            desc: '随手、遗址、文物三处落笔', route: 'pages/NoteCenterPage' })
          ArchiveEntryCard({ glyph: '读', title: '研读', count: `${this.studiedSections} 段`,
            desc: '五段阅读进度与剖面完整度', route: 'pages/StudyPage' })
          ArchiveEntryCard({ glyph: '络', title: '主题网络图', count: '',
            desc: '收藏与标签长成的根系', route: 'pages/NetworkPage' })
        }
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 24, bottom: BLOCK_GAP })
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .width('100%')
      .layoutWeight(1)

      AppNavBar({ active: 1 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}

// 入口卡：左侧一个展示体单字作展签标记，中间标题 + 一句说明，右侧数字与 chevron。
// 数字跟在标题后而不是右对齐成一列——它回答「这一格有多少」，不是表格的一列。
// 必须是独立组件而不是 @Builder：@Builder 按值传参，count 只停留在首帧的值，
// 状态变了也不会重画（hilog 实测 promise 已带回 favs 9、卡上仍是「0 条」）。
@Component
struct ArchiveEntryCard {
  @Prop glyph: string = '';
  @Prop title: string = '';
  @Prop count: string = '';
  @Prop desc: string = '';
  @Prop route: string = '';
  @State pressed: boolean = false;

  build() {
    Row({ space: 12 }) {
      Text(this.glyph)
        .fontSize(FS_DISPLAY)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(ACCENT)
        .width(40)
        .textAlign(TextAlign.Center)

      Column({ space: 4 }) {
        Row({ space: ROW_GAP }) {
          Text(this.title)
            .fontSize(FS_TITLE)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
          if (this.count !== '') {
            Text(this.count)
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_MONO)
              .fontColor(SUB)
          }
        }
        .alignItems(VerticalAlign.Bottom)

        Text(this.desc)
          .fontSize(FS_BODY)
          .fontFamily(FONT_SERIF)
          .fontColor(SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(FS_TITLE)
        .fontColor(SUB)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(CARD_PAD)
    .backgroundColor(SURFACE_CARD)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(RADIUS_CARD_LG)
    .onClick(() => {
      router.pushUrl({ url: this.route });
    })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .scale({
      x: this.pressed ? PRESS_SCALE : 1,
      y: this.pressed ? PRESS_SCALE : 1
    })
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`${this.title}，${this.desc}${this.count === '' ? '' : '，' + this.count}`)
    .accessibilityLevel('yes')
  }
}
