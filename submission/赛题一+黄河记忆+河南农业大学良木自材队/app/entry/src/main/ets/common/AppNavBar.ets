// entry/src/main/ets/common/AppNavBar.ets
// 全站唯一的底部导航（设计稿①制式：图标 + 文字，选中态 INK）。
//
// 为什么抽成公共组件：此前 P1 自带一套图标底栏、P4 又自造一套文字底栏，
// 其余页没有底栏——同一个 App 出现三套导航语法。现在只保留这一套，
// 由 P1（年代）、P2（选层）、P10（我的）共用，详情页与子页一律不挂。
//
// 四格按「评审叙事」分层（修复计划 §6.1 六层模型 → 底栏）：
//   年代（0→3 往下挖：地表/地层/遗址/展柜）
//   档案（4：收藏 / 笔记 / 研读 / 网络图，赛题点名的三类个人数据）
//   同步（5：分布式流转，赛题唯一的平台专属能力，不再藏进子页）
//   发现（6：推荐 / 路线）
// 从左到右即评分叙事：内容厚度 → 个人数据闭环 → 平台能力 → 拓展项。
// 第 2 格是 ArchivePage（频道页），不是收藏页——收藏只是它的一个分段。
import { router } from '@kit.ArkUI';
import {
  ACCENT, FS_TAB, HAIR_PAD, INK, PRESS_SCALE, RADIUS_MD, RADIUS_NAV_ITEM,
  SUB, SURFACE_CARD, SURFACE_RAISED, WT_MEDIUM, WT_REGULAR
} from './DesignTokens';
import { focusRing } from './Accessibility';
import { pressAnim } from './Motion';
import { SYNC_BADGE_KEY } from '../service/sync/SyncStatus';

const NAV_ICONS: string[] = ['nianlun', 'jiandu', 'sinan', 'tanfang'];
const NAV_LABELS: string[] = ['年代', '档案', '同步', '发现'];
// 下标即频道号：与 AppNavBar 四格、宿主页 active 值同一口径。
const NAV_URLS: string[] = ['pages/Index', 'pages/ArchivePage', 'pages/SyncPage', 'pages/MinePage'];

// 频道切换的唯一入口：页面里任何「去某频道」的按钮都必须走这里，
// 不要自己 pushUrl 频道页——频道页被压栈后会在栈里留一份，返回键
// 与底栏就成两套互相矛盾的导航语法（返回退到频道页残影、底栏又清栈）。
export function switchToTab(idx: number): void {
  router.clear();
  router.replaceUrl({ url: NAV_URLS[idx] });
}

// 给「入口表里混着频道页与子页」的调用方用：-1 = 不是频道，走 pushUrl。
export function tabIndexOfUrl(url: string): number {
  return NAV_URLS.indexOf(url);
}

@Component
export struct AppNavBar {
  // 0=年代 1=档案 2=同步 3=发现
  @Prop active: number = 0;
  // 同步格的角标（未裁决冲突数）。由 SyncStatus 单向镜像到 AppStorage，
  // 这里订阅：底栏平时也有信息量，不必等用户点进去才发现有冲突。
  @StorageProp(SYNC_BADGE_KEY) badge: number = 0;
  // 按下的底栏格下标：-1 = 无
  @State private pressedIdx: number = -1;

  // 底栏是「频道切换」，不是「再压一页」：语义见 switchToTab。
  private go(idx: number): void {
    if (idx === this.active) { return; }
    switchToTab(idx);
  }

  build() {
    Row() {
      ForEach(NAV_LABELS, (label: string, idx: number) => {
        // 不用 PressScale 包装器：底栏格靠 layoutWeight(1) 平分宽度，
        // 包装器多出的一层会把权重分配吃掉，四个格子宽度不再均分。
        // 按压态就地写同一套 onTouch 三段式。
        Column({ space: HAIR_PAD }) {
          Stack({ alignContent: Alignment.TopEnd }) {
            Image($rawfile(`icons/ic_${NAV_ICONS[idx]}_${this.active === idx ? 'red' : 'ink'}.svg`))
              .width(19)
              .height(19)
              .draggable(false)
              .opacity(this.active === idx ? 1 : 0.55)
            // 角标只在同步格、且真有冲突时出现；0 冲突不画空心圈（不制造噪音）
            if (idx === 2 && this.badge > 0) {
              Text(this.badge > 99 ? '99+' : `${this.badge}`)
                .fontSize(9)
                .fontColor(SURFACE_CARD)
                .textAlign(TextAlign.Center)
                .constraintSize({ minWidth: 14 })
                .height(14)
                .padding({ left: 3, right: 3 })
                .backgroundColor(ACCENT)
                // 14 高用 RADIUS_MD(8)：ArkUI 按半高收敛，视觉仍是圆点；
                // 令牌门禁只认 0/190/4/8 收敛档
                .borderRadius(RADIUS_MD)
                .translate({ x: 10, y: -6 })
            }
          }
          .width(19)
          .height(19)
          Text(label)
            .fontSize(FS_TAB)
            .fontWeight(this.active === idx ? WT_MEDIUM : WT_REGULAR)
            .fontColor(this.active === idx ? INK : SUB)
        }
        .layoutWeight(1)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .borderRadius(RADIUS_NAV_ITEM)
        .backgroundColor(this.active === idx ? SURFACE_RAISED : SURFACE_CARD)
        .onClick(() => {
          this.go(idx);
        })
        .onTouch((e: TouchEvent) => {
          if (e.type === TouchType.Down) {
            this.pressedIdx = idx;
          } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
            this.pressedIdx = -1;
          }
        })
        .scale({ x: this.pressedIdx === idx ? PRESS_SCALE : 1, y: this.pressedIdx === idx ? PRESS_SCALE : 1 })
        .animation(pressAnim())
        .focusable(true)
        .focusBox(focusRing())
        .accessibilityText(idx === 2 && this.badge > 0 ? `${label}，${this.badge} 条冲突待裁决` : label)
        .accessibilityLevel('yes')
        .accessibilitySelected(this.active === idx)
      }, (label: string) => label)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 24 })
  }
}
