// entry/src/main/ets/common/EmptyState.ets
// 空态的唯一实现。
//
// 为什么要抽（制式整改清单 §0 / §1）：空态此前有五套写法——
// 笔记页标题只有 FS_ITEM 15 且没有色点；收藏页「展厅尚未布展」是居中裸文字；
// 路线页 / 网络图页 / 回收站页各自一套。空态是用户最容易当成"坏了"的画面，
// 语法不统一会直接影响可信度。
//
// 制式（参数钉死）：
//   8×8 层色点 + FS_TITLE 22 一句话 + FS_CAPTION/SUB 说明 + 次级描边按钮；
//   **整块左对齐**（居中会让它像弹窗而不是页面内容）。
// 按钮走 PillButton 的次级档——空态不该再抢一个实心主按钮
// （同页两个实心主按钮是清单 N4 的问题）。
import {
  FONT_DISPLAY, FS_CAPTION, FS_TITLE, INK, RADIUS_SM,
  SUB, WT_DISPLAY
} from './DesignTokens';
import { PillButton } from './PillButton';

@Component
export struct EmptyState {
  @Prop dotColor: string = INK;
  @Prop headline: string = '';
  @Prop desc: string = '';
  // actionLabel 为空则不渲染按钮。
  @Prop actionLabel: string = '';
  onAction: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      Row()
        .width(8)
        .height(8)
        .borderRadius(RADIUS_SM)
        .backgroundColor(this.dotColor)
      Text(this.headline)
        .fontSize(FS_TITLE)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(INK)
      if (this.desc !== '') {
        Text(this.desc)
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
      }
      if (this.actionLabel !== '') {
        PillButton({
          label: this.actionLabel,
          secondary: true,
          onPress: () => {
            this.onAction();
          }
        })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
