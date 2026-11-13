// entry/src/main/ets/pages/MinePage.ets —— 「发现」（原「我的」）
//
// 为什么改名瘦身（修复计划 §6.2 矛盾一）：
// 旧「我的」是杂物袋——网络图、导出、文物图录、全部笔记、同步面板全塞在这里，
// 与底栏其它格重复，且零条款的「主题路线」排在赛题权重最高的同步面板之上。
// 现在职责重新分配：
//   收藏 / 笔记 / 研读 / 网络图 → 档案页（底栏第 2 格）
//   导出 → 档案页右上溢出操作
//   同步面板 → 底栏第 3 格
//   文物图录 → 本页第 02 行（Index 尚无「遗址 ⇄ 文物」分段，图录无其它平级入口）
//   本页只留「接下来看什么」：推荐 + 图录 + 路线，版权收进页脚。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { AttributionRepo } from '../repository/AttributionRepo';
import type { AttributionData } from '../service/content/Attribution';
import { THEME_BG } from '../common/EraTheme';
import {
  ACCENT, CARD_PAD, FONT_DISPLAY, FONT_MONO, FONT_SERIF, FS_BODY, FS_CAPTION,
  FS_ITEM, FS_PAGE, INK, LH_CAPTION, LH_PAGE, LINE_HAIR, HAIR,
  PAGE_PAD_X, PRESS_OPACITY, RADIUS_CARD_LG,
  ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SUB, SURFACE_CARD, WT_BOLD, WT_DISPLAY
} from '../common/DesignTokens';
import { focusRing } from '../common/Accessibility';
import { PressFade } from '../common/PressScale';
import { AppNavBar } from '../common/AppNavBar';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';
import { SyncStatusBar } from '../common/SyncStatusBar';

interface DiscoverRow {
  no: string;
  label: string;
  desc: string;
  url: string;
}

// 「发现」只回答一个问题：接下来看什么。
// 文物图录在这行补上时的实况：Index 里没有「遗址 ⇄ 文物」分段，
// RelicListBody 全站零引用，底栏四格都到不了文物线——
// 只剩 ListPage 的「文物图录 ›」和 SearchPage 的结果入口两条窄路。
// pages/RelicListPage 是已注册路由，这里补一条平级入口兜住可达性。
const ROWS: DiscoverRow[] = [
  { no: '01', label: '为我推荐', desc: '按浏览与收藏的脉络计算', url: 'pages/RecommendPage' },
  { no: '02', label: '文物图录', desc: '104 件器物，按年代 / 材质 / 遗址查', url: 'pages/RelicListPage' },
  { no: '03', label: '主题路线', desc: '按站排序的遗址清单，带完成度', url: 'pages/RouteListPage' }
];

@Entry
@Component
struct MinePage {
  @State photoCount: number = 0;
  // 按下的入口行序号
  @State pressedRow: string = '';

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
    // 在包实拍张数从署名记录读，不写死（写死过一次，图库从 76 涨到 101 就过期了）
    AttributionRepo.load(ctx).then((d: AttributionData) => {
      this.photoCount = d.images.length;
    });
  }

  build() {
    Column() {
      // 顶栏：频道页不挂返回键——底栏切频道是清栈替换。
      Row() {
        Text('发现')
          .fontSize(FS_PAGE)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .letterSpacing(1)
          .fontColor(INK)
        Blank()
        Text('接下来看什么')
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SERIF)
          .fontColor(SUB)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 12 })

      Scroll() {
        Column() {
          // 同步状态：属性常驻，与底栏同步格（可演示证据）不重复
          SyncStatusBar()

          // 「继续走」入口：白卡 + 大标题，与档案页同一制式
          Column() {
            Text('从地表往下，\n还有这些路可走')
              .fontSize(FS_PAGE)
              .fontFamily(FONT_DISPLAY)
              .fontWeight(WT_DISPLAY)
              .lineHeight(LH_PAGE)
              .fontColor(INK)
              .letterSpacing(1)
            Text('推荐按你的收藏脉络重排；路线按地理顺序串成一条可走完的线。')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .lineHeight(LH_CAPTION)
              .fontColor(SUB)
              .margin({ top: 12 })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(CARD_PAD)
          .backgroundColor(SURFACE_CARD)
          .border({ width: HAIR, color: LINE_HAIR })
          .borderRadius(RADIUS_CARD_LG)
          .margin({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 8, bottom: 8 })

          // 入口列表：白卡行 + mono 序号
          Column({ space: 0 }) {
            ForEach(ROWS, (r: DiscoverRow) => {
              // 不用 PressFade 包装器：这一行 width('100%') 且内含
              // layoutWeight(1)，套进包装器后百分比与权重都会算在包装器里。
              Row({ space: 12 }) {
                Text(r.no)
                  .fontSize(FS_CAPTION)
                  .fontFamily(FONT_MONO)
                  .fontColor(ACCENT)
                Column({ space: 4 }) {
                  Text(r.label)
                    .fontSize(FS_ITEM)
                    .fontFamily(FONT_DISPLAY)
                    .fontWeight(WT_DISPLAY)
                    .fontColor(INK)
                  Text(r.desc)
                    .fontSize(FS_CAPTION)
                    .fontFamily(FONT_SERIF)
                    .fontColor(SUB)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('›')
                  .fontSize(FS_BODY)
                  .fontColor(SUB)
              }
              .width('100%')
              .padding({ top: 16, bottom: 16 })
              .border({ width: { bottom: HAIR }, color: LINE_HAIR })
              .accessibilityText(r.label)
              .accessibilityLevel('yes')
              .accessibilityTextHint(r.desc)
              .onClick(() => {
                router.pushUrl({ url: r.url });
              })
              .onTouch((e: TouchEvent) => {
                if (e.type === TouchType.Down) {
                  this.pressedRow = r.no;
                } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                  this.pressedRow = '';
                }
              })
              .opacity(this.pressedRow === r.no ? PRESS_OPACITY : 1)
              .animation(pressAnim())
              .focusable(true)
              .focusBox(focusRing())
            }, (r: DiscoverRow) => r.no)
          }
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })

          // 语料说明
          Column({ space: 8 }) {
            Text('语料')
              .fontSize(FS_CAPTION)
              .letterSpacing(3)
              .fontColor(SUB)
            Text('42 处黄河中下游遗址、104 件代表文物，按 6 年代 × 4 类型 × 5 市的覆盖矩阵整编，字段含考古、历史、诗词、文旅、介绍五段。同步为单机双档案仿真，也支持真机软总线分布式；合并算法与传输层解耦。')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .lineHeight(LH_CAPTION)
              .fontColor(SUB)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 24, bottom: 8 })

          // 页脚：版权与来源（原「我的」第 08 行降级为页脚链接，不再占一行主入口）
          Row() {
            Blank()
            PressFade() {
              Text(`图片版权与来源 · ${this.photoCount} 张实拍逐条署名`)
                .fontSize(FS_CAPTION)
                .fontFamily(FONT_SERIF)
                .fontColor(SUB)
                .padding({ top: 6, bottom: 6 })
                .accessibilityText('打开图片版权与来源')
                .onClick(() => {
                  router.pushUrl({ url: 'pages/CreditsPage' });
                })
                .focusable(true)
                .focusBox(focusRing())
            }
            Blank()
          }
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 24 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // 底栏第 4 格（active: 3）——「发现」
      AppNavBar({ active: 3 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}
