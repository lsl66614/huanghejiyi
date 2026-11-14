# 只读：为每个 onClick 生成「插什么、插在哪一行之后」的清单。
#
# 不写源文件。原因同 apply_font_converge 的教训：批量写入脚本
# 曾经把六个源文件写坏。清单给人看，改动用 Edit 逐处做。
#
# 插入策略（关键）：ArkUI 修饰符挂在组件链尾部，而 onClick 后面常常还跟着
# 别的修饰符（accessibilityText / accessibilityLevel / .width 等）。
# 必须插在**整条链的末尾**，也就是这条链最后一个修饰符之后，
# 而不是紧跟 .onClick( 那一行。所以这里不是按行号插，而是标出
# 「链尾行号」——从 onClick 往下找，直到遇见组件起始或链尾。
#
# 用法：python tools/apply_focus_plan.py [文件名]

import os
import re
import sys

ETS = 'app/entry/src/main/ets'

ON_CLICK = re.compile(r'\.onClick\(')
COMPONENT = re.compile(r'^\s*([A-Z][A-Za-z]*)\s*\(')
CHAIN_MODIFIER = re.compile(r'^\s*\.([A-Za-z][A-Za-z0-9]*)\s*\(')
ACCESSIBILITY = re.compile(r'^\s*\.accessibility[A-Za-z]*\s*\(')


def line_is_comment(line):
    s = line.strip()
    return s.startswith('//') or s.startswith('*') or s.startswith('/*')


def find_chain_end(lines, start):
    """从 onClick 所在行往下找到整条修饰符链的末尾（相对缩进不变浅）。

    关键：`.onClick(() => {` 后面跟着多行块，光看缩进会在块的
    内部就误判成链尾。因此先做括号配平，跳过整个块，再继续找链。
    """
    base = len(lines[start]) - len(lines[start].lstrip())
    depth = 0
    last = start
    seen_open = False
    for j in range(start, len(lines)):
        s = lines[j]
        depth += s.count('(') - s.count(')')
        if s.count('{'):
            seen_open = True
        if seen_open and depth <= 0 and j > start:
            # onClick 的参数块刚闭合，接着看它后面还挂不挂别的修饰符
            break
        last = j
    # 从闭合点往后，同缩进的链式修饰符仍属本链
    for j in range(last + 1, len(lines)):
        s = lines[j]
        stripped = s.strip()
        if not stripped:
            continue
        indent = len(s) - len(s.lstrip())
        if indent < base:
            break
        if indent == base and not CHAIN_MODIFIER.match(s) \
                and not stripped.startswith('.') and not stripped.startswith('}'):
            break
        last = j
    return last


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    total = 0
    files = {}
    for dirpath, _, fs in os.walk(ETS):
        for fn in sorted(fs):
            if not fn.endswith('.ets'):
                continue
            if only and fn != only:
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ETS).replace(os.sep, '/')
            if rel.startswith('common/'):
                continue
            lines = open(full, encoding='utf-8').readlines()
            hits = []
            for i, line in enumerate(lines):
                if not ON_CLICK.search(line) or line_is_comment(line):
                    continue
                end = find_chain_end(lines, i)
                tail = lines[end].rstrip()
                # 整条链上找 focusBox：从 onClick 往下到链尾，再从 onClick
                # 往上到组件起始。只查链尾会漏掉写在 onClick **之前**的
                # .focusBox()——Button 那几处就是这么写的。
                already = any('focusBox' in lines[k] for k in range(i, end + 1))
                if not already:
                    for j in range(i - 1, max(-1, i - 30), -1):
                        if lines[j].strip().startswith('Text(') or \
                                lines[j].strip().startswith('Button(') or \
                                lines[j].strip().startswith('Image(') or \
                                lines[j].strip().startswith('Row(') or \
                                lines[j].strip().startswith('Column('):
                            break
                        if 'focusBox' in lines[j]:
                            already = True
                            break
                hits.append((i + 1, end + 1, tail, already))
            if hits:
                files[fn] = hits
                total += len(hits)

    for fn in sorted(files):
        print('\n═══ %s （%d 处）' % (fn, len(files[fn])))
        for onc, endl, tail, done in files[fn]:
            mark = '已完成' if done else '待改  '
            print('  onClick@%-4d 链尾@%-4d %s  %s'
                  % (onc, endl, mark, tail.strip()[:44]))
    print('\n合计 %d 处，文件 %d 个' % (total, len(files)))
    return 0


if __name__ == '__main__':
    sys.exit(main())