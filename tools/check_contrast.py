#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""设计令牌对比度 lint。

为什么需要这个：黄河题材大量使用中间调背景（年代色 6 个、土黄/赭石），
这类底色与黑字白字都容易在 4.5:1 边缘上打滑。此前只能靠人工目视，
本脚本把 WCAG 2.2 的相对亮度公式落成可复核的门禁，改令牌后必跑。

用法：
    python tools/check_contrast.py
退出码 0 = 全过，1 = 有 FAIL。
"""

import os
import re
import sys

# ---------- WCAG 2.2 相对亮度与对比度 ----------

def srgb_to_linear(c: int) -> float:
    x = c / 255.0
    return x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4


def luminance(hex_color: str) -> float:
    h = hex_color.lstrip('#')
    if len(h) == 8:                      # #AARRGGBB，按不透明处理
        h = h[2:]
    if len(h) == 3:
        h = ''.join(ch * 2 for ch in h)
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return (0.2126 * srgb_to_linear(r)
            + 0.7152 * srgb_to_linear(g)
            + 0.0722 * srgb_to_linear(b))


def contrast(fg: str, bg: str):
    """返回 (比值, 取整后的比值字符串)。不做四舍五入美化：
    WCAG 明确规定不得对计算结果取整，4.499:1 不满足 4.5:1。"""
    lf, lb = luminance(fg), luminance(bg)
    hi, lo = max(lf, lb), min(lf, lb)
    ratio = (hi + 0.05) / (lo + 0.05)
    return ratio, ('%.2f' % ratio)


def composite(fg: str, bg: str, alpha_hex: str) -> str:
    """把半透明前景按 src-over 合成到底色上，得到实际呈现的颜色。"""
    a = int(alpha_hex, 16) / 255.0
    f, b = fg.lstrip('#'), bg.lstrip('#')
    out = ''
    for i in (0, 2, 4):
        fv, bv = int(f[i:i + 2], 16), int(b[i:i + 2], 16)
        out += '%02X' % round(fv * a + bv * (1 - a))
    return '#' + out


# ---------- 阈值 ----------
# 工信部《移动互联网应用(APP)适老化通用设计规范》：正文对比度 >= 4.5:1。
# WCAG 2.2 AA 同为 4.5:1（普通文本）/ 3:1（>=18pt 或 >=14pt 粗体的大文本）。
AA_NORMAL = 4.5
AA_LARGE = 3.0

# ---------- 令牌解析（单一事实源 = app/entry/src/main/ets/common/*.ets） ----------
# 之前本文件维护了一份手抄色表，与 EraTheme.ets 各改各的，是上一轮
# 「改了周色但 lint 还是绿的」这类漏检的根源。现在改为直接读源码。

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS_DIR = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets', 'common')


def read_ets(name: str) -> str:
    path = os.path.join(ETS_DIR, name)
    if not os.path.isfile(path):
        print('FATAL  找不到令牌源文件: %s' % path)
        sys.exit(2)
    with open(path, encoding='utf-8') as fh:
        return fh.read()


def parse_flat_consts(src: str, prefix: str = '') -> dict:
    """抓 `export const NAME: string = '#RRGGBB';` / `= 123;` 这类平铺声明。"""
    out = {}
    pat = re.compile(
        r'export\s+const\s+([A-Z0-9_]+)\s*:\s*(?:string|number)\s*=\s*'
        r"('#[0-9A-Fa-f]{6,8}'|-?\d+(?:\.\d+)?)\s*;")
    for name, value in pat.findall(src):
        out[prefix + name] = value.strip("'")
    return out


def parse_map(src: str, const_name: str) -> dict:
    """抓 `const X: Map<string,string> = new Map([['k','v'],...])` 的键值对。"""
    m = re.search(const_name + r'\s*(?::[^=]+)?=\s*new Map\(\[([\s\S]*?)\]\)', src)
    if not m:
        return {}
    return dict(re.findall(r"\[\s*'([^']+)'\s*,\s*'([^']+)'\s*\]", m.group(1)))


TOKENS = parse_flat_consts(read_ets('DesignTokens.ets'))
ERA_SRC = read_ets('EraTheme.ets')

ERA_COLORS = parse_map(ERA_SRC, 'ERA_COLORS')
ERA_INKS = parse_map(ERA_SRC, 'ERA_INKS')
ERA_INK_FLOORS = parse_map(ERA_SRC, 'ERA_INK_FLOORS')
ERA_TEXT = parse_map(ERA_SRC, 'ERA_TEXT')
ERA_TEXT_DARK = parse_map(ERA_SRC, 'ERA_TEXT_DARK')

THEME_BG = TOKENS.get('SURFACE_PAGE', '#F5F1E8')
THEME_INK = TOKENS.get('INK', '#2B2622')
SURFACES = {
    '主题底 SURFACE_PAGE': THEME_BG,
    '卡片底 SURFACE_CARD': TOKENS.get('SURFACE_CARD', '#FBF8F0'),
    '灯箱底 SURFACE_VIEWER': TOKENS.get('SURFACE_VIEWER', '#F2EDE3'),
    '筛选底 SURFACE_RAISED': TOKENS.get('SURFACE_RAISED', '#EFE8D8'),
}

# 语义文字层级 -> 令牌名。键是 DesignTokens.ets 里的常量名，
# 值是对比度门禁的适用面。
TEXT_TOKENS = {
    'INK': TOKENS.get('INK', '#2B2622'),
    'BODY': TOKENS.get('BODY', '#4A443B'),
    'SUB': TOKENS.get('SUB', '#6B6357'),
    'ACCENT': TOKENS.get('ACCENT', '#9C4A2F'),
}

# 深底文字（RelicPage 展柜）：这些不落在纸底体系里，单列一组。
DARK_SURFACE = TOKENS.get('ON_DARK_PANEL', '#1C1A18')
DARK_RAISED = TOKENS.get('ON_DARK_RAISED', '#262320')
DARK_TEXT_TOKENS = {
    'ON_DARK_TEXT': TOKENS.get('ON_DARK_TEXT', '#F7F4EF'),
    'ON_DARK_TEXT_ALT': TOKENS.get('ON_DARK_TEXT_ALT', '#E3DFD8'),
    'ON_DARK_SUB': TOKENS.get('ON_DARK_SUB', '#9A9288'),
    'ON_DARK_GOLD': TOKENS.get('ON_DARK_GOLD', '#D0AA27'),
    'ON_DARK_ACCENT': TOKENS.get('ON_DARK_ACCENT', '#E0A07C'),
}

# 图上文字的 scrim 机制：scrim = #141210 按 alpha 合成到最坏底（照片纯白
# #FFFFFF）上，再验白字。三档阈值见 DesignTokens.ets 的 SCRIM_* 注释。
SCRIM_COLOR = TOKENS.get('SCRIM', '#141210')
SCRIM_CASES = [
    ('头图主标题/正文', float(TOKENS.get('SCRIM_ALPHA_TEXT', 0.60))),
    ('示意图角标(9pt)', float(TOKENS.get('SCRIM_ALPHA_BADGE', 0.70))),
    ('底部渐变实端', float(TOKENS.get('SCRIM_ALPHA_EDGE', 0.68))),
]
WHITE = '#FFFFFF'

# 半透明 ink 在各调用位点的原始 alpha（改动前需通过钳制达标）
INK_ALPHA_CALLS = [
    ('Index 示意图角标', '99'),
    ('Index 文化别称', 'BF'),
    ('Index 年代跨度', 'B3'),
    ('ListPage 计数', '66'),
    ('DetailPage 整备标签', '59'),
]

results = []   # (级别, 说明, 数值串)


def check(label: str, fg: str, bg: str, need: float = AA_NORMAL):
    ratio, s = contrast(fg, bg)
    ok = ratio >= need
    results.append(('PASS' if ok else 'FAIL', label,
                    '%s on %s = %s:1 (需 %.1f)' % (fg, bg, s, need)))
    return ok


def main() -> int:
    fails = 0

    # 1. 主题文字层级在所有浅底上
    for name, color in TEXT_TOKENS.items():
        for surf_name, surf in SURFACES.items():
            if not check('%s @ %s' % (name, surf_name), color, surf):
                fails += 1

    # 2. 年代色作为底 + 其 ink（不透明主文字）
    for era in ERA_COLORS:
        if not check('%s 底 + 主文字' % era, ERA_INKS[era], ERA_COLORS[era]):
            fails += 1

    # 3. 半透明 ink：先按 floor 钳制，再验证实际合成结果
    for call_name, alpha in INK_ALPHA_CALLS:
        worst, worst_era = 99.0, ''
        for era in ERA_COLORS:
            eff = max(int(alpha, 16), int(ERA_INK_FLOORS[era], 16))
            actual = composite(ERA_INKS[era], ERA_COLORS[era], '%02X' % eff)
            r, s = contrast(actual, ERA_COLORS[era])
            if r < worst:
                worst, worst_era = r, era
        ok = worst >= AA_NORMAL
        if not ok:
            fails += 1
        results.append(('PASS' if ok else 'FAIL',
                        '%s (alpha %s→钳制)' % (call_name, alpha),
                        '最低 %s:1 @ %s (需 4.5)' % ('%.2f' % worst, worst_era)))

    # 4. 年代色作文字（画布 10px 标签等）
    for era in ERA_COLORS:
        if not check('%s 文字色' % era, ERA_TEXT[era], THEME_BG):
            fails += 1

    # 4b. 深底（RelicPage 展柜）文字层级
    # 刻意不验「浅色文字压年代色块」：eraColor() 底永远配 eraInk()，
    # 而 ERA_INKS 本身按明度分深浅两组（周/汉唐/宋用 #1F1B16），
    # 那种组合在代码里不存在，验它只会逼着放宽真实令牌。
    for name, color in DARK_TEXT_TOKENS.items():
        # ON_DARK_TEXT_ALT 与 ON_DARK_ACCENT 在第三级 RAISED 上也用
        # （展柜选中态），双双校验。
        for surf_name, surf in (('@深底展柜', DARK_SURFACE), ('@深底抬升', DARK_RAISED)):
            if not check('%s %s' % (name, surf_name), color, surf):
                fails += 1

    # 4c. 年代色深底文字变体（ERA_TEXT_DARK）——白盒体系新增。
    # 原块色在深底上最低只有 1.29:1（龙山），完全不可读；提亮变体是
    # RelicPage 文物名的唯一合法来源。
    for era in ERA_COLORS:
        if not check('%s 深底文字色 @展柜' % era, ERA_TEXT_DARK[era], DARK_SURFACE):
            fails += 1
        if not check('%s 深底文字色 @抬升' % era, ERA_TEXT_DARK[era], DARK_RAISED):
            fails += 1

    # 4d. scrim 三档：以照片纯白为最坏底算合成色，再验白字。
    # 这条守的是"压在照片上的文字"——照片明度不可控，所以按最坏情况算。
    for label, alpha in SCRIM_CASES:
        alpha_hex = '%02X' % int(round(alpha * 255))
        worst_bg = composite(SCRIM_COLOR, WHITE, alpha_hex)
        if not check('scrim %s (α=%s)' % (label, alpha), WHITE, worst_bg):
            fails += 1

    # 5. 源码扫描：不得再出现已淘汰的低对比令牌
    ets = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets')
    banned = {'#9A9184': '2.76:1 @ THEME_BG，已由 #6B6357 取代'}
    hits = []
    if os.path.isdir(ets):
        for dirpath, _, files in os.walk(ets):
            for fn in files:
                if not fn.endswith('.ets'):
                    continue
                p = os.path.join(dirpath, fn)
                with open(p, encoding='utf-8') as fh:
                    for ln, line in enumerate(fh, 1):
                        for token, why in banned.items():
                            if token in line.upper():
                                hits.append('%s:%d  %s (%s)'
                                    % (os.path.relpath(p, ROOT), ln, token, why))
    if hits:
        fails += len(hits)
        results.append(('FAIL', '已淘汰令牌残留',
                        '%d 处：%s ...' % (len(hits), hits[0])))

    for level, label, detail in results:
        print('%-4s  %-34s %s' % (level, label, detail))
    print('-' * 78)
    print('合计 %d 项，FAIL %d 项' % (len(results), fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
