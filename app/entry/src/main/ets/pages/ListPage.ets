import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { CITIES, ERAS, SITE_TYPES, SiteInfo } from '../model/ContentModels';
import { ContentRepo } from '../repository/ContentRepo';
import { filterSites, searchSites } from '../service/content/ContentParse';
import { buildMaterialIndex, MaterialBucket, MaterialIndex } from '../service/content/MaterialIndex';
import { BackLink } from '../common/BackLink';
import { eraColor, eraInkA, eraName, eraSpan, THEME_BG } from '../common/EraTheme';
import { ACCENT, BODY, CARD_PAD, CHIP_H, CHIP_RADIUS, FONT_DISPLAY, FONT_MONO, FONT_SANS, FONT_SERIF, FS_CAPTION, FS_HEAD, FS_ITEM, FS_MICRO, FS_PAGE, FS_TAB, FS_TITLE, HAIR, INK, ITEM_GAP, LINE_HAIR, MAT_COLOR_BONE, MAT_COLOR_EARTH, MAT_COLOR_JADE, MAT_COLOR_METAL, MAT_COLOR_ORGANIC, MAT_COLOR_POTTERY, MAT_COLOR_STONE, PAGE_PAD_X, PRESS_SCALE, RADIUS_DOT_6, RADIUS_MD, RADIUS_SM, ROUTE_FADE_MIN, ROUTE_SHIFT_VP, ROW_GAP, SHADOW_CARD_COLOR_LIGHT, SHADOW_CARD_OFFSET, SHADOW_CARD_RADIUS, SUB, SURFACE_CARD, SURFACE_RAISED, WT_DISPLAY, WT_MEDIUM, WT_REGULAR } from '../common/DesignTokens';
import { firstRealImage } from '../common/ImagePolicy';
import { cityName, typeName } from '../common/Labels';
import { materialKind as relicMaterialKind } from '../common/RelicIcon';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut, pressAnim } from '../common/Motion';
import { RevealOnScroll } from '../common/RevealOnScroll';
import { PressFade, PressScale } from '../common/PressScale';
import { LayerBadge } from '../common/LayerBadge';
import { StratumCrumb } from '../common/StratumCrumb';

@Entry
@Component
struct ListPage {
  @State era: string = '';
  @State city: string = '';
  @State siteType: string = '';
  @State keyword: string = '';
  @State showFilters: boolean = false;
  // 按材质逛：与三维筛选正交的第四维度，空串 = 不按材质过滤
  @State material: string = '';
  // 必须是 @State：材质条读的是它，非响应式字段只会在首帧渲染一次，
  // 之后改城市/类型筛选，列表数字变了而「当前 N 件」还挂着旧值（2026-11-06 实测）。
  @State matIdx: MaterialIndex = new MaterialIndex();
  private all: SiteInfo[] = [];
  @State sites: SiteInfo[] = [];
  // onError 兜底：JSON 引用了 real_ 图但盘上缺文件时，$rawfile 不报错、
  // Image 渲染成永久空白；记下失败条目，翻回无实拍的同款占位。
  @State failedThumbs: string[] = [];
  // 按下的列表卡站点 id
  @State pressedSite: string = '';

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
    if (p !== undefined) {
      this.era = p['era'] ?? '';
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
      this.all = sites;
      this.matIdx = buildMaterialIndex(sites);
      this.apply();
    });
  }

  apply(): void {
    // 维度过滤走 ContentParse 纯函数：组内并集、组间交集；关键词在过滤后的集合上检索
    const eras: string[] = this.era === '' ? [] : [this.era];
    const types: string[] = this.siteType === '' ? [] : [this.siteType];
    const cities: string[] = this.city === '' ? [] : [this.city];
    let out: SiteInfo[] = searchSites(filterSites(this.all, eras, types, cities), this.keyword);
    // 材质计数必须跟当前范围走：年代选「宋」时若仍显示全库 104 件，
    // 「未记 1」点进去却是别的年代的文物，数字与列表对不上。
    this.matIdx = buildMaterialIndex(out);
    if (this.material !== '') {
      // 按材质逛是「遗址里有没有这类材质的文物」，不是遗址自身的属性——
      // 语料的 site 级没有 material 字段，只有 relics[] 有。故在结果集上
      // 再过一层：保留至少挂着一件该材质文物的遗址。
      out = out.filter((s: SiteInfo): boolean => {
        for (const r of s.relics) {
          if (relicMaterialKind(r.material) === this.material) { return true; }
        }
        return false;
      });
    }
    this.sites = out;
  }

  // 是否有年代/城市/类型/关键词限定——决定材质计数表头写「当前」还是「全库」
  hasScope(): boolean {
    return this.era !== '' || this.city !== '' || this.siteType !== '' || this.keyword.trim() !== '';
  }

  // 材质入口的色点：七类各给一个可辨的色。刻意不复用年代色——
  // 年代色在年代 chips 上已有语义，混用会让两个维度看起来是同一个。
  // 取值收在 DesignTokens 的 MAT_COLOR_* 一组里。
  materialColor(kind: string): string {
    if (kind === '陶') { return MAT_COLOR_POTTERY; }
    if (kind === '金属') { return MAT_COLOR_METAL; }
    if (kind === '土') { return MAT_COLOR_EARTH; }
    if (kind === '玉') { return MAT_COLOR_JADE; }
    if (kind === '石') { return MAT_COLOR_STONE; }
    if (kind === '骨') { return MAT_COLOR_BONE; }
    if (kind === '有机') { return MAT_COLOR_ORGANIC; }
    return SUB; // 未记
  }

  build() {
    Column() {
      // 顶栏：只有返回。数量与年代只在「入选遗址」表头说一次，
      // 不在顶栏、筛选行、表头各重复一遍（首屏信息过载）。
      Row({ space: ROW_GAP }) {
        BackLink()
        Blank()
        // 遗址列表与文物图录是两条平级主线，在这里给一个直达口，
        // 不用退回首页再进。
        // 带 era 下去：这一页是某个年代的遗址列表，图录入口就该只看
        // 这一层的文物，不带年代等于让用户重新选一次（A 方案双轴：
        // 年代卡上的「N 处遗址 · M 件文物」两个数字要能各自落到实处）。
        PressFade() {
          Text(this.era === '' ? '文物图录 ›' : `${eraName(this.era)}层文物 ›`)
            .fontSize(FS_CAPTION)
            .fontColor(ACCENT)
            .accessibilityText(this.era === '' ? '打开文物图录' : `打开${eraName(this.era)}层文物图录`)
            .onClick(() => {
              const prm: Record<string, string> = { 'era': this.era };
              router.pushUrl({ url: 'pages/RelicListPage', params: prm });
            })
            .focusable(true)
            .focusBox(focusRing())
        }
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16 })

      // 层位面包屑（修复计划 §6.3 / 清单 C2）：地表 › 仰韶
      // 给内容页一个显式层位——返回键的每一次按压都在重放这条下降线。
      // 全部遗址（era 为空）时不渲染"地表 › 地表"，只留地表一段。
      Column() {
        if (this.era === '') {
          StratumCrumb({ era: '', eraLabel: '' })
        } else {
          StratumCrumb({ era: this.era, eraLabel: eraName(this.era) })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 6 })

      // 标题区：30pt 展示体。标题下不再画短杠（2026-11-05 全站撤除，
      // 见 common/SectionTitle 的说明）。
      Column({ space: 6 }) {
        Text(this.era === '' ? '全部遗址' : `${eraName(this.era)}时代`)
          .fontSize(FS_PAGE)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: PAGE_PAD_X, top: 16, bottom: 6 })

      // 关键词检索：属于页头，不是独立区块——搜索行自身不再给上间距，
      // 否则「标题 bottom 16 + 搜索 top 8」加上行高会撑出 34vp 空洞（2026-11-06 实测）。
      Row({ space: ROW_GAP }) {
        Text('搜')
          .fontSize(FS_CAPTION)
          .letterSpacing(1)
          .fontColor(SUB)
        TextInput({ placeholder: '遗址名 / 标签 / 提要关键词', text: this.keyword })
          .accessibilityText('搜索遗址：名称、标签或提要关键词')
          .layoutWeight(1)
          .fontSize(FS_CAPTION)
          .fontColor(INK)
          .placeholderColor(SUB)
          .backgroundColor(Color.Transparent)
          .padding(0)
          .height(34)
          .onChange((v: string) => {
            this.keyword = v;
            this.apply();
          })
        if (this.keyword !== '') {
          PressFade() {
            Text('清空')
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
              .onClick(() => {
                this.keyword = '';
                this.apply();
              })
              .focusable(true)
              .focusBox(focusRing())
          }
        }
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 0, bottom: 12 })
      .border({ width: { bottom: HAIR }, color: LINE_HAIR })

      // 三维筛选胶囊：三行堆叠太占首屏。折叠为「年代 + 更多」两行，
      // 「更多」点开才出城市 / 类型两行；折叠态只剩 6 枚年代胶囊 + 城市/类型 chip 各一。
      Scroll() {
        Column({ space: 8 }) {
          Row({ space: 4 }) {
            Text('年代')
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
              .margin({ right: 4 })
            ForEach(ERAS, (e: string) => {
              PressScale() {
                Row({ space: 6 }) {
                  Row()
                    .width(8)
                    .height(8)
                    .borderRadius(4)
                    .backgroundColor(this.era === e ? SURFACE_CARD : eraColor(e))
                  Text(eraName(e))
                    .fontSize(FS_CAPTION)
                    .fontFamily(FONT_SANS)
                    .fontWeight(WT_REGULAR)
                    .fontColor(this.era === e ? SURFACE_CARD : INK)
                }
                .height(CHIP_H)
                .padding({ left: 12, right: 12 })
                .backgroundColor(this.era === e ? INK : SURFACE_CARD)
                .border({ width: HAIR, color: this.era === e ? INK : LINE_HAIR })
                .borderRadius(CHIP_RADIUS)
                .onClick(() => {
                  this.era = this.era === e ? '' : e;
                  this.apply();
                })
                .focusable(true)
                .focusBox(focusRing())
                .accessibilityText(`${eraName(e)}，${this.era === e ? '已选中' : '未选中'}`)
                .accessibilityLevel('yes')
                .accessibilitySelected(this.era === e)
              }
            }, (e: string) => e)
          }
          .width('100%')

          if (this.showFilters) {
            Row({ space: 4 }) {
              Text('城市')
                .fontSize(FS_CAPTION)
                .fontColor(SUB)
                .margin({ right: 4 })
              ForEach(CITIES, (c: string) => {
                PressScale() {
                  Text(cityName(c))
                    .fontSize(FS_CAPTION)
                    .fontFamily(FONT_DISPLAY)
                    .fontWeight(WT_DISPLAY)
                    .fontColor(this.city === c ? SURFACE_CARD : BODY)
                    .height(CHIP_H)
                    .padding({ left: 12, right: 12 })
                    .backgroundColor(this.city === c ? INK : SURFACE_CARD)
                    .border({ width: HAIR, color: this.city === c ? INK : LINE_HAIR })
                    .borderRadius(CHIP_RADIUS)
                    .textAlign(TextAlign.Center)
                    .onClick(() => {
                      this.city = this.city === c ? '' : c;
                      this.apply();
                    })
                    .focusable(true)
                    .focusBox(focusRing())
                    .accessibilityText(`${cityName(c)}，${this.city === c ? '已选中' : '未选中'}`)
                    .accessibilityLevel('yes')
                    .accessibilitySelected(this.city === c)
                }
              }, (c: string) => c)
            }
            .width('100%')

            Row({ space: 4 }) {
              Text('类型')
                .fontSize(FS_CAPTION)
                .fontColor(SUB)
                .margin({ right: 4 })
              ForEach(SITE_TYPES, (t: string) => {
                PressScale() {
                  Text(typeName(t))
                    .fontSize(FS_CAPTION)
                    .fontFamily(FONT_DISPLAY)
                    .fontWeight(WT_DISPLAY)
                    .fontColor(this.siteType === t ? SURFACE_CARD : BODY)
                    .height(CHIP_H)
                    .padding({ left: 12, right: 12 })
                    .backgroundColor(this.siteType === t ? INK : SURFACE_CARD)
                    .border({ width: HAIR, color: this.siteType === t ? INK : LINE_HAIR })
                    .borderRadius(CHIP_RADIUS)
                    .textAlign(TextAlign.Center)
                    .onClick(() => {
                      this.siteType = this.siteType === t ? '' : t;
                      this.apply();
                    })
                    .focusable(true)
                    .focusBox(focusRing())
                    .accessibilityText(`${typeName(t)}，${this.siteType === t ? '已选中' : '未选中'}`)
                    .accessibilityLevel('yes')
                    .accessibilitySelected(this.siteType === t)
                }
              }, (t: string) => t)
            }
            .width('100%')

            // 按材质逛：三维筛选之外的第二入口。默认折叠，展开才出现——
            // 首屏只留搜索 + 年代，八格材质不再和年代胶囊抢注意力。
            // 计数口径跟当前筛选走，表头写明范围，避免在年代页误读成全库。
            Column({ space: 8 }) {
              Row({ space: 6 }) {
                Text('按材质逛')
                  .fontSize(FS_CAPTION)
                  .letterSpacing(2)
                  .fontColor(SUB)
                Blank()
                Text(this.matIdx.totalRelics > 0
                  ? `${this.hasScope() ? '当前' : '全库'} ${this.matIdx.totalRelics} 件`
                  : '当前范围无文物')
                  .fontSize(FS_TAB)
                  .fontColor(SUB)
              }
              .width('100%')

              Row({ space: 8 }) {
                ForEach(this.matIdx.buckets, (b: MaterialBucket) => {
                  PressScale() {
                    Column({ space: 4 }) {
                      Row()
                        .width(10)
                        .height(10)
                        .borderRadius(RADIUS_DOT_6)
                        .backgroundColor(this.materialColor(b.kind))
                      Text(b.kind)
                        .fontSize(FS_CAPTION)
                        .fontWeight(WT_MEDIUM)
                        .fontColor(this.material === b.kind ? SURFACE_CARD : INK)
                      Text(`${b.relicCount}`)
                        .fontSize(FS_TAB)
                        .fontFamily(FONT_MONO)
                        .fontColor(this.material === b.kind ? SURFACE_CARD : SUB)
                    }
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor(this.material === b.kind ? INK : SURFACE_RAISED)
                    .border({ width: HAIR, color: this.material === b.kind ? INK : LINE_HAIR })
                    .borderRadius(RADIUS_SM)
                    // 当前范围没有这类材质时不可点：0 件点进去只会得到空列表。
                    // 清单 §3.4：不用 .enabled(false)——系统禁用外观会盖掉自绘的
                    // 选中态底色与描边；禁用只表达为 opacity，判定放在点击里。
                    .opacity(b.relicCount > 0 || this.material === b.kind ? 1 : 0.4)
                    .onClick(() => {
                      if (b.relicCount === 0 && this.material !== b.kind) { return; }
                      this.material = this.material === b.kind ? '' : b.kind;
                      this.apply();
                    })
                    .focusable(true)
                    .focusBox(focusRing())
                    .accessibilityText(`${b.kind}，${b.relicCount} 件，${this.material === b.kind ? '已选中' : '未选中'}`)
                    .accessibilityLevel('yes')
                    .accessibilitySelected(this.material === b.kind)
                  }
                }, (b: MaterialBucket) => b.kind)
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 4, bottom: 12 })
            .border({ width: { bottom: HAIR }, color: LINE_HAIR })
          }
        }
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .padding({ top: 4, bottom: 10 })

      // 折叠态显示：清空筛选 / 更多筛选
      Row({ space: 8 }) {
        PressFade() {
          Text(this.showFilters ? '收起' : '更多筛选')
            .fontSize(FS_CAPTION)
            .fontColor(SUB)
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 4, bottom: 8 })
            .onClick(() => {
              this.showFilters = !this.showFilters;
            })
            .focusable(true)
            .focusBox(focusRing())
        }
        if (this.city !== '' || this.siteType !== '' || this.material !== '') {
          PressFade() {
            Text('清空筛选')
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
              .padding({ right: PAGE_PAD_X, top: 4, bottom: 8 })
              .onClick(() => {
                this.city = '';
                this.siteType = '';
                this.material = '';
                this.apply();
              })
              .focusable(true)
              .focusBox(focusRing())
          }
        }
      }
      .width('100%')

      // Section Header（设计稿②）：区块标题 + 计数
      Row({ space: 0 }) {
        Text('入选遗址')
          .fontSize(FS_HEAD)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(INK)
        Blank()
        Text(`${this.sites.length} 处 · ${this.era === '' ? '全部' : eraName(this.era) + '层'}`)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SERIF)
          .fontColor(SUB)
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 12, bottom: 12 })

      if (this.sites.length === 0) {
        // 空态：层色点 + 一句话（设计稿②「土里没翻到」）
        Column({ space: 10 }) {
          Row()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(this.era === '' ? INK : eraColor(this.era))
          Text('土里没翻到。')
            .fontSize(FS_TITLE)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(INK)
          Text('放宽一级筛选，再往下挖')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontColor(SUB)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 32, right: 32 })
      } else {
        // 列表：白卡 + 阴影 + 发丝（设计稿②制式）
        List() {
          ForEach(this.sites, (s: SiteInfo, idx: number) => {
            ListItem() {
              RevealOnScroll() {
                // 不用 PressScale 包装器：这一行 width('100%') 且内含
                // layoutWeight(1)，套进包装器后百分比按包装器算、权重
                // 分配也落在包装器里，封面列会被压扁。按压态就地写。
                Row({ space: ITEM_GAP }) {
                  // 封面位：实拍走图，无实拍走层色整块 +「图像整备中」
                  if (firstRealImage(s.images) !== '' && this.failedThumbs.indexOf(s.id) < 0) {
                    Image($rawfile(firstRealImage(s.images)))
                      .width(96)
                      .height(64)
                      .objectFit(ImageFit.Cover)
                      .draggable(false)
                      .borderRadius(RADIUS_SM)
                      .onError(() => {
                        this.failedThumbs = this.failedThumbs.concat([s.id]);
                      })
                  } else {
                    Stack({ alignContent: Alignment.Center }) {
                      Row()
                        .width(96)
                        .height(64)
                        .backgroundColor(eraColor(s.era))
                        .borderRadius(RADIUS_SM)
                      Text('图像整备中')
                        .fontSize(FS_MICRO)
                        .letterSpacing(1)
                        .fontColor(SURFACE_CARD)
                        .opacity(0.85)
                    }
                  }
                  Column({ space: 4 }) {
                    Text(s.name)
                      .fontSize(FS_ITEM)
                      .fontFamily(FONT_DISPLAY)
                      .fontWeight(WT_DISPLAY)
                      .fontColor(INK)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${eraName(s.era)} · ${cityName(s.city)} · ${typeName(s.siteType)}`)
                      .fontSize(FS_CAPTION)
                      .fontFamily(FONT_SERIF)
                      .fontColor(SUB)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    // 双实体（A 方案）：这一行还挂着几件文物。
                    // 文物的年代可能与遗址不同（巩义窑址出唐三彩），
                    // 故这里只报件数、不报年代，避免同屏出现两个年代。
                    if (s.relics.length > 0) {
                      Text(`${s.relics.length} 件文物`)
                        .fontSize(FS_TAB)
                        .fontFamily(FONT_MONO)
                        .fontColor(SUB)
                    }
                    // 层号章：白底 + 层色点 + 发丝（设计稿②的 Layer Badge）
                    // 标签格式「遗址 · 距今 XXXX 年」——从年代跨度取起始年，
                    // 与 Index 年代卡副题同源，不另造数据。
                    LayerBadge({
                      layerCode: this.layerCodeOf(s),
                      era: s.era,
                      eraLabel: '遗址 · ' + this.eraSpanShort(s.era)
                    })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                  Text(idx < 9 ? `0${idx + 1}` : `${idx + 1}`)
                    .fontSize(FS_CAPTION)
                    .fontFamily(FONT_MONO)
                    .fontColor(SUB)
                    .margin({ right: 4 })
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
                .padding(CARD_PAD)
                .backgroundColor(SURFACE_CARD)
                .borderRadius(RADIUS_MD)
                .border({ width: HAIR, color: LINE_HAIR })
                .shadow({
                  radius: SHADOW_CARD_RADIUS,
                  color: SHADOW_CARD_COLOR_LIGHT,
                  offsetX: 0,
                  offsetY: SHADOW_CARD_OFFSET
                })
                .onClick(() => {
                  const prm: Record<string, string> = { 'id': s.id };
                  router.pushUrl({ url: 'pages/DetailPage', params: prm });
                })
                .onTouch((e: TouchEvent) => {
                  if (e.type === TouchType.Down) {
                    this.pressedSite = s.id;
                  } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
                    this.pressedSite = '';
                  }
                })
                .scale({ x: this.pressedSite === s.id ? PRESS_SCALE : 1, y: this.pressedSite === s.id ? PRESS_SCALE : 1 })
                .animation(pressAnim())
                .focusable(true)
                .focusBox(focusRing())
                // 一行里有期名 / 城市 / 类型 / 序号四段碎文字，读屏逐段念完
                // 才到得下一点。合并成一句，摘要留给 hint。
                .accessibilityText(`${s.name}，${eraName(s.era)}，${cityName(s.city)}，${typeName(s.siteType)}`)
                .accessibilityLevel('yes')
                .accessibilityTextHint(s.summary)
              }
            }
            .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: ITEM_GAP })
          }, (s: SiteInfo) => s.id)        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .width('100%')
        .clip(true)
      }

      // 子页不挂底栏：ListPage 是 push 进来的，返回键回到来源页。
      // 之前挂 AppNavBar(active:0) 造成双导航语法——点「年代」清栈，
      // 顶栏「返回」又退回来源，两个入口语义互相矛盾。
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }

  // 遗址的层号：取年代序 + 1（与 Index 的 L1–L6 同一口径）。
  // 站点级没有独立层号字段，年代序就是它在剖面里的位置。
  layerCodeOf(s: SiteInfo): string {
    const i = ERAS.indexOf(s.era);
    return i >= 0 ? `L${i + 1}` : '';
  }

  // 年代起始年短格式：「约前5000 — 前3000」→「6000 年」。
  // 设计稿②的 Layer Badge 标签用「遗址 · 距今 6000 年」，
  // 取跨度串里第一个数字（起始年）。
  eraSpanShort(era: string): string {
    const full: string = eraSpan(era);
    if (full === '') { return ''; }
    const m = full.match(/(\d+)/);
    if (m === null) { return ''; }
    return `距今 ${m[1]} 年`;
  }
}
