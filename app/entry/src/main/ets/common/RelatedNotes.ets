// common/RelatedNotes.ets —— 详情页/文物页的「相关笔记」
//
// 为什么是自取数的组件而不是父页面传数组：
//   详情页与文物页都要这块，两页的数据加载链已经很长；把「读笔记 + 挑三条」
//   收在组件里，父页面只给一个 targetKey。父页面在 onPageShow 里递增 epoch，
//   组件用 @Watch 重读——用户刚在里面写完笔记返回时，这里不该还是旧内容。
//
// 为什么每行都要写理由：同一个词条下的笔记与「共享标签」的笔记，对用户的
// 意义完全不同。只把三条正文排在一起，用户会以为是随机推荐。
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';
import { NoteView } from '../model/UserDataModels';
import { UserDataRepo } from '../repository/UserDataRepo';
import { isSameTarget, relatedNotes, sameTargetTags } from '../service/notes/NoteReview';
import {
  ACCENT, FONT_DISPLAY, FONT_SERIF, FS_BODY, FS_CAPTION, FS_TITLE, INK, ITEM_GAP,
  LH_BODY, LINE_HAIR, ON_DARK_GOLD, ON_DARK_LINE, ON_DARK_RAISED, ON_DARK_SUB,
  ON_DARK_TEXT, ON_DARK_TEXT_ALT, PAGE_PAD_X, PRESS_OPACITY, RADIUS_CARD_LG, SUB,
  SURFACE_CARD, WT_DISPLAY
} from './DesignTokens';
import { stamp } from './Time';
import { focusRing } from './Accessibility';
import { pressAnim } from './Motion';

const MAX_RELATED: number = 3;

class RelNoteRow {
  noteId: string = '';
  text: string = '';
  targetKey: string = '';
  time: number = 0;
  reason: string = '';
  same: boolean = false;
}

@Component
export struct RelatedNotes {
  @Prop targetKey: string = '';
  @Prop selfTitle: string = '';
  @Prop dark: boolean = false;
  // 父页面自己已经留了左右边距时要传 false，否则卡片会被挤成两倍边距。
  // 详情页的直接父级是整页滚动的根列（无内边距）→ true；
  // 文物页的父级内容列已有 PAGE_PAD_X → false。
  @Prop padX: boolean = true;
  @Prop @Watch('onEpoch') epoch: number = 0;
  @State rows: RelNoteRow[] = [];
  @State pressed: string = '';

  aboutToAppear(): void {
    this.load();
  }

  onEpoch(): void {
    this.load();
  }

  private load(): void {
    if (this.targetKey === '') { return; }
    const host = this.getUIContext().getHostContext();
    if (host === undefined) { return; }
    const ctx = host as common.UIAbilityContext;
    UserDataRepo.allNotes(ctx).then((list: NoteView[]) => {
      this.buildRows(list);
    }).catch((_e: Object) => {
      this.rows = [];
    });
  }

  private buildRows(list: NoteView[]): void {
    const shared: string[] = sameTargetTags(list, this.targetKey);
    const picked: NoteView[] = relatedNotes(list, this.targetKey, MAX_RELATED);
    const out: RelNoteRow[] = [];
    for (const n of picked) {
      const row = new RelNoteRow();
      row.noteId = n.noteId;
      row.text = n.text;
      row.targetKey = n.targetKey;
      row.time = n.updateTime;
      row.same = isSameTarget(n.targetKey, this.targetKey);
      // 同一处遗址的笔记不写遗址名：那是页面标题，重复一遍只是噪音。
      if (row.same) {
        row.reason = '本页笔记';
      } else {
        let tag: string = '';
        for (const t of n.tagIds) {
          if (shared.indexOf(t) >= 0) { tag = t; break; }
        }
        row.reason = tag === '' ? '其他笔记' : `同标签 · ${tag}`;
      }
      out.push(row);
    }
    this.rows = out;
  }

  private openRow(r: RelNoteRow): void {
    const prm: Record<string, string> = {
      'target': r.targetKey,
      'title': r.same && this.selfTitle !== '' ? this.selfTitle : '相关笔记'
    };
    router.pushUrl({ url: 'pages/NotePage', params: prm });
  }

  private cardBg(): string {
    return this.dark ? ON_DARK_RAISED : SURFACE_CARD;
  }

  private titleColor(): string {
    return this.dark ? ON_DARK_TEXT : INK;
  }

  private subColor(): string {
    return this.dark ? ON_DARK_SUB : SUB;
  }

  private bodyColor(): string {
    return this.dark ? ON_DARK_TEXT_ALT : INK;
  }

  private reasonColor(): string {
    return this.dark ? ON_DARK_GOLD : ACCENT;
  }

  private lineColor(): string {
    return this.dark ? ON_DARK_LINE : LINE_HAIR;
  }

  @Builder
  noteRow(r: RelNoteRow) {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        Text(r.reason)
          .fontSize(FS_CAPTION)
          .fontColor(this.reasonColor())
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(stamp(r.time))
          .fontSize(FS_CAPTION)
          .fontColor(this.subColor())
      }
      .width('100%')

      Text(r.text)
        .fontSize(FS_BODY)
        .fontFamily(FONT_SERIF)
        .lineHeight(LH_BODY)
        .fontColor(this.bodyColor())
        .width('100%')
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(16)
    .backgroundColor(this.cardBg())
    .border({ width: { left: 3 }, color: this.lineColor() })
    .borderRadius(RADIUS_CARD_LG)
    .margin({ bottom: 12 })
    .onClick(() => {
      this.openRow(r);
    })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.pressed = r.noteId;
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.pressed = '';
      }
    })
    .opacity(this.pressed === r.noteId ? PRESS_OPACITY : 1)
    .animation(pressAnim())
    .focusable(true)
    .focusBox(focusRing())
    .accessibilityText(`${r.reason}，${r.text}`)
  }

  build() {
    Column({ space: ITEM_GAP }) {
      if (this.rows.length > 0) {
        Column({ space: 4 }) {
          Text('相关笔记')
            .fontSize(FS_TITLE)
            .fontFamily(FONT_DISPLAY)
            .fontWeight(WT_DISPLAY)
            .fontColor(this.titleColor())
          Text('你自己的笔记里，同一处遗址的排前面，其次是共享标签的。')
            .fontSize(FS_CAPTION)
            .fontFamily(FONT_SERIF)
            .fontColor(this.subColor())
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Column() {
          ForEach(this.rows, (r: RelNoteRow) => {
            this.noteRow(r)
          }, (r: RelNoteRow) => `${r.noteId}:${r.time}`)
        }
        .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: this.padX ? PAGE_PAD_X : 0, right: this.padX ? PAGE_PAD_X : 0 })
  }
}
