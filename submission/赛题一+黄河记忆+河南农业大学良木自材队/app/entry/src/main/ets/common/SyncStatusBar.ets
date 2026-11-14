// entry/src/main/ets/common/SyncStatusBar.ets —— 首页/我的 顶部的一行同步状态
//
// 只读 SyncStatus 快照，不自己发起同步。点击进同步面板看细节。
// 用 1.5s 轮询而不是订阅：同步可能由 AutoSync 在后台触发，
// 订阅要处理页面生命周期里的注销，轮询在这个粒度上更不容易漏。
import { router } from '@kit.ArkUI';
import { SyncStatus, SyncSnapshot } from '../service/sync/SyncStatus';
import {
  ACCENT, CHIP_RADIUS, FONT_SERIF, FS_CAPTION, HAIR, INK, LINE_HAIR,
  MAT_COLOR_METAL, PAGE_PAD_X, PRESS_OPACITY, SEAL_RED, SUB, SURFACE_CARD
} from './DesignTokens';
import { focusRing } from './Accessibility';
import { pressAnim } from './Motion';

@Component
export struct SyncStatusBar {
  @State private snap: SyncSnapshot = SyncStatus.snapshot();
  @State private pressed: boolean = false;
  private timer: number = -1;

  aboutToAppear(): void {
    this.snap = SyncStatus.snapshot();
    this.timer = setInterval((): void => {
      this.snap = SyncStatus.snapshot();
    }, 1500);
  }

  aboutToDisappear(): void {
    if (this.timer >= 0) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  private dotColor(): string {
    if (this.snap.state === 'synced') { return MAT_COLOR_METAL; }
    if (this.snap.state === 'syncing') { return ACCENT; }
    if (this.snap.state === 'failed' || this.snap.state === 'auth' ||
      this.snap.state === 'no_peer') {
      return SEAL_RED;
    }
    return SUB;
  }

  private ago(t: number): string {
    const diff: number = Date.now() - t;
    if (diff < 60000) { return '刚刚'; }
    if (diff < 3600000) { return `${Math.floor(diff / 60000)} 分钟前`; }
    if (diff < 86400000) { return `${Math.floor(diff / 3600000)} 小时前`; }
    return `${Math.floor(diff / 86400000)} 天前`;
  }

  private statusText(): string {
    if (this.snap.state === 'syncing') { return '同步中…'; }
    if (this.snap.state === 'synced') {
      return this.snap.lastSyncTime > 0
        ? `已同步 · ${this.ago(this.snap.lastSyncTime)}`
        : '已同步';
    }
    if (this.snap.state === 'offline') { return '离线，数据已保存在本机'; }
    if (this.snap.state === 'auth') { return '待授权，点此去同步页'; }
    if (this.snap.state === 'no_peer') { return '未发现配对设备，点此查看'; }
    if (this.snap.state === 'failed') { return '同步失败，点此去同步页'; }
    return '同步待命 · 点此查看';
  }

  build() {
    Row({ space: 8 }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(4)
        .backgroundColor(this.dotColor())

      Text(this.statusText())
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .fontColor(INK)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.snap.conflictCount > 0) {
        Row({ space: 4 }) {
          Row()
            .width(6)
            .height(6)
            .borderRadius(4)
            .backgroundColor(SEAL_RED)
          Text(`冲突 ${this.snap.conflictCount}`)
            .fontSize(FS_CAPTION)
            .fontColor(SEAL_RED)
        }
      }

      Text('›')
        .fontSize(FS_CAPTION)
        .fontColor(SUB)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(SURFACE_CARD)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(CHIP_RADIUS)
    .margin({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 8, bottom: 8 })
    .onClick(() => {
      router.pushUrl({ url: 'pages/SyncPage' });
    })
    // 整条横条是点击区：按下必须看得见。stateStyles 在本项目真机上
    // 抓不到按下态（见 Motion.ets），所以用验证有效的 @State + onTouch。
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = true;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .opacity(this.pressed ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(this.statusText())
    .accessibilityLevel('yes')
  }
}
