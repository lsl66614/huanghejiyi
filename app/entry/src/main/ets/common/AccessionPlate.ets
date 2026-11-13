// entry/src/main/ets/common/AccessionPlate.ets
// 藏品签（catalogue tag）——「待入藏」占位的统一制式。
//
// 为什么重做：104 件文物 0 实拍，占位态就是主画面。原先的做法是一句
// 「图像整备中 / 待实拍入仓」——诚实，但读起来是「没做完」。博物馆对
// 未展出藏品的处理不是留白，而是**编目**：给它一个编号、一个材质章、
// 一个出土层位，让它作为一条档案存在。
//
// 本组件因此同时服务三种场景（深浅底各一套字色）：
//   深底   RelicPage 展柜主视觉（210vp）
//   浅底   DetailPage 代表文物横滑卡（120vp）、FavoritesPage 缩略（40vp）
// 由 onDark 一个入参切换，避免两个平行实现漂移。
//
// 信息层级（自上而下）：
//   ① 剪影     材质线稿，居中，占画面 62%
//   ② 材质章   中文材质名 + 英文码，仅大展签（≥200）
//   ③ 编号     藏编号制式「L3 · 014」——层号 + 序号
//   ④ 状态行   「待实拍入仓」/「REAL PHOTO PENDING」，仅大展签
//
// 尺寸契约：①②③④ 的取舍只由 plateSize 决定，且**组件总高会超过
// plateSize**——③ 排在图下，120 档实际占 144 高。调用方给 120 图位时
// 必须留够高度，否则文字溢出到卡片标题上（DetailPage 实测踩过）。
//
// 克制原则：占位态必须比真实态安静。不加边框、不加投影、不加角标，
// 只靠年代本体色做底——因为色块本身就是「年代」这条信息的承载体。
import { eraColor, eraTextDark, eraName } from './EraTheme';
import { relicIconSrc, materialKind } from './RelicIcon';
import {
  FONT_DISPLAY, FONT_MONO, FONT_SERIF, FS_CAPTION, FS_LABEL, FS_TITLE,
  HAIR, ON_DARK_LINE, ON_DARK_PANEL, ON_DARK_SUB, ON_DARK_TEXT_ALT,
  RADIUS_DOT_6, RADIUS_SM, SUB, WT_DISPLAY, WT_REGULAR, WT_SERIF
} from './DesignTokens';

// 层号：年代在六层剖面里的序位，与 LayerBadge 的 L1–L6 同一套口径。
// 早年代在前——地层越往下越老，编号越小。
const ERA_LAYER: Map<string, string> = new Map([
  ['yangshao', 'L1'], ['longshan', 'L2'], ['xiashang', 'L3'],
  ['zhou', 'L4'], ['hantang', 'L5'], ['song', 'L6']
]);

// 序号取该文物在其遗址 relics 数组中的位次（1 起），格式化为三位。
// 这不是「入藏进度」——馆藏入库比例是另一套数据，本项目没有，
// 不能拿序号冒充百分比（同 RelicPage 展签序位的纪律：序位用分段标记，不用进度条）。
function seqOf(relicId: string, siteRelicIds: string[]): string {
  const i: number = siteRelicIds.indexOf(relicId);
  const n: number = i >= 0 ? i + 1 : 1;
  return n < 10 ? `00${n}` : (n < 100 ? `0${n}` : `${n}`);
}

@Component
export struct AccessionPlate {
  // 画面边长（vp）：深底 210 / 浅底卡 120 / 收藏夹缩略 40
  plateSize: number = 120;
  era: string = '';
  material: string = '';
  relicId: string = '';
  // 该遗址下所有文物的 id，用于算序号；空数组时序号退化为 001
  siteRelicIds: string[] = [];
  // 深底（展柜）用暖白线条与浅字；浅底用墨色字
  onDark: boolean = false;
  // 是否显示材质章（窄画面关掉）
  showMaterial: boolean = true;

  private layer(): string {
    const l = ERA_LAYER.get(this.era);
    return l !== undefined ? l : 'L1';
  }

  private accessionCode(): string {
    return `${this.layer()} · ${seqOf(this.relicId, this.siteRelicIds)}`;
  }

  // 纵向间距随画面大小走：大画面要呼吸，小画面（缩略）不留缝。
  // 必须是方法——ArkUI 的属性参数里写不出嵌套三元。
  private stackSpace(): number {
    if (this.plateSize >= 200) { return 12; }
    if (this.plateSize >= 100) { return 8; }
    return 0;
  }

  // 材质章（深底版）：年代色点 + 归一化类名，带描边的一枚签。
  // 拆成 @Builder 是因为 build() 里 if 块内不能声明局部变量
  // （ArkTS 10905209：Only UI component syntax can be written here）。
  @Builder
  materialStamp() {
    Row({ space: 6 }) {
      Row()
        .width(6)
        .height(6)
        .borderRadius(RADIUS_DOT_6)
        .backgroundColor(eraTextDark(this.era))
      Text(materialKind(this.material))
        .fontSize(FS_CAPTION)
        .fontColor(ON_DARK_TEXT_ALT)
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor(ON_DARK_PANEL)
    .border({ width: HAIR, color: ON_DARK_LINE })
    .borderRadius(RADIUS_SM)
  }

  build() {
    Column({ space: this.stackSpace() }) {
      // ① 剪影：年代本体色底 + 材质线稿
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(this.plateSize)
          .height(this.plateSize)
          .backgroundColor(eraColor(this.era))
        Image($rawfile(relicIconSrc(this.material)))
          .width(this.plateSize * 0.62)
          .height(this.plateSize * 0.62)
          .objectFit(ImageFit.Contain)
          .draggable(false)
      }
      .width(this.plateSize)
      .height(this.plateSize)

      // ② 材质章：仅大展签。120 窄卡的材质由卡片说明行给，
      // 这里再画一遍会挤出剪影格（见下方高度约束）。
      if (this.showMaterial && this.plateSize >= 200) {
        if (this.onDark) {
          this.materialStamp()
        } else {
          Text(materialKind(this.material))
            .fontSize(FS_CAPTION)
            .fontColor(SUB)
        }
      }

      // ③ 编号：层号 + 序号，等宽体——编号要能逐字符读
      if (this.plateSize >= 100) {
        Text(this.accessionCode())
          .fontSize(this.plateSize >= 200 ? FS_TITLE : FS_CAPTION)
          .fontFamily(FONT_MONO)
          .fontColor(this.onDark ? ON_DARK_TEXT_ALT : SUB)
          .letterSpacing(1)
      }

      // ④ 状态行：只有大展签说。窄卡下方已有卡片自己的标题与材质，
      // 再说一遍「待实拍入仓」既重复又没地方放。
      if (this.plateSize >= 200) {
        Text('待 实 拍 入 仓')
          .fontSize(FS_TITLE)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(ON_DARK_TEXT_ALT)
          .letterSpacing(4)
        Text('REAL PHOTO PENDING')
          .fontSize(FS_LABEL)
          .fontFamily(FONT_SERIF)
          .fontWeight(WT_SERIF)
          .fontColor(ON_DARK_SUB)
          .letterSpacing(1)
      }
    }
    .alignItems(HorizontalAlign.Center)
  }
}

// 出土层的完整名：「L1 · 仰韶」制式，供展签标题行复用
export function layerName(era: string): string {
  const l = ERA_LAYER.get(era);
  const code: string = l !== undefined ? l : 'L1';
  return `${code} · ${eraName(era)}`;
}

// 层号本体：「L1」–「L6」。DetailPage 层号角标、LayerBadge、藏品签
// 三处共用同一口径，避免各自 indexOf 后漂移。
export function layerCode(era: string): string {
  const l = ERA_LAYER.get(era);
  return l !== undefined ? l : '';
}
