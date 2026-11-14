# 只读交叉校验：字重令牌与字族令牌是否配对正确。
#
# 抓的是「replace_all 把 sans 站点一起改成 WT_SERIF」这类误伤 —— 本批次
# 实际发生过两次（FavoritesPage:537、SyncPage:481）。这类错误编译期不报错，
# 屏上也只是「看着有点重」，靠肉眼看不出来。
#
# 规则：
#   1. 用了 FONT_SERIF 的组件，字重必须是 WT_SERIF
#   2. 用了 FONT_DISPLAY 的组件，字重必须是 WT_DISPLAY（单一 400 面）
#   3. 没用 FONT_SERIF 的组件，字重不得是 WT_SERIF
#   4. FONT_MONO 的组件不得带 WT_SERIF（等宽数字不靠衬线字重表意）；
#      允许 WT_MEDIUM —— HarmonyOS Sans Mono 带 wght 变轴，500 命中真面
#      不触发合成加粗，设计稿的层号 L1 用的就是它。
# 只读，不写源文件。

import os
import re
import sys

ETS = 'app/entry/src/main/ets'

COMPONENT = re.compile(r'\b(Text|Row|Column|Stack|Flex|Grid)\s*\(')
FONT_FAMILY = re.compile(r"\.fontFamily\(\s*(FONT_[A-Z]+|'[^']*')\s*\)")
# 三元形态也要匹配：`this.x ? WT_BOLD : WT_REGULAR` 的两支都是令牌。
FONT_WEIGHT = re.compile(r'\.fontWeight\(\s*(?:[^)]*?\?\s*(WT_[A-Z]+|[0-9]+)\s*:\s*)?(WT_[A-Z]+|[0-9]+)\s*\)')


def line_is_comment(line):
    s = line.strip()
    return s.startswith('//') or s.startswith('*') or s.startswith('/*')


def scan_up(lines, lineno, pattern):
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


def main():
    problems = []
    checked = 0
    for dirpath, _, files in os.walk(ETS):
        for fn in sorted(files):
            if not fn.endswith('.ets'):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ETS).replace(os.sep, '/')
            lines = open(full, encoding='utf-8').readlines()
            for i, line in enumerate(lines):
                if 'fontWeight' not in line or line_is_comment(line):
                    continue
                wm = FONT_WEIGHT.search(line)
                if not wm:
                    problems.append(('%s:%d' % (rel, i + 1), '字重不是令牌',
                                     line.strip()))
                    continue
                weights = [g for g in wm.groups() if g]
                family = scan_up(lines, i, FONT_FAMILY)
                checked += 1
                if family == 'FONT_SERIF':
                    bad = [w for w in weights if w != 'WT_SERIF']
                    if bad:
                        problems.append(('%s:%d' % (rel, i + 1),
                                         '衬线用了非 WT_SERIF 的字重', ','.join(bad)))
                elif family == 'FONT_DISPLAY':
                    bad = [w for w in weights if w != 'WT_DISPLAY']
                    if bad:
                        problems.append(('%s:%d' % (rel, i + 1),
                                         '展示体用了非 WT_DISPLAY 的字重（合成加粗，笔画糊）',
                                         ','.join(bad)))
                elif family == 'FONT_MONO':
                    # 等宽只禁 WT_SERIF：等宽数字不靠衬线字重表意，
                    # 但 WT_MEDIUM 命中真面（Sans Mono 有 wght 轴）。
                    bad = [w for w in weights if w == 'WT_SERIF']
                    if bad:
                        problems.append(('%s:%d' % (rel, i + 1),
                                         '等宽数字不该带衬线字重', ','.join(bad)))
                else:
                    bad = [w for w in weights if w == 'WT_SERIF']
                    if bad:
                        problems.append(('%s:%d' % (rel, i + 1),
                                         '非衬线却用了 WT_SERIF（合成加粗，笔画糊）',
                                         '字族=%s' % (family or '(sans)')))

    print('交叉校验 %d 处字重 × 字族配对\n' % checked)
    if not problems:
        print('配对全部正确。')
        return 0
    print('%d 处问题：' % len(problems))
    for where, what, detail in problems:
        print('  %-28s %-34s %s' % (where, what, detail))
    return 1


if __name__ == '__main__':
    sys.exit(main())