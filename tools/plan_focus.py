# 只读：列出每个 .onClick 的宿主组件类型与所在文件、行号、accessibilityText。
#
# 用途：Phase 3c 给可见焦点环时，逐处加 .focusBox() 是 63 个改动点，
# 必须先知道哪些宿主是 Row/Column（容器，需要显式 focusable）、
# 哪些已经是 Button（原生带焦点），否则会漏或重复加。
#
# 只读，不写源文件。

import os
import re
import sys

ETS = 'app/entry/src/main/ets'

ON_CLICK = re.compile(r'\.onClick\(')
COMPONENT = re.compile(r'^\s*([A-Z][A-Za-z]*)\s*\(')
ACCESSIBILITY_TEXT = re.compile(r"\.accessibilityText\(\s*([^)]*)\)")


def line_is_comment(line):
    s = line.strip()
    return s.startswith('//') or s.startswith('*') or s.startswith('/*')


def find_host(lines, lineno):
    """往上找这个 onClick 挂在哪个组件上（ArkUI 修饰符挂在组件链尾部）。"""
    for j in range(lineno - 1, max(-1, lineno - 30), -1):
        prev = lines[j]
        if line_is_comment(prev):
            continue
        m = COMPONENT.match(prev)
        if m:
            return m.group(1), j + 1
        if ACCESSIBILITY_TEXT.search(prev):
            continue
        # 链上出现别的 onClick 说明已经越过本组件
        if ON_CLICK.search(prev):
            return None, j + 1
    return None, 0


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
                if not ON_CLICK.search(line) or line_is_comment(line):
                    continue
                host, hline = find_host(lines, i)
                # 收集本组件链上的 accessibilityText（从宿主往上）
                acc = ''
                for j in range(hline - 1, max(-1, hline - 25), -1):
                    m = ACCESSIBILITY_TEXT.search(lines[j])
                    if m:
                        acc = m.group(1)[:30]
                        break
                    if COMPONENT.match(lines[j]):
                        break
                rows.append((fn, i + 1, host or '(未识别)', acc))

    print('共 %d 处 onClick\n' % len(rows))
    print('%-20s %5s %-14s %s' % ('文件', 'onClick行', '宿主组件', 'accessibilityText'))
    print('-' * 76)
    for fn, ln, host, acc in sorted(rows):
        print('%-20s %5d %-14s %s' % (fn, ln, host, acc))

    print('\n按宿主组件汇总')
    print('-' * 76)
    tally = {}
    for fn, ln, host, acc in rows:
        tally.setdefault(host, []).append('%s:%d' % (fn[:3], ln))
    for host in sorted(tally, key=lambda h: -len(tally[h])):
        print('%-16s %2d 处   %s'
              % (host, len(tally[host]), ' '.join(tally[host][:8])
                 + (' …' if len(tally[host]) > 8 else '')))
    return 0


if __name__ == '__main__':
    sys.exit(main())