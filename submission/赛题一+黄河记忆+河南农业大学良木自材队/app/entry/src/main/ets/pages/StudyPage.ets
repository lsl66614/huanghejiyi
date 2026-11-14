// entry/src/main/ets/pages/StudyPage.ets —— 「研读」页：一张剖面图
//
// 为什么单独成页（修复计划 §7.13）：档案页原先把研读做成内嵌分段，
// 于是同一屏叠了两个大标题——档案页的 30pt「档案」+ 分段的节标题，
// 用户读作「标题乱了」。改成从档案页的四张入口卡 pushUrl 进来后，
// 这一屏只有一个 30pt 标题，返回键回到档案落地页。
//
// 为什么是一张图而不是两组统计卡 + 六行进度条（修复计划 §7.14）：
// 「研读」在这套产品里本来就有图形语言——地层剖面。原先那种
// 「统计卡 + 百分比条」是通用 dashboard，和其余三屏一样没有身份。
// 现在层高＝该层总段数、填充＝已读段数，深度和进度由同一根柱子说话，
// 数字退到右侧标注，点一层直接进那一层的遗址列表。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import type { FavoriteDO, NoteView, ProgressDO } from '../model/UserDataModels';
import type { SiteInfo } from '../model/ContentModels';
import { ERAS } from '../model/ContentModels';
import { ContentRepo } from '../repository/ContentRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import { BackLink } from '../common/BackLink';
import { THEME_BG, eraColor, eraColorA, eraName } from '../common/EraTheme';
import {
  BLOCK_GAP, FONT_MONO, FONT_SERIF, FS_BODY, FS_CAPTION, FS_ITEM, HAIR, INK, ITEM_GAP,
  LH_CAPTION, LINE_HAIR, PAGE_PAD_X, PRESS_OPACITY, ROUTE_FADE_MIN, ROUTE_SHIFT_VP,
  ROW_GAP, SUB, WT_SERIF
} from '../common/DesignTokens';
import { SectionTitle } from '../common/SectionTitle';

import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';

// 一个年代格：研读进度（已读段数 / 总段数）
class EraProgress {
  era: string = '';
  label: string = '';
  done: number = 0;
  total: number = 0;
  percent: number = 0;
}

// 一段研读在剖面上占多高。层高必须真的等于段数，
// 否则这张图只是在装饰，读者从柱子里读不出「这一层有多少可读的」。
const SEG_H: number = 3;
// 0 段层的最小高：画成 0 就看不见，六层剖面会莫名其妙少一层。
const MIN_LAYER_H: number = 40;
// 柱宽：给右侧标注留出可读的宽度。
// 原先 120（vp）——在 1320px 屏上只占 360px，柱体右侧到读数之间空出
// 600px，整页读作"左边几个色块 + 右边几个数字"，剖面没有分量（实测截图）。
// 现在柱体占屏宽的近四成，标注紧贴柱体右侧，读数仍右对齐到页缘。
const COLUMN_W: number = 200;
// 未读部分的层色底：只做"这层存在"的提示，不承载读数信息。
// 浅到不与实色填充混淆，实色一填上来就能一眼分出读了多少。
const LAYER_TINT_ALPHA: string = '2E';

@Entry
@Component
struct StudyPage {
  @State favCount: number = 0;
  @State noteCount: number = 0;
  @State studiedSections: number = 0;
  @State siteTotal: number = 0;
  @State relicTotal: number = 0;
  @State eventTotal: number = 0;
  @State poemTotal: number = 0;
  @State eraRows: EraProgress[] = [];
  // 按下的层：@Builder 产物是独立子树，按压态只能记在页面上。
  @State pressedEra: string = '';

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

  onPageShow(): void {
    this.reload();
  }

  // 剖面完整度（spec §5.5 的全局深度尺）：每个年代一层，
  // 分母是该年代遗址的五段研读总段数，分子是已完成段数。
  // 只统计真实存在的 progress 记录，不估算、不补零。
  private buildEraRows(sites: SiteInfo[], progress: ProgressDO[]): EraProgress[] {
    const doneKeys: string[] = [];
    for (const p of progress) {
      if (p.done) { doneKeys.push(`${p.targetKey}#${p.section}`); }
    }
    const out: EraProgress[] = [];
    for (const era of ERAS) {
      let total: number = 0;
      let done: number = 0;
      for (const s of sites) {
        if (s.era !== era) { continue; }
        total += 5;
        for (const sec of ['intro', 'arch', 'events', 'poems', 'tourism']) {
          if (doneKeys.includes(`site:${s.id}#${sec}`)) { done += 1; }
        }
      }
      const row = new EraProgress();
      row.era = era;
      row.label = eraName(era);
      row.done = done;
      row.total = total;
      row.percent = total === 0 ? 0 : Math.round(done * 100 / total);
      out.push(row);
    }
    return out;
  }

  totalSegs(): number {
    let n: number = 0;
    for (const r of this.eraRows) { n += r.total; }
    return n;
  }

  layerH(r: EraProgress): number {
    return r.total === 0 ? MIN_LAYER_H : Math.max(MIN_LAYER_H, r.total * SEG_H);
  }

  reload(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
      ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
        this.eraRows = this.buildEraRows(sites, p);
      });
    });
    ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
      let relics: number = 0;
      let events: number = 0;
      let poems: number = 0;
      for (const s of sites) {
        relics += s.relics.length;
        events += s.events.length;
        poems += s.poems.length;
      }
      this.siteTotal = sites.length;
      this.relicTotal = relics;
      this.eventTotal = events;
      this.poemTotal = poems;
      if (this.eraRows.length === 0) {
        this.eraRows = this.buildEraRows(sites, []);
      }
    });
  }

  // 一层：左边柱体（层高＝总段数，自底向上填已读），右边标注。
  // 层与层之间不留缝——剖面是一根连续的柱子，边界由发丝给。
  @Builder
  layerRow(r: EraProgress, no: number) {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Bottom }) {
        // 未读部分也必须是层色，不是白底（2026-11-05 实测截图）：
        // 一段没读时整根柱子只剩一个白框发丝，读作"图没加载出来"，
        // 六层并排就是满屏空白。剖面图里每一层本来就有自己的沉积色，
        // 浅调打底 + 实色填充，0 段也看得出这是哪一层。
        Row()
          .width('100%')
          .height(this.layerH(r))
          .backgroundColor(eraColorA(r.era, LAYER_TINT_ALPHA))
          .border({ width: HAIR, color: LINE_HAIR })
        if (r.done > 0) {
          // 填充：层色实底，高度按已读段数比例。不做渐变、不做动效。
          Row()
            .width('100%')
            .height(this.layerH(r) * r.done / r.total)
            .backgroundColor(eraColor(r.era))
        }
      }
      .width(COLUMN_W)
      .height(this.layerH(r))

      // 标注：层号与年代名靠左，读数右对齐到页缘。
      // 原先三行全挤在左端（标注列虽撑满宽度，内容只占 x=456..594，
      // 右边 600px 全空），读作一列没有对齐的散字。右对齐读数后，
      // 六个层的数字上下成一列，剖面才读得出"逐层对照"。
      Column({ space: 4 }) {
        Text(`L${no}`)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_MONO)
          .fontColor(SUB)
        Text(r.label)
          .fontSize(FS_BODY)
          .fontFamily(FONT_SERIF)
          .fontWeight(WT_SERIF)
          .fontColor(INK)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Column({ space: 4 }) {
        if (r.total === 0) {
          Text('这一层暂无遗址')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_MONO)
            .fontColor(SUB)
            .textAlign(TextAlign.End)
        } else {
          Text(`${r.done} / ${r.total}`)
            .fontSize(FS_ITEM)
            .fontFamily(FONT_MONO)
            .fontColor(INK)
            .textAlign(TextAlign.End)
          Text('段已读')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_MONO)
            .fontColor(SUB)
            .textAlign(TextAlign.End)
        }
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: ITEM_GAP, bottom: ITEM_GAP })
    .onClick(() => {
      const prm: Record<string, string> = { 'era': r.era };
      router.pushUrl({ url: 'pages/ListPage', params: prm });
    })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.pressedEra = r.era;
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.pressedEra = '';
      }
    })
    .opacity(this.pressedEra === r.era ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`${r.label}，第 ${no} 层，已读 ${r.done} / ${r.total} 段，进入这一层的遗址列表`)
    .accessibilityLevel('yes')
  }

  build() {
    Column() {
      // 顶栏只有返回（与 ListPage 同款）：标题交给下面的 SectionTitle，
      // 不在顶栏再写一遍页名——那正是内嵌分段时代的病。
      Row({ space: ROW_GAP }) {
        BackLink({ backToParent: true })
        Blank()
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16 })

      Column({ space: 6 }) {
        SectionTitle({
          title: '研读',
          caption: `${this.studiedSections} 段已读 · 共 ${ERAS.length} 层剖面`
        })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: PAGE_PAD_X, top: 16, bottom: 16 })

      Scroll() {
        Column({ space: BLOCK_GAP }) {
          // 数字退成两行 mono 小字：这一屏的主角是剖面图，不是统计卡。
          Column({ space: 4 }) {
            Text(`已读 ${this.studiedSections} / ${this.totalSegs()} 段 · 收藏 ${this.favCount} · 笔记 ${this.noteCount}`)
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_MONO)
              .lineHeight(LH_CAPTION)
              .fontColor(INK)
            Text(`语料 遗址 ${this.siteTotal} · 文物 ${this.relicTotal} · 事件 ${this.eventTotal} · 诗词 ${this.poemTotal}`)
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_MONO)
              .lineHeight(LH_CAPTION)
              .fontColor(SUB)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })

          // 剖面图本体
          Column() {
            ForEach(this.eraRows, (r: EraProgress, i: number) => {
              this.layerRow(r, i + 1)
            }, (r: EraProgress) => `${r.era}|${r.done}|${r.total}`)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })

          Text('层高＝这一层所有遗址的五段研读总段数（介绍 / 考古 / 大事 / 诗词 / 文旅）；'
            + '填充自底向上，按真实读过的段数，不估算、不补零。点一层进那一层的遗址列表。')
            .fontSize(FS_CAPTION)
            .lineHeight(LH_CAPTION)
            .fontColor(SUB)
            .width('100%')
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 24 })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}
