#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""无障碍 lint。

规则 1（symbol）：可见文字是纯符号的可交互元素必须有 accessibilityText。
    「‹」「›」「✕」「◀」「☆」这类字符对读屏用户是无意义的——语音引擎
    会念「左尖括号」或干脆跳过，用户听到的是一个没有动词的控件。
    本项目此前全站 accessibilityText 计数为 0，是评审表里最硬的扣分项。

规则 2（motion）：.animation({duration: N}) / animateTo({duration: N})
    的 N 必须是 dur*() 调用，不能是字面量。
    否则系统「减弱动画」开关对该处无效——这是适配性缺陷，不是风格问题。

关于「规则 3（card）」：曾想用「带 onClick 的容器若内部有 ≥3 个 Text 则
必须有 accessibilityText」来卡碎片朗读。写出来后大量误报——ArkUI 的
accessibilityText 写在闭合链上（Index 年代卡隔了 27 行才写到那个箭头），
任何基于「向上/向下看 N 行」的近似都会判错。故本版不实现该规则；
标签覆盖率改由本脚本末尾的统计输出观察，不作门禁。

用法：
    python tools/lint_a11y.py
退出码 0 = 通过，1 = 有缺陷。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets')

# 纯符号/图标类可见文字。命中即要求同链路上有 accessibilityText。
SYMBOL_RE = re.compile(
    r"Text\(\s*'([^']*)'\s*\)")

def is_symbolic(s: str) -> bool:
    """整串由非汉字、非字母数字的装饰字符构成。"""
    if not s:
        return False
    has_word = False
    for ch in s:
        if ch.isalnum():
            has_word = True
            break
        if '一' <= ch <= '鿿':   # CJK 统一表意文字
            has_word = True
            break
    return not has_word


CLICK = re.compile(r'\.onClick\(')
# 只认「能提供可访问名称」的属性。
# accessibilityLevel（标记为可聚焦无障碍节点）与 accessibilityTextHint
# （操作提示）都不是名称——把它们算作标签，会让「有焦点无名字」的控件
# 混过门禁。accessibilityGroup 会把子节点并成一个节点，等价于给了合并名。
A11Y_TEXT = re.compile(r'\.accessibilityText\(|'
                       r'\.accessibilityGroup\(|'
                       r'\.accessibilityDescription\(')
ANIM_LITERAL = re.compile(
    r'(?:\.animation\(\s*\{\s*duration:\s*|animateTo\(\s*\{\s*duration:\s*)(\d+)')
ANIM_OPTS_LITERAL = re.compile(r'animation:\s*\{\s*duration:\s*(\d+)')

# 能承载无障碍标签的容器。Text 之外的组件，标签一般写在它自己的闭合链上。
CONTAINER_RE = re.compile(
    r'^\s*(Row|Column|Stack|Flex|Grid|GridItem|List|ListItem|Scroll|'
    r'Tabs|TabContent|RelativeContainer|ListItemGroup)\s*\(')


def line_comment(line: str) -> bool:
    s = line.strip()
    return s.startswith('//') or s.startswith('*') or s.startswith('/*')


def indent_of(line: str) -> int:
    return len(line) - len(line.lstrip())


def strip_strings(line: str) -> str:
    """去掉单/双/反引号字符串内容，让括号计数不被文案里的花括号带偏。"""
    return re.sub(r"'[^']*'|\"[^\"]*\"|`[^`]*`", '""', line)


def find_close(lines, start):
    """块体组件的起始行 -> 匹配的 '}' 所在行号；无块体返回 None。

    括号只在整行结算：`Column({ space: 10 }) {` 这一行里参数的花括号
    会让深度中途回到 0，逐字符判定会误认为「本行即闭合」。
    """
    if not lines[start].rstrip().endswith('{'):
        return None
    depth = 0
    for k in range(start, len(lines)):
        if line_comment(lines[k]):
            continue
        for ch in strip_strings(lines[k]):
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
        if depth == 0:
            return k
    return None


def brace_delta(line: str) -> int:
    d = 0
    for ch in strip_strings(line):
        if ch == '{':
            d += 1
        elif ch == '}':
            d -= 1
    return d


def chain_span(lines, start):
    """组件起始行 -> 其修饰符链覆盖到的行号（0-based，闭区间）。

    ArkUI 的链是竖着写的，且有两种形态：
      形态 A  Text('x').fontSize(12).accessibilityText('…')      —— 链紧随其后
      形态 B  Row() { … } .accessibilityText('…')                —— 标签在块体闭合之后
    Index 的年代卡是形态 B，且闭合链隔了二十多行，所以既不能按固定行数
    窥视，也不能只往下扫。

    链上还会夹着回调体（`.onClick(() => { … })`），必须整块跳过：
    回调体里的 `router.pushUrl(...)` 不以 `.` 开头，一行就足以把链截断。
    """
    n = len(lines)
    j = start
    close = find_close(lines, start)
    if close is not None:
        j = close
    while j + 1 < n:
        nxt = lines[j + 1]
        s = nxt.strip()
        if not s or line_comment(nxt):
            j += 1
            continue
        if s.startswith('.') or s.startswith('}') or s.startswith(')'):
            j += 1
            delta = brace_delta(nxt)
            if delta > 0:
                end = find_close(lines, j)
                if end is None:
                    break
                j = end
            continue
        break
    return j


def chain_start(lines, at):
    """链上任一行 -> 所属组件的起始行（0-based）。

    规则 3 的 onClick 多数写在链尾，而 focusBox 常写在 onClick 之前
    （先样式后行为是这个项目的手序）。只从 onClick 往后看会漏判，
    所以必须先回退到组件起点再让 chain_span 往前扫。

    回退按花括号深度走，而不是按首字符：`.onClick(() => {` 的块体里
    `this.openNote();` 既不以 . 也不带 }，只看首字符会当场停住；
    反过来 `})` 收尾行本身又不属于新组件，必须连着链一起跳过。
    depth < 0 表示这一行是个块的结尾，depth > 0 表示还在块体里，
    两种都只是链的一部分，继续往上走。
    """
    i = at
    depth = 0
    while i > 0:
        i -= 1
        t = lines[i].strip()
        if not t or line_comment(lines[i]):
            continue
        depth -= brace_delta(lines[i])
        if depth != 0:
            continue
        if t.startswith(('.', '}', ')')):
            continue
        break
    return i


def labelled(lines, start):
    """该组件自身链上是否有无障碍标签。

    只看闭合链那一段，不看块体内部——否则外层页面 Column 会「继承」到
    子节点自己的 accessibilityText，一条都没标的列表行反而被判合格。
    块体组件从闭合行起算，修饰符优先的组件从起始行起算。
    """
    close = find_close(lines, start)
    first = close if close is not None else start
    end = chain_span(lines, start)
    for k in range(first, end + 1):
        if line_comment(lines[k]):
            continue
        if A11Y_TEXT.search(lines[k]):
            return True
    return False


def ancestor_labelled(lines, start, indent):
    """逐层向外找带标签的祖先容器。start 为 0 基行号。

    装饰箭头（`›`）自己没有标签是正常的——它的父容器通常已经把整张卡
    合并成一句话了，读屏根本不会单独聚焦到箭头。所以向上找是必要的，
    而且必须一路走到文件头，不能只窥视固定行数。
    """
    for up in range(start - 1, -1, -1):
        line = lines[up]
        if line_comment(line):
            continue
        if indent_of(line) >= indent:
            continue
        if CONTAINER_RE.match(line):
            indent = indent_of(line)
            if labelled(lines, up):
                return True
    return False


def scan():
    findings = []
    scanned = 0
    a11y_n = 0
    for dirpath, _, files in os.walk(ETS):
        for fn in sorted(files):
            if not fn.endswith('.ets'):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT)
            with open(full, encoding='utf-8') as fh:
                lines = fh.readlines()
            scanned += 1

            # 规则 2：动效字面量
            for ln, line in enumerate(lines, 1):
                if line_comment(line):
                    continue
                for m in list(ANIM_LITERAL.finditer(line)) + list(ANIM_OPTS_LITERAL.finditer(line)):
                    findings.append(('motion', rel, ln,
                                     'duration: %s（字面量）' % m.group(1),
                                     '应改为 dur*()，否则系统「减弱动画」开关无效'))

            # 规则 1：符号 Text 必须在自身链或任一祖先容器上有 accessibilityText。
            for ln, line in enumerate(lines, 1):
                if line_comment(line):
                    continue
                for m in SYMBOL_RE.finditer(line):
                    if not is_symbolic(m.group(1)):
                        continue
                    if labelled(lines, ln - 1):
                        continue
                    if ancestor_labelled(lines, ln - 1, indent_of(line)):
                        continue
                    findings.append(('symbol', rel, ln,
                                     "Text('%s')" % m.group(1),
                                     '符号按钮需自身或祖先配 accessibilityText'))

            a11y_n += sum(1 for line in lines if A11Y_TEXT.search(line))

            # 规则 3：可交互元素必须有焦点环。
            # 理由：触屏点得中，但键盘、开关控制、读屏「逐项浏览」三种场景
            # 全靠焦点遍历。只加 focusBox 不加 focusable(true) 时环根本不
            # 显示（Text、Image 默认不可聚焦）；只加 focusable 则有焦点
            # 无指示，用户会以为页面卡住。两条缺一不可。
            for ln, line in enumerate(lines, 1):
                if line_comment(line) or '.onClick(' not in line:
                    continue
                # 空回调不算交互：ArkUI 的触摸会冒泡到父级，容器必须挂一个
                # 空 onClick 把事件吃掉（灯箱的主图区就是这样防误关的）。
                # 判据是回调体里除了注释没有别的语句。
                end = find_close(lines, ln - 1)
                if end is not None and not any(
                        lines[k].strip() and not line_comment(lines[k])
                        for k in range(ln, end)):
                    continue
                start = chain_start(lines, ln - 1)
                end = chain_span(lines, start)
                if not any('focusBox(' in lines[k]
                           for k in range(start, end + 1)):
                    findings.append(('focus', rel, ln,
                                     '.onClick 无 focusBox',
                                     '需 .focusBox(focusRing())；'
                                     'Text/Image 还需 .focusable(true)'))

    return findings, scanned, a11y_n


def main():
    findings, scanned, a11y_n = scan()
    by_rule = {}
    for f in findings:
        by_rule.setdefault(f[0], []).append(f)

    for rule in sorted(by_rule):
        items = by_rule[rule]
        print('\n[%s] %d 处' % (rule, len(items)))
        for _, rel, ln, text, why in items[:100]:
            print('  %-40s %4d  %-28s %s' % (rel, ln, text[:28], why))
        if len(items) > 100:
            print('  ... 另有 %d 处' % (len(items) - 100))

    print('\n' + '-' * 78)
    print('扫描 %d 个文件，无障碍标签 %d 处，缺陷 %d 处'
          % (scanned, a11y_n, len(findings)))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())