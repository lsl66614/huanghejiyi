// entry/src/main/ets/pages/RecommendPage.ets —— 脉络推荐（P2：解释、冷启动、负反馈）
//
// 这一页的核心不是“排得准”，而是“说得清”。没有行为的用户先看到的是
// 一个选择器而不是一串陌生遗址；有行为的用户看到“因为你最近看过 X”；
// 每条结果最多两条理由，点开才看全部。理由不是装饰，是让用户能反驳：
// 看到“同城”才发现自己其实想换一座城，于是点“不感兴趣”。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { SiteInfo } from '../model/ContentModels';
import type { FavoriteDO, VisitDO, RecoFeedbackDO } from '../model/UserDataModels';
import { ContentRepo } from '../repository/ContentRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import type { RecoRow } from '../service/recommend/RecoSource';
import {
  recoRowsFor, globalRows, interestRows, parsePrefs, serializePrefs,
  InterestPrefs, RecoFilter
} from '../service/recommend/RecoSource';
import { BackLink } from '../common/BackLink';
import { eraColor, eraName, THEME_BG, THEME_INK } from '../common/EraTheme';
import { typeName } from '../common/Labels';
import {
  ACCENT, BODY, CHIP_RADIUS, FONT_DISPLAY, FONT_SERIF, FS_BODY, FS_CAPTION,
  FS_DISPLAY, FS_ITEM, FS_TITLE, HAIR, INK, LH_BODY, LH_CAPTION, LINE_HAIR, PAGE_PAD_X,
  PRESS_OPACITY, ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SUB, SURFACE_CARD,
  SURFACE_RAISED, WT_DISPLAY
} from '../common/DesignTokens';
import { focusRing } from '../common/Accessibility';
import { PressFade } from '../common/PressScale';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';

const DOMAIN = 0x0001;
const TAG = 'RecommendPage';

const FB_SEEN: string = 'seen';
const FB_DISLIKE: string = 'dislike';
const FB_ERA: string = 'era';
const FB_TYPE: string = 'type';

const ERAS: string[] = ['yangshao', 'longshan', 'xiashang', 'zhou', 'hantang', 'song'];
const TYPES: string[] = ['capital', 'burial', 'kiln', 'ancient_arch'];

// 反馈行存的是带前缀的 key，这里翻回筛选器。
// 单条与整类的区别只在“排掉一行”还是“排掉一组”，不做权重衰减——
// 本地语料只有 42 条，半衰期参数没有数据支撑，不如行为直接可预期。
function toFilter(list: RecoFeedbackDO[]): RecoFilter {
  const f = new RecoFilter();
  for (const fb of list) {
    const parts: string[] = fb.key.split(':');
    const id: string = parts.length > 1 ? parts[1] : '';
    if (id === '') { continue; }
    if (parts[0] === 'era') {
      if (!f.excludeEras.includes(id)) { f.excludeEras.push(id); }
    } else if (parts[0] === 'type') {
      if (!f.excludeTypes.includes(id)) { f.excludeTypes.push(id); }
    } else if (!f.excludeIds.includes(id)) {
      f.excludeIds.push(id);
    }
  }
  return f;
}

@Entry
@Component
struct RecommendPage {
  @State srcName: string = '';
  @State srcEra: string = '';
  @State rows: RecoRow[] = [];
  @State global: boolean = false;
  @State hasBehavior: boolean = true;
  @State fromInterest: boolean = false;
  @State coldStart: boolean = false;
  @State ready: boolean = false;
  @State failed: boolean = false;
  // 按下的推荐条目 id
  @State pressedRow: string = '';
  // 展开了全部理由的条目；'' = 都收着
  @State expandedRow: string = '';
  // 展开了“不感兴趣”二级原因的条目
  @State fbRow: string = '';
  @State pickedEras: string[] = [];
  @State pickedTypes: string[] = [];
  @State hint: string = '';

  private sites: SiteInfo[] = [];
  private favs: FavoriteDO[] = [];
  private visits: VisitDO[] = [];
  private prefs: InterestPrefs = new InterestPrefs();
  private filter: RecoFilter = new RecoFilter();

  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }

  aboutToAppear(): void {
    const p = router.getParams() as Record<string, string> | undefined;
    const fromId: string = p !== undefined && p['from'] !== undefined ? p['from'] : '';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 一次性把语料、行为、反馈、偏好取齐再算：少一个维度就会先渲染一版
    // 不带过滤的列表，再闪一下换成带过滤的。
    ContentRepo.load(ctx)
      .then((sites: SiteInfo[]): Promise<FavoriteDO[]> => {
        this.sites = sites;
        return UserDataRepo.listFavoritesOf(ctx);
      })
      .then((favs: FavoriteDO[]): Promise<VisitDO[]> => {
        this.favs = favs;
        return UserDataRepo.recentVisits(ctx, 20);
      })
      .then((visits: VisitDO[]): Promise<RecoFeedbackDO[]> => {
        this.visits = visits;
        return UserDataRepo.recoFeedback(ctx);
      })
      .then((fbs: RecoFeedbackDO[]): Promise<string> => {
        this.filter = toFilter(fbs);
        return UserDataRepo.readRecoPrefs(ctx);
      })
      .then((json: string) => {
        this.prefs = parsePrefs(json);
        this.apply(fromId);
        this.ready = true;
      })
      .catch((_e: Object) => {
        this.failed = true;
        this.ready = true;
      });
  }

  private apply(fromId: string): void {
    if (fromId !== '') {
      let found: SiteInfo | null = null;
      for (const s of this.sites) {
        if (s.id === fromId) { found = s; break; }
      }
      if (found !== null) {
        this.global = false;
        this.coldStart = false;
        this.srcName = found.name;
        this.srcEra = found.era;
        this.rows = recoRowsFor(found, this.sites, this.favs, 12, this.visits, this.filter);
        return;
      }
    }
    this.global = true;
    const g = globalRows(this.sites, this.favs, this.visits, 12, this.prefs, this.filter);
    this.hasBehavior = g.hasBehavior;
    this.fromInterest = g.fromInterest;
    this.srcName = g.seedName;
    this.srcEra = g.seedEra;
    // 无行为、无偏好：先让用户选，而不是拿语料首条冒充“为你推荐”。
    this.coldStart = !g.hasBehavior && !g.fromInterest;
    this.rows = this.coldStart ? [] : g.rows;
    if (this.coldStart) {
      this.pickedEras = this.prefs.eras.slice();
      this.pickedTypes = this.prefs.types.slice();
    }
  }

  private toggleEra(e: string): void {
    const out: string[] = this.pickedEras.slice();
    const i = out.indexOf(e);
    if (i >= 0) {
      out.splice(i, 1);
    } else if (out.length < 3) {
      out.push(e);
    } else {
      this.hint = '最多选 3 个年代。先取消一个再加。';
      return;
    }
    this.pickedEras = out;
    this.hint = '';
  }

  private toggleType(t: string): void {
    const out: string[] = this.pickedTypes.slice();
    const i = out.indexOf(t);
    if (i >= 0) {
      out.splice(i, 1);
    } else if (out.length < 2) {
      out.push(t);
    } else {
      this.hint = '最多选 2 个类型。先取消一个再加。';
      return;
    }
    this.pickedTypes = out;
    this.hint = '';
  }

  private confirmInterest(): void {
    if (this.pickedEras.length === 0 && this.pickedTypes.length === 0) {
      this.hint = '至少选一个年代或类型，推荐才有依据。';
      return;
    }
    const p = new InterestPrefs();
    p.eras = this.pickedEras.slice();
    p.types = this.pickedTypes.slice();
    this.prefs = p;
    this.coldStart = false;
    this.fromInterest = true;
    this.hasBehavior = false;
    this.srcEra = p.eras.length > 0 ? p.eras[0] : '';
    this.rows = interestRows(this.sites, p, 12, this.filter);
    this.hint = '';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    UserDataRepo.writeRecoPrefs(ctx, serializePrefs(p)).catch((_e: Object) => {
      // 偏好写失败只影响下次冷启动，不影响这一次的结果，不打断用户
      hilog.error(DOMAIN, TAG, 'recoPrefs save fail');
    });
  }

  private interestTitle(): string {
    const parts: string[] = [];
    for (const e of this.prefs.eras) { parts.push(eraName(e)); }
    for (const t of this.prefs.types) { parts.push(typeName(t)); }
    return parts.length === 0 ? '你选的兴趣' : parts.join(' · ');
  }

  private reopenInterest(): void {
    this.pickedEras = this.prefs.eras.slice();
    this.pickedTypes = this.prefs.types.slice();
    this.coldStart = true;
    this.hint = '';
  }

  private typeOf(row: RecoRow): string {
    return row.siteType;
  }

  private rerank(list: RecoRow[]): RecoRow[] {
    for (let i = 0; i < list.length; i++) {
      list[i].rank = i < 9 ? `0${i + 1}` : `${i + 1}`;
    }
    return list;
  }

  // 负反馈：先写库，再立刻从当前列表里摘掉。
  // 不重查全表——那会把整页打回 loading，用户点一下“不感兴趣”
  // 却看到满屏闪白，比不改还糟。
  private suppress(row: RecoRow, reason: string): void {
    let key: string = `site:${row.id}`;
    if (reason === FB_ERA) {
      key = `era:${row.era}`;
      if (!this.filter.excludeEras.includes(row.era)) { this.filter.excludeEras.push(row.era); }
    } else if (reason === FB_TYPE) {
      const t: string = this.typeOf(row);
      if (t === '') { return; }
      key = `type:${t}`;
      if (!this.filter.excludeTypes.includes(t)) { this.filter.excludeTypes.push(t); }
    } else if (!this.filter.excludeIds.includes(row.id)) {
      this.filter.excludeIds.push(row.id);
    }

    const kept: RecoRow[] = [];
    for (const r of this.rows) {
      let drop: boolean = r.id === row.id;
      if (reason === FB_ERA && r.era === row.era) { drop = true; }
      if (reason === FB_TYPE && this.typeOf(r) === this.typeOf(row)) { drop = true; }
      if (!drop) { kept.push(r); }
    }
    this.rows = this.rerank(kept);
    this.fbRow = '';
    this.expandedRow = '';
    if (this.rows.length === 0) {
      this.hint = '这条脉已经排空了。多看几处，再回来会有新的。';
    } else {
      this.hint = '已减少这类推荐，下次不会再出现。';
    }

    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    UserDataRepo.addRecoFeedback(ctx, key, reason).catch((_e: Object) => {
      hilog.error(DOMAIN, TAG, 'reco feedback save fail');
    });
  }

  private showReasons(row: RecoRow): string[] {
    if (this.expandedRow === row.id || row.reasons.length <= 2) { return row.reasons; }
    return row.reasons.slice(0, 2);
  }

  @Builder
  interestChip(label: string, on: boolean, key: string, isEra: boolean) {
    PressFade() {
      Text(label)
        .fontSize(FS_CAPTION)
        .fontColor(on ? SURFACE_CARD : INK)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(on ? ACCENT : SURFACE_RAISED)
        .border({ width: HAIR, color: on ? ACCENT : LINE_HAIR })
        .borderRadius(CHIP_RADIUS)
        .margin({ right: 8, bottom: 8 })
        .onClick(() => {
          if (isEra) {
            this.toggleEra(key);
          } else {
            this.toggleType(key);
          }
        })
        .focusable(true)
        .focusBox(focusRing())
        .accessibilityText(`${label}${on ? '，已选' : '，未选'}`)
    }
  }

  @Builder
  interestPicker() {
    Column({ space: 12 }) {
      Text('先选三个感兴趣的方向')
        .fontSize(FS_TITLE)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(THEME_INK)
      Text('还没有浏览记录。选 2–3 个年代，或 1–2 个类型，推荐会按你的选择起步；以后有足迹了会自动换成按足迹推荐。')
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .lineHeight(LH_CAPTION)
        .fontColor(SUB)

      Text('年代 · 最多 3 个')
        .fontSize(FS_CAPTION)
        .letterSpacing(1)
        .fontColor(SUB)
        .padding({ top: 8 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(ERAS, (e: string) => {
          this.interestChip(eraName(e), this.pickedEras.includes(e), e, true)
        }, (e: string) => `era_${e}`)
      }
      .width('100%')

      Text('类型 · 最多 2 个')
        .fontSize(FS_CAPTION)
        .letterSpacing(1)
        .fontColor(SUB)
        .padding({ top: 8 })
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(TYPES, (t: string) => {
          this.interestChip(typeName(t), this.pickedTypes.includes(t), t, false)
        }, (t: string) => `type_${t}`)
      }
      .width('100%')

      PressFade() {
        Text(this.pickedEras.length + this.pickedTypes.length === 0 ? '先选一项' : '看看推荐')
          .fontSize(FS_CAPTION)
          .fontColor(SURFACE_CARD)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor(this.pickedEras.length + this.pickedTypes.length === 0 ? SUB : ACCENT)
          .borderRadius(CHIP_RADIUS)
          .onClick(() => {
            this.confirmInterest();
          })
          .focusable(true)
          .focusBox(focusRing())
          .accessibilityText('按所选兴趣生成推荐')
          .margin({ top: 8 })
      }

      Text('只在本机计算，不上传任何偏好。')
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .fontColor(SUB)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 8, bottom: 24 })
  }

  @Builder
  fbChip(row: RecoRow, reason: string, label: string) {
    PressFade() {
      Text(label)
        .fontSize(FS_CAPTION)
        .fontColor(BODY)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(SURFACE_CARD)
        .border({ width: HAIR, color: LINE_HAIR })
        .borderRadius(CHIP_RADIUS)
        .margin({ right: 8, bottom: 8 })
        .onClick(() => {
          this.suppress(row, reason);
        })
        .focusable(true)
        .focusBox(focusRing())
        .accessibilityText(`${label}，减少这类推荐`)
    }
  }

  @Builder
  feedbackPanel(row: RecoRow) {
    Column({ space: 8 }) {
      Text('为什么不想看？选了会立刻减少这类结果。')
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .fontColor(SUB)
      Flex({ wrap: FlexWrap.Wrap }) {
        this.fbChip(row, FB_SEEN, '已经看过')
        this.fbChip(row, FB_DISLIKE, '不感兴趣')
        this.fbChip(row, FB_ERA, `少看${eraName(row.era)}`)
        this.fbChip(row, FB_TYPE, `少看${typeName(this.typeOf(row))}`)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ bottom: 8 })
  }

  @Builder
  recoItem(row: RecoRow) {
    Column({ space: 4 }) {
      Column({ space: 10 }) {
        Row({ space: 12 }) {
          Text(row.rank)
            .fontSize(FS_CAPTION)
            .fontColor(ACCENT)
          Text(row.name)
            .fontSize(FS_TITLE)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .letterSpacing(1)
            .fontColor(THEME_INK)
            .layoutWeight(1)
          // 清单 G3：不再上屏裸分数（如 0.75）。下面的层色进度条已经把
          // 「这条有多贴」表达成可读的相对长度，再给一个无量纲数字只是噪音。
        }
        .width('100%')

        Text(row.meta)
          .fontSize(FS_CAPTION)
          .letterSpacing(1)
          .fontColor(SUB)

        Row()
          .width(`${row.bar}%`)
          .height(3)
          .backgroundColor(eraColor(row.era))

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.showReasons(row), (rs: string) => {
            Text(rs)
              .fontSize(FS_CAPTION)
              .fontColor(THEME_INK)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(SURFACE_RAISED)
              .border({ width: HAIR, color: LINE_HAIR })
              .borderRadius(CHIP_RADIUS)
              .margin({ right: 8, bottom: 8 })
          }, (rs: string) => rs)
          if (row.reasons.length > 2) {
            PressFade() {
              Text(this.expandedRow === row.id ? '收起' : `展开 ${row.reasons.length} 条理由`)
                .fontSize(FS_CAPTION)
                .fontColor(ACCENT)
                .padding({ left: 4, right: 8, top: 4, bottom: 4 })
                .onClick(() => {
                  this.expandedRow = this.expandedRow === row.id ? '' : row.id;
                })
                .focusable(true)
                .focusBox(focusRing())
            }
          }
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .onClick(() => {
        // push 不是 replace：replace 会把推荐页自己替换掉，
        // 从详情返回时回不到推荐列表，栈序断裂。
        const prm: Record<string, string> = { 'id': row.id };
        router.pushUrl({ url: 'pages/DetailPage', params: prm });
      })
      .onTouch((e: TouchEvent) => {
        if (e.type === TouchType.Down) {
          this.pressedRow = row.id;
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.pressedRow = '';
        }
      })
      .opacity(this.pressedRow === row.id ? PRESS_OPACITY : 1)
      .animation(pressAnim())
      .focusable(true)
      .focusBox(focusRing())
      .accessibilityText(`${row.name}，${row.meta}`)
      .accessibilityTextHint(row.reasons.join('；'))

      // “不感兴趣”放在可点区域之外：点评分卡的点击是“进去看看”，
      // 点这四个字是“别给我看”，两个意图不能共用一个热区。
      Row() {
        PressFade() {
          Text(this.fbRow === row.id ? '算了' : '不感兴趣')
            .fontSize(FS_CAPTION)
            .fontColor(SUB)
            .padding({ top: 6, bottom: 6, right: 8 })
            .onClick(() => {
              this.fbRow = this.fbRow === row.id ? '' : row.id;
              this.expandedRow = '';
            })
            .focusable(true)
            .focusBox(focusRing())
            .accessibilityText(`对${row.name}不感兴趣，展开原因`)
        }
        Blank()
      }
      .width('100%')

      if (this.fbRow === row.id) {
        this.feedbackPanel(row)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 16, bottom: 8 })
    .border({ width: { bottom: HAIR }, color: LINE_HAIR })
  }

  @Builder
  seedHeader(label: string, title: string) {
    Row({ space: 12 }) {
      Row()
        .width(6)
        .height(64)
        .backgroundColor(eraColor(this.srcEra))
      Column({ space: 6 }) {
        Text(label)
          .fontSize(FS_CAPTION)
          .letterSpacing(3)
          .fontColor(SUB)
        Text(title)
          .fontSize(FS_DISPLAY)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .letterSpacing(1)
          .fontColor(THEME_INK)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 8, bottom: 24 })
  }

  @Builder
  emptyState() {
    Column({ space: 8 }) {
      Text(this.global ? '还没凑够可推荐的' : '这条还没有可对照的脉络')
        .fontSize(FS_ITEM)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(THEME_INK)
      Text(this.global
        ? '先多看几处遗址，或去图录里翻几件文物，推荐会更准。这里不硬凑条目。'
        : '这条遗址缺少可以对照的年代、类型与标签。换一条看看。')
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .lineHeight(LH_CAPTION)
        .fontColor(SUB)
      PressFade() {
        Text('去全部遗址')
          .fontSize(FS_CAPTION)
          .fontColor(SURFACE_CARD)
          .padding({ left: 16, right: 16, top: 10, bottom: 10 })
          .backgroundColor(ACCENT)
          .borderRadius(CHIP_RADIUS)
          .onClick(() => {
            // push：replace 会把推荐页吞掉，从遗址列表返回时断链。
            router.pushUrl({ url: 'pages/ListPage' });
          })
          .focusable(true)
          .focusBox(focusRing())
          .margin({ top: 8 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 32 })
  }

  build() {
    Column() {
      Row() {
        BackLink()
        Blank()
        Text('脉络')
          .fontSize(FS_CAPTION)
          .letterSpacing(3)
          .fontColor(SUB)
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 16 })

      Scroll() {
        Column() {
          if (!this.ready) {
            Text('正在整理推荐…')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .padding({ top: 40 })
          } else if (this.failed) {
            Text('语料读取失败，推荐暂时不可用。')
              .fontSize(FS_BODY)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .padding({ top: 40 })
          } else if (this.coldStart) {
            this.interestPicker()
          } else {
            if (this.global) {
              this.seedHeader(
                this.hasBehavior ? '因为你最近看过' :
                  (this.fromInterest ? '按你选的兴趣' : '尚无浏览足迹'),
                this.hasBehavior ? this.srcName :
                  (this.fromInterest ? this.interestTitle() : '先从这里起步'))
            } else {
              this.seedHeader('由这条出发的脉络', this.srcName === '' ? '…' : this.srcName)
            }

            Row() {
              // 清单 G3：不把评分的权重公式与裸分数搬上屏。
              // 「同年代 0.4 · 同类型 0.3」是工程内部语言，读者要的是"为什么推给我"。
              // 权重仍然存在、仍然可复算，只是留在代码与设计方案里。
              Text(this.fromInterest
                ? '按你选的年代与类型各取一批，同类同城各留 5 条'
                : '先看同年代与同类型，再看同城与相近标签，最近看过的会略微加权')
                .fontSize(FS_CAPTION)
                .letterSpacing(1)
                .fontColor(SUB)
                .layoutWeight(1)
              if (this.fromInterest) {
                PressFade() {
                  Text('重新选')
                    .fontSize(FS_CAPTION)
                    .fontColor(ACCENT)
                    .padding({ left: 8, top: 4, bottom: 4 })
                    .onClick(() => {
                      this.reopenInterest();
                    })
                    .focusable(true)
                    .focusBox(focusRing())
                }
              }
            }
            .width('100%')
            .margin({ bottom: 8 })

            if (this.hint !== '') {
              Text(this.hint)
                .fontSize(FS_CAPTION)
                .fontColor(ACCENT)
                .width('100%')
                .padding({ bottom: 8 })
            }

            ForEach(this.rows, (row: RecoRow) => {
              this.recoItem(row)
            }, (row: RecoRow) => row.id)

            if (this.rows.length === 0) {
              this.emptyState()
            } else {
              Text(this.global
                ? '按你的浏览、收藏与反馈在本机计算 · 不联网'
                : `这几条都是和${this.srcName}读到一起的 · 本地计算 · 不联网`)
                .fontSize(FS_CAPTION)
                .letterSpacing(1)
                .fontColor(SUB)
                .margin({ top: 24 })
            }
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 40 })
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
