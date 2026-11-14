// entry/src/main/ets/pages/NotePage.ets —— P6 笔记编辑器（风格A 纸墨语言）
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import type { NoteView } from '../model/UserDataModels';
import { UserDataRepo } from '../repository/UserDataRepo';
import { BackLink } from '../common/BackLink';
import { THEME_BG } from '../common/EraTheme';
import { ACCENT, CAPSULE_H, CAPSULE_RADIUS, CARD_PAD, CHIP_H, CHIP_RADIUS, FONT_DISPLAY, FONT_MONO, FONT_SERIF, FS_BODY, FS_CAPTION, FS_ITEM, FS_PAGE, FS_TITLE, HAIR, INK, ITEM_GAP, LH_BODY, LINE_HAIR, PAGE_PAD_X, PRESS_SCALE, RADIUS_CARD_LG, RADIUS_SM, ROUTE_FADE_MIN, ROUTE_SHIFT_VP, SHADOW_CARD_COLOR_LIGHT, SHADOW_CARD_OFFSET, SHADOW_CARD_RADIUS, SUB, SURFACE_CARD, SURFACE_RAISED, WT_BOLD, WT_DISPLAY } from '../common/DesignTokens';
import { stamp } from '../common/Time';
import { focusRing } from '../common/Accessibility';
import { curveIn, curveOut, durRouteIn, durRouteOut } from '../common/Motion';
import { PressFade, PressScale } from '../common/PressScale';
import { pressAnim } from '../common/Motion';

@Entry
@Component
struct NotePage {
  @State targetKey: string = '';
  @State title: string = '';
  @State notes: NoteView[] = [];
  @State tagPool: string[] = [];
  @State picked: string[] = [];
  // 按下的笔记 id：@Builder 产物是独立子树，按压态只能记在页面上。
  @State pressedNote: string = '';
  @State draft: string = '';
  @State editingId: string = '';
  @State editingCreated: number = 0;
  @State newTag: string = '';
  @State savedAt: number = 0;
  @State hint: string = '';

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
    const tgt: string = p !== undefined ? (p['target'] ?? '') : '';
    const ttl: string = p !== undefined ? (p['title'] ?? '') : '';
    this.targetKey = tgt;
    this.title = ttl;
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.reload(ctx);
  }

  reload(ctx: common.UIAbilityContext): void {
    UserDataRepo.notesOf(ctx, this.targetKey).then((list: NoteView[]) => {
      this.notes = list;
    });
    UserDataRepo.allTags(ctx).then((t: string[]) => {
      this.tagPool = t;
    });
  }

  isPicked(t: string): boolean {
    return this.picked.includes(t);
  }

  toggleTag(t: string): void {
    const next: string[] = this.picked.slice();
    const i = next.indexOf(t);
    if (i >= 0) {
      next.splice(i, 1);
    } else {
      next.push(t);
    }
    this.picked = next;
  }

  addTag(): void {
    const t = this.newTag.trim();
    if (t === '') { return; }
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!this.tagPool.includes(t)) {
      this.tagPool = this.tagPool.concat([t]);
    }
    if (!this.isPicked(t)) {
      this.toggleTag(t);
    }
    this.newTag = '';
    UserDataRepo.ensureTag(ctx, t).then(() => {
      this.reload(ctx);
    });
  }

  editNote(n: NoteView): void {
    this.editingId = n.noteId;
    this.editingCreated = n.createTime;
    this.draft = n.text;
    this.picked = n.tagIds.slice();
    this.hint = '';
  }

  resetDraft(): void {
    this.editingId = '';
    this.editingCreated = 0;
    this.draft = '';
    this.picked = [];
  }

  saveNote(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const body = this.draft.trim();
    if (body === '') {
      this.hint = '正文为空，先写点什么。';
      return;
    }
    const id = this.editingId;
    const tags = this.picked.slice();
    UserDataRepo.saveNote(ctx, this.targetKey, body, tags, id).then((_v: string): void => {
      this.savedAt = Date.now();
      this.hint = `${id === '' ? '已新建' : '已改写'} · ${stamp(this.savedAt)}`;
      this.resetDraft();
      this.reload(ctx);
    });
  }

  removeNote(n: NoteView): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    UserDataRepo.removeNote(ctx, n.noteId).then(() => {
      if (this.editingId === n.noteId) {
        this.resetDraft();
      }
      this.reload(ctx);
    });
  }

  insertStamp(): void {
    const line = `[${stamp(Date.now())}]`;
    this.draft = this.draft === '' ? `${line} ` : `${this.draft}\n${line} `;
  }

  @Builder
  cellHead(label: string) {
    Row({ space: 10 }) {
      Text(label)
        .fontSize(FS_CAPTION)
        .letterSpacing(3)
        .fontColor(SUB)
      Row()
        .layoutWeight(1)
        .height(1)
        .backgroundColor(LINE_HAIR)
    }
    .width('100%')
    .margin({ top: 24, bottom: 12 })
  }

  @Builder
  noteCard(n: NoteView) {
    Column({ space: 10 }) {
      Text(n.text)
        .fontSize(FS_BODY)
        .fontFamily(FONT_SERIF)
        .lineHeight(LH_BODY)
        .fontColor(INK)
        .width('100%')
        .maxLines(5)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
        Text(n.tagIds.length === 0 ? '未分类' : n.tagIds.join(' / '))
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
        Blank()
        Text(stamp(n.updateTime))
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
          .margin({ left: 10 })
        Text('改写')
          .fontSize(FS_CAPTION)
          .fontColor(ACCENT)
          .margin({ left: 12 })
        PressFade() {
          Text('删除')
            .fontSize(FS_CAPTION)
            .fontColor(SUB)
            .margin({ left: 12 })
            .accessibilityText('删除这条笔记')
            .onClick(() => {
              this.removeNote(n);
            })
            .focusable(true)
            .focusBox(focusRing())
        }
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(this.editingId === n.noteId ? SURFACE_RAISED : SURFACE_RAISED)
    .border({ width: { left: 3 }, color: this.editingId === n.noteId ? ACCENT : LINE_HAIR })
    .margin({ bottom: 12 })
    .onClick(() => {
      this.editNote(n);
    })
    // 按压态记在页面上：@Builder 产物是独立子树，包装器套不到卡片自身。
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressedNote = n.noteId;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressedNote = '';
      }
    })
    .scale({ x: this.pressedNote === n.noteId ? PRESS_SCALE : 1, y: this.pressedNote === n.noteId ? PRESS_SCALE : 1 })
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        BackLink()
        Blank()
        Text(this.title === '' ? '笔记' : this.title)
          .fontSize(FS_TITLE)
          .fontFamily(FONT_DISPLAY)
          .fontWeight(WT_DISPLAY)
          .fontColor(INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        // 保存胶囊：ACCENT 底 + 白字（设计稿⑤「存档」制式）
        PressScale() {
          Text('存档')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .letterSpacing(2)
            .fontColor(SURFACE_CARD)
            .height(36)
            .padding({ left: 16, right: 16 })
            .backgroundColor(ACCENT)
            .borderRadius(CHIP_RADIUS)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.saveNote();
            })
            .focusable(true)
            .focusBox(focusRing())
            .accessibilityText('保存笔记')
        }
      }
      .width('100%')
      .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 16, bottom: 16 })

      Text(`本机档案   |   最近保存 ${stamp(this.savedAt)}`)
        .fontSize(FS_CAPTION)
        .letterSpacing(1)
        .fontColor(SUB)
        .width('100%')
        .padding({ left: PAGE_PAD_X, right: PAGE_PAD_X, top: 8, bottom: 8 })
        .backgroundColor(SURFACE_RAISED)

      Scroll() {
        Column() {
          this.cellHead(this.notes.length === 0 ? '尚无笔记' : `已有笔记 ${this.notes.length} 条`)
          ForEach(this.notes, (n: NoteView) => {
            this.noteCard(n)
          }, (n: NoteView) => `${n.noteId}:${n.updateTime}`)

          this.cellHead(this.editingId === '' ? '新建笔记' : '改写中')
          if (this.editingId !== '') {
            Text(`建档 ${stamp(this.editingCreated)} · 挂载 ${this.targetKey}`)
              .fontSize(FS_CAPTION)
              .letterSpacing(1)
              .fontColor(SUB)
              .width('100%')
              .margin({ bottom: 10 })
          }

          TextArea({ text: this.draft, placeholder: '随手记下考据、疑问或现场感受……' })
            .accessibilityText(`笔记正文，${this.draft.length} 字`)
            .fontSize(FS_BODY)
            .lineHeight(LH_BODY)
            .fontColor(INK)
            .placeholderColor(SUB)
            .backgroundColor(Color.Transparent)
            .border({ width: { bottom: HAIR }, color: { bottom: LINE_HAIR }, style: BorderStyle.Solid })
            .height(180)
            .padding(CARD_PAD)
            .onChange((v: string) => {
              this.draft = v;
            })

          Row() {
            Text(`${this.draft.length} 字`)
              .fontSize(FS_CAPTION)
              .fontColor(SUB)
            Blank()
            PressFade() {
              Text('＋ 插入当前时间戳')
                .fontSize(FS_CAPTION)
                .fontColor(ACCENT)
                .accessibilityText('在正文末尾插入当前时间戳')
                .onClick(() => {
                  this.insertStamp();
                })
                .focusable(true)
                .focusBox(focusRing())
            }
          }
          .width('100%')
          .margin({ top: 8 })

          this.cellHead('标签')
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.tagPool, (t: string) => {
              PressScale() {
                Text(t)
                  .fontSize(FS_CAPTION)
                  .fontColor(this.isPicked(t) ? SURFACE_CARD : SUB)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .backgroundColor(this.isPicked(t) ? ACCENT : Color.Transparent)
                  // 未选中走发丝、选中才上 ACCENT（清单 §1.1）
                  .border({
                    width: HAIR,
                    color: this.isPicked(t) ? ACCENT : LINE_HAIR
                  })
                  .borderRadius(CHIP_RADIUS)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.toggleTag(t);
                  })
                  .focusable(true)
                  .focusBox(focusRing())
              }
            }, (t: string) => t)
          }
          .width('100%')

          Row({ space: 10 }) {
            TextInput({ text: this.newTag, placeholder: '自建标签，如 彩陶 / 都邑' })
              .accessibilityText('自建标签名称')
              .fontSize(FS_CAPTION)
              .fontColor(INK)
              .placeholderColor(SUB)
              .backgroundColor(Color.Transparent)
              .border({ width: { bottom: HAIR }, color: { bottom: LINE_HAIR }, style: BorderStyle.Solid })
              .height(38)
              .layoutWeight(1)
              .onChange((v: string) => {
                this.newTag = v;
              })
            PressScale() {
              Text('添加')
                .fontSize(FS_CAPTION)
                .fontColor(SURFACE_CARD)
                .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                .backgroundColor(ACCENT)
                .borderRadius(CHIP_RADIUS)
                .onClick(() => {
                  this.addTag();
                })
                .focusable(true)
                .focusBox(focusRing())
            }
          }
          .width('100%')
          .margin({ top: 12 })

          if (this.hint !== '') {
            Text(this.hint)
              .fontSize(FS_CAPTION)
              .letterSpacing(1)
              .fontColor(ACCENT)
              .width('100%')
              .margin({ top: 16 })
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

