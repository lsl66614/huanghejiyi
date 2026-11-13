// entry/src/main/ets/common/StrataSpineCard.ets
// 层色脊卡：设计稿「StrataSpineCard」的通用实现。
//
// 构成（全部来自设计稿①年代卡）：
//   左 8vp 层色脊 + 封面图（3:2）+ 白底 LayerBadge 层号章
//   + 卡片名（年代色 18pt 展示体）+ 副题（SUB 12pt 衬线）
//
// 两条硬约束：
//   1. 脊色是「展签色标」，不是装饰。它和图是并列的两个信息通道：
//      图回答"长什么样"，脊回答"属于哪一层"。
//   2. 封面图缺失时走层色整块 + 「图像整备中」占位（§6 占位态）。
//      占位态必须比真实态更克制——它是在说"这里将有一张图"，
//      不能用花哨图案伪装成内容。
import { eraColor } from './EraTheme';
import {
  FONT_DISPLAY, FONT_MONO, FONT_SERIF, FS_CAPTION, FS_TITLE, HAIR, LINE_HAIR,
  RADIUS_MD, ROW_GAP, SHADOW_CARD_COLOR_LIGHT, SHADOW_CARD_OFFSET,
  SHADOW_CARD_RADIUS, SUB, SURFACE_CARD, WT_DISPLAY
} from './DesignTokens';
import { LayerBadge } from './LayerBadge';
import { MiniProfile } from './MiniProfile';
import { focusRing } from './Accessibility';

@Component
export struct StrataSpineCard {
  // 年代键，决定脊色、章色、标题色
  era: string = '';
  // 层号显示文本，如 'L1'
  layerCode: string = '';
  // 卡片主标题
  title: string = '';
  // 副标题（文化类型 · 距今约XXXX年）
  subtitle: string = '';
  // 封面图资源路径；空串走占位态
  coverImage: string = '';
  // 研读完成度：已读完五段的站点数 / 该年代站点总数。
  // 0/0 时进度条不渲染（不是画 6 格空条）。
  done: number = 0;
  total: number = 0;
  // 双轴计数（A 方案）：这一层的文物件数。
  // 传入时卡片在标题区下方多出一行「N 处遗址 · M 件文物」——
  // 两个数字并列，读者一眼知道这一层里站着两种实体。
  // 不传（< 0）时不渲染该行，保持旧卡的干净版式。
  relicCount: number = -1;
  // 点击回调
  onTap: () => void = () => {};

  build() {
    // 卡面直接用左侧 8vp 层色边框当「脊」。
    // 不再用独立子节点撑通高：内容列写 height('100%') 时，百分比会
    // 解析成 Scroll 视口高度，整张卡被拉成一屏（P1 实测大片空白）。
    Column() {
        // 封面区：设计稿 186vp 高，图片 Cover 填充。
        // Stack 的 alignContent 必须是 TopStart——用 BottomStart 时
        // 满高的 Image 会被推到底部，顶部露出 Stack 自身底色成一条白带。
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.coverImage !== '') {
            // rawfile 资源必须走 $rawfile()——直接 Image(字符串) 不解析路径，
            // 结果是静默空白（实测：整块封面区全白）。
            // 高度必须写 186 而不是 '100%'：Stack 的 100% 会解析成
            // 「Stack 当前高度的 100%」，而 Stack 自身高度靠这个 Image 定，
            // 循环下退化成内容高，顶部就露出一道白带。
            Image($rawfile(this.coverImage))
              .width('100%')
              .height(186)
              .objectFit(ImageFit.Cover)
              .draggable(false)
          } else {
            // 占位态：层色整块 + 居中「图像整备中」
            Column() {
              Text('图像整备中')
                .fontSize(FS_CAPTION)
                .fontColor(SURFACE_CARD)
                .opacity(0.85)
            }
            .width('100%')
            .height(186)
            .backgroundColor(eraColor(this.era))
            .justifyContent(FlexAlign.Center)
          }

          // 层号章：白底，浮在封面左上
          LayerBadge({
            layerCode: this.layerCode,
            era: this.era,
            eraLabel: ''
          })
          .position({ left: 12, top: 12 })
        }
        .width('100%')
        .height(186)

        // 文字区
        Column({ space: 4 }) {
          Text(this.title)
            .fontSize(FS_TITLE)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(eraColor(this.era))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.subtitle !== '') {
            Text(this.subtitle)
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          // 双轴计数（A 方案）：遗址数与文物数并列。
          // 放在副题之后而不是取代副题——副题答"这层是什么"，
          // 这一行答"这层里站着多少东西"，两件事不互相顶替。
          if (this.relicCount >= 0) {
            Row({ space: ROW_GAP }) {
              Text(`${this.total} 处遗址 ·`)
                .fontSize(FS_CAPTION)
                .fontFamily(FONT_SERIF)
                .fontColor(SUB)
              Text(`${this.relicCount} 件文物`)
                .fontSize(FS_CAPTION)
                .fontFamily(FONT_MONO)
                .fontColor(SUB)
            }
            .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })

        // 发掘进度条：六格小段，已读实色、未读 50% 透明灰（设计稿①）。
        // 没有数据（total=0）时整条不渲染——画 6 格空条会说谎。
        if (this.total > 0) {
          MiniProfile({ total: this.total, done: this.done, era: this.era })
            .padding({ left: 16, right: 16, bottom: 12 })
        }
    }
    .width('100%')
    .backgroundColor(SURFACE_CARD)
    .borderRadius(RADIUS_MD)
    // 左侧 8vp 层色即「脊」：边框随卡高自然通高，不依赖百分比高度。
    .border({
      width: { left: 8, top: HAIR, right: HAIR, bottom: HAIR },
      color: {
        left: eraColor(this.era),
        top: LINE_HAIR,
        right: LINE_HAIR,
        bottom: LINE_HAIR
      }
    })
    .shadow({
      radius: SHADOW_CARD_RADIUS,
      color: SHADOW_CARD_COLOR_LIGHT,
      offsetX: 0,
      offsetY: SHADOW_CARD_OFFSET
    })
    .clip(true)
    .onClick(() => this.onTap())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(this.title + (this.subtitle !== '' ? '，' + this.subtitle : ''))
    .accessibilityLevel('yes')
  }
}
