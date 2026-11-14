#!/usr/bin/env python3
# tools/fix_depth_json.py — 修复 depth-src 中因中文引号混入导致的 JSON 语法错误。
#
# 成因：撰写文案时中文引号被写成 ASCII 双引号 "（U+0022）。落在 JSON 字符串
# 值内部时会提前闭合该值，使解析报 "Expecting ',' delimiter"。
#
# 关键约束：JSON 本身的结构性引号（键名两侧、值两侧、数组元素分隔）必须原样
# 保留——只有已经进入某个字符串值内部的裸 " 才换成中文引号。因此这里用一次
# 逐字符扫描跟踪"当前是否在字符串内"，而不是全局替换。
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEPTH = ROOT / "tools" / "depth-src"

LEFT, RIGHT = "“", "”"


def repair(raw: str) -> str:
    # 第一步：还原被误转义的单引号（正文里的 \' 会被 json 解析吞掉反斜杠）
    raw = raw.replace("\\'", "'")

    # 第二步：扫描 JSON 结构，仅替换字符串值内部的裸双引号
    out = []
    in_str = False       # 当前是否位于某个字符串值内部
    str_start = -1       # 当前字符串值的起始引号下标
    pending_open = True  # 本字符串内下一个裸 " 应作为左引号还是右引号
    i, n = 0, len(raw)

    while i < n:
        ch = raw[i]
        if not in_str:
            out.append(ch)
            if ch == '"':
                in_str, str_start, pending_open = True, i, True
            i += 1
            continue

        # 字符串内部
        if ch == '\\' and i + 1 < n:
            out.append(raw[i:i + 2])
            i += 2
            continue

        if ch == '"':
            # 若是该字符串值的收尾引号：其后（跳过空白）应为 , ] } : 或 EOF
            j = i + 1
            while j < n and raw[j] in ' \t\r\n':
                j += 1
            nxt = raw[j] if j < n else ''
            if nxt in (',', ']', '}', ':', ''):
                out.append('"')
                in_str, pending_open = False, True
            else:
                out.append(LEFT if pending_open else RIGHT)
                pending_open = not pending_open
            i += 1
            continue

        out.append(ch)
        i += 1

    return "".join(out)


def main() -> int:
    fixed, still_bad = [], []
    for f in sorted(DEPTH.glob("*.json")):
        raw = f.read_text(encoding="utf-8")
        try:
            json.loads(raw)
            continue
        except json.JSONDecodeError:
            pass
        cand = repair(raw)
        try:
            json.loads(cand)
        except json.JSONDecodeError as e:
            still_bad.append((f.name, str(e)))
            continue
        f.write_text(cand, encoding="utf-8")
        fixed.append(f.name)

    print(f"修复 {len(fixed)} 个文件")
    for n in fixed:
        print("  +", n)
    if still_bad:
        print(f"仍有 {len(still_bad)} 个文件无法自动修复：")
        for n, e in still_bad:
            print("  !", n, e)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
