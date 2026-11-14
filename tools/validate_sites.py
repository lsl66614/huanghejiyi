#!/usr/bin/env python3
# tools/validate_sites.py — schema 校验 + 配额矩阵报告 + 剥离 source 生成发布版
import json, re, sys, copy
from pathlib import Path

ERA_PREHISTORIC = {"yangshao", "longshan"}

def load_schema(base: Path) -> dict:
    return json.loads((base / "site.schema.json").read_text(encoding="utf-8"))

def check_paths(obj: dict, res_root: Path | None) -> list[str]:
    """图片路径制式 + 存在性。
    进包树（rawfile 下）额外要求只能是 real_：渲染层全程过 isRealImage/firstRealImage，
    非实拍项写进 JSON 也永不上屏，只会白进 HAP。
    tools/sites-src 母本不承担这个不变式——它的职责是留全量语料（含示意图），
    且是手写紧凑数组排版，按 real_ 硬卡会逼出一整轮无意义的重排。
    $rawfile 取不到文件时界面只回落剪影、不报错，所以存在性必须单独查。"""
    errs = []
    paths = list(obj.get("images", []))
    for r in obj.get("relics", []):
        paths += list(r.get("images", []))
    shipped = res_root is not None
    shape = r"^images/[a-z0-9_]+/real_[a-z0-9_]+\.webp$" if shipped else r"^images/[a-z0-9_]+/[a-z0-9_]+\.webp$"
    for p in paths:
        if not re.match(shape, str(p)):
            errs.append("图片引用不合规%s: %s"
                        % ("（进包内容只允许 real_ 实拍，示意图写了也不上屏）" if shipped else "", p))
        elif shipped and not (res_root / p).exists():
            errs.append(f"图片文件不在盘上: {p}")
    return errs

def check_site(obj: dict, schema: dict) -> list[str]:
    errs = []
    for k in schema["required"]:
        if k not in obj:
            errs.append(f"缺字段 {k}")
    if errs:
        return errs
    props = schema["properties"]
    for name, spec in props.items():
        v = obj.get(name)
        if v is None:
            continue
        if "enum" in spec and v not in spec["enum"]:
            errs.append(f"{name}={v!r} 不在枚举 {spec['enum']}")
        if spec.get("type") == "string" and "minLength" in spec and len(v) < spec["minLength"]:
            errs.append(f"{name} 过短({len(v)}<{spec['minLength']})")
        if spec.get("type") == "array" and "minItems" in spec and len(v) < spec["minItems"]:
            errs.append(f"{name} 条目数 {len(v)}<{spec['minItems']}")
        if spec.get("type") == "array" and "maxItems" in spec and len(v) > spec["maxItems"]:
            errs.append(f"{name} 条目数 {len(v)}>{spec['maxItems']}")
    sec = obj["sections"]
    for k in ("intro", "arch"):
        if len(sec.get(k, "")) < 10:
            errs.append(f"sections.{k} 过短")
    # events：旧版单段字符串，或新版事件对象数组
    evs = sec.get("events")
    if isinstance(evs, str):
        if len(evs) < 20:
            errs.append("sections.events 过短")
    elif isinstance(evs, list):
        if not evs:
            errs.append("sections.events 为空数组")
        for e in evs:
            for f in ("year", "title", "summary"):
                if not str(e.get(f, "")).strip():
                    errs.append(f"events 缺 {f}（事件必须有时间、标题与摘要）")
            if len(str(e.get("summary", ""))) < 40:
                errs.append("events.summary 过短")
            figs = e.get("figures", [])
            if not isinstance(figs, list):
                errs.append("events.figures 必须是数组")
    else:
        errs.append("sections.events 类型非法（应为字符串或对象数组）")
    # tourism：旧版单段字符串，或新版 overview/guide/itinerary 对象
    tou = sec.get("tourism")
    if isinstance(tou, str):
        if len(tou) < 10:
            errs.append("sections.tourism 过短")
    elif isinstance(tou, dict):
        if len(str(tou.get("overview", "")).strip()) < 10:
            errs.append("sections.tourism.overview 过短")
        g = tou.get("guide", {})
        if g and not isinstance(g, dict):
            errs.append("sections.tourism.guide 必须是对象")
    else:
        errs.append("sections.tourism 类型非法（应为字符串或对象）")
    poems = sec.get("poems", [])
    for p in poems:
        for f in ("text", "author", "source"):
            if not str(p.get(f, "")).strip():
                errs.append(f"poems 缺 {f}（诗词必须真句真作者真出处）")
    if not poems and obj["era"] not in ERA_PREHISTORIC:
        errs.append("非史前遗址 poems 为空")
    for r in obj.get("relics", []):
        if r.get("era") not in schema["properties"]["era"]["enum"]:
            errs.append(f"relic {r.get('id')} era 非法")
    return errs

def strip_source(obj: dict) -> dict:
    o = copy.deepcopy(obj)
    o.pop("source", None)
    for r in o.get("relics", []):
        r.pop("source", None)
    return o

def check_orphans(sites: list[dict], res_root: Path | None) -> list[str]:
    """反向差集：rawfile/images 里没人引用的 webp 一样会被 hvigor 打进 HAP。
    .gitignore 只挡 git，不挡打包——只查"引用缺文件"会漏掉这半边（PITFALLS #63）。
    引用面不止内容 JSON：EraTheme.ets 里按年代硬编码了 6 张兜底图，
    所以连源码一起扫，否则会把在用的图误报成死重。"""
    if res_root is None:
        return []
    refs = set()
    IMG = re.compile(r"images/[A-Za-z0-9_]+/[A-Za-z0-9_.-]+\.webp")
    for s in sites:
        for p in list(s.get("images", [])):
            refs.add(p)
        for r in s.get("relics", []):
            for p in r.get("images", []):
                refs.add(p)
    src_root = res_root.parent.parent  # .../src/main/resources/rawfile → .../src/main
    for f in list(src_root.rglob("*.ets")) + list(src_root.rglob("*.ts")):
        refs.update(IMG.findall(f.read_text(encoding="utf-8", errors="replace")))
    img = res_root / "images"
    if not img.exists():
        return []
    orph = [str(p.relative_to(res_root)).replace("\\", "/")
            for p in img.rglob("*.webp") if str(p.relative_to(res_root)).replace("\\", "/") not in refs]
    # 只把 real_ 判死：那一类是"下载来待核图"的临时件，留在 rawfile 就是没承诺要挂的图。
    # 其余未引用的是自有示意图，IMAGES.md 记着"已入仓/待生成"的配额账，属内容线待办，
    # 报数不判红（实测 6 张 0.10 MB）。
    unmounted = [o for o in orph if o.split("/")[-1].startswith("real_")]
    pool = [o for o in orph if o not in unmounted]
    errs = []
    if unmounted:
        errs.append("rawfile 里有 %d 张未挂载的 real_ 图（%.2f MB 白进 HAP，应移入 tools/staging_unmounted）：%s"
                    % (len(unmounted), sum((res_root / o).stat().st_size for o in unmounted) / 1048576,
                       ", ".join(sorted(unmounted))))
    if pool:
        print("NOTE 未引用的自有示意图 %d 张 %.2f MB（内容线待办，不判红）：%s"
              % (len(pool), sum((res_root / o).stat().st_size for o in pool) / 1048576,
                 ", ".join(sorted(pool)[:6])))
    return errs


def main(src_dir: str, out_dir: str | None) -> int:
    base = Path(__file__).parent
    schema = load_schema(base)
    src = Path(src_dir)
    # 只有进包的那棵树才查文件存在性；tools/sites-src 母本的图未必已落盘。
    res_root = None
    for anc in [src, *src.parents]:
        if anc.name == "rawfile":
            res_root = anc
            break
    sites = []
    fail = False
    for f in sorted(src.glob("*.json")):
        obj = json.loads(f.read_text(encoding="utf-8"))
        errs = check_site(obj, schema) + check_paths(obj, res_root)
        if errs:
            fail = True
            print(f"[FAIL] {f.name}: " + "; ".join(errs))
        sites.append(obj)
    for e in check_orphans(sites, res_root):
        fail = True
        print(f"[FAIL] {e}")

    # 配额矩阵（报告，不判失败——满配 40 条由内容线补齐时再收紧为硬闸门）
    cities = sorted({s["city"] for s in sites})
    eras = sorted({s["era"] for s in sites})
    types_ = sorted({s["site_type"] for s in sites})
    print(f"共 {len(sites)} 条 | 城市覆盖 {cities}")
    print(f"年代覆盖 {eras} | 类型覆盖 {types_}")
    for c in schema["properties"]["city"]["enum"]:
        n = sum(1 for s in sites if s["city"] == c)
        print(f"  city {c}: {n}")
    for e in schema["properties"]["era"]["enum"]:
        n = sum(1 for s in sites if s["era"] == e)
        print(f"  era {e}: {n}")
    ids = [s["id"] for s in sites] + [r["id"] for s in sites for r in s.get("relics", [])]
    dup = {i for i in ids if ids.count(i) > 1}
    if dup:
        print(f"[FAIL] id 重复: {dup}"); fail = True
    if not fail and out_dir:
        od = Path(out_dir); od.mkdir(exist_ok=True)
        for s in sites:
            (od / f"{s['id']}.json").write_text(
                json.dumps(strip_source(s), ensure_ascii=False, indent=1), encoding="utf-8")
        print(f"发布版已生成 → {out_dir} ({len(sites)} 文件)")
    return 1 if fail else 0

if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if a != "--no-out"]
    # 默认落在 tools/，不跟着 src_dir 走——src_dir 是 rawfile/sites 时
    # 派生目录会写进 rawfile 里被一起打进 HAP（42 份重复 JSON，实测 568 KB）。
    default_out = str(Path(__file__).parent / "sites-out")
    # --no-out：只做校验不生成发布版（门禁路径用，避免派生文件污染工作树）
    out = None if "--no-out" in sys.argv[1:] else (args[1] if len(args) > 1 else default_out)
    sys.exit(main(args[0], out))
