// entry/src/main/ets/common/BackLink.ets
// 子页顶栏的「‹ 返回」——全站唯一实现。
//
// 为什么抽件（2026-11-05 普查）：15 个子页各手写一遍，已经漂成 4 个维度——
//   fontSize  FS_BODY(3) / FS_CAPTION(12)
//   fontColor SUB(11) / THEME_INK(2) / INK(1) / ON_IMAGE_TEXT(1)
//   a11y      「返回上一页」(12) / 「返回档案」(3)
//   连 onClick 里 router.back() 都重复了 15 遍。
// 这些差异没有任何设计依据，是逐页手写的必然结果。
//
// 制式（钉死，页内不许覆盖）：FS_CAPTION + SUB 字。
// 两个可选入参都有明确触发条件，不是「顺手加个参数」：
//   onImage = true   压在头图上的页面（DetailPage）用 ON_IMAGE_TEXT，
//                    否则白底页的 SUB 在照片上读不出。
//   backToParent = true  父级是档案落地页的三个子页（收藏/笔记/研读），
//                    a11y 说「返回档案」而不是「返回上一页」——读屏用户
//                    需要知道这一下退到哪，而不是笼统的「上一页」。
import { FS_CAPTION, ON_IMAGE_TEXT, SUB } from './DesignTokens';
import { PressFade } from './PressScale';
import { focusRing } from './Accessibility';
import { router } from '@kit.ArkUI';

@Component
export struct BackLink {
  // 压在头图/深底上时置 true：改用 ON_IMAGE_TEXT，SUB 在照片上不可读。
  @Prop onImage: boolean = false;
  // 父级是档案落地页时置 true：读屏文案说「返回档案」。
  @Prop backToParent: boolean = false;

  build() {
    PressFade() {
      Text('‹ 返回')
        .fontSize(FS_CAPTION)
        .fontColor(this.onImage ? ON_IMAGE_TEXT : SUB)
        .accessibilityText(this.backToParent ? '返回档案' : '返回上一页')
        .onClick(() => {
          router.back();
        })
        .focusable(true)
        .focusBox(focusRing())
    }
  }
}
