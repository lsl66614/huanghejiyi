// entry/src/main/ets/common/IconMenu.ets
// 图标按钮 + 弹出菜单：把「换一种排法 / 看哪一类」这类切换收进一枚图标。
//
// 为什么需要（spec §3.8 的 L1–L4 切换器分层）：
// 档案页每个分段原先挤 3 排胶囊——页签行、视图切换行、数据筛选行。
// 页签已改成下划线制式，剩下两排都是「黑底/白底圆角胶囊」，
// 用户的读法是「一排排胶囊」，分不出哪排管什么。
// spec 的规矩是 L3（数据筛选）用胶囊、L4（视图切换）必须与 L3 分开，
// 而胶囊和胶囊分不开。于是把 L4 收进一枚图标按钮：
//   · 页面上少一排圆角控件，筛选胶囊仍是唯一的胶囊层；
//   · 视图切换的选项变少（2–4 项），放进菜单反而比横排更省地方；
//   · 菜单项是文字，语义比两个并排胶囊清楚。
//
// 为什么不用 IconButton：IconButton 自带 onClick，点击会先把事件吃掉，
// bindMenu 就不触发了。本件自己画按钮并只绑菜单，不设 onClick。
//
// SDK 事实：bindMenu 的元素类型是 MenuElement（不是 MenuItem），
// 字段为 value / icon / symbolIcon / enabled / action，见
// ets/build-tools/ets-loader/declarations/common.d.ts 的 MenuElement。
import {
  CHIP_H, CHIP_RADIUS, FONT_SANS, FS_CAPTION, FS_TITLE, HAIR, INK, LINE_HAIR,
  NAV_ICON_BTN_H, NAV_ICON_BTN_RADIUS, ROW_GAP, SUB, SURFACE_CARD, WT_BOLD
} from './DesignTokens';
import { focusRing } from './Accessibility';

// 菜单项。key 是内部标识，label 是屏上文字。
export class MenuEntry {
  key: string = '';
  label: string = '';
}

@Component
export struct IconMenu {
  // 按钮上的字形（用文字符号，不用 svg：这类符号没有现成图标资源）
  @Prop glyph: string = '';
  // 无障碍名称，必须说明「这是切换 + 当前选中什么」
  @Prop label: string = '';
  @Prop items: MenuEntry[] = [];
  // 当前选中项的 key：菜单里给它加 ✓。
  // 为什么必须有：图标按钮本身看不出选中哪一项（范围切换的字形是固定的），
  // 菜单打开后若四项长得一样，用户不知道现在生效的是哪一条。
  @Prop selected: string = '';
  // text 非空 = 文字档：画一枚「当前值 + ⌄」的下拉胶囊，而不是圆形图标。
  // 为什么要这一档：圆形图标本身不携带任何信息，收进去之后页面上只剩
  // 「眉标 + 一个空圆圈」，那一行等于白占——实测笔记页的「范围 ☰」行
  // 就是这个样子。文字档把当前值摆到按钮上（档案页的身份胶囊「设备 A ⌄」
  // 早就是这个制式），一行才真正说出「现在是哪一类」。
  @Prop text: string = '';
  onPick: (key: string) => void = () => {};

  private menuElements(): MenuElement[] {
    const out: MenuElement[] = [];
    for (const e of this.items) {
      out.push({
        value: this.selected === e.key ? `✓ ${e.label}` : e.label,
        action: (): void => {
          this.onPick(e.key);
        }
      });
    }
    return out;
  }

  build() {
    if (this.text !== '') {
      Row({ space: ROW_GAP }) {
        Text(this.text)
          .fontSize(FS_CAPTION)
          .fontFamily(FONT_SANS)
          .fontWeight(WT_BOLD)
          .fontColor(INK)
        Text('⌄')
          .fontSize(FS_CAPTION)
          .fontColor(SUB)
      }
      .height(CHIP_H)
      .padding({ left: 12, right: 10 })
      .backgroundColor(SURFACE_CARD)
      .border({ width: HAIR, color: LINE_HAIR })
      .borderRadius(CHIP_RADIUS)
      .justifyContent(FlexAlign.Center)
      .bindMenu(this.menuElements())
      .focusable(true)
      .focusBox(focusRing())
      .accessibilityText(this.label)
      .accessibilityLevel('yes')
    } else {
      Column() {
        Text(this.glyph)
          .fontSize(FS_TITLE)
          .fontColor(INK)
      }
      .width(NAV_ICON_BTN_H)
      .height(NAV_ICON_BTN_H)
      .borderRadius(NAV_ICON_BTN_RADIUS)
      .backgroundColor(SURFACE_CARD)
      .border({ width: HAIR, color: LINE_HAIR })
      .justifyContent(FlexAlign.Center)
      .bindMenu(this.menuElements())
      .focusable(true)
      .focusBox(focusRing())
      .accessibilityText(this.label)
      .accessibilityLevel('yes')
    }
  }
}
