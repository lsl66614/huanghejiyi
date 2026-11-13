#!/usr/bin/env python3
"""tools/build_attribution.py —— 生成随包发布的图片署名清单 rawfile/attribution.json。

为什么需要：`tools/commons_manifest.json` 里 91 项有 **79 项是 CC BY-SA**（78×4.0 + 1×3.0），
BY-SA 要求署名并说明修改；而台账只在 tools/ 下、不进包，App 内此前没有任何署名位。

数据来源两处，本脚本做合并与补缺：
  A. docs/IMAGES.md 的批次表（第一批/第二批是 5 列：路径 | 原文件 | 作者 | 许可 | 来源）
  B. tools/commons_manifest.json（第三轮起的挂载台账：site/name/file/licence/author/desc）
两处都只记了文件名，来源链接按 Commons 文件页规则生成（空格转下划线）。

任何一张在包里的 real_ 图拿不到署名记录 → 非 0 退出，不产出文件（宁可不生成，
也不生成一份"看起来齐了"的清单）。

用法：python tools/build_attribution.py [--write]
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "app/entry/src/main/resources/rawfile"
MANIFEST = ROOT / "tools/commons_manifest.json"
IMAGES_DOC = ROOT / "docs/IMAGES.md"

# 本项目对所有实拍图做的事：长边压到 1024、重编码为 WebP —— BY-SA 4.0 要求"说明修改"。
ADAPTED = "已按本项目用途调整：长边缩放至 1024、重编码为 WebP（原图为 JPEG）"

FILE_URL = "https://commons.wikimedia.org/wiki/File:%s"


def commons_url(file_name: str) -> str:
    """文件页链接是署名的核心（CC 要求可点回来源）。
    ⚠  Commons 标题里的空格要写成下划线，且中文文件名必须 percent-encode，
    否则链接直接 404（本批 21 张是中文名）。"""
    name = file_name.strip()
    if name.startswith("File:"):
        name = name[len("File:"):]
    return FILE_URL % quote(name.replace(" ", "_"), safe="")


def shipped_images() -> dict[str, str]:
    """在包内的实拍图：{site/name.webp 相对路径 -> 站点 id}"""
    out: dict[str, str] = {}
    img = RAW / "images"
    if not img.exists():
        return out
    for p in sorted(img.rglob("*.webp")):
        rel = p.relative_to(RAW).as_posix()
        if p.name.startswith("real_"):
            out[rel] = p.parent.name
    return out


def parse_images_doc(text: str) -> dict[str, dict]:
    """吃 IMAGES.md 里所有含"路径 + real_ 文件名"的表。
    ⚠ 各批次列序不同：第一批是 `路径|原文件|作者|许可|来源`，
    第二批是 `路径|原文件|落点|作者|许可`——所以按表头列名映射，不按位置取。"""
    rec: dict[str, dict] = {}
    header: list[str] | None = None
    for line in text.splitlines():
        s = line.strip()
        if not s.startswith("|"):
            header = None if s == "" else header
            if s == "":
                header = None
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if set("".join(cells)) <= set("-: "):      # 分隔行 |---|---|
            continue
        if cells and cells[0] in ("路径", "挂给谁", "图片位"):
            header = cells
            continue
        if header is None or len(cells) != len(header):
            continue
        col = dict(zip(header, cells))
        path = col.get("路径", "")
        if not re.match(r"^images/[a-z0-9_]+/real_[a-z0-9_]+\.webp$", path):
            continue
        file_name = col.get("原文件", "") or col.get("Commons 文件", "")
        author, licence = col.get("作者", ""), col.get("许可", "")
        # "CC BY-SA 4.0 / Windmemories" 合写在许可列的老格式
        if licence and not author and " / " in licence:
            licence, author = licence.split(" / ", 1)
        url = next((v for v in cells if v.startswith("http")), "")
        if not url and file_name:
            url = commons_url(file_name)
        if file_name and author and licence:
            rec[path] = {"file": file_name, "author": author, "licence": licence, "source": url}
    return rec


def parse_manifest() -> dict[str, dict]:
    if not MANIFEST.exists():
        return {}
    items = json.loads(MANIFEST.read_text(encoding="utf-8"))["items"]
    out: dict[str, dict] = {}
    for it in items:
        name, site = it.get("name", ""), it.get("site", "")
        if not name or not site:
            continue
        path = f"images/{site}/{name}.webp"
        file_name = it.get("file") or ""
        out[path] = {
            "file": file_name,
            "author": it.get("author", ""),
            "licence": it.get("licence", ""),
            "source": commons_url(file_name) if file_name else "",
            "desc": it.get("desc", ""),
        }
    return out


def build() -> tuple[list[dict], list[str]]:
    ship = shipped_images()
    from_doc = parse_images_doc(IMAGES_DOC.read_text(encoding="utf-8"))
    from_man = parse_manifest()
    records: list[dict] = []
    missing: list[str] = []
    for path in sorted(ship):
        a, b = from_doc.get(path), from_man.get(path)
        pick = b or a          # 台账更新、字段更规整；缺则回落到批次表
        if pick is None:
            missing.append(path)
            continue
        if a and b and (a["licence"] != b["licence"] or a["author"] != b["author"]):
            print("  ⚠ 两处口径不一致，取台账：%s  文档=%s/%s 台账=%s/%s"
                  % (path, a["licence"], a["author"], b["licence"], b["author"]), file=sys.stderr)
        rec = {"path": path, "file": pick["file"], "author": pick["author"],
               "licence": pick["licence"], "source": pick["source"], "adapted": ADAPTED}
        if not rec["file"] or not rec["author"] or not rec["licence"]:
            missing.append(path + "（记录字段不全）")
            continue
        records.append(rec)
    return records, missing


def ai_covers() -> list[dict]:
    """EraTheme 硬编码的首页年代卡封面：自有 AI 生成图，不走 Commons 署名，
    但必须显式声明是 AI 生成——它们带「示意图」角标上屏。"""
    ets = (ROOT / "app/entry/src/main/ets/common/EraTheme.ets").read_text(encoding="utf-8")
    pairs = re.findall(r"\['([a-z]+)',\s*'(images/[^']+\.webp)'\]", ets)
    return [{"era": era, "path": path, "kind": "ai-illustration",
             "note": "AI 生成示意图，非考古现场照片，仅用于首页年代块视觉引导"}
            for era, path in pairs]


# 随包字体。这两个文件是改名+子集化的成品，本地 name 表证据不均等：
# ZCOOL 那份自带 OFL 声明（nameID 13/14），Noto 那份的 name 表被剥到只剩
# family/subfamily——所以许可信息一律以 **上游 google/fonts 的 OFL.txt** 为准，
# 并把原文取回随包（rawfile/font/OFL-*.txt），记录里的 copyright 逐字取自
# 该原文首行，脚本会核对，换字体或改原文就会判红而不是继续"看起来对"。
FONT_LICENCES = [
    {
        "file": "NotoSerifSC-Head800.ttf",
        "family": "Noto Serif SC",
        "designer": "Google Inc.（上游版权行）",
        "licence": "SIL Open Font License 1.1",
        "licence_url": "http://scripts.sil.org/OFL",
        "source": "https://github.com/google/fonts/tree/main/ofl/notoserifsc",
        "licence_file": "font/OFL-NotoSerifSC.txt",
        "adapted": "本项目随包的是按设计稿取用字面并改名后的文件，经 getFont().registerFont() 在 Index 页注册；文件名与上游不同（Head800 / Sub）。",
    },
    {
        "file": "ZCOOLXiaoWei-Sub.ttf",
        "family": "ZCOOL XiaoWei",
        "designer": "xiaowei / ZCOOL（取自该 ttf 的 name 表 nameID 7/8）",
        "licence": "SIL Open Font License 1.1",
        "licence_url": "http://scripts.sil.org/OFL",
        "source": "https://github.com/google/fonts/tree/main/ofl/zcoolxiaowei",
        "licence_file": "font/OFL-ZCOOLXiaoWei.txt",
        "adapted": "本项目随包的是按设计稿取用字面并改名后的文件，经 getFont().registerFont() 在 Index 页注册；文件名与上游不同（Head800 / Sub）。",
    },
]


def shipped_fonts() -> list[str]:
    d = RAW / "font"
    if not d.exists():
        return []
    return sorted(f.name for f in d.iterdir()
                  if f.suffix.lower() in ('.ttf', '.otf', '.woff', '.woff2'))


def fonts() -> tuple[list[dict], list[str]]:
    """产出字体记录，并对不齐的一律进 problems（宁可不生成）。"""
    recs: list[dict] = []
    problems: list[str] = []
    on_disk = shipped_fonts()
    declared = [f["file"] for f in FONT_LICENCES]
    for name in on_disk:
        if name not in declared:
            problems.append("%s 在包里但没有许可记录（要在 FONT_LICENCES 里补，并随包附许可原文）" % name)
    for f in FONT_LICENCES:
        if f["file"] not in on_disk:
            problems.append("FONT_LICENCES 记了 %s，但 rawfile/font 里没有这个文件" % f["file"])
            continue
        lic_path = RAW / f["licence_file"]
        if not lic_path.exists():
            problems.append("%s 的许可原文未随包：%s" % (f["file"], f["licence_file"]))
            continue
        first = lic_path.read_text(encoding='utf-8', errors='replace').splitlines()[0].strip()
        r = dict(f)
        r["copyright"] = first
        # OFL 要求分发时带上版权行与许可本身；这里把两条都钉成可核对的字段
        if "Copyright" not in first:
            problems.append("%s 的许可原文首行不含 Copyright：%s" % (f["file"], first[:60]))
        recs.append(r)
    return recs, problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="写 rawfile/attribution.json")
    a = ap.parse_args()
    records, missing = build()
    cov = len(records)
    total = len(shipped_images())
    lic: dict[str, int] = {}
    for r in records:
        lic[r["licence"]] = lic.get(r["licence"], 0) + 1
    print("在包实拍 %d 张 → 署名记录 %d 张；许可分布 %s" % (total, cov, lic))
    print("AI 示意图声明 %d 张（首页年代卡）" % len(ai_covers()))
    font_records, font_problems = fonts()
    print("在包字体 %d 个 → 许可记录 %d 个" % (len(shipped_fonts()), len(font_records)))
    for p in font_problems:
        print("[FAIL] 字体：", p)
    if missing or font_problems:
        if missing:
            print("[FAIL] 以下在包实拍图没有署名记录：")
            for m in missing:
                print("   ", m)
        return 1
    if not a.write:
        print("（未写盘，加 --write 生成 rawfile/attribution.json）")
        return 0
    out = {
        "generated_by": "tools/build_attribution.py",
        "policy": "CC BY-SA 4.0 / 3.0 要求署名并说明修改；CC0 为自愿记录。原始许可与作者以 Commons 文件页为准。"
                  "字体按 SIL OFL 1.1 随包附原文。",
        "images": records,
        "ai_illustrations": ai_covers(),
        "fonts": font_records,
    }
    dst = RAW / "attribution.json"
    dst.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("已生成 %s（%d 条图片记录 + %d 条字体记录）" % (dst.relative_to(ROOT), len(records), len(font_records)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
