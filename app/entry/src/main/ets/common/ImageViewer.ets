// entry/src/main/ets/common/ImageViewer.ets
// 全屏看图（Lightbox）：点击缩略图 → bindContentCover 拉起页面级遮罩。
//
// 为什么用 bindContentCover 而不是 Overlay：Overlay 挂在页面内容树里，会被外层
// Scroll 裁剪且随内容滚动；bindContentCover 是页面级遮罩，不受 Scroll 影响，
// 且自带遮罩点击关闭与返回键响应（Competitor ImageGallery.ets 同思路）。
//
// 为什么走 getRawFileContent → createPixelMap 动态解码而不是 $rawfile()：
// $rawfile 交给 Image 组件自行解码，webp 大图在高密度屏上首帧慢且不可控；
// 动态解码能自己控制失败分支——解码失败显示占位卡而不是空白。
//
// 状态：@State 数组整体赋值触发刷新（ArkUI 约束：@State 数组 push 不触发刷新）。
//
// 缩放：双指捏合 + 双击 + 放大后单指平移，判定全在 common/ZoomMath（纯函数、有单测）。
// 这里只负责三件事——实测盒子尺寸、把增量手势折算成绝对状态、换张时复位。

import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ACCENT, FONT_MONO, FS_BODY, FS_CAPTION, FS_HERO, FS_TITLE, LINE_HAIR, SUB, SURFACE_RAISED,
  SURFACE_VIEWER
} from './DesignTokens';
import { focusRing } from './Accessibility';
import {
  ZOOM_MIN, ZoomOffset, clampOffset, clampScale, isZoomed, tapScale
} from './ZoomMath';

const DOMAIN = 0x0000;
const TAG = 'ImageViewer';

/** 图集输入：rawfile 相对路径数组 + 当前索引 */
@Component
export struct ImageViewer {
  images: string[] = [];
  startIndex: number = 0;
  /** 与 images 同序的署名图注（作者 · 许可）；空串表示这张没有可展示的署名。 */
  credits: string[] = [];
  onClose: () => void = () => {};
  @State private loaded: (image.PixelMap | null)[] = [];
  @State private index: number = 0;
  private disposed: boolean = false;
  // 缩放状态：只作用在主图那一个节点上，顶栏/图注/缩略图不参与变换。
  // 字段名不能叫 scale——ArkUI 给每个自定义组件都挂了 .scale() 属性，
  // 同名 @State 会把属性遮蔽掉，编译期直接报 10505001（不报在这里，报在 build 里）。
  @State private zoom: number = ZOOM_MIN;
  @State private offX: number = 0;
  @State private offY: number = 0;
  // 主图盒子的实测尺寸（vp）。平移上限要按它算——写死屏宽在折叠屏/平板上会错位。
  @State private boxW: number = 0;
  @State private boxH: number = 0;
  // 手势基线：ArkUI 的 event.scale / event.offsetX 都是相对**起点**的量，
  // 不在 onActionStart 记下起始值，每次 update 就会在旧值上再叠一层，越捏越快。
  private pinchBase: number = ZOOM_MIN;
  private panBaseX: number = 0;
  private panBaseY: number = 0;

  aboutToAppear(): void {
    this.index = this.startIndex;
    const init: (image.PixelMap | null)[] = [];
    for (let i = 0; i < this.images.length; i++) {
      init.push(null);
    }
    this.loaded = init;
    this.decodeAll();
  }

  aboutToDisappear(): void {
    this.disposed = true;
  }

  private async decodeAll(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (host === undefined) {
      return;
    }
    const rm = host.resourceManager;
    for (let i = 0; i < this.images.length; i++) {
      const path: string = this.images[i];
      if (path === '') {
        continue;
      }
      try {
        const data: Uint8Array = await rm.getRawFileContent(path);
        const src: image.ImageSource = image.createImageSource(data.buffer as ArrayBuffer);
        const pm: image.PixelMap = await src.createPixelMap();
        if (this.disposed) {
          return;
        }
        const next: (image.PixelMap | null)[] = this.loaded.slice();
        next[i] = pm;
        this.loaded = next;
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'decode failed: %{public}s', path);
      }
    }
  }

  private step(delta: number): void {
    const n: number = this.images.length;
    if (n === 0) {
      return;
    }
    this.index = (this.index + delta + n) % n;
    this.resetZoom();
  }

  // 换张必回 1×：带着 3× 的位移翻页，下一页开口就是半张文物 + 大片黑底。
  private resetZoom(): void {
    this.zoom = ZOOM_MIN;
    this.offX = 0;
    this.offY = 0;
    this.pinchBase = ZOOM_MIN;
    this.panBaseX = 0;
    this.panBaseY = 0;
  }

  private applyScale(next: number, recenter: boolean): void {
    this.zoom = clampScale(next);
    if (recenter) {
      this.offX = 0;
      this.offY = 0;
    }
    // 倍率一变，能拖的范围也跟着变：先按新倍率重夹一次，
    // 否则从 4× 捏回 1.2× 时旧位移会留在屏外，看着像图片跑丢了。
    const o: ZoomOffset = clampOffset(this.offX, this.offY, this.zoom, this.boxW, this.boxH);
    this.offX = o.dx;
    this.offY = o.dy;
    if (!isZoomed(this.zoom)) {
      this.zoom = ZOOM_MIN;
    }
  }

  private onDoubleTap(): void {
    this.applyScale(tapScale(this.zoom), true);
  }

  private onPinchStart(): void {
    this.pinchBase = this.zoom;
  }

  private onPinchUpdate(e: GestureEvent): void {
    this.applyScale(this.pinchBase * e.scale, false);
  }

  private onPanStart(): void {
    this.panBaseX = this.offX;
    this.panBaseY = this.offY;
  }

  private onPanUpdate(e: GestureEvent): void {
    if (!isZoomed(this.zoom)) {
      // 1× 时不平移：否则手指会把刚好适应屏幕的文物拖离中心，且再也对不回。
      return;
    }
    const o: ZoomOffset = clampOffset(this.panBaseX + e.offsetX, this.panBaseY + e.offsetY,
      this.zoom, this.boxW, this.boxH);
    this.offX = o.dx;
    this.offY = o.dy;
  }

  // 顶栏右侧那一格做两用：没放大时它是入口提示（放大这件事得让人知道能按），
  // 放大后变成读数——读数同时是给读屏和自动化断言用的，光靠 .scale() 屏上没有证据。
  private zoomLabel(): string {
    return `${(Math.round(this.zoom * 10) / 10).toFixed(1)}×`;
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 深色遮罩：点空白处关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(SURFACE_VIEWER)
        // 遮罩是可点区：点空白关闭。Column 默认不可聚焦，必须显式开。
        .focusable(true)
        .focusBox(focusRing())
        .onClick(() => {
          this.onClose();
        })

      Column({ space: 16 }) {
        // 顶栏：标题 + 关闭
        Row() {
          Text('文物细观')
            .fontSize(FS_BODY)
            .letterSpacing(3)
            .fontColor(SUB)
          Blank()
          // 放大时给读数（读屏与自动化都靠它取证），没放大时给入口提示。
          if (isZoomed(this.zoom)) {
            Text(this.zoomLabel())
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_MONO)
              .fontColor(SUB)
              .margin({ right: 12 })
              .accessibilityText(`当前放大 ${this.zoomLabel()}`)
          } else {
            Text('双指 / 双击可放大')
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
              .margin({ right: 12 })
          }
          Text('关闭 ✕')
            .fontSize(FS_BODY)
            .fontColor(SUB)
            .padding({ left: 12, right: 4, top: 8, bottom: 8 })
            .accessibilityText('关闭细观')
            .focusable(true)
            .focusBox(focusRing())
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 4 })
        // 主图区：左右轻点切换，图片本体不触发关闭
        Stack({ alignContent: Alignment.Center }) {
          if (this.index >= 0 && this.index < this.loaded.length) {
            if (this.loaded[this.index] !== null) {
              Image(this.loaded[this.index])
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                // 变换只作用于图片本体；translate 在前、scale 在后按 ArkUI 的合成语义
                // 是以节点中心为原点缩放，所以放大天然居中，不需要额外补偿。
                .scale({ x: this.zoom, y: this.zoom })
                .translate({ x: this.offX, y: this.offY })
                // 图本身没有可念的文字；页码与署名各是独立节点，
                // 这里只报「这是什么」，不把「第几张」重复念两遍。
                .accessibilityText(isZoomed(this.zoom)
                  ? `文物细观图片，放大 ${this.zoomLabel()}`
                  : '文物细观图片')
            } else {
              Column({ space: 10 }) {
                Text('◌')
                  .fontSize(FS_HERO)
                  .fontColor(SUB)
                Text('图片解码中 / 未入仓')
                  .fontSize(FS_BODY)
                  .fontColor(SUB)
              }
              // ◌ 是装饰占位符，不合并的话读屏会先念一个「空心圆」。
              .accessibilityText('图片解码中或未入仓')
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        // 放大后必须裁在这一格里：不裁的话文物会盖住顶栏读数和底部箭头，
        // 读作"界面被图片吃掉了"。
        .clip(true)
        // 平移上限按实测盒子算，不拿屏宽当尺寸——这一格上下还有图注与页码。
        .onAreaChange((_o: Area, a: Area) => {
          this.boxW = a.width as number;
          this.boxH = a.height as number;
        })
        // Exclusive：双击、捏合、平移互不抢事件。
        // 顺序是硬规定：SDK 在 GestureGroupGestureHandlerOptions.gestures 的 NOTE 里写明
        // "双击要排在单击之前，反了两者都不工作"。这里原本挂的是 .onClick（等价于
        // count:1 的识别器），实测 uitest doubleClick 打上去完全不放大——就是它把两次
        // 单击吃掉了一半。改成组内 count:1 的空操作，既保住"点图不穿透遮罩"，
        // 又让 count:2 先判。
        .gesture(
          GestureGroup(GestureMode.Exclusive,
            TapGesture({ count: 2 })
              .onAction((_e: GestureEvent) => {
                this.onDoubleTap();
              }),
            PinchGesture({ fingers: 2 })
              .onActionStart((_e: GestureEvent) => {
                this.onPinchStart();
              })
              .onActionUpdate((e: GestureEvent) => {
                this.onPinchUpdate(e);
              }),
            PanGesture({ direction: PanDirection.All, distance: 4 })
              .onActionStart((_e: GestureEvent) => {
                this.onPanStart();
              })
              .onActionUpdate((e: GestureEvent) => {
                this.onPanUpdate(e);
              }),
            TapGesture({ count: 1 })
              .onAction((_e: GestureEvent) => {
                // 空操作：图片节点必须有识别器才不会被"穿透"到下层遮罩把灯箱关掉。
                // 原先这是一句 .onClick，理由见上面那段注释。
              })
          )
        )

        // 署名图注：CC BY-SA 要求署名出现在作品旁边，而不只在版权页里。
        // 无记录（示意图 / 未入仓）时整行不渲染，避免出现空行高。
        if (this.index >= 0 && this.index < this.credits.length && this.credits[this.index] !== '') {
          Text(this.credits[this.index])
            .fontSize(FS_BODY)
            .fontColor(SUB)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
            .padding({ left: 24, right: 24 })
        }

        // 底部：页码 + 切换箭头
        Row({ space: 24 }) {
          Text('◀')
            .fontSize(FS_TITLE)
            .fontColor(this.images.length > 1 ? SUB : LINE_HAIR)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            // 读屏只会念「◀」这一个符号，补上「上一张」。
            .accessibilityText(this.index > 0 ? '上一张' : '已是第一张')
            .enabled(this.index > 0)
            .focusable(true)
            .focusBox(focusRing())
            .onClick(() => {
              this.step(-1);
            })
          Text(`${this.index + 1} / ${this.images.length}`)
            .fontSize(FS_BODY)
            .letterSpacing(2)
            .fontColor(SUB)
            .accessibilityText(`第 ${this.index + 1} 张，共 ${this.images.length} 张`)
          Text('▶')
            .fontSize(FS_TITLE)
            .fontColor(this.images.length > 1 ? SUB : LINE_HAIR)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .accessibilityText(this.index < this.images.length - 1 ? '下一张' : '已是最后一张')
            .enabled(this.index < this.images.length - 1)
            .focusable(true)
            .focusBox(focusRing())
            .onClick(() => {
              this.step(1);
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 8, bottom: 24 })

        // 缩略图条：点任一张直接跳过去
        if (this.images.length > 1) {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.images, (p: string, i: number) => {
                Column() {
                  if (this.loaded[i] !== null) {
                    Image(this.loaded[i])
                      .width(52)
                      .height(52)
                      .objectFit(ImageFit.Cover)
                  } else {
                    Column()
                      .width(52)
                      .height(52)
                      .backgroundColor(SURFACE_RAISED)
                  }
                }
                .border({ width: this.index === i ? 2 : 1, color: this.index === i ? ACCENT : LINE_HAIR })
                .accessibilityText(`第 ${i + 1} 张缩略图`)
                .accessibilitySelected(this.index === i)
                .focusable(true)
                .focusBox(focusRing())
                .onClick(() => {
                  this.index = i;
                  this.resetZoom();
                })
              }, (p: string) => p)
            }
            .padding({ left: 24, right: 24 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .height(64)
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}