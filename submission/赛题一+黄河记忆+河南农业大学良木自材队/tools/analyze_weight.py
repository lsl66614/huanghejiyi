# 只读分析器：把每个 fontWeight 站点的「同一组件链上的字号 / 字族」列出来。
#
# 为什么不用 grep -B：ArkUI 修饰符挂在组件链的尾部，一个 Row 里可以同时有
# fontSize(12) 的眉标和 fontSize(18) 的标题，grep 会把上一段的字号安到下一段头上。
# 这里沿链往上找，遇到组件边界就停（与 lint_aging.size_on_chain 同一套规则）。
#
# 只读，不写任何源文件。

import os
import re
import sys

ETS = 'app/entry/src/main/ets'

COMPONENT = re.compile(r'\b(Text|Row|Column|Stack|Flex|Grid|Image|Button|ListItem)\s*\(')
FONT_SIZE = re.compile(r'\.fontSize\(\s*([0-9]+(?:\.[0-9]+)?|FS_[A-Z]+)\s*\)')
FONT_FAMILY = re.compile(r"\.fontFamily\(\s*'([^']*)'\s*\)")
FONT_WEIGHT = re.compile(r'\.fontWeight\(\s*(.+?)\s*\)\s*$')
TEXT_LIT = re.compile(r"Text\(\s*[`']([^`']{0,18})")


def line_is_comment(line):
    s = line.strip()
    return s.startswith('//') or s.startswith('*') or s.startswith('/*')


def scan_up(lines, lineno, pattern):
    """沿组件链往上找最近的一个匹配；跨过组件边界就返回 None。"""
    for j in range(lineno - 1, -1, -1):
        prev = lines[j]
        if line_is_comment(prev):
            continue
        m = pattern.search(prev)
        if m:
            return m.group(1)
        if COMPONENT.search(prev):
            return None
    return None


def text_near(lines, lineno):
    """找这个组件自己的 Text(...) 字面量。"""
    for j in range(lineno - 1, max(-1, lineno - 14), -1):
        s = lines[j].strip()
        if s.startswith('Text('):
            m = TEXT_LIT.search(s)
            return m.group(1) if m else '…'
        if COMPONENT.search(s) and not s.startswith('Text('):
            return None
    return None


def main():
    rows = []
    for dirpath, _, files in os.walk(ETS):
        for fn in sorted(files):
            if not fn.endswith('.ets'):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ETS).replace(os.sep, '/')
            if rel.startswith('common/'):
                continue
            lines = open(full, encoding='utf-8').readlines()
            for i, line in enumerate(lines):
                if 'fontWeight' not in line or line_is_comment(line):
                    continue
                m = FONT_WEIGHT.search(line.rstrip())
                if not m:
                    continue
                rows.append({
                    'rel': rel.split('/')[-1],
                    'path': rel,
                    'line': i + 1,
                    'weight': m.group(1),
                    'size': scan_up(lines, i, FONT_SIZE) or '?',
                    'family': scan_up(lines, i, FONT_FAMILY) or '(sans)',
                    'text': text_near(lines, i) or '?',
                })

    ternary = [r for r in rows if '?' in r['weight']]
    plain = [r for r in rows if '?' not in r['weight']]

    print('共 %d 处 fontWeight：二元选中态 %d 处，固定 %d 处\n'
          % (len(rows), len(ternary), len(plain)))
    print('%-20s %5s %-8s %-12s %s' % ('文件', '行', '字号', '字族', '字重'))
    print('-' * 78)
    for r in sorted(rows, key=lambda r: (r['rel'], r['line'])):
        print('%-20s %5d %-8s %-12s %-34s %s'
              % (r['rel'], r['line'], r['size'], r['family'],
                 r['weight'][:34], r['text'][:18]))

    print('\n按「字族 × 字重」汇总')
    print('-' * 78)
    tally = {}
    for r in rows:
        key = (r['family'], '二元' if '?' in r['weight'] else r['weight'])
        tally.setdefault(key, []).append('%s:%d' % (r['rel'][:3], r['line']))
    for key in sorted(tally):
        print('%-12s %-38s %2d 处  %s'
              % (key[0], key[1], len(tally[key]), ' '.join(tally[key])))

    return 0


if __name__ == '__main__':
    sys.exit(main())