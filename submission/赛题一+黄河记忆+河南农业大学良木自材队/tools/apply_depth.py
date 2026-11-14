#!/usr/bin/env python3
# tools/apply_depth.py — 把 tools/depth-src/ 的深度内容合并进 rawfile 语料。
#
# 分工：depth-src 只重写 sections.intro/arch/events/tourism 四个字段，
# 其余字段（id/name/city/era/site_type/summary/tags/images/relics/poems）一律沿用
# rawfile 原值——深度内容由子代理撰写，不允许连带改动已验证的语料主干。
#
# 用法：python tools/apply_depth.py [--dry-run]
import json, sys, copy
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEPTH = ROOT / "tools" / "depth-src"
RAW = ROOT / "app" / "entry" / "src" / "main" / "resources" / "rawfile" / "sites"

# 深度层可改写的字段白名单
WRITABLE = ("intro", "arch", "events", "tourism")


def depth_stats(sec: dict) -> str:
    intro = len(sec.get("intro", "") or "")
    arch = len(sec.get("arch", "") or "")
    evs = sec.get("events")
    n_ev = len(evs) if isinstance(evs, list) else 0
    tou = sec.get("tourism")
    if isinstance(tou, dict):
        tov = len(tou.get("overview", "") or "") + len(tou.get("itinerary", "") or "")
    else:
        tov = len(tou or "")
    return f"intro {intro} / arch {arch} / events {n_ev} / tourism {tov}"


def main(dry: bool) -> int:
    if not DEPTH.is_dir():
        print(f"[FAIL] 深度内容目录不存在: {DEPTH}")
        return 1

    applied, skipped = [], []
    for f in sorted(DEPTH.glob("*.json")):
        site_id = f.stem
        target = RAW / f"{site_id}.json"
        if not target.exists():
            print(f"[SKIP] rawfile 无对应站点，跳过: {site_id}")
            skipped.append(site_id)
            continue

        base = json.loads(target.read_text(encoding="utf-8"))
        deep = json.loads(f.read_text(encoding="utf-8"))

        # 身份字段必须一致，否则说明深度稿张冠李戴
        for k in ("id", "name", "city", "era", "site_type"):
            if str(base.get(k)) != str(deep.get(k)):
                print(f"[FAIL] {site_id}: 身份字段 {k} 不一致 base={base.get(k)!r} deep={deep.get(k)!r}")
                return 1

        new_sec = copy.deepcopy(base["sections"])
        deep_sec = deep.get("sections", {})
        for k in WRITABLE:
            if k in deep_sec:
                new_sec[k] = deep_sec[k]

        merged = copy.deepcopy(base)
        merged["sections"] = new_sec
        if deep.get("source"):
            merged["source"] = deep["source"]

        applied.append((site_id, depth_stats(new_sec)))
        if not dry:
            target.write_text(json.dumps(merged, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    tag = "（dry-run，未写入）" if dry else ""
    print(f"合并 {len(applied)} 站，{len(skipped)} 站无 rawfile 对应 {tag}")
    for sid, st in applied:
        print(f"  {sid:26s} {st}")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    sys.exit(main("--dry-run" in args))
