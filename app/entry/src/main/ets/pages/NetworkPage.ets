// entry/src/main/ets/pages/NetworkPage.ets —— P9 主题网络图（力导向）
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { SiteInfo } from '../model/ContentModels';
import type { FavoriteDO } from '../model/UserDataModels';
import { ContentRepo } from '../repository/ContentRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import { buildGraph, ownerSiteOf, expansionSeed, unseenSiteIds,
  NetGraph, NetNode, NetRow } from '../service/network/NetworkSource';
import { forceLayout, ForceInput } from '../service/network/ForceLayout';
import { recoRowsFor, RecoRow } from '../service/recommend/RecoSource';
import { BackLink } from '../common/BackLink';
import { eraColor, eraText, THEME_BG, THEME_INK } from '../common/EraTheme';
import {
  ACCENT, CAPSULE_H, CAPSULE_RADIUS, CHIP_RADIUS, FONT_DISPLAY, FONT_SERIF, FS_BODY,
  FS_CAPTION, FS_DISPLAY, GRAPH_EDGE, GRAPH_ROOT, HAIR,
  LH_BODY, LH_CAPTION, LINE_HAIR, PAGE_PAD_X,
  PRESS_OPACITY, PRESS_SCALE, RADIUS_PILL, ROUTE_FADE_MIN,
  ROUTE_SHIFT_VP, SUB, SURFACE_CARD, SURFACE_RAISED, WT_BOLD,
  WT_DISPLAY, WT_SERIF
} from '../common/DesignTokens';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durBase, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';
import { PressFade } from '../common/PressScale';
import { switchToTab } from '../common/AppNavBar';

// 已放标签的包围盒两两相交即视为压字
function overlaps(placed: number[][], x: number, y: number, tw: number): boolean {
  const x0 = x - tw, x1 = x + tw, y0 = y - 11, y1 = y + 3;
  for (const q of placed) {
    if (x0 < q[2] && x1 > q[0] && y0 < q[3] && y1 > q[1]) { return true; }
  }
  return false;
}

@Entry
@Component
struct NetworkPage {
  @State graph: NetGraph = new NetGraph();
  // 拓展推荐：赛题创新拓展第 1 条「并推荐拓展内容」。种子取选中节点（没选就
  // 取连边最多的遗址），算法复用 RecoSource.recoRowsFor，再滤掉图上已有的。
  private sites: SiteInfo[] = [];
  private favs: FavoriteDO[] = [];
  @State expansion: RecoRow[] = [];
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private phase: number = 0;
  private timerId: number = -1;
  // 力导向算出的坐标：id → [x, y]。布局只在数据就绪时跑一次，
  // 呼吸动画只重绘不重算——否则每 110ms 跑一轮 80 迭代会持续吃 CPU。
  private layout: Map<string, number[]> = new Map();
  // 画布尺寸就绪后才跑过布局。onReady 之前 ctx.width 为 0。
  private layoutReady: boolean = false;
  // 选中节点：点中的节点高亮，其余降透明度；再点空白处取消
  @State picked: string = '';
  // 画布按压态：Canvas 是叶子节点，套 PressScale 会改变命中区，故就地手写。
  @State canvasPressed: boolean = false;
  // 按下的底部按钮：'fav' / 'sync' / ''（无）
  @State pressedBtn: string = '';
  // 按下的文字入口芯片：存节点 id。与 pressedBtn 分开，避免 id 与 'fav' 撞值。
  @State chipPressed: string = '';
  // 画布内边距：力导向不保证不出界，布局时夹在 pad 内
  private pad: number = 34;
  // 脉络抽屉：图例 / 文字入口 / 清单 / 按钮全部收进这里，画布独占余下整屏。
  // 抽屉开合改变画布可用高度，所以开合后必须重跑布局（onAreaChange 触发）。
  @State drawerOpen: boolean = false;
  private drawerH: number = 360;

  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }

  aboutToAppear(): void {
    this.loadGraph();
    // 中心"我的黄河"年轮呼吸：~8fps 轻量重绘，仅本页存活期间运行。
    // 只重绘不算布局——力导向 80 迭代每 110ms 跑一遍会持续吃 CPU。
    this.timerId = setInterval((): void => {
      this.phase = this.phase + 0.16;
      this.paint();
    }, 110);
  }

  // 从详情页返回时必须重算：在那边新收藏的遗址/文物要立刻长进图里。
  // aboutToAppear 只在页面创建时跑一次，页面在栈里被盖住再回来不会触发，
  // 于是会停在进图那一刻的快照上（实测：收藏了文物，回来仍显示「文物 0」）。
  onPageShow(): void {
    this.loadGraph();
  }

  loadGraph(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
      UserDataRepo.listFavoritesOf(ctx).then((favs: FavoriteDO[]) => {
        const keys: string[] = [];
        for (const f of favs) { keys.push(f.targetKey); }
        UserDataRepo.allNotes(ctx).then((notes) => {
          this.sites = sites;
          this.favs = favs;
          this.graph = buildGraph(sites, keys, notes);
          // 重新构图后旧的选中 id 可能已不存在（取消收藏），清掉免得残留高亮
          if (this.picked !== '' && !this.hasNode(this.picked)) { this.picked = ''; }
          this.refreshExpansion();
          // 画布可能已就绪（onReady 先于数据），此时补跑布局；
          // 否则留给 onReady——那里会检查 nodes.length
          if (this.layoutReady) { this.runLayout(); }
          this.paint();
        });
      });
    });
  }

  // 顺着这张图还能看什么：种子取选中节点（没选就取连边最多的遗址），
  // 算法复用 RecoSource.recoRowsFor，再滤掉图上已有的，只留三条。
  private refreshExpansion(): void {
    if (this.sites.length === 0 || this.graph.empty) {
      this.expansion = [];
      return;
    }
    const seedNodeId: string = expansionSeed(this.graph, this.picked);
    if (seedNodeId === '') {
      this.expansion = [];
      return;
    }
    const seedId: string = seedNodeId.substring('site:'.length);
    let seed: SiteInfo | null = null;
    for (const s of this.sites) {
      if (s.id === seedId) { seed = s; break; }
    }
    if (seed === null) {
      this.expansion = [];
      return;
    }
    const src: SiteInfo = seed;
    const rows: RecoRow[] = recoRowsFor(src, this.sites, this.favs, 6);
    const unseen: string[] = unseenSiteIds(this.graph, rows.map((r: RecoRow): string => r.id));
    const out: RecoRow[] = [];
    for (const r of rows) {
      if (unseen.indexOf(r.id) >= 0) { out.push(r); }
      if (out.length >= 3) { break; }
    }
    this.expansion = out;
  }

  hasNode(id: string): boolean {
    for (const n of this.graph.nodes) {
      if (n.id === id) { return true; }
    }
    return false;
  }

  // 画布上的年代根与标签叶只能靠触摸命中：读屏与键盘用户到不了。
  // 这里把同一批节点整理成一行文字入口，选中走的是与 onTap 相同的 picked，
  // 说明文字仍由 pickNote() 统一给出，不另写一套文案。
  structNodes(): NetNode[] {
    const out: NetNode[] = [];
    for (const n of this.graph.nodes) {
      if (n.kind === 'era' || n.kind === 'tag') { out.push(n); }
    }
    return out;
  }

  // 条目节点（遗址/文物）的文字等价清单：画布上这两类节点「点了就走」，
  // 但命中靠坐标，读屏与键盘用户到不了。这里给同一批节点一份可聚焦的
  // 芯片清单，点击导航与 onTap 完全同路（遗址 → 详情页，文物 → 器物页），
  // 语义不再只能靠图例与年代清单间接获知。
  entryNodes(): NetNode[] {
    const out: NetNode[] = [];
    for (const n of this.graph.nodes) {
      if (n.kind === 'site' || n.kind === 'relic') { out.push(n); }
    }
    return out;
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  // 选中节点的说明：连了几条边、与谁相连、因哪些标签共现。
  // 共现标签来自 buildGraph 的 forceTags（key = "a|b" 字典序）。
  pickNote(): string {
    if (this.picked === '') {
      return this.graph.empty ? '' : '点遗址/文物节点进入详情，点年代或标签查看关联';
    }
    let nbr = 0;
    const names: string[] = [];
    for (const e of this.graph.forces) {
      let other = '';
      if (e.a === this.picked) { other = e.b; }
      else if (e.b === this.picked) { other = e.a; }
      if (other === '') { continue; }
      nbr++;
      if (names.length < 3) {
        for (const n of this.graph.nodes) {
          if (n.id === other) { names.push(n.label); break; }
        }
      }
    }
    const tags: string[] = this.sharedTagsOf(this.picked);
    let s = `关联 ${nbr} 项`;
    if (names.length > 0) { s += `：${names.join('、')}`; }
    if (names.length < nbr) { s += ' 等'; }
    if (tags.length > 0) { s += `　因「${tags.join('、')}」共现`; }
    return s;
  }

  // 与选中节点共现的标签（去重、最多三个）
  private sharedTagsOf(id: string): string[] {
    const out: string[] = [];
    this.graph.forceTags.forEach((tags: string[], key: string) => {
      const parts: string[] = key.split('|');
      if (parts[0] !== id && parts[1] !== id) { return; }
      for (const t of tags) {
        if (!out.includes(t)) { out.push(t); }
      }
    });
    return out.slice(0, 3);
  }

  // 收起态的一行状态：N 节点 · M 连线 · 枢纽「X」。
  // 枢纽 = 共现处数最多的标签节点；没有标签时不提枢纽。
  statusLine(): string {
    if (this.graph.empty) { return '根系还是空的'; }
    let hub = '';
    let best = 0;
    for (const n of this.graph.nodes) {
      if (n.kind === 'tag' && n.size > best) {
        best = n.size;
        hub = n.label;
      }
    }
    let s = `${this.graph.nodes.length} 节点 · ${this.graph.forces.length} 连线`;
    if (hub !== '') { s += ` · 枢纽「${hub}」`; }
    return s;
  }

  // 命中测试：返回坐标处最近的节点 id（在半径 + 触控余量内），无则空串
  hitTest(x: number, y: number): string {
    const cx = this.ctx.width / 2;
    const cy = this.ctx.height / 2;
    let best: string = '';
    let bestD = 1e9;
    for (const n of this.graph.nodes) {
      const p = this.posOf(n.id, cx, cy);
      const d = Math.sqrt((p[0] - x) * (p[0] - x) + (p[1] - y) * (p[1] - y));
      const reach = this.radiusOf(n) + 14; // 14px 触控余量：节点再小也点得到
      if (d <= reach && d < bestD) { bestD = d; best = n.id; }
    }
    return best;
  }

  // 点节点：条目节点（遗址/文物）直接进详情；结构节点（中心/年代/标签）
  // 选中并高亮其连通子图；点空白处取消选中。
  //
  // 为什么条目节点是「点了就走」而不是先选中再点按钮：图的存在意义就是
  // 从一个条目跳到另一个条目（与 Obsidian 图谱一致），多一次点击反而打断
  // 探索。结构节点没有详情可进，才留给高亮。
  onTap(x: number, y: number): void {
    const hit = this.hitTest(x, y);
    if (hit === '') {
      this.picked = '';
      this.refreshExpansion();
      this.paint();
      return;
    }
    if (hit.startsWith('site:')) {
      const prm: Record<string, string> = { 'id': hit.substring('site:'.length) };
      router.pushUrl({ url: 'pages/DetailPage', params: prm });
      return;
    }
    if (hit.startsWith('relic:')) {
      const relicId: string = hit.substring('relic:'.length);
      const siteId: string = ownerSiteOf(this.graph, hit);
      if (siteId !== '') {
        const prm: Record<string, string> = { 'site': siteId, 'relic': relicId };
        router.pushUrl({ url: 'pages/RelicPage', params: prm });
        return;
      }
      // 找不到所属遗址（图不完整）时退回选中，不把用户丢到空页面
    }
    this.picked = hit;
    this.refreshExpansion();
    this.paint();
  }

  // 文物节点自己不带所属遗址（id 只有 relic:{id}），从图上那条
  // site → relic 的叶边反查。找不到返回空串。
  // （实现放在 NetworkSource，纯函数、可单测。）
  

  // 跑力导向。数据就绪后只跑一次；结果存进 this.layout。
  runLayout(): void {
    const w = this.ctx.width;
    const h = this.ctx.height;
    if (w <= 0 || h <= 0 || this.graph.nodes.length === 0) { return; }
    const input = new ForceInput();
    input.nodes = this.graph.nodes;
    input.edges = this.graph.forces;
    this.layout = forceLayout(input, w, h, this.pad);
  }

  // 取节点坐标：布局没跑过（首帧）时退回画布中心，避免空白
  posOf(id: string, cx: number, cy: number): number[] {
    const p = this.layout.get(id);
    if (p === undefined) { return [cx, cy]; }
    return p;
  }

  // 节点半径：权重越大越粗。标签节点按共现处数放大，一眼看出哪个标签是枢纽
  radiusOf(n: NetNode): number {
    if (n.kind === 'root') { return 26; }
    if (n.kind === 'era') { return 12 + n.size * 2.4; }
    if (n.kind === 'site') { return 6 + n.size * 1.6; }
    if (n.kind === 'tag') { return 5 + n.size * 2.0; }
    return 4 + n.size * 1.2;
  }

  paint(): void {
    const c = this.ctx;
    const w = c.width;
    const h = c.height;
    c.clearRect(0, 0, w, h);
    const cx = w / 2;
    const cy = h / 2;

    // 边：共现权重决定线宽与透明度。权重 1 是发丝，权重 ≥3 才够粗到「看得见」
    for (const e of this.graph.forces) {
      const a = this.layout.get(e.a);
      const b = this.layout.get(e.b);
      if (a === undefined || b === undefined) { continue; }
      const dim: boolean = this.picked !== '' && e.a !== this.picked && e.b !== this.picked;
      const wt: number = e.weight > 0 ? e.weight : 1;
      c.beginPath();
      c.moveTo(a[0], a[1]);
      c.lineTo(b[0], b[1]);
      if (e.a === 'root' || e.b === 'root') {
        c.strokeStyle = GRAPH_ROOT;
        c.lineWidth = 1.2;
        c.globalAlpha = dim ? 0.25 : 0.85;
      } else {
        c.strokeStyle = GRAPH_EDGE;
        c.lineWidth = Math.min(4, 0.8 + wt * 0.9);
        c.globalAlpha = dim ? 0.15 : (0.35 + Math.min(0.5, wt * 0.18));
      }
      c.stroke();
    }
    c.globalAlpha = 1;

    // 节点
    for (const n of this.graph.nodes) {
      const p = this.posOf(n.id, cx, cy);
      const rad = this.radiusOf(n);
      const dim: boolean = this.picked !== '' && n.id !== this.picked &&
        !this.isNeighbor(n.id);
      c.globalAlpha = dim ? 0.3 : 1;
      c.beginPath();
      c.arc(p[0], p[1], rad, 0, 6.28318);
      if (n.kind === 'root') {
        // 中心"我的黄河"：年轮呼吸环（半径与透明度随相位）
        const t: number = (Math.sin(this.phase) + 1) / 2;
        const ringR: number = rad + 3 + t * 7;
        c.beginPath();
        c.arc(p[0], p[1], ringR, 0, 6.28318);
        c.strokeStyle = 'rgba(43,38,34,' + (0.42 * (1 - t)).toFixed(3) + ')';
        c.lineWidth = 1.4;
        c.stroke();
        c.beginPath();
        c.arc(p[0], p[1], rad, 0, 6.28318);
        c.fillStyle = this.picked === 'root' ? ACCENT : THEME_INK;
        c.fill();
      } else if (n.kind === 'era') {
        c.fillStyle = THEME_BG;
        c.fill();
        c.strokeStyle = eraColor(n.era);
        c.lineWidth = 2.6;
        c.stroke();
      } else if (n.kind === 'site') {
        // 遗址：年代本体色实心。选中时套一圈赭红外环
        c.fillStyle = eraColor(n.era);
        c.fill();
        if (this.picked === n.id) {
          c.beginPath();
          c.arc(p[0], p[1], rad + 5, 0, 6.28318);
          c.strokeStyle = ACCENT;
          c.lineWidth = 2;
          c.stroke();
        }
      } else if (n.kind === 'tag') {
        c.fillStyle = THEME_BG;
        c.fill();
        c.strokeStyle = this.picked === n.id ? ACCENT : THEME_INK;
        c.lineWidth = this.picked === n.id ? 2.4 : 1.4;
        c.stroke();
      } else {
        c.fillStyle = eraColor(n.era);
        c.fill();
      }
    }
    c.globalAlpha = 1;

    // 标签：沿「远离中心」的方向外推，再夹回画布内
    c.textAlign = 'center';
    const placed: number[][] = [];
    for (const n of this.graph.nodes) {
      const p = this.posOf(n.id, cx, cy);
      const rad = this.radiusOf(n);
      const dim: boolean = this.picked !== '' && n.id !== this.picked && !this.isNeighbor(n.id);
      c.globalAlpha = dim ? 0.25 : 1;
      // 外推方向 = 从中心指向节点，力导向下不再是固定角度但仍成立
      let co = p[0] - cx;
      let si = p[1] - cy;
      const len = Math.sqrt(co * co + si * si);
      if (len < 1) { co = 0; si = 1; } else { co = co / len; si = si / len; }
      const gap = rad + 9;
      c.font = n.kind === 'site' ? 'bold 26px sans-serif' : '22px sans-serif';
      c.fillStyle = n.kind === 'tag' ? SUB : (n.kind === 'era' ? eraText(n.era) : THEME_INK);
      const tw = c.measureText(n.label).width / 2;
      const bx = Math.max(tw + 8, Math.min(w - tw - 8, p[0] + co * gap));
      const dir: number = si >= 0 ? 1 : -1;
      const by = n.kind === 'root' ? p[1] + gap + 10 : (si >= 0 ? p[1] + gap + 8 : p[1] - gap - 2);
      let ly = by;
      for (let k = 1; k < 9; k++) {
        // 交替向下/向上让位，标签不会整列往一侧漂走
        const sgn: number = k % 2 === 1 ? dir : 0 - dir;
        const cand = by + (Math.floor(k / 2) + 1) * 24 * sgn;
        if (cand < 24 || cand > h - 10) { continue; }
        if (!overlaps(placed, bx, cand, tw)) { ly = cand; break; }
      }
      placed.push([bx - tw, ly - 24, bx + tw, ly + 4]);
      c.fillText(n.label, bx, ly);
    }
    c.globalAlpha = 1;
  }

  // 选中节点的邻居：与它有边相连的节点。用于高亮连通子图。
  private isNeighbor(id: string): boolean {
    if (this.picked === '') { return false; }
    for (const e of this.graph.forces) {
      if (e.a === this.picked && e.b === id) { return true; }
      if (e.b === this.picked && e.a === id) { return true; }
    }
    return false;
  }

  build() {
    Column() {
      Row() {
        BackLink()
        Blank()
        Text('主题网络图')
          .fontSize(FS_BODY)
          .letterSpacing(4)
          .fontColor(THEME_INK)
        Blank()
        Text(this.picked === '' ? '力导向' : '已选中')
          .fontSize(FS_CAPTION)
          .letterSpacing(2)
          .fontColor(ACCENT)
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 12 })

      Text('我的收藏如何长成一条脉络')
        .fontSize(FS_DISPLAY)
        .fontFamily(FONT_DISPLAY)
        .fontWeight(WT_DISPLAY)
        .fontColor(THEME_INK)
        .letterSpacing(2)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 4 })

      // 选中说明紧跟画布：点中节点后这里讲清「它和谁相连、因为什么」。
      // 空态时给一句操作提示——Canvas 不可聚焦，键盘用户靠这句知道能点什么。
      Text(this.pickNote())
        .fontSize(FS_CAPTION)
        .fontColor(ACCENT)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 10 })

      // 画布占满标题与抽屉之间的全部余高（修复计划 §7.14）：
      // 原先固定 400vp 高、和图例清单一起塞进 Scroll，图被压成一条横幅；
      // 现在画布 layoutWeight(1)，信息整体收进底部「脉络」抽屉。
      Stack() {
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .onReady(() => {
            // 尺寸此时才可信。数据可能还没到（ContentRepo 异步），
            // 故布局拆两步：这里保证「已就绪」，数据到达时再补跑。
            this.layoutReady = true;
            if (this.graph.nodes.length > 0) { this.runLayout(); }
            this.paint();
          })
          // 抽屉开合会改变画布可用高度，布局按旧尺寸算的坐标全部作废，
          // 必须重跑。onReady 只在首次挂载触发，这里兜住之后的一切尺寸变化。
          .onAreaChange((_o: Area, _n: Area) => {
            if (this.layoutReady && this.graph.nodes.length > 0) {
              this.runLayout();
              this.paint();
            }
          })
          .onClick((e: ClickEvent) => {
            this.onTap(e.x, e.y);
          })
          // Canvas 是可交互面（点选节点），必须给键盘用户一个可聚焦入口与焦点环。
          // 按压反馈用 opacity 而非 scale：缩放会让整张图抖，而这里要的是「点到了」。
          .focusable(true)
          .focusBox(focusRing())
          // 画布本身读不出内容，替代文本至少要说清三件事：图有多大、点节点会怎样、
          // 以及不靠触摸时去哪（下方脉络抽屉）。统计串与页面上的同一句同源。
          .accessibilityText(`主题网络图画布，${this.graph.stat}。点遗址或文物节点进入详情，点年代或标签查看关联；键盘与读屏用户可展开画布下方的脉络抽屉，用文字入口选择年代与标签，或用条目清单逐条进入遗址与文物详情`)
          .onTouch((e: TouchEvent) => {
            if (e.type === TouchType.Down) {
              this.canvasPressed = true;
            } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
              this.canvasPressed = false;
            }
          })
          .opacity(this.canvasPressed ? PRESS_OPACITY : 1)
          .animation(pressAnim())
        if (this.graph.empty) {
          Text('根系还是空的。\n去遗址页点 ☆ 收藏，再在笔记里打标签，\n这张图就按你自己的口味长出来。')
            .fontSize(FS_BODY)
            .lineHeight(LH_BODY)
            .fontColor(SUB)
            .textAlign(TextAlign.Center)
            .backgroundColor(THEME_BG)
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 12 })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .alignContent(Alignment.Center)

      // ── 脉络抽屉：收起时只剩一行状态 + 拉手，展开装下全部文字信息。
      // 高度动画挂在容器 .animation 上；不用 animateTo 包状态变更——
      // 那会与 .animation() 互相打断（Motion 注释里的实测结论）。
      Column() {
        PressFade() {
          Row({ space: 8 }) {
            Text('脉络')
              .fontSize(FS_BODY)
              .fontFamily(FONT_DISPLAY)
              .fontWeight(WT_DISPLAY)
              .fontColor(THEME_INK)
              .letterSpacing(2)
            Text(this.statusLine())
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
              .letterSpacing(1)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.drawerOpen ? '⌃' : '⌄')
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
          }
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 12 })
          .border({ width: { top: 1 }, color: LINE_HAIR })
          .accessibilityText(`脉络抽屉，${this.statusLine()}，${this.drawerOpen ? '点按收起' : '点按展开图例、文字入口与清单'}`)
          .onClick(() => {
            this.drawerOpen = !this.drawerOpen;
          })
          .focusable(true)
          .focusBox(focusRing())
        }

        // 抽屉内容常挂载、只动画高度：条件渲染的节点没有「前值」，
        // .animation() 对新插入的节点根本不会播——这是实测过的坑。
        // 收起时高度归零 + 裁切，内容不可见也不可点。
        Scroll() {
            Column({ space: 0 }) {
              Row({ space: 16 }) {
                this.legend('年代根', eraColor('yangshao'), true)
                this.legend('遗址', eraColor('hantang'), false)
                this.legend('标签', THEME_BG, false)
                this.legend('粗线=多标签共现', GRAPH_EDGE, false)
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .padding({ top: 10, bottom: 16 })

              // 文字入口：画布上的年代根与标签叶只有触摸能命中，这里给同一批节点
              // 一份等价的、可聚焦的选择方式。
              if (!this.graph.empty) {
                Column({ space: 6 }) {
                  Text('选年代或标签看关联')
                    .fontSize(FS_CAPTION)
                    .fontColor(SUB)
                    .letterSpacing(1)
                    .width('100%')
                    .accessibilityText('文字入口：选年代或标签，看它与哪些收藏相连')
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach(this.structNodes(), (n: NetNode) => {
                      this.nodeChip(n)
                    }, (n: NetNode) => `chip_${n.id}`)
                  }
                  .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 4 })
              }

              if (!this.graph.empty) {
                Column({ space: 0 }) {
                  ForEach(this.graph.rows, (r: NetRow) => {
                    Column({ space: 3 }) {
                      Row({ space: 8 }) {
                        Row()
                          .width(8)
                          .height(8)
                          .borderRadius(4)
                          .backgroundColor(eraColor(r.era))
                        Text(r.name)
                          .fontSize(FS_BODY)
                          .fontWeight(WT_BOLD)
                          .fontColor(THEME_INK)
                          .letterSpacing(2)
                        Blank()
                        Text(`${r.count} 处`)
                          .fontSize(FS_CAPTION)
                          .fontColor(SUB)
                          .letterSpacing(1)
                      }
                      .width('100%')
                      Text(r.names)
                        .fontSize(FS_CAPTION)
                        .lineHeight(LH_CAPTION)
                        .fontColor(SUB)
                        .width('100%')
                        .padding({ left: 16 })
                    }
                    .width('100%')
                    .padding({ top: 12, bottom: 12 })
                    .border({ width: { bottom: 1 }, color: LINE_HAIR })
                    .alignItems(HorizontalAlign.Start)
                  }, (r: NetRow) => r.era)
                }
                .width('100%')
                .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })
                .margin({ bottom: 16 })
              }

              // 条目清单：画布上「点了就走」的遗址/文物节点，这里给同一批节点的
              // 可聚焦文字版。
              if (!this.graph.empty) {
                Column({ space: 6 }) {
                  Text('图里的每一处，点名称直接进详情')
                    .fontSize(FS_CAPTION)
                    .fontColor(SUB)
                    .letterSpacing(1)
                    .width('100%')
                    .accessibilityText('条目清单：图中的遗址与文物，逐条点按进入详情页')
                  Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
                    ForEach(this.entryNodes(), (n: NetNode) => {
                      this.entryChip(n)
                    }, (n: NetNode) => `entry_${n.id}`)
                  }
                  .width('100%')
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 4 })
              }

              // 拓展推荐：顺着这张图的脉络还能看什么。种子随选中节点变化，
              // 结果与"图里每一处"分开排，避免把已有节点误读成新发现。
              if (this.expansion.length > 0) {
                Column({ space: 6 }) {
                  Text('顺着脉络再看')
                    .fontSize(FS_CAPTION)
                    .fontColor(SUB)
                    .letterSpacing(1)
                    .width('100%')
                    .accessibilityText('拓展推荐：图上还没有的相邻遗址，点名称进入详情')
                  Text(`${this.expansion.length} 处还未进这张图`)
                    .fontSize(FS_CAPTION)
                    .fontColor(ACCENT)
                    .width('100%')
                  ForEach(this.expansion, (r: RecoRow) => {
                    this.expansionRow(r)
                  }, (r: RecoRow) => `expand_${r.id}`)
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
                .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 10, bottom: 12 })
              }

              Row({ space: 12 }) {
                // 两个按钮用 layoutWeight(1) 平分宽度，包装器多出的一层会把权重
                // 分配吃掉，故按压态就地写 onTouch 三段式。
                Button('看我的收藏')
                  .fontSize(FS_BODY)
                  .fontColor(SURFACE_CARD)
                  .backgroundColor(ACCENT)
                  .borderRadius(CAPSULE_RADIUS)
                  .height(CAPSULE_H)
                  .layoutWeight(1)
                  // Button 自带焦点能力，focusBox 已足够；Text / Image 默认不可聚焦，
                  // 那两处必须额外写 .focusable(true)，否则焦点环根本不会显示。
                  .focusBox(focusRing())
                  .onClick(() => {
                    // 收藏是频道页：压栈会在栈里留一份，与底栏两套语法打架，
                    // 统一走频道切换。
                    switchToTab(1);
                  })
                  .onTouch((e: TouchEvent) => {
                    if (e.type === TouchType.Down) {
                      this.pressedBtn = 'fav';
                    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                      this.pressedBtn = '';
                    }
                  })
                  .scale({ x: this.pressedBtn === 'fav' ? PRESS_SCALE : 1, y: this.pressedBtn === 'fav' ? PRESS_SCALE : 1 })
                  .animation(pressAnim())
                Button('同步面板')
                  .fontSize(FS_BODY)
                  .fontColor(THEME_INK)
                  .backgroundColor(SURFACE_CARD)
                  .border({ width: 1, color: LINE_HAIR })
                  .borderRadius(CAPSULE_RADIUS)
                  .height(CAPSULE_H)
                  .layoutWeight(1)
                  .focusBox(focusRing())
                  .onClick(() => {
                    router.pushUrl({ url: 'pages/SyncPage' });
                  })
                  .onTouch((e: TouchEvent) => {
                    if (e.type === TouchType.Down) {
                      this.pressedBtn = 'sync';
                    } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                      this.pressedBtn = '';
                    }
                  })
                  .scale({ x: this.pressedBtn === 'sync' ? PRESS_SCALE : 1, y: this.pressedBtn === 'sync' ? PRESS_SCALE : 1 })
                  .animation(pressAnim())
              }
              .width('100%')
              .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 24 })
            }
            .width('100%')
          }
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .width('100%')
          .height(this.drawerOpen ? this.drawerH : 0)
          .clip(true)
          .animation({ duration: durBase(), curve: curveOut() })
      }
      .width('100%')
      .backgroundColor(THEME_BG)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }

  // 选中态直接读 this.picked（与 RecommendPage 的兴趣芯片同一种写法）：
  // 写在 @Builder 里的状态依赖会被追踪，不像按值传进来的参数那样停在首帧。
  @Builder
  nodeChip(n: NetNode) {
    Row({ space: 6 }) {
      Text(n.label)
        .fontSize(FS_CAPTION)
        .fontColor(this.picked === n.id ? SURFACE_CARD : THEME_INK)
      Text(n.meta)
        .fontSize(FS_CAPTION)
        .fontColor(this.picked === n.id ? SURFACE_CARD : SUB)
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(this.picked === n.id ? ACCENT : SURFACE_RAISED)
    .border({ width: HAIR, color: this.picked === n.id ? ACCENT : LINE_HAIR })
    .borderRadius(CHIP_RADIUS)
    .margin({ right: 8, bottom: 8 })
    .accessibilityText(`${n.kind === 'era' ? '年代' : '标签'}「${n.label}」，${n.meta}${this.picked === n.id ? '，已选中' : ''}`)
    .onClick(() => {
      // 再点一次取消：与画布上「点空白处取消」保持同一种手感。
      this.picked = this.picked === n.id ? '' : n.id;
      this.refreshExpansion();
      this.paint();
    })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.chipPressed = n.id;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.chipPressed = '';
      }
    })
    .opacity(this.chipPressed === n.id ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
  }

  // 条目芯片：样式与结构芯片（nodeChip）同一套令牌，行为与画布 onTap 同路。
  // 区别在语义：结构芯片是「选中看关联」，这里是「直接进详情」，
  // 故替代文本写清动作与去向，不与 picked 状态混用。
  @Builder
  entryChip(n: NetNode) {
    Row({ space: 6 }) {
      Row()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(eraColor(n.era))
      Text(n.label)
        .fontSize(FS_CAPTION)
        .fontColor(THEME_INK)
      Text(n.kind === 'site' ? '遗址' : '文物')
        .fontSize(FS_CAPTION)
        .fontColor(SUB)
    }
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(SURFACE_RAISED)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(CHIP_RADIUS)
    .margin({ right: 8, bottom: 8 })
    .accessibilityText(`${n.kind === 'site' ? '遗址' : '文物'}「${n.label}」，点按进入${n.kind === 'site' ? '遗址' : '文物'}详情`)
    .onClick(() => {
      if (n.kind === 'site') {
        const prm: Record<string, string> = { 'id': n.id.substring('site:'.length) };
        router.pushUrl({ url: 'pages/DetailPage', params: prm });
        return;
      }
      const siteId: string = ownerSiteOf(this.graph, n.id);
      if (siteId !== '') {
        const prm: Record<string, string> = { 'site': siteId, 'relic': n.id.substring('relic:'.length) };
        router.pushUrl({ url: 'pages/RelicPage', params: prm });
      }
    })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.chipPressed = n.id;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.chipPressed = '';
      }
    })
    .opacity(this.chipPressed === n.id ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
  }

  // 拓展推荐行：与条目芯片分开，因为这里带"为什么推"的理由，且结果是
  // 图上还没有的遗址——点进去是探索，不是回看已有收藏。
  @Builder
  expansionRow(r: RecoRow) {
    Row({ space: 8 }) {
      Text(r.rank)
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_DISPLAY)
        .fontColor(ACCENT)
      Column({ space: 4 }) {
        Text(r.name)
          .fontSize(FS_CAPTION)
          .fontColor(THEME_INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${r.meta} · ${r.reasons.length > 0 ? r.reasons[0] : '脉络相邻'}`)
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(FS_BODY)
        .fontColor(SUB)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(SURFACE_RAISED)
    .border({ width: HAIR, color: LINE_HAIR })
    .borderRadius(CHIP_RADIUS)
    .margin({ bottom: 6 })
    .accessibilityText(`拓展推荐：${r.name}，${r.meta}，${r.reasons.join('、')}，点按进入详情`)
    .onClick(() => {
      const prm: Record<string, string> = { 'id': r.id };
      router.pushUrl({ url: 'pages/DetailPage', params: prm });
    })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.chipPressed = `expand_${r.id}`;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.chipPressed = '';
      }
    })
    .opacity(this.chipPressed === `expand_${r.id}` ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
  }

  @Builder
  legend(label: string, color: string, ring: boolean) {
    Row({ space: 6 }) {
      Row()
        .width(10)
        .height(10)
        .borderRadius(RADIUS_PILL)
        .backgroundColor(ring ? THEME_BG : color)
        .border({ width: 1.6, color: color })
      Text(label)
        .fontSize(FS_CAPTION)
        .fontColor(SUB)
        .letterSpacing(1)
    }
  }
}

