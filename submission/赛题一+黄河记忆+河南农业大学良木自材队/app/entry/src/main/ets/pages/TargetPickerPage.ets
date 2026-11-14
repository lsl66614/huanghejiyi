// entry/src/main/ets/pages/TargetPickerPage.ets —— 把一条笔记关联到遗址 / 文物
//
// 只改 note.target_key，不改正文、不改 note_id、不重写 note_tag。
// 因此同步时仍是同一行收敛，不会因为“换了个挂靠对象”多出一条笔记。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import type { SiteInfo } from '../model/ContentModels';
import { ContentRepo } from '../repository/ContentRepo';
import { UserDataRepo } from '../repository/UserDataRepo';
import { THEME_BG, eraName } from '../common/EraTheme';
import { cityName } from '../common/Labels';
import {
  ACCENT, CHIP_RADIUS, FONT_DISPLAY, FONT_SERIF, FS_BODY, FS_CAPTION, FS_ITEM,
  FS_TITLE, HAIR, INK, LINE_HAIR, PAGE_PAD_X, RADIUS_CARD_LG, ROUTE_FADE_MIN,
  ROUTE_SHIFT_VP, SUB, SURFACE_CARD, SURFACE_RAISED, WT_DISPLAY
} from '../common/DesignTokens';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut } from '../common/Motion';
import { PressFade } from '../common/PressScale';

class PickItem {
  key: string = '';
  label: string = '';
  sub: string = '';
  kind: string = '';
}

@Entry
@Component
struct TargetPickerPage {
  @State items: PickItem[] = [];
  @State shown: PickItem[] = [];
  @State keyword: string = '';
  @State currentKey: string = '';
  @State currentTitle: string = '';
  @State noteId: string = '';
  @State loading: boolean = true;
  @State failed: boolean = false;
  @State hint: string = '';
  @State pressedKey: string = '';

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
    this.noteId = p !== undefined ? (p['noteId'] ?? '') : '';
    this.currentKey = p !== undefined ? (p['target'] ?? '') : '';
    this.currentTitle = p !== undefined ? (p['title'] ?? '') : '';
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.load(ctx);
  }

  load(ctx: common.UIAbilityContext): void {
    this.loading = true;
    this.failed = false;
    ContentRepo.load(ctx).then((sites: SiteInfo[]) => {
      const out: PickItem[] = [];
      const inbox = new PickItem();
      inbox.key = 'notebook:inbox';
      inbox.label = '随手笔记';
      inbox.sub = '不挂靠任何遗址或文物';
      inbox.kind = '收件箱';
      out.push(inbox);
      for (const s of sites) {
        const site = new PickItem();
        site.key = `site:${s.id}`;
        site.label = s.name;
        site.sub = `${eraName(s.era)} · ${cityName(s.city)}`;
        site.kind = '遗址';
        out.push(site);
        for (const r of s.relics) {
          const relic = new PickItem();
          relic.key = `relic:${r.id}`;
          relic.label = r.name;
          relic.sub = `${s.name} · ${eraName(r.era)}`;
          relic.kind = '文物';
          out.push(relic);
        }
      }
      this.items = out;
      this.loading = false;
      this.apply();
    }).catch((_e: Object) => {
      this.loading = false;
      this.failed = true;
    });
  }

  apply(): void {
    const kw = this.keyword.trim().toLowerCase();
    if (kw === '') {
      this.shown = this.items;
      return;
    }
    const out: PickItem[] = [];
    for (const it of this.items) {
      if (it.label.toLowerCase().includes(kw) || it.sub.toLowerCase().includes(kw) ||
        it.kind.toLowerCase().includes(kw)) {
        out.push(it);
      }
    }
    this.shown = out;
  }

  pick(it: PickItem): void {
    if (this.noteId === '' || it.key === this.currentKey) {
      router.back();
      return;
    }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.hint = '';
    UserDataRepo.moveNote(ctx, this.noteId, it.key).then(() => {
      router.back();
    }).catch((_e: Object) => {
      this.hint = '关联失败，请重试';
    });
  }

  @Builder
  pickRow(it: PickItem) {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(it.label)
          .fontSize(FS_ITEM)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(it.sub)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SERIF)
          .fontColor(SUB)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (it.key === this.currentKey) {
        Text('当前')
          .fontSize(FS_CAPTION)
          .fontColor(ACCENT)
      } else {
        Text(it.kind)
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.pressedKey === it.key ? SURFACE_RAISED : SURFACE_CARD)
    .border({ width: 1, color: it.key === this.currentKey ? ACCENT : LINE_HAIR })
    .borderRadius(RADIUS_CARD_LG)
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressedKey = it.key;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedKey = '';
      }
    })
    .onClick(() => {
      this.pick(it);
    })
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`${it.kind}，${it.label}${it.key === this.currentKey ? '，当前关联' : ''}`)
    .accessibilitySelected(it.key === this.currentKey)
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        PressFade() {
          Text('‹ 取消')
            .fontSize(FS_CAPTION)
            .fontColor(INK)
            .accessibilityText('取消关联，返回笔记列表')
            .onClick(() => {
              router.back();
            })
            .focusable(true)
            .focusBox(focusRing())
        }
        Blank()
        Text('关联到')
          .fontSize(FS_TITLE)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(INK)
        Blank()
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 12 })

      Text(this.currentTitle === '' ? '当前：未关联' : `当前：${this.currentTitle}`)
        .fontSize(FS_CAPTION)
        .fontColor(SUB)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 4 })

      Text('换挂靠对象只改归属，笔记正文、标签和时间都不变。')
        .fontSize(FS_CAPTION)
        .fontFamily(FONT_SERIF)
        .fontColor(SUB)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 10 })

      if (this.hint !== '') {
        Text(this.hint)
          .fontSize(FS_CAPTION)
          .fontColor(ACCENT)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 6 })
      }

      TextInput({ text: this.keyword, placeholder: '搜遗址名、文物名或城市' })
        .accessibilityText('搜索关联对象：遗址、文物或城市')
        .fontSize(FS_BODY)
        .fontColor(INK)
        .placeholderColor(SUB)
        .backgroundColor(Color.Transparent)
        .border({ width: { bottom: HAIR }, color: { bottom: LINE_HAIR }, style: BorderStyle.Solid })
        .height(40)
        .margin({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 10 })
        .onChange((v: string) => {
          this.keyword = v;
          this.apply();
        })

      if (this.loading) {
        Text('正在读取遗址与文物…')
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 32 })
      } else if (this.failed) {
        Column({ space: 10 }) {
          Text('语料没能读出来')
            .fontSize(FS_ITEM)
            .fontFamily(FONT_DISPLAY)
            .fontColor(INK)
          Text('先返回笔记列表；稍后重试仍可关联。')
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
                const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
                this.load(ctx);
              })
              .focusable(true)
              .focusBox(focusRing())
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 32 })
      } else {
        Text(`共 ${this.shown.length} 个可选条目`)
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
          .width('100%')
          .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 8 })

        List({ space: 8 }) {
          ForEach(this.shown, (it: PickItem) => {
            ListItem() {
              this.pickRow(it)
            }
          }, (it: PickItem) => it.key)
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, bottom: 24 })
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(THEME_BG)
  }
}
