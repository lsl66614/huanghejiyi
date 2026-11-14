# 从 设计方案.md 生成匿名提交稿 docx（正文宋体小四、1.5 倍行距）。
# 提交版改写规则集中在 REPL/DROP：去过程腔、本机路径、日期与新旧对照，不改变设计结论。
import re, sys
from docx import Document
from docx.shared import Pt, RGBColor, Cm
from docx.enum.text import WD_LINE_SPACING
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

SRC = "设计方案.md"
OUT = "设计方案-提交稿.docx"

# 赛题硬性要求：正文宋体、小四号（12pt）、1.5 倍行距。正文、表格、引用块一律 BODY_PT，
# 仅代码块用 CODE_PT（小四号下代码块仍偏大，9pt 属图示性内容，不算正文）。
BODY_PT = 12
CODE_PT = 9

# 整行替换：原文（去首尾空白后精确匹配或正则）→ 替换后的 markdown 行
REPL = [
    (r"^> 版本 v.*$", "> 版本 v1.3 ｜ 状态：提交稿"),
    (r"^> 本文档为提交用 Word.*$", None),  # 删除母稿自注
    (r"（详见 §风格A 改版 §1，为唯一权威取值）", "（见 §11.1）"),
    (r"（见 §风格A §1 表）", "（见 §11.1）"),
    (r"^\| R1 \|.*$",
     "| R1 | 模拟器镜像合规口径（已解决） | 主 SDK 为 OpenHarmony API 26，满足 API≥12 且模拟器免商用签名；ArkTS 与 HarmonyOS 同源，同代码改 build-profile 即可二次演示 |"),
    # 提交版不提渠道与命名模板：这两件是提交动作，写进作品文档既无必要
    # 也与匿名要求相冲突（母稿保留原文，只在出稿时改写）。
    (r"^\| W6 \(–11/06\) \|.*$",
     "| W6 (–11/06) | 交付三件套：Word 设计方案（正文宋体小四 1.5 倍行距）、演示视频（≤5 分钟、≤100MB）、路演 PPT（10 分钟）；三件套完成匿名化复核后，按赛事通知规定的命名与渠道打包提交 |"),
    # 历史当轮读数容易被误读成现值，出稿时补一句指向当前口径。
    ("Node 侧 **73/73**", "Node 侧 73/73（当轮口径，现已扩至 158/158，见 T8）"),
    ("重核 41 张实拍", "重核 41 张实拍（当轮数量，最终在包 101 张实拍逐条署名，见 §7.1）"),
    (r"^## §风格A 国风强化改版.*$", "## 11 设计系统定稿（国风强化）"),
    (r"^## 8 测试计划.*$", "## 8 测试计划与结果"),
    (r"^调研来源：.*$", "设计依据：对同类文博数字化产品的公开设计案例调研（博物馆类小程序与数字博物馆专题），提炼出四条结论。"),
    (r"^本节\*\*取代\*\*上文.*$", "本章为设计系统的最终定稿口径，与 §7.2 互为引用；布局骨架（P1–P10 十屏、五段式详情、纸底同步面板）如前述各章所述。"),
    (r"^### 1\. 时代色改按.*$", "### 11.1 时代色系（按出土物本体色）"),
    (r"^旧 `#5C7153 / #7A8B8F`.*$",
     "周、汉唐两档原候选色明度过近，在深色头图上文字对比不足，故按出土物本体色重定。前景色按每个色块实际对比度逐一给定（表内即结论）。"),
    (r"^### 2\. 字体分层.*$", "### 11.2 字体分层"),
    (r"^- ArkTS 侧衬线字体\*\*已注册落地.*$",
     "- 衬线字体以工程化方式落地：思源宋体实例化为单一字重（800），按语料与界面全字符集子集化后随包预置于 rawfile 字体资源，运行时注册字体族并挂载到上述标题层级；正文与用户笔记始终使用无衬线系统字体。"),
    (r"^### 3\. 夯层纹理.*$", "### 11.3 夯层纹理（P1 色块 + 全局底层）"),
    (r"^### 4\. 结构母题替换$", "### 11.4 结构母题"),
    (r"^### 5\. P4 展签强化为真实标签制式$", "### 11.5 展签制式（P4）"),
    (r"^### 6\. 微文案口径$", "### 11.6 微文案"),
    (r"^### 7\. 按钮制式.*$", "### 11.7 按钮制式"),
]
# 删除整段（匹配到标题行即连同后续非标题行一起删，直到下一个标题/分隔线）
DROP_BLOCKS = [r"^### 落地档位$"]

def transform(lines):
    out, skipping = [], False
    for ln in lines:
        s = ln.strip()
        if skipping:
            if s.startswith("#") or s == "---":
                skipping = False
            else:
                continue
        drop = False
        for pat in DROP_BLOCKS:
            if re.match(pat, s):
                skipping = True; drop = True; break
        if drop:
            continue
        whole = None
        for pat, rep in REPL:
            if pat.startswith("^"):
                if re.match(pat, s):
                    whole = rep
                    break
        if whole is None and not any(re.match(p, s) for p, r in REPL if p.startswith("^") and r is None):
            for pat, rep in REPL:
                if not pat.startswith("^") and pat in s:
                    s = s.replace(pat, rep)
            out.append(s)
        elif whole is not None:
            out.append(whole)
    return out

INLINE = re.compile(r"(\*\*.+?\*\*|`[^`]+`)")

def add_runs(p, text, base_bold=False):
    for tok in INLINE.split(text):
        if not tok:
            continue
        bold, code = base_bold, False
        if tok.startswith("**") and tok.endswith("**"):
            tok = tok[2:-2]; bold = True
        elif tok.startswith("`") and tok.endswith("`"):
            tok = tok[1:-1]; code = True
        r = p.add_run(tok)
        r.bold = bold
        if code:
            r.font.name = "Consolas"
            r._element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
            r.font.size = Pt(BODY_PT)

def set_east_asia(style_or_run, name):
    rpr = style_or_run.element.get_or_add_rPr() if hasattr(style_or_run, "element") else style_or_run._element.get_or_add_rPr()
    rf = rpr.find(qn("w:rFonts"))
    if rf is None:
        rf = OxmlElement("w:rFonts"); rpr.append(rf)
    rf.set(qn("w:eastAsia"), name)

def shade(cell_or_para_el, color):
    sh = OxmlElement("w:shd")
    sh.set(qn("w:val"), "clear"); sh.set(qn("w:fill"), color)
    cell_or_para_el.append(sh)

def main():
    lines = transform(open(SRC, encoding="utf-8").read().splitlines())
    doc = Document()
    st = doc.styles["Normal"]
    st.font.name = "Times New Roman"; st.font.size = Pt(12)
    set_east_asia(st, "宋体")
    st.paragraph_format.line_spacing = 1.5
    for sec in doc.sections:
        sec.top_margin = sec.bottom_margin = Cm(2.54)
        sec.left_margin = sec.right_margin = Cm(3.17)
    for name, sz in (("Heading 1", 16), ("Heading 2", 14), ("Heading 3", 12.5)):
        h = doc.styles[name]
        h.font.name = "Arial"; h.font.size = Pt(sz); h.font.bold = True
        h.font.color.rgb = RGBColor(0x1F, 0x1B, 0x16)
        set_east_asia(h, "黑体")

    i, n = 0, len(lines)
    while i < n:
        ln = lines[i]; s = ln.strip()
        if not s or s == "---":
            i += 1; continue
        if s.startswith("```"):
            buf = []
            i += 1
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i]); i += 1
            i += 1
            for cl in buf:
                p = doc.add_paragraph()
                p.paragraph_format.line_spacing = 1.0
                p.paragraph_format.left_indent = Cm(0.5)
                shade(p._p.get_or_add_pPr(), "F4F1EA")
                r = p.add_run(cl if cl.strip() else " ")
                r.font.name = "Courier New"; r.font.size = Pt(CODE_PT)
                r._element.rPr.rFonts.set(qn("w:eastAsia"), "宋体")
            continue
        if s.startswith("|"):
            rows = []
            while i < n and lines[i].strip().startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-{2,}:?", c or "-") for c in cells):
                    rows.append(cells)
                i += 1
            if rows and any("旧值" in c for c in rows[0]):
                k = next(j for j, c in enumerate(rows[0]) if "旧值" in c)
                rows = [r[:k] + r[k+1:] for r in rows]
                for r in rows:
                    r[:] = [c.replace("新值", "色值") for c in r]
            w = max(len(r) for r in rows)
            rows = [r + [""] * (w - len(r)) for r in rows]
            t = doc.add_table(rows=len(rows), cols=w)
            t.style = "Table Grid"
            for ri, row in enumerate(rows):
                for ci, cell in enumerate(row):
                    c = t.cell(ri, ci)
                    p = c.paragraphs[0]
                    p.paragraph_format.line_spacing = 1.15
                    add_runs(p, cell, base_bold=(ri == 0))
                    for r in p.runs:
                        r.font.size = Pt(BODY_PT)
                    if ri == 0:
                        shade(c._tc.get_or_add_tcPr(), "EDE6D6")
            doc.add_paragraph()
            continue
        m = re.match(r"^(#{1,3})\s+(.*)$", s)
        if m:
            lvl = len(m.group(1))
            p = doc.add_heading("", level=lvl)
            add_runs(p, m.group(2), base_bold=True)
            for r in p.runs:
                r.font.color.rgb = RGBColor(0x1F, 0x1B, 0x16)
            i += 1; continue
        if s.startswith("> "):
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Cm(0.75)
            add_runs(p, s[2:])
            for r in p.runs:
                r.font.size = Pt(BODY_PT)
                r.font.color.rgb = RGBColor(0x6B, 0x63, 0x57)
            i += 1; continue
        mb = re.match(r"^[-*]\s+(.*)$", s)
        if mb:
            p = doc.add_paragraph(style="List Bullet")
            add_runs(p, mb.group(1))
            i += 1; continue
        mn = re.match(r"^(\d+)[.、]\s+(.*)$", s)
        if mn:
            p = doc.add_paragraph(style="List Number")
            add_runs(p, mn.group(2))
            i += 1; continue
        p = doc.add_paragraph()
        p.paragraph_format.first_line_indent = Pt(24)
        add_runs(p, s)
        i += 1
    doc.save(OUT)
    print("saved", OUT)

if __name__ == "__main__":
    main()
