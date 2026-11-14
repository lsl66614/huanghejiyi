// entry/src/main/ets/pages/ExportPage.ets —— 把我的档案带走
//
// 为什么要有这一页：
//   这个应用的所有用户数据都只在本机 RDB（或两台设备之间）里，删应用就没了。
//   「分布式个人档案」如果连自己的东西都拿不出来，说服力是有限的。导出是
//   最便宜的兜底：不加密、不联网、不依赖服务端，格式是最普通的文本。
//
// 为什么给两种格式而不是一种：
//   Markdown 是给人读的（贴进任何笔记软件都成型）；
//   JSON 是给机器留档的（字段全、顺序稳定，以后要导回来就靠它）。
//   两者内容同源——都来自同一个 buildArchive()，只是排版不同。
import { common } from '@kit.AbilityKit';

// 注意：NoteDO / FavoriteDO / ProgressDO 在下面要 new 出实例，
// 不能用 `import type`——那只引入类型，编译期会报
// "'NoteDO' cannot be used as a value because it was imported using 'import type'"。
import { FavoriteDO, FavoriteTagDO, NoteDO, NoteView, ProgressDO, TagDO } from '../model/UserDataModels';
import type { SiteInfo } from '../model/ContentModels';
import { ContentRepo } from '../repository/ContentRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import type { IDataRepository } from '../repository/IDataRepository';
import { saveTextFile, SaveResult, readTextFile, ReadResult } from '../repository/ArchiveExport';
import { TargetLabels } from '../service/content/TargetLabel';
import { buildGraph } from '../service/network/NetworkSource';
import {
  buildArchive, ExportArchive, exportFileName, exportJson, exportMarkdown,
  ExportGraph, ExportGraphEdge, ExportGraphNode, ExportTag, FORMAT_JSON, FORMAT_MD
} from '../service/export/ExportFormat';
import {
  ImportParseResult, PlannedFavorite, PlannedNote, PlannedProgress, PlannedTag,
  maxImportedTime, parseArchive, planFavoriteImports, planNoteImports,
  planProgressImports, planTagImports
} from '../service/import/ImportPlan';
import { BackLink } from '../common/BackLink';
import { THEME_BG } from '../common/EraTheme';
import {
  ACCENT, BODY, CAPSULE_H, FONT_DISPLAY, FONT_MONO, FONT_SERIF, FS_BODY, FS_CAPTION,
  FS_ITEM, FS_META, FS_PAGE, HAIR, INK, LH_CAPTION, LINE_HAIR, PAGE_PAD_X,
  PRESS_OPACITY, PRESS_SCALE, RADIUS_CARD_LG, ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SUB,
  SURFACE_CARD, SURFACE_RAISED, WT_DISPLAY
} from '../common/DesignTokens';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';

// 一键恢复的本机快照：与导出文件同源（同一个 archive 对象序列化），
// 只做"省掉选文件这一步"，跨设备迁移仍以导出的 JSON 文件为准。
const SNAPSHOT_KEY: string = 'lastArchiveJson';
const SNAPSHOT_META: string = 'lastArchiveMeta';

class FormatCard {
  format: string = '';
  title: string = '';
  suffix: string = '';
  desc: string = '';
}

const FORMATS: FormatCard[] = [
  {
    format: FORMAT_MD,
    title: 'Markdown',
    suffix: '.md',
    desc: '纯文本，笔记按条目分段，贴进任何笔记软件都能读'
  },
  {
    format: FORMAT_JSON,
    title: 'JSON',
    suffix: '.json',
    desc: '字段完整、顺序固定，适合留档，也方便以后导回来'
  }
];

// 计数必须走独立 @Component：@Builder 的参数按值拷贝，异步读回来的
// 条数不会让文本重绘（同步页 MetricCell、我的 StatCell 都踩过同一个坑）。
@Component
struct CountCell {
  @Prop label: string = '';
  @Prop value: string = '';
  build() {
    Column({ space: 4 }) {
      Text(this.label)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .fontColor(SUB)
      Text(this.value)
        .fontSize(FS_ITEM)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(INK)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }
}

@Entry
@Component
struct ExportPage {
  @State format: string = FORMAT_MD;
  @State noteCount: number = 0;
  @State favCount: number = 0;
  @State progCount: number = 0;
  @State deviceId: string = '';
  @State loading: boolean = true;
  @State failed: boolean = false;
  @State busy: boolean = false;
  @State hint: string = '';
  @State hintBad: boolean = false;
  @State pressedFmt: string = '';
  @State exportPressed: boolean = false;
  // 导入状态：importing 走与导出同一个 busy 语义（互斥、按钮防连点）
  @State importing: boolean = false;
  @State importPressed: boolean = false;
  @State restorePressed: boolean = false;
  @State importResult: string = '';
  @State importBad: boolean = false;

  private notes: NoteView[] = [];
  private favs: FavoriteDO[] = [];
  private favTags: FavoriteTagDO[] = [];
  private progress: ProgressDO[] = [];
  private tags: TagDO[] = [];
  private sites: SiteInfo[] = [];
  private labels: TargetLabels = new TargetLabels();
  // 导出/快照用的库句柄：必须与导出内容同一个库，否则快照会写到另一个库
  // （仿真身份切过之后 get() 返回哪份库会变，见 PITFALLS 77）。
  private repo: IDataRepository | null = null;
  // 一键恢复用：上次成功导出的档案原文，只存本机 meta，不进同步域
  // （这是"本机快照"，跨设备仍靠导出文件）。
  @State hasSnapshot: boolean = false;

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

  private async load(): Promise<void> {
    const ctx = this.ctx();
    this.loading = true;
    this.failed = false;
    try {
      // 语料只决定标题好不好看：读不到就退回原始 key，导出不该因为
      // 一份语料解析失败而整页不可用。
      try {
        const sites: SiteInfo[] = await ContentRepo.load(ctx);
        this.sites = sites;
        this.labels.build(sites);
      } catch (_e) {
        this.labels = new TargetLabels();
      }
      // 取数全程锁在同一个库句柄上：仿真身份切过之后 get() 会返回另一份库，
      // 若每步各取一次，导出内容与快照可能分家（PITFALLS 77）。
      this.repo = await UserDataRepo.get(ctx);
      const repo: IDataRepository = this.repo;
      this.notes = await UserDataRepo.allNotes(ctx);
      this.favs = await UserDataRepo.listFavoritesOf(ctx);
      this.favTags = await UserDataRepo.favoriteTagRows(ctx);
      this.progress = await UserDataRepo.allProgress(ctx);
      this.tags = await UserDataRepo.allTagRows(ctx);
      this.deviceId = await UserDataRepo.deviceIdOf(ctx);
      this.hasSnapshot = (await repo.getMeta(SNAPSHOT_KEY)) !== '';
      const a: ExportArchive = this.archive();
      this.noteCount = a.counts.notes;
      this.favCount = a.counts.favorites;
      this.progCount = a.counts.progress;
    } catch (_e) {
      this.failed = true;
    }
    this.loading = false;
  }

  // 导出前重算一次：停在页面上多写了几条笔记再回来，导出的应当是最新的。
  private archive(): ExportArchive {
    const tags: ExportTag[] = [];
    for (const t of this.tags) {
      const e = new ExportTag();
      e.name = t.name;
      e.isPreset = t.isPreset;
      e.updateTime = t.updateTime;
      e.deviceId = t.deviceId;
      tags.push(e);
    }
    const favKeys: string[] = this.favs.map((f: FavoriteDO): string => f.targetKey);
    const g = buildGraph(this.sites, favKeys, this.notes);
    const graph = new ExportGraph();
    for (const n of g.nodes) {
      const e = new ExportGraphNode();
      e.id = n.id; e.label = n.label; e.kind = n.kind;
      graph.nodes.push(e);
    }
    for (const e0 of g.edges) {
      const e = new ExportGraphEdge();
      e.a = e0.a; e.b = e0.b;
      graph.edges.push(e);
    }
    graph.stat = g.stat;
    return buildArchive(this.notes, this.favs, this.favTags, this.progress, this.labels,
      this.deviceId, Date.now(), tags, graph);
  }

  private totalCount(): number {
    return this.noteCount + this.favCount + this.progCount;
  }

  private archiveLabel(): string {
    if (this.deviceId === 'deviceA') { return '手机'; }
    if (this.deviceId === 'deviceB') { return '平板'; }
    return '本机档案';
  }

  private doExport(): void {
    if (this.busy || this.totalCount() === 0) { return; }
    this.busy = true;
    this.hint = '';
    this.hintBad = false;
    const ctx = this.ctx();
    const now: number = Date.now();
    const a: ExportArchive = this.archive();
    const isJson: boolean = this.format === FORMAT_JSON;
    const content: string = isJson ? exportJson(a) : exportMarkdown(a);
    const name: string = exportFileName(now, this.format);
    saveTextFile(ctx, name, `.${this.format}`, content).then((r: SaveResult) => {
      this.busy = false;
      if (r.cancelled) {
        this.hint = '已取消，没有写出文件。';
        return;
      }
      this.hintBad = !r.ok;
      this.hint = r.ok
        ? `${name} 已写入你选择的位置。`
        : r.message;
      if (r.ok && this.repo !== null) {
        // 无论导出的是 md 还是 json，快照都存 JSON（只有它能被导回）。
        const snapshot: string = exportJson(a);
        const meta: string = JSON.stringify({ name: name, at: now });
        const repo: IDataRepository = this.repo;
        repo.setMeta(SNAPSHOT_KEY, snapshot)
          .then(() => repo.setMeta(SNAPSHOT_META, meta))
          .then(() => { this.hasSnapshot = true; })
          .catch((_e: Object): void => { /* 快照写失败不影响导出本身 */ });
      }
    }).catch((_e: Object) => {
      this.busy = false;
      this.hintBad = true;
      this.hint = '导出失败，本机存储暂不可用，请稍后再试。';
    });
  }

  // 一键恢复：读本机留存的导出快照，走与「选文件导入」完全相同的落库链。
  // 快照只在本机 meta 里，不进同步域；跨设备迁移仍以导出的 JSON 文件为准。
  private async restoreSnapshot(): Promise<void> {
    if (this.busy || this.importing) { return; }
    let raw: string = '';
    try {
      // 用与导出数据同一个库句柄：不重新 get()，免得身份切换后落到另一份库。
      const repo: IDataRepository | null = this.repo;
      raw = repo === null ? '' : await repo.getMeta(SNAPSHOT_KEY);
    } catch (_e) {
      raw = '';
    }
    if (raw === '') {
      this.importBad = true;
      this.importResult = '本机没有可恢复的导出快照，请用「选择 JSON 档案导入」挑一份文件。';
      return;
    }
    await this.doImport(raw);
  }

  private pickFormat(f: string): void {
    if (this.busy) { return; }
    this.format = f;
    this.hint = '';
    this.hintBad = false;
  }

  // ---- 导回（导入）-------------------------------------------------------
  //
  // 与导出对称：格式是本应用自己导出的 JSON（IMPORT_SCHEMA），写入走 UserDataRepo
  // 的常规写入口。裁决在 service/import/ImportPlan（纯函数、有单测），这里只执行：
  // 取数 → 计划 → 逐条落库 → 吸收版本号高水位 → 报告。
  //
  // 版本号语义：导入记录保留导出时的 updateTime（见 ImportPlan 头注释），
  // 所以这里**不能**像常规写入那样先取 nextWriteTime 盖章；note_id 用
  // nextWriteTime 生成只是主键，不影响同步版本。
  private async doImport(rawOverride: string = ''): Promise<void> {
    if (this.busy || this.importing) { return; }
    this.importing = true;
    this.importResult = '';
    this.importBad = false;
    try {
      const ctx = this.ctx();
      let raw: string = rawOverride;
      if (raw === '') {
        const read: ReadResult = await readTextFile(ctx);
        if (read.cancelled) {
          this.importing = false;
          this.importResult = '已取消，没有读入文件。';
          return;
        }
        if (!read.ok) {
          this.importing = false;
          this.importBad = true;
          this.importResult = read.message;
          return;
        }
        raw = read.content;
      }
      const parsed: ImportParseResult = parseArchive(raw);
      if (!parsed.ok) {
        this.importing = false;
        this.importBad = true;
        this.importResult = parsed.error;
        return;
      }
      const repo: IDataRepository = this.repo !== null ? this.repo : await UserDataRepo.get(ctx);
      // 判重与 LWW 需要本机现状：笔记按正文判重；收藏要连墓碑一起看
      // （导出后删过的不复活）；进度逐行比版本号；标签按名字判重。
      const existingNotes: NoteView[] = await UserDataRepo.allNotes(ctx);
      const liveFavs: FavoriteDO[] = await UserDataRepo.listFavoritesOf(ctx);
      const tombFavs: FavoriteDO[] = await UserDataRepo.deletedFavorites(ctx, 0);
      const progressRows: ProgressDO[] = await UserDataRepo.allProgress(ctx);
      const tagRows: TagDO[] = await UserDataRepo.allTagRows(ctx);

      const notePlan = planNoteImports(parsed.notes, existingNotes, parsed.deviceId);
      const favPlan = planFavoriteImports(parsed.favorites, liveFavs, tombFavs, parsed.deviceId);
      const progPlan = planProgressImports(parsed.progress, progressRows, parsed.deviceId);
      const tagPlan = planTagImports(parsed.tags, tagRows.map((t: TagDO): string => t.name),
        parsed.deviceId);

      for (const p of notePlan.planned) {
        const now = await repo.nextWriteTime();
        const note = new NoteDO();
        note.noteId = `n${now.toString(36)}${Math.floor(Math.random() * 1e4).toString(36)}`;
        note.targetKey = p.targetKey;
        note.text = p.text;
        note.createTime = p.createTime;
        note.updateTime = p.updateTime; // 同步版本 = 导出版本，不重新盖章
        note.deviceId = p.deviceId;
        note.isDeleted = false;
        await repo.upsertNote(note);
        if (p.tags.length > 0) {
          await repo.setNoteTags(note.noteId, p.tags, p.updateTime, p.deviceId);
        }
      }
      for (const f of favPlan.planned) {
        const fav = new FavoriteDO();
        fav.targetKey = f.targetKey;
        fav.createTime = f.createTime;
        fav.updateTime = f.createTime; // 收藏行的最后编辑就是收藏本身
        fav.deviceId = f.deviceId;
        fav.isDeleted = false;
        await repo.upsertFavorite(fav);
        if (f.tags.length > 0) {
          await repo.setFavoriteTags(f.targetKey, f.tags, f.createTime, f.deviceId);
        }
      }
      for (const p of progPlan.planned) {
        const prog = new ProgressDO();
        prog.targetKey = p.targetKey;
        prog.section = p.section;
        prog.done = true;
        prog.updateTime = p.updateTime;
        prog.deviceId = p.deviceId;
        await repo.upsertProgress(prog);
      }
      for (const p of tagPlan.planned) {
        const tag = new TagDO();
        tag.tagId = p.name;
        tag.name = p.name;
        tag.isPreset = p.isPreset;
        tag.updateTime = p.updateTime; // 保留导出版本号，不重新盖章
        tag.deviceId = p.deviceId;
        tag.isDeleted = false;
        await repo.upsertTag(tag);
      }

      // 高水位吸收：导入版本可能大于本机时钟（导出设备时钟更快）。
      // 放在所有写入之后、报告之前，失败不算导入失败（下次写入的
      // nextWriteTime 仍会按墙钟取值，最坏退回 LWW 平局裁决）。
      const hi = maxImportedTime(parsed, 0);
      if (hi > 0) {
        await repo.observeExternalTime(hi);
      }
      this.importResult = this.importReport(notePlan.skipped + notePlan.planned.length,
        favPlan.skipped + favPlan.planned.length, progPlan.skipped + progPlan.planned.length,
        notePlan.planned.length, favPlan.planned.length, progPlan.planned.length,
        tagPlan.planned.length, parsed.graph.nodes.length);
    } catch (_e) {
      this.importBad = true;
      this.importResult = '导入失败，请稍后再试。';
    }
    this.importing = false;
  }

  private importReport(noteTotal: number, favTotal: number, progTotal: number,
    noteNew: number, favNew: number, progNew: number,
    tagNew: number = 0, graphNodes: number = 0): string {
    const parts: string[] = [];
    if (noteNew > 0) { parts.push(`笔记 ${noteNew} 条`); }
    if (favNew > 0) { parts.push(`收藏 ${favNew} 个`); }
    if (progNew > 0) { parts.push(`已读进度 ${progNew} 段`); }
    if (tagNew > 0) { parts.push(`自建标签 ${tagNew} 个`); }
    if (parts.length === 0) {
      return `档案已核对：笔记 ${noteTotal} 条、收藏 ${favTotal} 个、进度 ${progTotal} 段在本机都已存在，没有写入重复内容。`;
    }
    const skipped: string[] = [];
    const skipN = noteTotal - noteNew;
    const skipF = favTotal - favNew;
    const skipP = progTotal - progNew;
    if (skipN > 0) { skipped.push(`笔记 ${skipN} 条重复`); }
    if (skipF > 0) { skipped.push(`收藏 ${skipF} 个已存在或已删除`); }
    if (skipP > 0) { skipped.push(`进度 ${skipP} 段较旧`); }
    let s = `已导入${parts.join('、')}。`;
    if (skipped.length > 0) { s += `另有${skipped.join('、')}，未覆盖本机内容。`; }
    // 图谱是从收藏/笔记/标签派生的，不需要逐节点写库；档案里带的是结构快照，
    // 写清楚"随基础数据重建"，免得用户以为漏了一块没恢复。
    if (graphNodes > 0) { s += ` 知识图谱 ${graphNodes} 节点随上述数据重建。`; }
    return s;
  }

  private selectedTitle(): string {
    return this.format === FORMAT_JSON ? 'JSON' : 'Markdown';
  }

  @Builder
  formatCard(c: FormatCard) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(c.title)
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(this.format === c.format ? ACCENT : INK)
        Text(c.suffix)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_MONO)
          .fontColor(SUB)
        Blank()
        if (this.format === c.format) {
          Text('已选')
            .fontSize(FS_CAPTION)
            .fontColor(ACCENT)
        }
      }
      .width('100%')

      Text(c.desc)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .lineHeight(LH_CAPTION)
        .fontColor(SUB)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(SURFACE_CARD)
    .border({
      width: this.format === c.format ? 1.5 : HAIR,
      color: this.format === c.format ? ACCENT : LINE_HAIR
    })
    .borderRadius(RADIUS_CARD_LG)
    .margin({ bottom: 12 })
    .accessibilityText(`${c.title}，${c.desc}${this.format === c.format ? '，已选' : ''}`)
    .onClick(() => {
      this.pickFormat(c.format);
    })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressedFmt = c.format;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedFmt = '';
      }
    })
    .opacity(this.pressedFmt === c.format ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        BackLink()
        Blank()
        Text('导出档案')
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .letterSpacing(2)
          .fontColor(INK)
        Blank()
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 8 })

      Scroll() {
        Column() {
          Text('带走你写下的东西')
            .fontSize(FS_PAGE)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
            .width('100%')
          Text('导出的一个文件里，只有你的收藏、笔记和研读进度；预置的遗址与文物语料不在其中。')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .lineHeight(LH_CAPTION)
            .fontColor(SUB)
            .width('100%')
            .padding({ top: 8 })

          // 本次导出的范围：先让用户看到「有多少东西」，再让他选格式。
          Column({ space: 6 }) {
            Row({ space: 12 }) {
              CountCell({ label: '笔记', value: this.loading ? '—' : `${this.noteCount}` })
              CountCell({ label: '收藏', value: this.loading ? '—' : `${this.favCount}` })
              CountCell({ label: '已读', value: this.loading ? '—' : `${this.progCount}` })
            }
            .width('100%')
            Text(`当前档案：${this.archiveLabel()}${this.loading ? '' : ' · 不含最近删除里的条目'}`)
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(16)
          .backgroundColor(SURFACE_RAISED)
          .borderRadius(RADIUS_CARD_LG)
          .margin({ top: 16, bottom: 24 })

          Text('选择格式')
            .fontSize(FS_META)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
            .width('100%')
            .padding({ bottom: 8 })

          ForEach(FORMATS, (c: FormatCard) => {
            this.formatCard(c)
          }, (c: FormatCard) => c.format)

          if (this.loading) {
            Text('正在读取本机档案…')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .fontColor(SUB)
              .width('100%')
              .padding({ top: 4, bottom: 8 })
          } else if (this.failed) {
            Text('读取失败，无法确定导出内容。请返回后重试。')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .lineHeight(LH_CAPTION)
              .fontColor(SUB)
              .width('100%')
              .padding({ top: 4, bottom: 8 })
          } else if (this.totalCount() === 0) {
            Text('这台设备上还没有可导出的内容。写一条笔记或收藏一处遗址后再来。')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .lineHeight(LH_CAPTION)
              .fontColor(SUB)
              .width('100%')
              .padding({ top: 4, bottom: 8 })
          }

          // 不可导出时走「抬升底 + 次级文字」：与最近删除的「恢复中」同一套，
          // 不另造一个白字压中灰的组合。
          Button(this.busy ? '正在写出…' : `导出为 ${this.selectedTitle()}`)
            .fontSize(FS_BODY)
            .fontColor(this.totalCount() === 0 || this.busy ? SUB : SURFACE_CARD)
            .backgroundColor(this.totalCount() === 0 || this.busy ? SURFACE_RAISED : ACCENT)
            .borderRadius(RADIUS_CARD_LG)
            .height(CAPSULE_H)
            .width('100%')
            // 清单 §3.4：不用 .enabled(false)——系统禁用外观会盖掉下面的自绘禁用色。
            // 禁用条件在 onClick 里判，外观由上面的 fontColor/backgroundColor 表达。
            .accessibilityText(this.totalCount() > 0 && !this.busy && !this.loading && !this.failed
              ? `导出为 ${this.selectedTitle()}` : '导出，当前不可用')
            .focusBox(focusRing())
            .onClick(() => {
              if (this.totalCount() === 0 || this.busy || this.loading || this.failed) { return; }
              this.doExport();
            })
            .onTouch((e: TouchEvent) => {
              if (e.type === TouchType.Down) {
                this.exportPressed = true;
              } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                this.exportPressed = false;
              }
            })
            .scale({ x: this.exportPressed ? PRESS_SCALE : 1, y: this.exportPressed ? PRESS_SCALE : 1 })
            .animation(pressAnim())

          if (this.hint !== '') {
            Text(this.hint)
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .lineHeight(LH_CAPTION)
              .fontColor(this.hintBad ? ACCENT : BODY)
              .width('100%')
              .padding({ top: 12 })
          }

          // 导回区：与导出同页，因为「带走」和「放回来」用的是同一个文件。
          // 放在导出流程之后——先看到这份档案是什么，再决定要不要读回来。
          //
          // 「回」不能进展示体：ZCOOLXiaoWei-Sub 里 U+56DE 的三条轮廓绕向全为负，
          // 非零填充把内白填死，屏上是一个纯黑方块（2026-11-06 模拟器实测）。
          // 字体是 OFL 且有 Reserved Font Name，不重制二进制，改写文案绕开这个字。
          Column({ space: 6 }) {
            Text('把带走的档案放进来')
              .fontSize(FS_META)
              .fontFamily(FONT_DISPLAY)
              .fontWeight(WT_DISPLAY)
              .fontColor(INK)
              .width('100%')
              .padding({ top: 24 })
            Text('选择之前导出的 JSON 档案，笔记、收藏与已读进度会合回本机；与同步的合并规则一致，不会覆盖本机更新的内容。')
              .fontSize(FS_CAPTION)
              .fontFamily(FONT_SERIF)
              .lineHeight(LH_CAPTION)
              .fontColor(SUB)
              .width('100%')
            Button(this.importing ? '正在导入…' : '选择 JSON 档案导入')
              .fontSize(FS_BODY)
              .fontColor(this.importing ? SUB : THEME_BG)
              .backgroundColor(this.importing ? SURFACE_RAISED : INK)
              .borderRadius(RADIUS_CARD_LG)
              .height(CAPSULE_H)
              .width('100%')
              .accessibilityText(this.importing || this.busy
                ? '导入，当前不可用'
                : '选择之前导出的 JSON 档案文件，把笔记、收藏和研读进度合回本机')
              .focusBox(focusRing())
              .onClick(() => {
                // 清单 §3.4：禁用判在点击里，不用 .enabled(false)
                if (this.importing || this.busy) { return; }
                this.doImport();
              })
              .onTouch((e: TouchEvent) => {
                if (e.type === TouchType.Down) {
                  this.importPressed = true;
                } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                  this.importPressed = false;
                }
              })
              .scale({ x: this.importPressed ? PRESS_SCALE : 1, y: this.importPressed ? PRESS_SCALE : 1 })
              .animation(pressAnim())
            // 一键恢复：赛题创新拓展第 2 条要「完整迁移与一键恢复」。选文件是
            // 跨设备的正路，本机自己恢复不必再挑一次——导出成功后留的那份快照
            // 走的是同一条落库链（doImport 只是跳过 picker）。
            if (this.hasSnapshot) {
              Button(this.importing ? '正在导入…' : '一键恢复上次导出')
                .fontSize(FS_BODY)
                .fontColor(this.importing ? SUB : INK)
                .backgroundColor(this.importing ? SURFACE_RAISED : SURFACE_CARD)
                .border({ width: HAIR, color: LINE_HAIR })
                .borderRadius(RADIUS_CARD_LG)
                .height(CAPSULE_H)
                .width('100%')
                .margin({ top: 8 })
                .accessibilityText(this.importing || this.busy
                  ? '一键恢复上次导出，当前不可用'
                  : '一键恢复上次导出的档案，不用再去文件列表里挑')
                .focusBox(focusRing())
                .onClick(() => {
                  if (this.importing || this.busy) { return; }
                  this.restoreSnapshot();
                })
                .onTouch((e: TouchEvent) => {
                  if (e.type === TouchType.Down) {
                    this.restorePressed = true;
                  } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                    this.restorePressed = false;
                  }
                })
                .scale({ x: this.restorePressed ? PRESS_SCALE : 1, y: this.restorePressed ? PRESS_SCALE : 1 })
                .animation(pressAnim())
            }
            if (this.importResult !== '') {
              Text(this.importResult)
                .fontSize(FS_CAPTION)
                .fontFamily(FONT_SERIF)
                .lineHeight(LH_CAPTION)
                .fontColor(this.importBad ? ACCENT : BODY)
                .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          Text('这个文件不会上传到任何地方。要不要备份、备份到哪，由你在系统保存框里决定。')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .lineHeight(LH_CAPTION)
            .fontColor(SUB)
            .width('100%')
            .padding({ top: 24, bottom: 40 })        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 8 })
      }
      .scrollBar(BarState.Off)
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}
