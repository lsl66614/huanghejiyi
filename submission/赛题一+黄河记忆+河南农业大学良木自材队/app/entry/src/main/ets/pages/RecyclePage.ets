// entry/src/main/ets/pages/RecyclePage.ets —— 最近删除（30 天回收站）
//
// 为什么只做「恢复」不做「彻底删除」：
// 本项目的删除是软删（isDeleted=1 + 新 updateTime/deviceId），墓碑行还要
// 参与 LWW 合并——物理删除会让对端把「删除」读成「从未存在」，下一次
// 同步又把旧行推回来。回收站因此只读墓碑、只翻回 0，不碰 DELETE。
//
// 30 天窗口在查询里（updateTime >= since），页面不自己过滤：
// 两处各写一个阈值，迟早会出现「列表里没有、却还能恢复」的幽灵条目。
import { common } from '@kit.AbilityKit';

import type { FavoriteDO, NoteView } from '../model/UserDataModels';
import type { SiteInfo } from '../model/ContentModels';
import { ContentRepo } from '../repository/ContentRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import { BackLink } from '../common/BackLink';
import { THEME_BG } from '../common/EraTheme';
import {
  ACCENT, BODY, CHIP_RADIUS, FONT_DISPLAY, FONT_SERIF, FS_BODY, FS_CAPTION,
  FS_ITEM, FS_PAGE, HAIR, INK, LH_BODY, LH_CAPTION, LINE_HAIR, PAGE_PAD_X,
  ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SURFACE_CARD, SURFACE_RAISED, SUB, WT_DISPLAY
} from '../common/DesignTokens';
import { stamp } from '../common/Time';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut } from '../common/Motion';
import { PressFade } from '../common/PressScale';
import { itemLabel } from '../service/content/ItemTarget';

const KIND_FAV: string = 'fav';
const KIND_NOTE: string = 'note';
const KEEP_DAYS: number = 30;
const DAY_MS: number = 24 * 60 * 60 * 1000;
// 列表摘要的截断长度：两行正文约 40 字，超出用省略号，避免一条笔记
// 把整屏撑满、把后面待恢复的条目挤出视口。
const EXCERPT_MAX: number = 40;

function sectionLabel(sec: string): string {
  if (sec === 'intro') { return '介绍'; }
  if (sec === 'arch') { return '考古'; }
  if (sec === 'events') { return '历史'; }
  if (sec === 'poems') { return '诗词'; }
  if (sec === 'tourism') { return '文旅'; }
  return sec;
}

// target_key → 可读标题。语料加载失败时退化为原始 key，不把列表留白。
class RecycleIndex {
  private siteNames: Map<string, string> = new Map();
  private relicNames: Map<string, string> = new Map();

  build(sites: SiteInfo[]): void {
    for (const s of sites) {
      this.siteNames.set(s.id, s.name);
      for (const r of s.relics) {
        this.relicNames.set(r.id, r.name);
      }
    }
  }

  label(key: string): string {
    if (key === 'notebook:inbox') { return '随手笔记'; }
    const parts: string[] = key.split(':');
    if (parts[0] === 'site') {
      const raw = this.siteNames.get(parts[1]);
      const site = raw === undefined ? parts[1] : raw;
      const item: string = itemLabel(key, site);
      if (item !== '') { return item; }
      if (parts.length >= 3 && parts[2] !== '') {
        return `${site} · ${sectionLabel(parts[2])}`;
      }
      return site;
    }
    if (parts[0] === 'relic') {
      const raw = this.relicNames.get(parts[1]);
      return raw === undefined ? parts[1] : raw;
    }
    return key;
  }
}

class RecycleItem {
  kind: string = '';
  key: string = '';        // 收藏 = targetKey；笔记 = noteId
  title: string = '';
  meta: string = '';
  excerpt: string = '';    // 仅笔记有
}

@Entry
@Component
struct RecyclePage {
  @State items: RecycleItem[] = [];
  @State loading: boolean = true;
  @State failed: boolean = false;
  @State hint: string = '';
  @State busy: string = '';

  private favs: FavoriteDO[] = [];
  private notes: NoteView[] = [];
  private index: RecycleIndex = new RecycleIndex();

  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }

  aboutToAppear(): void {
    this.load();
  }

  private ctx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private load(): void {
    const ctx = this.ctx();
    this.loading = true;
    this.failed = false;
    // 语料只影响标题可读性：读不到就用原始 key，回收站仍要能打开。
    // 两条链不串行——笔记/收藏列表不该等整份语料解析完才出现。
    ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
      this.index.build(sites);
      if (!this.loading) { this.rebuild(); }
    }).catch((_e: Object) => {
      this.index = new RecycleIndex();
    });
    const since = Date.now() - KEEP_DAYS * DAY_MS;
    UserDataRepo.deletedFavorites(ctx, since).then((favs: FavoriteDO[]) => {
      this.favs = favs;
      UserDataRepo.deletedNotes(ctx, since).then((notes: NoteView[]) => {
        this.notes = notes;
        this.rebuild();
        this.loading = false;
      }).catch((_e: Object) => {
        this.failed = true;
        this.loading = false;
      });
    }).catch((_e: Object) => {
      this.failed = true;
      this.loading = false;
    });
  }

  // 摘要压成一行：笔记正文里的换行会让行高在列表里忽高忽低。
  private excerptOf(text: string): string {
    const flat = text.replace(/\s+/g, ' ').trim();
    if (flat.length <= EXCERPT_MAX) { return flat; }
    return `${flat.substring(0, EXCERPT_MAX)}…`;
  }

  private rebuild(): void {
    const out: RecycleItem[] = [];
    for (const f of this.favs) {
      const it = new RecycleItem();
      it.kind = KIND_FAV;
      it.key = f.targetKey;
      it.title = this.index.label(f.targetKey);
      it.meta = `删于 ${stamp(f.updateTime)}`;
      out.push(it);
    }
    for (const n of this.notes) {
      const it = new RecycleItem();
      it.kind = KIND_NOTE;
      it.key = n.noteId;
      it.title = this.index.label(n.targetKey);
      it.meta = `删于 ${stamp(n.updateTime)}`;
      it.excerpt = this.excerptOf(n.text);
      out.push(it);
    }
    this.items = out;
  }

  private countOf(kind: string): number {
    let n = 0;
    for (const it of this.items) {
      if (it.kind === kind) { n++; }
    }
    return n;
  }

  private itemsOf(kind: string): RecycleItem[] {
    return this.items.filter((it: RecycleItem): boolean => it.kind === kind);
  }

  private restore(it: RecycleItem): void {
    if (this.busy !== '') { return; }
    this.busy = it.key;
    const ctx = this.ctx();
    const job: Promise<void> = it.kind === KIND_FAV
      ? UserDataRepo.restoreFavorite(ctx, it.key)
      : UserDataRepo.restoreNote(ctx, it.key);
    job.then(() => {
      // 只从本页的墓碑数组里摘掉；库里仍是同一行，只是 isDeleted 翻回 0。
      // 不重新全量查询：那会把 loading 打回 true，列表闪一下白屏。
      if (it.kind === KIND_FAV) {
        this.favs = this.favs.filter((f: FavoriteDO): boolean => f.targetKey !== it.key);
      } else {
        this.notes = this.notes.filter((n: NoteView): boolean => n.noteId !== it.key);
      }
      this.hint = `已恢复「${it.title}」，回到${it.kind === KIND_FAV ? '收藏' : '笔记'}。`;
      this.rebuild();
      this.busy = '';
    }).catch((_e: Object) => {
      this.hint = '恢复失败，本机存储暂不可用，请稍后再试。';
      this.busy = '';
    });
  }

  @Builder
  sectionHead(kind: string) {
    Row({ space: 8 }) {
      Text(kind === KIND_FAV ? '收藏' : '笔记')
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .letterSpacing(1)
        .fontColor(INK)
      Text(`${this.countOf(kind)}`)
        .fontSize(FS_CAPTION)
        .fontColor(SUB)
      Blank()
    }
    .width('100%')
    .padding({ top: 16, bottom: 4 })
  }

  @Builder
  itemRow(it: RecycleItem) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(it.title)
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(INK)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        PressFade() {
          Text(this.busy === it.key ? '恢复中' : '恢复')
            .fontSize(FS_CAPTION)
            .fontColor(this.busy === it.key ? SUB : SURFACE_CARD)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .backgroundColor(this.busy === it.key ? SURFACE_RAISED : ACCENT)
            .borderRadius(CHIP_RADIUS)
            .accessibilityText(`恢复${it.kind === KIND_FAV ? '收藏' : '笔记'}：${it.title}`)
            .onClick(() => {
              this.restore(it);
            })
            .focusable(true)
            .focusBox(focusRing())
        }
      }
      .width('100%')

      Text(it.meta)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .fontColor(SUB)
        .width('100%')

      if (it.excerpt !== '') {
        Text(it.excerpt)
          .fontSize(FS_BODY)
          .fontFamily(FONT_SERIF)
          .lineHeight(LH_BODY)
          .fontColor(BODY)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: HAIR }, color: LINE_HAIR })
  }

  @Builder
  emptyState() {
    Column({ space: 8 }) {
      Text('没有待恢复的内容')
        .fontSize(FS_ITEM)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(INK)
      Text('删除的收藏和笔记会在这里保留 30 天，随时可以放回去。超过 30 天后不再显示。')
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .lineHeight(LH_CAPTION)
        .fontColor(SUB)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ top: 40 })
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        BackLink()
        Blank()
        Text('最近删除')
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .letterSpacing(2)
          .fontColor(INK)
        Blank()
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 8 })

      Text('删掉的，还在这里')
        .fontSize(FS_PAGE)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(INK)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 8 })

      Text('收藏与笔记保留 30 天。恢复后会回到原来的列表，并同步到其他设备。')
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .lineHeight(LH_CAPTION)
        .fontColor(SUB)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 8 })

      if (this.hint !== '') {
        Text(this.hint)
          .fontSize(FS_CAPTION)
          .fontColor(ACCENT)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 8 })
      }

      Scroll() {
        Column() {
          if (this.loading) {
            Text('正在读取最近删除…')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .width('100%')
              .padding({ top: 40 })
          } else if (this.failed) {
            Column({ space: 8 }) {
              Text('最近删除读取失败')
                .fontSize(FS_ITEM)
                .fontFamily(FONT_DISPLAY)
                .fontWeight(WT_DISPLAY)
                .fontColor(INK)
              Text('本机存储暂时不可用。数据没有丢，稍后重试即可。')
                .fontSize(FS_CAPTION)
                .fontFamily(FONT_SERIF)
                .lineHeight(LH_CAPTION)
                .fontColor(SUB)
              PressFade() {
                Text('重试')
                  .fontSize(FS_CAPTION)
                  .fontColor(SURFACE_CARD)
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(ACCENT)
                  .borderRadius(CHIP_RADIUS)
                  .onClick(() => {
                    this.load();
                  })
                  .focusable(true)
                  .focusBox(focusRing())
              }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ top: 40 })
          } else if (this.items.length === 0) {
            this.emptyState()
          } else {
            if (this.countOf(KIND_FAV) > 0) {
              this.sectionHead(KIND_FAV)
              ForEach(this.itemsOf(KIND_FAV), (it: RecycleItem) => {
                this.itemRow(it)
              }, (it: RecycleItem) => `fav_${it.key}`)
            }
            if (this.countOf(KIND_NOTE) > 0) {
              this.sectionHead(KIND_NOTE)
              ForEach(this.itemsOf(KIND_NOTE), (it: RecycleItem) => {
                this.itemRow(it)
              }, (it: RecycleItem) => `note_${it.key}`)
            }
            Text('超过 30 天的条目不再显示。这里只做恢复，不会立刻清空数据。')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .lineHeight(LH_CAPTION)
              .fontColor(SUB)
              .width('100%')
              .padding({ top: 24 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 24 })
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
