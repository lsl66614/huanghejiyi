// entry/src/main/ets/pages/CreditsPage.ets —— 图片版权与来源（CC BY-SA 合规页）
//
// 随包 76 张实拍里 61 张是 CC BY-SA，该许可要求署名、给出许可链接并说明修改。
// 这三件事在本页一次做完：逐张作者与原文件名、按许可分组并附许可链接、
// 全局改动声明，外加首页 6 张 AI 示意图的非照片声明。

import { common } from '@kit.AbilityKit';
import type { AttributionData, AttributionRecord, FontRecord, LicenceGroup } from '../service/content/Attribution';
import {
  aiStatement, changeStatement, creditLine, groupByLicence, licenceUrl
} from '../service/content/Attribution';
import { AttributionRepo } from '../repository/AttributionRepo';
import { BackLink } from '../common/BackLink';
import { THEME_BG, THEME_INK } from '../common/EraTheme';
import {
  ACCENT, CARD_PAD, CHIP_RADIUS, FONT_DISPLAY, FONT_MONO, FONT_SERIF,
  FS_BODY, FS_CAPTION, FS_HEAD, FS_META, FS_PAGE, LH_CAPTION, LH_PAGE,
  HAIR, INK, ITEM_GAP, LH_BODY, LINE_HAIR, MICRO_GAP, PAGE_PAD_X,
  RADIUS_CARD_LG, ROUTE_FADE_MIN, ROUTE_SHIFT_VP,
  SUB, SURFACE_CARD, SURFACE_RAISED, WT_DISPLAY, WT_SERIF
} from '../common/DesignTokens';

import { curveIn, curveOut, durRouteIn, durRouteOut } from '../common/Motion';

@Entry
@Component
struct CreditsPage {
  @State groups: LicenceGroup[] = [];
  @State fonts: FontRecord[] = [];
  @State policy: string = '';
  @State statement: string = '';
  @State aiNote: string = '';
  @State total: number = 0;

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
    AttributionRepo.load(ctx).then((d: AttributionData) => {
      this.policy = d.policy;
      this.statement = changeStatement(d.images);
      this.aiNote = aiStatement(d.aiIllustrations);
      this.total = d.images.length;
      this.groups = groupByLicence(d.images);
      this.fonts = d.fonts;
    });
  }

  @Builder
  groupHead(g: LicenceGroup) {
    Column({ space: MICRO_GAP }) {
      Row({ space: ITEM_GAP }) {
        Text(g.licence)
          .fontSize(FS_HEAD)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(INK)
        Text(g.requiresCredit ? '需署名' : '自愿记录')
          .fontSize(FS_CAPTION)
          .fontColor(g.requiresCredit ? ACCENT : SUB)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(SURFACE_RAISED)
          .border({ width: HAIR, color: LINE_HAIR })
          .borderRadius(CHIP_RADIUS)
        Blank()
        Text(`${g.records.length} 张`)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_MONO)
          .fontColor(SUB)
      }
      .width('100%')

      if (licenceUrl(g.licence) !== '') {
        // 许可链接是 BY-SA 4.0 §3.a 的硬要求；长按可复制。
        Text(licenceUrl(g.licence))
          .fontSize(FS_META)
          .fontFamily(FONT_MONO)
          .fontColor(SUB)
          .copyOption(CopyOptions.LocalDevice)
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 24, bottom: 12 })
    .backgroundColor(THEME_BG)
  }

  @Builder
  recordRow(r: AttributionRecord) {
    Column({ space: MICRO_GAP }) {
      Text(r.file)
        .fontSize(FS_BODY)
        .fontFamily(FONT_SERIF)
        .fontWeight(WT_SERIF)
        .fontColor(INK)
        .lineHeight(LH_BODY)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(creditLine(r))
        .fontSize(FS_CAPTION)
        .fontColor(SUB)
        .width('100%')
      Text(r.source)
        .fontSize(FS_META)
        .fontFamily(FONT_MONO)
        .fontColor(SUB)
        .copyOption(CopyOptions.LocalDevice)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 12 })
    .border({ width: { top: HAIR }, color: LINE_HAIR })
    .accessibilityGroup(true)
    .accessibilityText(`${r.file}，${creditLine(r)}，来源 ${r.source}`)
  }

  @Builder
  fontRow(f: FontRecord) {
    Column({ space: MICRO_GAP }) {
      Text(f.family)
        .fontSize(FS_BODY)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(INK)
        .width('100%')
      Text(`${f.licence} · ${f.file}`)
        .fontSize(FS_CAPTION)
        .fontColor(SUB)
        .width('100%')
      Text(f.copyright)
        .fontSize(FS_META)
        .fontFamily(FONT_SERIF)
        .fontWeight(WT_SERIF)
        .fontColor(SUB)
        .width('100%')
      Text(`许可原文随包：${f.licenceFile}`)
        .fontSize(FS_META)
        .fontFamily(FONT_MONO)
        .fontColor(SUB)
        .copyOption(CopyOptions.LocalDevice)
        .width('100%')
      Text(f.source)
        .fontSize(FS_META)
        .fontFamily(FONT_MONO)
        .fontColor(SUB)
        .copyOption(CopyOptions.LocalDevice)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 12 })
    .border({ width: { top: HAIR }, color: LINE_HAIR })
    .accessibilityGroup(true)
    .accessibilityText(`${f.family}，${f.licence}，${f.copyright}`)
  }

  @Builder
  noteCard(title: string, body: string) {
    Column({ space: ITEM_GAP }) {
      Text(title)
        .fontSize(FS_CAPTION)
        .letterSpacing(3)
        .fontColor(SUB)
      Text(body)
        .fontSize(FS_BODY)
        .fontFamily(FONT_SERIF)
        .fontWeight(WT_SERIF)
        .fontColor(INK)
        .lineHeight(LH_BODY)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(CARD_PAD)
    .backgroundColor(SURFACE_CARD)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(RADIUS_CARD_LG)
  }

  build() {
    Column() {
      Row() {
        BackLink()
        Blank()
        Text('版权')
          .fontSize(FS_CAPTION)
          .letterSpacing(3)
          .fontColor(SUB)
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 16 })

      List({ space: 0 }) {
        ListItem() {
          Column({ space: 24 }) {
            Column({ space: 6 }) {
              Text('图片版权与来源')
                .fontSize(FS_PAGE)
                .fontFamily(FONT_DISPLAY)
                .fontWeight(WT_DISPLAY)
                .letterSpacing(1)
                .fontColor(THEME_INK)
                .lineHeight(LH_PAGE)
              Text(this.total === 0 ? '加载中…' : `随包实拍 ${this.total} 张，按许可分组列出`)
                .fontSize(FS_CAPTION)
                .letterSpacing(1)
                .fontColor(SUB)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')

            if (this.policy !== '') {
              this.noteCard('记录口径', this.policy)
            }
            if (this.statement !== '') {
              this.noteCard('对原图的改动', this.statement)
            }
            if (this.aiNote !== '') {
              this.noteCard('示意图说明', this.aiNote)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 8, bottom: 16 })
        }

        ForEach(this.groups, (g: LicenceGroup) => {
          ListItemGroup({ header: this.groupHead(g) }) {
            ForEach(g.records, (r: AttributionRecord) => {
              ListItem() {
                this.recordRow(r)
              }
            }, (r: AttributionRecord) => r.path)
          }
        }, (g: LicenceGroup) => `${g.licence}|${g.records.length}`)

        // 字体区：OFL 1.1 要求分发时带上版权行与许可原文，
        // 原文已放 rawfile/font/OFL-*.txt，屏上把「谁的字、什么许可、原文在哪」说清。
        if (this.fonts.length > 0) {
          ListItem() {
            Column({ space: MICRO_GAP }) {
              Text('字体')
                .fontSize(FS_HEAD)
                .fontFamily(FONT_DISPLAY)
                .fontWeight(WT_DISPLAY)
                .fontColor(INK)
              Text(`随包 ${this.fonts.length} 个字面，均按 SIL Open Font License 1.1 使用，许可原文一并随包`)
                .fontSize(FS_CAPTION)
                .letterSpacing(1)
                .fontColor(SUB)
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 24, bottom: 12 })
          }
          ForEach(this.fonts, (f: FontRecord) => {
            ListItem() {
              this.fontRow(f)
            }
          }, (f: FontRecord) => f.file)
        }

        ListItem() {
          Text('以上署名信息随包存储于 rawfile/attribution.json，'
            + '图片部分由 tools/build_attribution.py 从 Commons 元数据与台账生成，'
            + '字体部分取上游 google/fonts 的 OFL 原文；构建期由 check_attribution.py 校验完整性。')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontWeight(WT_SERIF)
            .fontColor(SUB)
            .lineHeight(LH_CAPTION)
            .width('100%')
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 24, bottom: 40 })
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}
