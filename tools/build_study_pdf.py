# 把 docs/答辩 + docs/学习路线 合成一份可打印 PDF。
#
# 为什么走 HTML → Edge 无头打印，而不是 python-docx / reportlab：
#   本机只有 python-markdown，没有 weasyprint / reportlab / pandoc。
#   Edge 自带的打印引擎能正确排版中文、表格与代码块，且中文字体随系统走。
#
# 用法：python -I tools/build_study_pdf.py [--out=路径]
import datetime
import os
import re
import subprocess
import sys

import markdown

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 顺序即阅读顺序。
# full  = 完整版（技术细节 + 代码摘录，给深读用）
# plain = 通俗版（类比 + 人话，给答辩前夜和手机上看）
DOCS_FULL = [
    ("docs/答辩/README.md", "目录与实测基线"),
    ("docs/答辩/01-十二页讲稿与数字口径.md", "第一部分 · 十二页讲稿与数字口径"),
    ("docs/答辩/02-老师提问速查.md", "第二部分 · 老师提问速查"),
    ("docs/答辩/03-现场操作清单.md", "第三部分 · 现场操作清单"),
    ("docs/学习路线.md", "第四部分 · 学习路线（长期）"),
    ("docs/源代码细节解释.md", "第五部分 · 源代码细节解释"),
]

DOCS_PLAIN = [
    ("docs/通俗讲解.md", ""),
]

DOCS_SRC = [
    ("docs/源代码细节解释.md", ""),
]

BUNDLES = {
    "full": (DOCS_FULL, "黄河记忆-答辩与学习资料.pdf",
             "黄河记忆 · 答辩与学习资料",
             "完整版：讲稿 · 提问速查 · 现场清单 · 学习路线 · 源码细节"),
    "plain": (DOCS_PLAIN, "黄河记忆-通俗讲解.pdf",
              "黄河记忆 · 通俗讲解",
              "通俗版：全用大白话和类比，不讲代码怎么写，只讲它是干什么的"),
    "src": (DOCS_SRC, "黄河记忆-源代码细节解释.pdf",
            "黄河记忆 · 源代码细节解释",
            "12 章机制详解 · 85 个文件速查表 · 带代码摘录与行号"),
}

EDGE_CANDIDATES = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]

CSS = """
@page { size: A4; margin: 16mm 14mm 18mm 14mm; }
* { box-sizing: border-box; }
body {
  font-family: "Microsoft YaHei", "Segoe UI", sans-serif;
  font-size: 10.5pt; line-height: 1.62; color: #1f1b16;
  margin: 0; padding: 0;
}
.cover { page-break-after: always; padding-top: 62mm; text-align: center; }
.cover h1 { font-size: 26pt; margin: 0 0 8mm; letter-spacing: 2px; color: #9C4A2F; }
.cover .sub { font-size: 12.5pt; color: #6e675e; margin-bottom: 4mm; }
.cover .meta { font-size: 10pt; color: #8a8177; margin-top: 26mm; line-height: 1.9; }
.cover .rule { width: 42mm; height: 2.5pt; background: #9C4A2F; margin: 7mm auto; }

h1.part {
  page-break-before: always; font-size: 17pt; color: #9C4A2F;
  border-bottom: 1.6pt solid #9C4A2F; padding-bottom: 2.5mm; margin: 0 0 5mm;
}
h1:not(.part) { font-size: 15pt; margin: 6mm 0 3mm; color: #1f1b16; }
h2 { font-size: 12.5pt; margin: 5mm 0 2.5mm; padding-left: 2.4mm;
     border-left: 3pt solid #B98A44; color: #1f1b16; }
h3 { font-size: 11pt; margin: 4mm 0 2mm; color: #3d3833; }

p { margin: 1.8mm 0; }
ul, ol { margin: 1.8mm 0 1.8mm 5.5mm; padding-left: 3mm; }
li { margin: 1.1mm 0; }
strong { color: #8E4028; }

blockquote {
  margin: 2.5mm 0; padding: 2mm 3.5mm; background: #F5EFE2;
  border-left: 2.6pt solid #9C4A2F; color: #3d3833;
}
blockquote p { margin: 0.8mm 0; }

table {
  border-collapse: collapse; width: 100%; margin: 3mm 0; font-size: 9pt;
  page-break-inside: auto;
}
th, td { border: 0.5pt solid #d8d1c4; padding: 1.6mm 2mm; text-align: left;
         vertical-align: top; }
th { background: #EDE6D6; font-weight: 600; }
tr { page-break-inside: avoid; }
tbody tr:nth-child(even) { background: #FAF7F0; }

code { font-family: "Cascadia Mono", Consolas, monospace; font-size: 9pt;
       background: #F2F0EC; padding: 0.3mm 1mm; border-radius: 1.2mm; }
pre { background: #F2F0EC; padding: 2.5mm 3mm; border-radius: 1.5mm;
      overflow-x: auto; page-break-inside: avoid; }
pre code { background: none; padding: 0; }

del { color: #a89f93; }
hr { border: none; border-top: 0.5pt dashed #d8d1c4; margin: 4mm 0; }
a { color: #9C4A2F; text-decoration: none; }
"""


def find_edge():
    for p in EDGE_CANDIDATES:
        if os.path.isfile(p):
            return p
    sys.exit("找不到 msedge.exe，无法打印 PDF")


def build_html(docs, cover_title, cover_sub):
    parts = []
    for rel, title in docs:
        path = os.path.join(ROOT, rel)
        if not os.path.isfile(path):
            sys.exit("缺文件：%s" % rel)
        with open(path, encoding="utf-8") as f:
            md = f.read()
        # python-markdown 默认不认 GFM 的 ~~删除线~~，会原样输出两个波浪号。
        # 表格里「~~126~~」这类反例必须真的显示成划掉，否则读者以为是要用的旧值。
        md = re.sub(r"~~(.+?)~~", r"<del>\1</del>", md)
        html = markdown.markdown(
            md,
            extensions=["tables", "fenced_code", "sane_lists"],
            output_format="html5",
        )
        # 不开 nl2br：正文多按句意折行，开它会在句中插 <br>，中文排版反而更碎
        # 单文档版（title 为空）不加分部标题，省掉一个多余的空页
        if title:
            parts.append('<h1 class="part">%s</h1>\n%s' % (title, html))
        else:
            parts.append(html)

    today = datetime.date.today().strftime("%Y-%m-%d")
    cover = (
        '<div class="cover">'
        '<h1>%s</h1>'
        '<div class="rule"></div>'
        '<div class="sub">第三届河南省高等学校信息技术应用创新大赛（开源鸿蒙）赛题一</div>'
        '<div class="sub">黄河文化分布式数字档案</div>'
        '<div class="sub" style="margin-top:6mm;font-size:11pt;color:#8a8177">%s</div>'
        '<div class="meta">'
        '数字口径基线：2026-11-10 实测<br>'
        '13/13 门禁 · 158/158 单测 · 101 张实拍 · HAP 23.62 MiB<br>'
        '生成日期：%s'
        '</div></div>' % (cover_title, cover_sub, today)
    )
    return (
        '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8">'
        "<title>%s</title>"
        "<style>%s</style></head><body>%s%s</body></html>"
        % (cover_title, CSS, cover, "".join(parts))
    )


def main():
    bundle = "full"
    out_pdf = None
    for a in sys.argv[1:]:
        if a.startswith("--out="):
            out_pdf = os.path.abspath(a[6:])
        elif a.startswith("--bundle="):
            bundle = a[9:]
    if bundle not in BUNDLES:
        sys.exit("未知 bundle：%s（可选：%s）" % (bundle, " / ".join(BUNDLES)))
    docs, default_name, cover_title, cover_sub = BUNDLES[bundle]
    if out_pdf is None:
        out_pdf = os.path.join(ROOT, default_name)

    html = build_html(docs, cover_title, cover_sub)
    html_path = os.path.join(ROOT, "_scratch", "study_%s.html" % bundle)
    os.makedirs(os.path.dirname(html_path), exist_ok=True)
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(html)
    print("[%s] html: %s %.1f KB"
          % (bundle, os.path.basename(html_path), os.path.getsize(html_path) / 1024))

    edge = find_edge()
    profile = os.path.join(ROOT, "_scratch", "edge-profile")
    cmd = [
        edge,
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-pdf-header-footer",
        "--user-data-dir=" + profile,
        "--print-to-pdf=" + out_pdf,
        "file:///" + html_path.replace("\\", "/"),
    ]
    r = subprocess.run(cmd, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=180)
    if not os.path.isfile(out_pdf):
        print(r.stdout[-1500:])
        print(r.stderr[-1500:])
        sys.exit("PDF 未生成（退出码 %d）" % r.returncode)
    print("pdf:", out_pdf, "%.1f KB" % (os.path.getsize(out_pdf) / 1024))
    return out_pdf


if __name__ == "__main__":
    main()
