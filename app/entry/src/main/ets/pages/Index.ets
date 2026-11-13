import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ERAS, RouteInfo, SiteInfo } from '../model/ContentModels';
import { ProgressDO, SECTIONS } from '../model/UserDataModels';
import type { VisitDO } from '../model/UserDataModels';
import { ContentRepo, ContentLoadResult } from '../repository/ContentRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import { buildEraRelicStats, EraRelicStat } from '../service/content/EraRelicCount';
import { eraColor, eraCoverImage, eraName, eraSpan, THEME_BG, THEME_INK } from '../common/EraTheme';
import {
  ACCENT, BLOCK_GAP, BODY, CARD_PAD, CHIP_H, CHIP_RADIUS,
  FONT_DISPLAY, FONT_SANS, FONT_SERIF, FS_CAPTION,
  FS_DISPLAY, FS_ITEM, FS_LOCKUP, FS_META,
  FS_TAB, FS_TITLE, HAIR, HAIR_PAD,
  INK, ITEM_GAP, LH_LOCKUP,
  LINE_HAIR, PAGE_PAD_X, PRESS_OPACITY,
  RADIUS_CARD_LG, RADIUS_NAV_ITEM, ROUTE_FADE_MIN, ROUTE_SHIFT_VP,
  ROW_GAP, SEAL_SIZE, SUB,
  SURFACE_CARD, SURFACE_RAISED, WT_DISPLAY, WT_MEDIUM,
  WT_REGULAR, WT_SERIF
} from '../common/DesignTokens';
import { focusRing } from '../common/Accessibility';
import { firstRealImage } from '../common/ImagePolicy';
import { relicIconSrc } from '../common/RelicIcon';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';
import { PressFade, PressScale } from '../common/PressScale';
import { cityName, ERA_ALIAS } from '../common/Labels';
import { StrataSpineCard } from '../common/StrataSpineCard';
import { LayerBadge } from '../common/LayerBadge';
import { MiniProfile } from '../common/MiniProfile';
import { HuangheSeal } from '../common/HuangheSeal';
import { HuiwenDivider } from '../common/HuiwenDivider';
import { AppNavBar } from '../common/AppNavBar';
import { SyncStatusBar } from '../common/SyncStatusBar';

class EraStat {
  era: string = '';
  count: number = 0;
  done: number = 0;   // 五段落全部读完的遗址数
  // 该年代的文物件数（A 方案双轴：与 count 并列，让双实体在首屏有落点）。
  // 按器物自己的年代计，不按遗址年代——语料里有 12 件跨代文物。
  relics: number = 0;
}

// 今日一物：按本地日期取一件，同一天稳定、跨天轮换。
class DailyRelic {
  id: string = '';
  name: string = '';
  era: string = '';
  material: string = '';
  images: string[] = [];
  siteId: string = '';
  siteName: string = '';
}

// 年代卡的副题：文化别称 + 距今约XXXX年。设计稿①的六条。
const ERA_SUBTITLES: Map<string, string> = new Map([
  ['yangshao', '庙底沟文化 · 距今约6000年'],
  ['longshan', '早期国家形态 · 距今约4300年'],
  ['xiashang', '青铜礼制初成 · 距今约3800年'],
  ['zhou', '礼乐制度 · 距今约3000年'],
  ['hantang', '丝路起点 · 距今约1400年'],
  ['song', '市井繁华 · 距今约900年']
]);

@Entry
@Component
struct Index {
  @State stats: EraStat[] = [];
  private sites: SiteInfo[] = [];
  private readKeys: Set<string> = new Set();
  private ctx: common.UIAbilityContext | null = null;
  @State loading: boolean = true;
  @State loadError: string = '';
  @State failedCount: number = 0;
  @State failedNames: string[] = [];
  // P1-4：今日一物 / 继续研读。两块都是全宽卡，用同一个按压态键。
  // 首页不再有文物图录 / 主题路线入口——两者是「我的」的第 03、04 行，
  // 在首页重复出现会让第一屏读作仪表盘而不是档案本身。
  // 语料体量（遗址/文物/事件/诗词）同理，改由「我的」的档案概览承担。
  @State daily: DailyRelic | null = null;
  @State contId: string = '';
  @State contName: string = '';
  @State contMeta: string = '';
  @State entryPressed: string = '';

  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }

  aboutToAppear(): void {
    this.ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 自定义字体注册须在页面 UIContext 上进行（onCreate 阶段 $rawfile 注册报 1300002）。
    // 两个字族都只有一个面：宋体 800 / 站酷小薇 400。传其他字重会触发合成加粗，
    // 笔画糊成一团——所以 registerFont 必须和 WT_SERIF / WT_DISPLAY 配对使用。
    try {
      this.getUIContext().getFont().registerFont({
        familyName: 'NotoSerifSC',
        familySrc: $rawfile('font/NotoSerifSC-Head800.ttf')
      });
      this.getUIContext().getFont().registerFont({
        familyName: 'ZCOOLXiaoWei',
        familySrc: $rawfile('font/ZCOOLXiaoWei-Sub.ttf')
      });
    } catch (e) {
      hilog.error(0x0000, 'FONT', 'register fail: %{public}s', JSON.stringify(e));
    }
    this.loadCorpus(false);
    this.refreshProgress();
  }

  // retry=true 时先清缓存：失败后重试必须真的重读 rawfile，
  // 否则拿到的还是上一份空结果。
  loadCorpus(retry: boolean): void {
    const ctx = this.ctx;
    if (ctx === null) { return; }
    if (retry) { ContentRepo.invalidate(); }
    this.loading = true;
    this.loadError = '';
    // T4 冷启动的唯一可观测锚点：语料解析+建索引的实际耗时。
    // 没有这一行，"≤2s" 就只能是靠感觉写的假绿。
    const t0 = Date.now();
    ContentRepo.loadReport(ctx).then((r: ContentLoadResult) => {
      hilog.info(0x0000, 'BOOT', 'corpus ready: %{public}d/%{public}d sites in %{public}d ms',
        r.sites.length, r.total, Date.now() - t0);
      this.sites = r.sites;
      this.failedCount = r.failed.length;
      this.failedNames = r.failed.slice(0, 3);
      if (r.total > 0 && r.sites.length === 0) {
        this.loadError = `全部 ${r.total} 份语料都无法解析`;
      }
      this.loading = false;
      this.refreshStats();
    }).catch((err: Object) => {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(0x0000, 'IDX', 'load fail %{public}s', msg);
      this.loading = false;
      this.loadError = msg;
    });
  }

  onPageShow(): void {
    // 从详情页返回后刷新研读完成度与“上次看到哪”
    this.refreshProgress();
    this.refreshContinue();
  }

  // 今日一物：本地日期哈希，同一天多次进入结果稳定，跨天自然轮换。
  // 不新建表、不写库，纯函数式取模。
  refreshDaily(): void {
    const all: DailyRelic[] = [];
    for (const s of this.sites) {
      for (const r of s.relics) {
        const d = new DailyRelic();
        d.id = r.id;
        d.name = r.name;
        d.era = r.era;
        d.material = r.material;
        d.images = r.images;
        d.siteId = s.id;
        d.siteName = s.name;
        all.push(d);
      }
    }
    if (all.length === 0) {
      this.daily = null;
      return;
    }
    const now = new Date();
    const seed: number = now.getFullYear() * 372 + (now.getMonth() + 1) * 31 + now.getDate();
    this.daily = all[seed % all.length];
  }

  // 继续研读：最近一条 site: 浏览记录。遗址还没加载完时先不动，
  // 加载完成后 refreshStats 会再触发一次。
  refreshContinue(): void {
    const ctx = this.ctx;
    if (ctx === null || this.sites.length === 0) { return; }
    UserDataRepo.recentVisits(ctx, 10).then((visits: VisitDO[]) => {
      for (const v of visits) {
        const parts: string[] = v.targetKey.split(':');
        if (parts[0] !== 'site') { continue; }
        for (const s of this.sites) {
          if (s.id !== parts[1]) { continue; }
          this.contId = s.id;
          this.contName = s.name;
          this.contMeta = `${eraName(s.era)} · ${cityName(s.city)}`;
          return;
        }
      }
      this.contId = '';
      this.contName = '';
      this.contMeta = '';
    }).catch((_e: Object) => {
      this.contId = '';
    });
  }

  // 拉取已读段落集合（targetKey|section）
  refreshProgress(): void {
    const ctx = this.ctx;
    if (ctx === null) { return; }
    UserDataRepo.allProgress(ctx).then((rows: ProgressDO[]) => {
      const keys: Set<string> = new Set();
      for (const p of rows) {
        if (p.done) { keys.add(`${p.targetKey}|${p.section}`); }
      }
      this.readKeys = keys;
      this.refreshStats();
    });
  }

  siteReadDone(siteId: string): boolean {
    for (const sec of SECTIONS) {
      if (!this.readKeys.has(`site:${siteId}|${sec}`)) { return false; }
    }
    return true;
  }

  refreshStats(): void {
    const arr: EraStat[] = [];
    // 双轴计数（A 方案）：遗址数与文物数同源算出，六个年代的数字
    // 一律走 buildEraRelicStats，不在页面里各算一遍——否则两处口径
    // 迟早漂移（文物的年代是器物自己的年代，不是遗址的年代）。
    const dual = buildEraRelicStats(this.sites, ERAS);
    for (const e of ERAS) {
      const st = new EraStat();
      st.era = e;
      let done = 0;
      for (const s of this.sites) {
        if (s.era === e) {
          st.count++;
          if (this.siteReadDone(s.id)) { done++; }
        }
      }
      st.done = done;
      const d = dual.find((x: EraRelicStat): boolean => x.era === e);
      st.relics = d !== undefined ? d.relicCount : 0;
      arr.push(st);
    }
    this.stats = arr;
    this.refreshDaily();
    this.refreshContinue();
  }

  failedHint(): string {
    if (this.failedNames.length === 0) {
      return `有 ${this.failedCount} 份内容未加载`;
    }
    return `有 ${this.failedCount} 份内容未加载（${this.failedNames.join('、')}）`;
  }

  subtitleOf(era: string): string {
    const s = ERA_SUBTITLES.get(era);
    return s !== undefined ? s : '';
  }

  dailyPhoto(): string {
    return this.daily !== null ? firstRealImage(this.daily.images) : '';
  }

  dailyMaterial(): string {
    return this.daily !== null ? this.daily.material : '';
  }

  // 今日一物的副标题（清单 B2）：这里的年代是**器物**的年代，不是遗址的年代。
  // 巩义窑址（宋）出的唐三彩马俑（汉唐）在旧写法下会同屏出现「汉唐 · 巩义窑址」
  // 与「巩义窑址 · 宋 · 郑州」两行，读作年代自相矛盾。
  // 加「器物」二字把主语钉死，两行各指其物、不再打架。
  dailyMeta(): string {
    if (this.daily === null) { return ''; }
    return `${eraName(this.daily.era)}器物 · ${this.daily.siteName}`;
  }

  openDaily(): void {
    if (this.daily === null) { return; }
    const prm: Record<string, string> = {
      'site': this.daily.siteId,
      'relic': this.daily.id
    };
    router.pushUrl({ url: 'pages/RelicPage', params: prm });
  }

  openContinue(): void {
    if (this.contId === '') { return; }
    const prm: Record<string, string> = { 'id': this.contId };
    router.pushUrl({ url: 'pages/DetailPage', params: prm });
  }

  @Builder
  dailyCard() {
    Row({ space: 12 }) {
      if (this.dailyPhoto() !== '') {
        Image($rawfile(this.dailyPhoto()))
          .width(72)
          .height(72)
          .objectFit(ImageFit.Cover)
          .borderRadius(RADIUS_CARD_LG)
          .draggable(false)
      } else {
        // 无实拍占位：线稿 SVG 的描边是浅色（#F5EFE2，为层色深底设计），
        // 底必须用年代层色——铺浅灰会把线稿吞掉（实机走查：空灰块）。
        // 与展签剪影格（AccessionPlate）同一制式。
        Column() {
          Image($rawfile(relicIconSrc(this.dailyMaterial())))
            .width(44)
            .height(44)
            .objectFit(ImageFit.Contain)
            .draggable(false)
        }
        .width(72)
        .height(72)
        .backgroundColor(this.daily !== null ? eraColor(this.daily.era) : SURFACE_RAISED)
        .borderRadius(RADIUS_CARD_LG)
        .justifyContent(FlexAlign.Center)
      }
      Column({ space: 4 }) {
        Text('今日一物')
          .fontSize(FS_CAPTION)
          .fontColor(ACCENT)
          .letterSpacing(1)
        Text(this.daily !== null ? this.daily.name : '')
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.dailyMeta())
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SERIF)
          .fontColor(SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(FS_TITLE)
        .fontColor(SUB)
    }
    .width('100%')
    .padding(CARD_PAD)
    .backgroundColor(SURFACE_CARD)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(RADIUS_CARD_LG)
    .onClick(() => {
      this.openDaily();
    })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.entryPressed = 'daily';
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.entryPressed = '';
      }
    })
    .opacity(this.entryPressed === 'daily' ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`今日一物，${this.daily !== null ? this.daily.name : ''}，${this.dailyMeta()}`)
    .margin({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 12 })
  }

  @Builder
  continueCard() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text('继续研读')
          .fontSize(FS_CAPTION)
          .fontColor(ACCENT)
          .letterSpacing(1)
        Text(this.contName)
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`上次看到 · ${this.contMeta}`)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SERIF)
          .fontColor(SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(FS_TITLE)
        .fontColor(SUB)
    }
    .width('100%')
    .padding(CARD_PAD)
    .backgroundColor(SURFACE_CARD)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(RADIUS_CARD_LG)
    .onClick(() => {
      this.openContinue();
    })
    .onTouch((ev: TouchEvent) => {
      if (ev.type === TouchType.Down) {
        this.entryPressed = 'continue';
      } else if (ev.type === TouchType.Up || ev.type === TouchType.Cancel) {
        this.entryPressed = '';
      }
    })
    .opacity(this.entryPressed === 'continue' ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`继续研读，${this.contName}，${this.contMeta}`)
    .margin({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 12 })
  }

  build() {
    Column() {
      // ── 页头：品牌头（印章 + 标题 + 搜索）与同步状态条。
      // 不做「遗址 ⇄ 文物」并列分段：双实体改由年代卡的双轴计数承担
      // （每张卡并列显示「N 处遗址 · M 件文物」，两个数字各自可点落到
      // 对应实体）。理由见 service/content/EraRelicCount.ets 头注与
      // docs/narrative-coherence.md 的 P0-1 处置。
      // 另：品牌头与同步条必须写在内容分支之外——曾写在遗址分支里，
      // 切视图时整块消失像换了个 App（修复计划 §7.8 V2）。
      // 现在顺序固定：页头 → 同步条 → 分段 → 分支内容，两视图页头逐像素一致。
      Row({ space: 12 }) {
        HuangheSeal({ sealBox: SEAL_SIZE })
        Column({ space: 4 }) {
          Text('黄河记忆')
            .fontSize(FS_LOCKUP)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
            .letterSpacing(3)
            .lineHeight(LH_LOCKUP)
          Text('从地表到展柜，四千年一层一层看清楚')
            .fontSize(FS_META)
            .fontFamily(FONT_SERIF)
            .fontColor(SUB)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        // 全局搜索入口：遗址 / 文物 / 笔记同框，别让用户先猜去哪一页。
        PressFade() {
          Text('搜索')
            .fontSize(FS_CAPTION)
            .fontColor(SUB)
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .accessibilityText('全局搜索')
            .onClick(() => {
              router.pushUrl({ url: 'pages/SearchPage' });
            })
            .focusable(true)
            .focusBox(focusRing())
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 4 })

      // 全局同步状态：不是装饰，是赛题「恢复后自动同步」的唯一可见证据。
      SyncStatusBar()

      Scroll() {
        Column() {
          // 语料错误/部分失败：以前只打日志，首页看起来就是「空的」。
          // 现在至少说清楚是加载失败、坏了几份，并给一个真的重试。
          if (this.loading) {
            Text('正在整编语料…')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .width('100%')
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 8, bottom: 8 })
          } else if (this.loadError !== '') {
            Column({ space: 8 }) {
              Text('内容加载失败')
                .fontSize(FS_ITEM)
                .fontFamily(FONT_DISPLAY)
                .fontWeight(WT_DISPLAY)
                .fontColor(INK)
              Text(this.loadError)
                .fontSize(FS_CAPTION)
                .fontFamily(FONT_SERIF)
                .fontColor(SUB)
              PressFade() {
                Text('重试')
                  .fontSize(FS_CAPTION)
                  .fontColor(SURFACE_CARD)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(ACCENT)
                  .borderRadius(CHIP_RADIUS)
                  .onClick(() => {
                    this.loadCorpus(true);
                  })
                  .focusable(true)
                  .focusBox(focusRing())
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 12 })
            .backgroundColor(SURFACE_CARD)
            .border({ width: 1, color: LINE_HAIR })
            .borderRadius(RADIUS_CARD_LG)
            .margin({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 8 })
          } else if (this.failedCount > 0) {
            Text(this.failedHint())
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .width('100%')
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 4, bottom: 8 })
          }

          // 今日一物 + 继续研读：首页只保留这两张卡（既定的信息架构）。
          if (this.daily !== null) {
            this.dailyCard()
          }
          if (this.contId !== '') {
            this.continueCard()
          }

          // 年代 chips：紧凑的一行入口。位置贴着下面的六张年代卡——
          // 原先夹在「继续研读」与「文物图录」之间，离它对应的内容隔了两张卡，
          // 读作一团没有归属的浮层。
          // chips 是「跳走」的入口不是本页筛选器（点了就 pushUrl），
          // 所以不给选中态：有选中态就等于宣称「本页被这个年代过滤了」，
          // 而下面的六张卡其实一直是全量。
          Column({ space: 8 }) {
            Text('按年代进入')
              .fontSize(FS_CAPTION)
              .letterSpacing(2)
              .fontColor(SUB)
              .width('100%')
            Row({ space: 4 }) {
              ForEach(ERAS, (e: string) => {
                PressScale() {
                  Row({ space: 6 }) {
                    Row()
                      .width(8)
                      .height(8)
                      .borderRadius(4)
                      .backgroundColor(eraColor(e))
                    Text(eraName(e))
                      .fontSize(FS_META)
                      // chips 只有 13pt：展示体的「宋」在这个字号下宀/木糊成
                      // 「市」（真机实测），小字按 §3.5 落系统黑体。
                      .fontFamily(FONT_SANS)
                      .fontWeight(WT_REGULAR)
                      .fontColor(BODY)
                  }
                  .height(CHIP_H)
                  .padding({ left: 12, right: 12 })
                  .backgroundColor(SURFACE_CARD)
                  .border({ width: HAIR, color: LINE_HAIR })
                  .borderRadius(CHIP_RADIUS)
                  .onClick(() => {
                    const prm: Record<string, string> = { 'era': e };
                    router.pushUrl({ url: 'pages/ListPage', params: prm });
                  })
                  .focusable(true)
                  .focusBox(focusRing())
                  .accessibilityText(`进入${eraName(e)}层列表`)
                  .accessibilityLevel('yes')
                }
              }, (e: string) => e)
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 4, bottom: 12 })

          // 六张年代卡：StrataSpineCard 完全体
          Column({ space: BLOCK_GAP }) {
            ForEach(this.stats, (st: EraStat) => {
              StrataSpineCard({
                era: st.era,
                layerCode: `L${ERAS.indexOf(st.era) + 1}`,
                title: `${eraName(st.era)}·${this.siteNameOf(st.era)}`,
                subtitle: this.subtitleOf(st.era),
                coverImage: eraCoverImage(st.era),
                done: st.done,
                total: st.count,
                relicCount: st.relics,
                onTap: () => {
                  const prm: Record<string, string> = { 'era': st.era };
                  router.pushUrl({ url: 'pages/ListPage', params: prm });
                }
              })
            }, (st: EraStat) => `${st.era}_${st.count}_${st.done}_${st.relics}`)
          }
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })

          // 回纹收尾：三个 16vp 回纹 + 两侧发丝（设计稿①制式）
          HuiwenDivider({ bandH: 20 })
        }
        .align(Alignment.Top)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // 底部导航：全站唯一一套（AppNavBar）。首页恒为「年代」= 0；
      // 之前用 navIdx 状态但从未更新，留着只会误导后续维护。
      AppNavBar({ active: 0 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }

  // 年代代表遗址名：取该年代第一处，供卡片标题「仰韶·半坡遗址」制式
  siteNameOf(era: string): string {
    for (const s of this.sites) {
      if (s.era === era) { return s.name; }
    }
    return '';
  }
}
