# 补齐 pptx 主题的东亚/复杂文本字体槽位（幂等）。
#
# 为什么单独一步：pptxgenjs 只写 latin 槽，主题里 `<a:ea typeface=""/>` 留空，
# 母版又是用 `+mn-ea` / `+mj-ea` 引用的——空槽等于「中文不指定字体」，
# 对方 Office 会按自己的默认 CJK 字体渲染（这台机器上常见是宋体），
# 行宽与换行点随之改变，本地量好的版式到演实现场就不可复现。
#
# 只替换空槽，不动 `typeface="+mn-ea"` 这类引用，也不动别的部件。
# 用法：python -I tools/pptx_ea_font.py <deck.pptx> [字体名]
import io
import re
import sys
import zipfile

TARGET = "ppt/theme/theme1.xml"
# 空槽的字面形态就是 typeface="" —— 只认这一种，不碰 +mn-ea 这类引用。
EMPTY = re.compile(r'<a:(ea|cs) typeface=""')


def main():
    src = sys.argv[1]
    font = sys.argv[2] if len(sys.argv) > 2 else "Microsoft YaHei"
    # 第三个参数：期望的 accent1 色值。applyTheme 失败时它会 throw 且
    # "Nothing was changed"，但 writeFile 早已把**未上色**的 pptx 留在盘上——
    # 谁不看退出码（管道给 head 就是典型）就会把 Office 默认主题的稿交出去。
    # 所以在唯一的复验点顺手确认主题真的写进去了。
    expect_accent = sys.argv[3] if len(sys.argv) > 3 else ""
    with zipfile.ZipFile(src) as z:
        items = [(i.filename, z.read(i.filename)) for i in z.infolist()]
        theme = next((d for nm, d in items if nm == TARGET), None)
        if theme is None:
            sys.exit("找不到 %s（不是标准 pptx？）" % TARGET)
        txt = theme.decode("utf-8")
        before = len(EMPTY.findall(txt))
        new_txt, n = EMPTY.subn(lambda m: '<a:%s typeface="%s"' % (m.group(1), font), txt)
        if n:
            buf = io.BytesIO()
            with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as out:
                for nm, data in items:
                    out.writestr(nm, new_txt.encode("utf-8") if nm == TARGET else data)
            with open(src, "wb") as f:
                f.write(buf.getvalue())
        # 写完必须复验：上一版这里因为正则写错，改了 0 处却打印「幂等通过」，
        # 报的是假阴性。现在读回文件确认空槽真的没了，否则直接失败退出。
        with zipfile.ZipFile(src) as z2:
            theme_after = z2.read(TARGET).decode("utf-8")
            left = len(EMPTY.findall(theme_after))
        if expect_accent and ('VAL="%s"' % expect_accent.upper()) not in theme_after.upper():
            sys.exit("复验失败：theme1.xml 里没有 accent1 %s，说明 applyTheme 没生效，"
                     "这份 pptx 还是 Office 默认配色——不能拿去交付" % expect_accent)
        if left:
            sys.exit("复验失败：仍剩 %d 个空槽（替换命中 %d，正则与文件实际写法不符）"
                     % (left, n))
        if before and not n:
            sys.exit("复验失败：改前有空槽却没替换命中")
        print(("已补齐 %d 处东亚/复杂文本字体槽位 -> %s（复验：剩余空槽 0）" % (n, font))
              if n else "槽位已齐，本次未改动（复验：剩余空槽 0）")
    return n


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    main()
