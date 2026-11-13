#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""适老化门禁：卡字号下限、行高下限、触摸热区。

依据是工信部《移动互联网应用（APP）适老化通用设计规范》：
  · 正文文字 ≥ 12pt
  · 行间距 ≥ 1.3 倍字号
另加一条 ArkUI 的硬约束：汉字行盒不小于「字号 + 4」，否则上下会被裁切。

为什么两个门禁要放在一起：一个字写成了 9pt，它旁边的行高再合规也没用；
反过来行高写成 18/11，字号抬到 12 之后这行仍会显得挤。二者互为条件，
但失败原因不同，分开报才看得见是哪条线被拉断。

本脚本只报「非豁免」处。豁免是有限列举，且每条都要写理由 ——
见 EXEMPT。凭空开一个「装饰性文字免检」的口子，等于把整个门禁作废。

用法：
    python tools/lint_aging.py            # 全量检查
    python tools/lint_aging.py --ladders  # 只看字号收敛进度
退出码 0 = 合规，1 = 有违规。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets')

# 令牌源自身不参与检查：这些文件按定义全是字面量。
TOKEN_FILES = {
    ('common', 'DesignTokens.ets'),
    ('common', 'EraTheme.ets'),
}

BODY_MIN_FONT = 12      # pt，工信部正文下限
LINE_HEIGHT_MIN_RATIO = 1.3
LINE_HEIGHT_MIN_DELTA = 4   # ArkUI 汉字行盒下限 = 字号 + 4
TOUCH_MIN = 50          # vp，适老热区下限

# ---------------------------------------------------------------- 收敛表
# 20 → 6。每处归到哪一档由语义层级决定，见 DesignTokens.ets 的注释。
# 下面这张表同时是 lint_tokens.py 的 OK_FONT_SIZE 来源，两处必须一致。
FONT_LADDER = {
    9: 'FS_MICRO',
    10: 'FS_TAB',
    11: 'FS_LABEL',
    12: 'FS_CAPTION',
    13: 'FS_META',
    14: 'FS_BODY',
    15: 'FS_ITEM',
    17: 'FS_HEAD',
    18: 'FS_TITLE',
    28: 'FS_DISPLAY',
    30: 'FS_PAGE',
    34: 'FS_LOCKUP',
    44: 'FS_HERO',
}

# 收敛前的历史值 → 收敛档。用于 --ladders 的进度统计。
CONVERGE_FROM = {
    8: 9, 9: 9,
    10: 12, 11: 12, 12: 12,
    13: 14, 14: 14, 15: 14,
    16: 18, 17: 18, 18: 18, 19: 18,
    22: 18,
    24: 28, 26: 28, 28: 28, 32: 28, 34: 28,
    40: 44, 44: 44,
}

LINE_HEIGHT_LADDER = {17, 22, 24, 32, 38, 40, 45, 52}

# ---------------------------------------------------------------- 豁免
# 每条 = (相对路径, 1-based 行号, 字号或 None) → 理由。
# 行号会随编辑漂移，故每个条目都附了原文片段做二次核对：
# 行号对不上、但文件里已无该片段时，脚本会报「豁免条目失效」，
# 提醒把这一行删掉，而不是让一个过期的豁免一直挂着。
EXEMPT = [
    # RelicPage 的「单色剪影占位」水印已删：它压在藏品签自带的
    # REAL PHOTO PENDING 上，信息也重复，豁免随之撤销。
    ('pages/ListPage.ets', 467, 9, '图像整备中',
     '列表缩略图的水印。原先是 8pt，收敛到 FS_MICRO 9pt '
     '后与另三处水印同档。'),
]

FONT_SIZE = re.compile(r'\.fontSize\(\s*([0-9]+(?:\.[0-9]+)?)\s*\)')
# 收敛完成后页面里写的是令牌名而不是数字；两者的排版结果等价，
# 统计与门禁都要认，故 TOKEN_SIZE 把令牌名也解析成数值。
TOKEN_SIZE = re.compile(r'\.fontSize\(\s*(FS_[A-Z]+)\s*\)')
TOKEN_VALUE = {v: k for k, v in FONT_LADDER.items()}
LINE_HEIGHT = re.compile(r'\.lineHeight\(\s*([0-9]+(?:\.[0-9]+)?|LH_[A-Z]+)\s*\)')
# LH_* 的数值必须与 DesignTokens.ets 一致，否则按令牌名写的行高
# 会被门禁跳过校验——令牌化本是为了让门禁更好用，不是让它失效。
LH_VALUE = {
    'LH_CAPTION': 17.0, 'LH_BODY': 22.0,
    'LH_TITLE': 24.0,
    'LH_DISPLAY': 38.0, 'LH_PAGE': 40.0, 'LH_LOCKUP': 45.0,
}
# 令牌名写错档位时门禁看不出来（数值合法但语义错），故并列出来供对照。
# 44pt（FS_HERO）是单行大字豁免档，行高 52 就地写数字、不走 LH_* 令牌
# （2026-11-05 起 LH_HERO/LH_META 两个死档已从 DesignTokens 删除）。
LH_FOR_SIZE = {
    9: 'LH_CAPTION', 10: 'LH_CAPTION', 11: 'LH_CAPTION', 12: 'LH_CAPTION',
    14: 'LH_BODY',
    18: 'LH_TITLE', 28: 'LH_DISPLAY',
    30: 'LH_PAGE', 34: 'LH_LOCKUP',
}
TEXT_ON_LINE = re.compile(r"Text\(\s*(.+?)\s*\)\s*(\(|$|\.)")


def line_is_comment(line):
    s = line.strip()
    return s.startswith('//') or s.startswith('*') or s.startswith('/*')


def exempt_for(rel, lineno, size):
    """返回豁理由；号漂移时按片段兜底比对。"""
    for r, ln, sz, needle, why in EXEMPT:
        if r == rel and ln == lineno and (sz is None or abs(sz - size) < 0.01):
            return why, True
    return None, False


def resolve_exempt_lines():
    """把 EXEMPT 的行号重定位到片段实际所在行。

    为什么需要重定位：豁免表原本按 (文件, 行号) 匹配，任何一次编辑都会
    让行号漂移，于是每改一次代码就要手工改一遍表——本轮改按压反馈时
    反复踩到。行号不该是豁免的身份，**片段才是**：豁免说的是「这一处
    特定的水印字」，不是「第 467 行的那几个字」。

    重定位规则：在同一文件里找唯一一处包含片段文本的行；找到就更新行号，
    找不到或找到多处都视为失效（失效会让门禁报错，提醒人来核对）。
    """
    global EXEMPT
    out = []
    for r, ln, sz, needle, why in EXEMPT:
        full = os.path.join(ETS, r.replace('/', os.sep))
        if not os.path.exists(full):
            out.append((r, ln, sz, needle, why))
            continue
        with open(full, encoding='utf-8') as fh:
            lines = fh.readlines()
        # 只认非注释行：片段常同时出现在解释性注释和实际代码里，
        # 注释不算「这一处豁免指向的位置」。
        hits = [i + 1 for i, l in enumerate(lines)
                if needle in l and not line_is_comment(l)]
        if len(hits) == 1:
            out.append((r, hits[0], sz, needle, why))
        else:
            out.append((r, ln, sz, needle, why))
    EXEMPT = out


def check_exempt_staleness():
    """豁免行号漂移了、片段又找不到的条目，报失效。

    判据是**片段在不在**，不是「这一行有没有裸 fontSize」。收敛完成后
    水印那几处已经写成 `.fontSize(FS_MICRO)`，裸数字消失，若还按数字
    匹配就会把仍然有效的豁免误报成失效。
    """
    dead = []
    alive = set()
    resolve_exempt_lines()
    for rel, ln, _sz, needle, _why in EXEMPT:
        full = os.path.join(ETS, rel.replace('/', os.sep))
        if not os.path.exists(full):
            dead.append((rel, ln, needle, '文件已不存在'))
            continue
        with open(full, encoding='utf-8') as fh:
            lines = fh.readlines()
        window = ''.join(lines[max(0, ln - 2):ln + 2])
        if needle not in window:
            dead.append((rel, ln, needle, '行号已漂移，片段不在附近'))
        else:
            alive.add((rel, ln))
    return dead, alive


def collect_ets_files():
    for dirpath, _, files in os.walk(ETS):
        for fn in sorted(files):
            if not fn.endswith('.ets'):
                continue
            rel = os.path.relpath(dirpath, ETS)
            yield os.path.join(dirpath, fn), (rel, fn)


def size_on_chain(lines, lineno):
    """往上找本条链的字号，但**不能跨组件边界**。

    上一版一路找到文件头，于是 SyncPage 那条 12pt 的提示借到了上方节标题
    的 FS_DISPLAY(28)，报成「行高 18 配字号 28 = 0.64×」——真实值是
    18/12 = 1.50×，本该合规。判据：遇到新起组件的行就停。
    """
    for j in range(lineno - 1, -1, -1):
        prev = lines[j]
        if line_is_comment(prev):
            continue
        f = FONT_SIZE.search(prev) or TOKEN_SIZE.search(prev)
        if f:
            raw = f.group(1)
            return float(raw) if raw.replace('.', '').isdigit() \
                else TOKEN_VALUE.get(raw)
        if re.search(r'\b(Text|Row|Column|Stack|Flex|Grid)\s*\(', prev):
            return None
    return None


def scan():
    violations = []
    scanned = 0
    used_exempt = set()
    histogram = {}
    dead, alive = check_exempt_staleness()
    used_exempt |= alive

    for full, rel_parts in collect_ets_files():
        if rel_parts in TOKEN_FILES:
            continue
        scanned += 1
        rel = rel_parts[0].replace(os.sep, '/') + '/' + rel_parts[1]
        with open(full, encoding='utf-8') as fh:
            lines = fh.readlines()

        for lineno, line in enumerate(lines, 1):
            if line_is_comment(line):
                continue

            m = FONT_SIZE.search(line) or TOKEN_SIZE.search(line)
            if not m:
                continue
            raw = m.group(1)
            size = float(raw) if raw.replace('.', '').isdigit() \
                else TOKEN_VALUE.get(raw)
            if size is None:
                continue
            histogram[int(size)] = histogram.get(int(size), 0) + 1

            # 豁免优先于任何判断：这些点写的是令牌名，数字匹配不到。
            why, _exact = exempt_for(rel, lineno, size)
            if why:
                used_exempt.add((rel, lineno))
                continue
            # 判「在不在档内」要比解析后的数值，不是原始字符串 raw：
            # 收敛后 raw 已是 'FS_BODY' 这类令牌名，拿它去查以整数为键的
            # FONT_LADDER 必然不中，会把全站 190 处令牌写法全报成档外。
            if int(size) in FONT_LADDER:
                continue
            target = CONVERGE_FROM.get(int(size))
            tok = FONT_LADDER.get(target, '?')
            if size < BODY_MIN_FONT:
                violations.append(
                    ('font', rel, lineno, size,
                     '低于正文下限 %dpt，应归 %s(%s)；'
                     '确为装饰请在 EXEMPT 里写明理由'
                     % (BODY_MIN_FONT, tok, target)))
            else:
                violations.append(
                    ('ladder', rel, lineno, size,
                     '档外取值，应归 %s(%s)' % (tok, target)))

            m = LINE_HEIGHT.search(line)
            if m:
                raw = m.group(1)
                lh = LH_VALUE[raw] if raw.startswith('LH_') else float(raw)
                fsize = size_on_chain(lines, lineno)
                if fsize is None:
                    continue
                if lh < fsize * LINE_HEIGHT_MIN_RATIO \
                        or lh < fsize + LINE_HEIGHT_MIN_DELTA:
                    violations.append(
                        ('lineHeight', rel, lineno, lh,
                         '字号 %g，行高需 ≥ %g（1.3×）且 ≥ %g（字号+4），'
                         '当前 %g = %.2f×'
                         % (fsize, fsize * 1.3, fsize + 4, lh, lh / fsize)))
                elif raw.startswith('LH_') and int(fsize) in LH_FOR_SIZE \
                        and raw != LH_FOR_SIZE[int(fsize)]:
                    violations.append(
                        ('lineHeight', rel, lineno, lh,
                         '%gpt 该配 %s，当前写的是 %s（数值合规但档位错）'
                         % (fsize, LH_FOR_SIZE[int(fsize)], raw)))

    for r, ln, _sz, needle, _why in EXEMPT:
        if (r, ln) not in used_exempt:
            dead.append((r, ln, needle, '未在预期位置命中，可能是行号漂移'))

    return violations, scanned, histogram, dead


def print_ladder(histogram):
    print('字号分布（收敛目标 7 档：%s）\n' % '/'.join(
        str(k) for k in sorted(FONT_LADDER)))
    total = sum(histogram.values())
    for size in sorted(histogram, reverse=True):
        n = histogram[size]
        target = CONVERGE_FROM.get(size)
        mark = '  ← 合规' if size in FONT_LADDER else (
            '  → 应归 %d' % target if target else '')
        print('  %3dpt  %3d 处 (%4.1f%%)%s' % (size, n, n * 100.0 / total, mark))
    off = sum(n for s, n in histogram.items() if s not in FONT_LADDER)
    print('\n  档内 %d 处，档外 %d 处（%.1f%%）' % (
        total - off, off, off * 100.0 / total))


def main(argv):
    ladders = '--ladders' in argv
    violations, scanned, histogram, dead = scan()

    if ladders:
        print('扫描 %d 个文件' % scanned)
        print_ladder(histogram)
        return 0

    if dead:
        print('\n[豁免失效] %d 处' % len(dead))
        for rel, ln, needle, why in dead:
            print('  %-26s %4d  片段「%s」：%s' % (rel, ln, needle, why))

    by_kind = {}
    for v in violations:
        by_kind.setdefault(v[0], []).append(v)

    for kind in sorted(by_kind):
        items = by_kind[kind]
        print('\n[%s] %d 处' % (kind, len(items)))
        for _, rel, lineno, val, why in items[:120]:
            print('  %-26s %4d  %-6g %s' % (rel, lineno, val, why))
        if len(items) > 120:
            print('  ... 另有 %d 处未列出' % (len(items) - 120))

    print('\n' + '-' * 78)
    print_ladder(histogram)
    print('扫描 %d 个文件，越规 %d 处（豁免 %d 处，失效 %d 处）'
          % (scanned, len(violations), len(EXEMPT), len(dead)))
    return 1 if violations or dead else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
