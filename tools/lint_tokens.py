#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""设计令牌 lint：拦截页面里的裸值。

为什么需要：迁移到 DesignTokens.ets 之前，19 种字号、30+ 种间距、
上百个裸色值散在十个页面里。「统一字号」这种需求当时无法执行——
不知道哪些 11 是该变成 12、哪些 11 是眉标。本脚本把「不许写裸值」
变成门禁，配合 lint_aging.py 的收敛表，让收敛过程可核查。

规则分级 —— 不是所有规则都该在同一天变绿：
  color    Phase 1 起强制。裸色值是设计与实现脱节的根源，且改动
           风险最低（纯替换，不改布局），一次性做完。
  radius   Phase 1 起强制。现状本来就只有 4 个值，改名即可。
  spacing  Phase 2 起强制。需要逐处判断吸附到哪一档，人工确认。
           2026-10-24 起常开：全站间距已全部落在档位上（lint_visual_
           consistency 的 6 条基线豁免同日清空），不再是「按需加 --all」。
  fontSize Phase 4 起强制。19→6 的收敛会改变排版，必须配合
           逐页视觉核对，不能批量替换。
  lineHeight Phase 4 起强制。同上，且要随字号一起调。

用法：
    python tools/lint_tokens.py              # 检查已启用的规则
    python tools/lint_tokens.py --all        # 含未启用规则（看剩余债务）
    python tools/lint_tokens.py --count      # 只出汇总
退出码 0 = 干净，1 = 有裸值。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets')

# 令牌源自身不参与检查（它们当然全是字面量）
TOKEN_FILES = {
    ('common', 'DesignTokens.ets'),
    ('common', 'EraTheme.ets'),
}

# 规则 -> 是否已启用。迁移批次推进时逐条打开。
#  fontSize / lineHeight 于 Phase 4 打开：字号 20 → 7 档已由
#  tools/apply_font_converge.py 全量落地，lint_aging.py 与本脚本
#  共享同一份收敛表，两者结论必须一致。
RULES = {
    'color': True,
    'radius': True,
    'spacing': True,
    'fontSize': True,
    'lineHeight': True,
    'fontWeight': True,
    'fontFamily': True,
}

# 已收敛到令牌的取值集合。命中即视为「已迁移」，不报错。
# 数值来自 common/DesignTokens.ets，改令牌表时同步这里。
OK_RADIUS = {'0', '4', '8', '190'}
OK_FONT_SIZE = {'9', '12', '14', '18', '22', '28', '44'}
OK_LINE_HEIGHT = {'17', '22', '24', '30', '38', '52'}
OK_FONT_WEIGHT = {'400', '500', '700', '800'}
OK_FONT_FAMILY = {'FONT_SERIF', 'FONT_MONO'}
OK_SPACING = {'0', '1', '3', '4', '6', '8', '10', '12', '16', '24', '32', '40', '80'}

# 颜色字面量。规则是「页面里不出现任何十六进制色值」，不做属性白名单：
# 属性白名单永远漏项（上一版就漏了 backgroundColor 和本地 const 声明），
# 而本地 const SUB = '#6B6357' 本身就是第二个事实源，正是要消灭的东西。
# 排除 Color.Transparent / Color.White 这类枚举 —— 它们不是裸值。
COLOR_LITERAL = re.compile(r"'#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?'")

RADIUS = re.compile(r'\.borderRadius\(\s*([0-9]+)\s*\)')
FONT_SIZE = re.compile(r'\.fontSize\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)')
LINE_HEIGHT = re.compile(r'\.lineHeight\(\s*([0-9]+(?:\.[0-9]+)?|LH_[A-Z]+)\s*\)')
LINE_HEIGHT_TOKEN = {'LH_CAPTION': '17', 'LH_BODY': '22', 'LH_TITLE': '24',
                     'LH_DISPLAY': '38'}

# 字重：只认裸数字。FontWeight.Bold / FontWeight.Bolder 这类枚举全部拦下 ——
# 它们是 700 与 800 两个不同的视觉重量，混用时在屏上看不出差别（实测
# 收敛前 18pt 上同时存在 700 与 800 两种写法）。
FONT_WEIGHT = re.compile(r'\.fontWeight\(\s*([0-9]{3})\s*\)')
FONT_WEIGHT_ENUM = re.compile(r'\.fontWeight\(\s*FontWeight\.[A-Za-z]+\s*\)')

# 字族：只认令牌名。FontFamily 里出现字符串字面量即为绕过令牌 ——
# Courier New 就是这么溜进来的（鸿蒙上没有，靠系统替换兜底，观感不可控）。
FONT_FAMILY = re.compile(r"\.fontFamily\(\s*'([^']*)'\s*\)")

# 间距：padding/margin 的对象字面量（取其中的裸数字）、Row/Column 的
# space 属性、以及 padding(14) 这种直接传数的形态。
SPACE_OBJ = re.compile(r'\.(?:padding|margin)\(\{([^}]*)\}\)')
SPACE_PROP = re.compile(r'\bspace:\s*([0-9]{1,3})\b')
SPACE_DIRECT = re.compile(r'\.(?:padding|margin)\(\s*([0-9]{1,3})\s*\)')

# 对象字面量里不是间距的数字形态（百分比、字号、行高）。
SPACE_SKIP = re.compile(r'%|fontSize|lineHeight|letterSpacing|duration')


def line_is_comment(line: str) -> bool:
    s = line.strip()
    return s.startswith('//') or s.startswith('*') or s.startswith('/*')


def collect_ets_files():
    for dirpath, _, files in os.walk(ETS):
        for fn in sorted(files):
            if not fn.endswith('.ets'):
                continue
            rel = os.path.relpath(dirpath, ETS)
            yield os.path.join(dirpath, fn), (rel, fn)


def scan(active_rules):
    """返回 (violations, scanned_count)。"""
    violations = []
    scanned = 0

    for full, rel_parts in collect_ets_files():
        if rel_parts in TOKEN_FILES:
            continue
        scanned += 1
        rel = os.path.join(*rel_parts)
        with open(full, encoding='utf-8') as fh:
            lines = fh.readlines()

        for lineno, line in enumerate(lines, 1):
            if line_is_comment(line):
                continue

            def add(rule, text, detail):
                if rule in active_rules:
                    violations.append((rel, lineno, rule, text, detail))

            if 'color' in active_rules:
                for m in COLOR_LITERAL.finditer(line):
                    add('color', m.group(0),
                        '应写 DesignTokens / EraTheme 里的语义令牌')

            if 'radius' in active_rules:
                for m in RADIUS.finditer(line):
                    v = m.group(1)
                    if v not in OK_RADIUS:
                        add('radius', m.group(0),
                            '收敛档 %s' % '/'.join(sorted(OK_RADIUS)))

            if 'fontSize' in active_rules:
                for m in FONT_SIZE.finditer(line):
                    if m.group(1) not in OK_FONT_SIZE:
                        add('fontSize', m.group(0),
                            '收敛档 %s' % '/'.join(sorted(OK_FONT_SIZE)))

            if 'lineHeight' in active_rules:
                for m in LINE_HEIGHT.finditer(line):
                    raw = m.group(1)
                    if raw.startswith('LH_'):
                        continue          # 已用令牌，归档正确
                    if raw not in OK_LINE_HEIGHT:
                        add('lineHeight', m.group(0),
                            '收敛档 %s' % '/'.join(sorted(OK_LINE_HEIGHT)))

            if 'fontWeight' in active_rules:
                for m in FONT_WEIGHT_ENUM.finditer(line):
                    add('fontWeight', m.group(0),
                        '用 WT_REGULAR/WT_MEDIUM/WT_BOLD/WT_SERIF，'
                        '不要写枚举（Bold 与 Bolder 是两个重量）')
                for m in FONT_WEIGHT.finditer(line):
                    if m.group(1) not in OK_FONT_WEIGHT:
                        add('fontWeight', m.group(0),
                            '收敛档 %s' % '/'.join(sorted(OK_FONT_WEIGHT)))

            if 'fontFamily' in active_rules:
                for m in FONT_FAMILY.finditer(line):
                    add('fontFamily', m.group(0),
                        '用 %s；需要新字族先在 DesignTokens 里定角色'
                        % '/'.join(sorted(OK_FONT_FAMILY)))

            if 'spacing' in active_rules:
                for pat, label in ((SPACE_OBJ, 'padding/margin 对象'),
                                   (SPACE_PROP, 'space'),
                                   (SPACE_DIRECT, 'padding/margin 直传')):
                    for m in pat.finditer(line):
                        body = m.group(1) if m.lastindex else m.group(0)
                        if SPACE_SKIP.search(m.group(0)):
                            continue
                        for n in re.findall(r'(?<![\w.])(\d{1,3})(?![\w.])', body):
                            if n in OK_SPACING:
                                continue
                            add('spacing', '%s → %s' % (label, n),
                                '吸附到 %s 之一' % '/'.join(sorted(OK_SPACING)))

    return violations, scanned


def main(argv):
    show_all = '--all' in argv
    count_only = '--count' in argv
    active = set(RULES) if show_all else {r for r, on in RULES.items() if on}

    violations, scanned = scan(active)

    if not count_only:
        by_rule = {}
        for v in violations:
            by_rule.setdefault(v[2], []).append(v)
        for rule in sorted(by_rule):
            items = by_rule[rule]
            print('\n[%s] %d 处' % (rule, len(items)))
            for rel, lineno, _, text, detail in items[:120]:
                print('  %-26s %4d  %-24s %s' % (rel, lineno, text[:24], detail))
            if len(items) > 120:
                print('  ... 另有 %d 处未列出' % (len(items) - 120))
        disabled = [r for r, on in RULES.items() if not on]
        if disabled:
            print('\n未启用规则（用 --all 查看）：%s' % ' '.join(sorted(disabled)))
        print('\n' + '-' * 78)

    print('扫描 %d 个文件，裸值 %d 处' % (scanned, len(violations)))
    return 1 if violations else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))