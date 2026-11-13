#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""字号收敛的规划器：只读、只出报告，绝不写源文件。

用途是把「把 20 档字号收敛到 7 档」这件机械活与「哪一格该归哪一档」
这件判断活分开。判断活由 tools/lint_aging.py 的收敛表定，本脚本负责
把结果摊到具体行上，好让人逐行点头。

它同时报出两类需要人工处置的行，这两类机械替换做不了：
  · 换档后行高会跌破 1.3× 的（.lineHeight 必须跟着改）
  · 换档后文字变宽、而所在容器是固定宽/固定高的（可能挤掉或换行）

用法：
    python tools/plan_font_converge.py              # 全量计划
    python tools/plan_font_converge.py --csv FILE   # 导出逐行清单
退出码恒为 0 —— 这是规划器，不是门禁。
"""

import argparse
import csv
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lint_aging import (  # noqa: E402  复用同一份收敛表，避免两处失同步
    CONVERGE_FROM, EXEMPT, FONT_LADDER, LINE_HEIGHT_LADDER,
    TOKEN_FILES, collect_ets_files, line_is_comment,
)

FONT_SIZE = re.compile(r'\.fontSize\(\s*([0-9]+)\s*\)')
LINE_HEIGHT = re.compile(r'\.lineHeight\(\s*([0-9]+)\s*\)')

# 只读这些属性判断容器是否有固定尺寸。缺 height 不代表能长高，
# 但缺了它就必须人工看一眼，所以宁可多报。
WIDTH = re.compile(r'\.width\(\s*([0-9]+)\s*\)')
HEIGHT = re.compile(r'\.height\(\s*([0-9]+)\s*\)')

# 换档后需要一并跟改的行高：既要对上新的 1.3×，又要落在档内。
# 值与 DesignTokens.ets 的 LH_* 一一对应，名字也一起带过来，
# 免得报告里出现「18pt 建议用 LH_BODY」这种自相矛盾的行。
LINE_HEIGHT_FOR = {
    9: (17, 'LH_CAPTION'),
    12: (17, 'LH_CAPTION'),
    14: (22, 'LH_BODY'),
    18: (24, 'LH_TITLE'),
    22: (30, 'LH_SECTION'),
    28: (38, 'LH_DISPLAY'),
    44: (52, 'LH_HERO'),
}


def is_exempt(rel, lineno, size):
    for r, ln, sz, _needle, _why in EXEMPT:
        if r == rel and ln == lineno and (sz is None or sz == size):
            return True
    return False


def container_is_fixed(lines, start):
    """从组件起始行往上找 10 行，判断所在容器是否定宽/定高。

    为什么往上找而不是往下：ArkUI 的容器修饰写在组件**闭合**处——
    `Text(..).fontSize(13)` 往上十几行才是父 Column 的 `.width(40)`。
    往下找会撞到**下一个兄弟**的尺寸，把不相干的容器报成约束
    （上一版正是这样把 22 行全报成了「定宽」，实则多数只是定高）。
    """
    head = '\n'.join(lines[max(0, start - 10):start + 1])
    return bool(WIDTH.search(head)), bool(HEIGHT.search(head))


def own_line_height(lines, start):
    """只看本条链上（向下 8 行内）的 lineHeight，不看兄弟的。"""
    chain = '\n'.join(lines[start:start + 8])
    return LINE_HEIGHT.search(chain)


def text_width_hint(text, size, letter_spacing):
    """估算一行占多宽（vp）。汉字按 1.0 字宽，ASCII 按 0.55。"""
    w = 0.0
    for ch in text:
        if ch in '，。·—－「」（）％≤…':
            w += 1.0
        elif ch.isascii():
            w += 0.55
        else:
            w += 1.0
    return w * (size + letter_spacing)


def plan():
    rows = []
    for full, rel_parts in collect_ets_files():
        if rel_parts in TOKEN_FILES:
            continue
        rel = rel_parts[0].replace(os.sep, '/') + '/' + rel_parts[1]
        with open(full, encoding='utf-8') as fh:
            lines = fh.readlines()

        for lineno, line in enumerate(lines, 1):
            if line_is_comment(line):
                continue
            m = FONT_SIZE.search(line)
            if not m:
                continue
            size = int(m.group(1))
            if size in FONT_LADDER:
                continue
            if is_exempt(rel, lineno, size):
                continue

            target = CONVERGE_FROM.get(size)
            token = FONT_LADDER.get(target, '??')

            # 找这段 Text 的字面量，用它估宽度
            text = ''
            t = re.search(r"Text\(\s*(.+?)\s*\)\s*(\(|$|\.)", line)
            if t:
                text = t.group(1)
            else:
                for j in range(max(0, lineno - 3), min(len(lines), lineno + 2)):
                    t = re.search(r"Text\(\s*(.+?)\s*\)\s*(\(|$|\.)", lines[j])
                    if t:
                        text = t.group(1)
                        break

            # 同一条链上的 letterSpacing 与 lineHeight。
            # 行高只认本组件链，不认兄弟——否则 DetailPage 节标题
            # （它自己没写 lineHeight）会错借诗词块的 29 进来。
            ls = None
            for k in range(lineno - 1, min(len(lines), lineno + 7)):
                if line_is_comment(lines[k]):
                    continue
                found = re.search(r'\.letterSpacing\(\s*([0-9.]+)\s*\)', lines[k])
                if found:
                    ls = found
                    break
            letter_spacing = float(ls.group(1)) if ls else 0.0
            lh = own_line_height(lines, lineno - 1)

            width_now = text_width_hint(text, size, letter_spacing)
            width_next = text_width_hint(text, target, letter_spacing)
            has_w, has_h = container_is_fixed(lines, lineno - 1)

            lh_note = ''
            lh_value, lh_token = LINE_HEIGHT_FOR[target]
            if lh:
                cur = int(lh.group(1))
                if cur < target * 1.3 or cur < target + 4:
                    lh_note = '行高 %d → %d (%s)' % (cur, lh_value, lh_token)
            elif target >= 14:
                # 正文档没有显式行高时，ArkUI 用字体自身的行盒：
                # 13pt→14pt 之后默认行盒只有字号+1~2，会让中文贴行。
                lh_note = '无显式行高，建议补 %s(%d)' % (lh_token, lh_value)

            flags = []
            if has_w:
                flags.append('定宽')
            if has_h:
                flags.append('定高')
            if width_next > width_now * 1.25:
                flags.append('变宽 %.0f%%' % ((width_next / width_now - 1) * 100
                                              if width_now else 0))

            rows.append({
                'file': rel,
                'line': lineno,
                'from': size,
                'to': target,
                'token': token,
                'text': text[:60],
                'flags': ' '.join(flags),
                'lh': lh_note,
            })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--csv')
    args = ap.parse_args()

    rows = plan()
    if args.csv:
        with open(args.csv, 'w', newline='', encoding='utf-8') as fh:
            w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print('已写出 %d 行 → %s' % (len(rows), args.csv))
        return 0

    need_lh = [r for r in rows if r['lh']]
    need_space = [r for r in rows if r['flags']]

    by_to = {}
    for r in rows:
        by_to.setdefault((r['from'], r['to']), []).append(r)

    print('计划替换 %d 处，%d → %d 档\n' % (
        len(rows), len({r['from'] for r in rows}), len(FONT_LADDER)))
    for (frm, to), items in sorted(by_to.items(), key=lambda kv: kv[0][1]):
        print('  %3dpt → %3dpt (%s)  %3d 处' % (frm, to, FONT_LADDER[to], len(items)))

    print('\n需一并改行高：%d 处' % len(need_lh))
    for r in need_lh:
        print('  %-22s %4d  %3d→%3d  %s' % (
            r['file'], r['line'], r['from'], r['to'], r['lh']))

    print('\n需人工看挤压风险：%d 处' % len(need_space))
    for r in need_space:
        print('  %-22s %4d  %3d→%3d  [%s] %s' % (
            r['file'], r['line'], r['from'], r['to'], r['flags'], r['text']))

    return 0


if __name__ == '__main__':
    sys.exit(main())
