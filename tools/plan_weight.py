# 只读预演：把每个 fontWeight 站点的新令牌与理由列出来，供人工核对后再手改。
#
# 为什么不让它直接写源文件：上一批次就是批量写入脚本把六个源文件写坏了。
# 这个脚本只打印，写入一律用 Edit 工具逐处改。
#
# 用法：python tools/plan_weight.py [文件名]

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from analyze_weight import (ETS, FONT_FAMILY, FONT_SIZE, FONT_WEIGHT,
                            line_is_comment, scan_up, text_near)

# 每个站点的目标令牌。键为 (文件名, 行号)，值为目标令牌名。
#
# 归类规则（先角色，后档位）：
#   A. 衬线 NotoSerifSC          → WT_SERIF(800)  无条件命中真面
#   B. 二元选中态               → 选中 WT_BOLD / 未选 WT_REGULAR
#   C. 页头、列表项标题、按钮   → WT_BOLD
#   D. 眉标、计数、统计数字     → WT_MEDIUM
#
# 逐条理由见每行末尾注释，改动前请先读 PLAN_REASON。
PLAN = {
    # ── A 衬线：16 处，只有 Head800 一个面，传 800 才是命中真面 ──
    ('DetailPage.ets', 153): 'WT_SERIF',      # 贰 文物 节标题 22pt
    ('DetailPage.ets', 481): 'WT_SERIF',      # 头图遗址名 28pt
    ('DetailPage.ets', 684): 'WT_SERIF',      # 脉络推荐 节标题 22pt
    ('FavoritesPage.ets', 394): 'WT_SERIF',   # 我的收藏 HERO 44pt
    ('FavoritesPage.ets', 454): 'WT_SERIF',   # 空态大字 28pt
    ('FavoritesPage.ets', 468): 'WT_SERIF',   # 标签下空态标题 18pt
    ('Index.ets', 108): 'WT_SERIF',           # 黄河记忆 页头 18pt
    ('Index.ets', 257): 'WT_SERIF',           # 年代卡期名 28pt
    ('ListPage.ets', 63): 'WT_SERIF',         # 页头 HERO 44pt
    ('ListPage.ets', 192): 'WT_SERIF',        # 空态标题 18pt
    ('ListPage.ets', 237): 'WT_SERIF',        # 遗址行标题 18pt
    ('MinePage.ets', 80): 'WT_SERIF',         # 我的页主标题 28pt
    ('NetworkPage.ets', 185): 'WT_SERIF',     # 页头主标题 28pt
    ('RecommendPage.ets', 88): 'WT_SERIF',    # 头图标题 28pt
    ('RelicPage.ets', 152): 'WT_SERIF',       # 页头主标题 28pt
    ('SyncPage.ets', 272): 'WT_SERIF',        # 同步面板标题 28pt

    # ── C 强调 700：列表项标题 / 页头 / 按钮文字 ──
    #   这 6 处原为 Bolder(800)，与同字号的 700 撞档，统一降到 700
    ('DetailPage.ets', 209): 'WT_BOLD',       # 事件标题 14pt，与邻行同级
    ('DetailPage.ets', 383): 'WT_MEDIUM',     # 文物名 12pt 缩略图下方 → 见 D
    ('DetailPage.ets', 708): 'WT_BOLD',       # 推荐行标题 18pt
    ('FavoritesPage.ets', 74): 'WT_BOLD',     # 贴标签页头 18pt
    ('FavoritesPage.ets', 341): 'WT_BOLD',    # 收藏行标题 14pt
    ('FavoritesPage.ets', 537): 'WT_BOLD',    # 年代分组头 14pt
    ('Index.ets', 152): 'WT_BOLD',            # 检索 14pt
    ('Index.ets', 179): 'WT_MEDIUM',          # 按年代进入 12pt 眉标 → 见 D
    ('Index.ets', 289): 'WT_MEDIUM',          # 年代环内计数 12pt → 见 D
    ('MinePage.ets', 103): 'WT_BOLD',         # 页内小节标题 18pt
    ('MinePage.ets', 164): 'WT_BOLD',         # 统计数字 22pt
    ('NetworkPage.ets', 239): 'WT_BOLD',      # 行内标题 14pt
    ('NotePage.ets', 200): 'WT_BOLD',         # 笔记页头 14pt
    ('NotePage.ets', 208): 'WT_BOLD',         # 保存按钮 14pt
    ('RecommendPage.ets', 112): 'WT_BOLD',    # 推荐行标题 18pt
    ('SyncPage.ets', 481): 'WT_BOLD',         # 统计数字 18pt
}


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    planned = {}

    for dirpath, _, files in os.walk(ETS):
        for fn in sorted(files):
            if not fn.endswith('.ets'):
                continue
            if only and fn != only:
                continue
            full = os.path.join(dirpath, fn)
            lines = open(full, encoding='utf-8').readlines()
            for i, line in enumerate(lines):
                if 'fontWeight' not in line or line_is_comment(line):
                    continue
                m = FONT_WEIGHT.search(line.rstrip())
                if not m:
                    continue
                key = (fn, i + 1)
                size = scan_up(lines, i, FONT_SIZE) or '?'
                family = scan_up(lines, i, FONT_FAMILY) or '(sans)'
                text = text_near(lines, i) or '?'
                if '?' in m.group(1):
                    target = '三元 → WT_BOLD / WT_REGULAR'
                else:
                    target = PLAN.get(key, '!! 未规划 !!')
                mark = 'A' if family == 'NotoSerifSC' else (
                    'B' if '?' in m.group(1) else 'C')
                planned[key] = True
                print('%s %-20s %4d  %-8s %-12s %-22s → %-28s %s'
                      % (mark, fn, i + 1, size, family, m.group(1)[:22],
                         target, text[:16]))

    missing = set(PLAN) - set(planned)
    if missing:
        print('\n!! 计划里有 %d 处行号对不上（文件可能已变动），需重新核对：'
              % len(missing))
        for fn, ln in sorted(missing):
            print('   %s:%d' % (fn, ln))
        return 1
    print('\n计划覆盖 %d 处固定字重 + 11 处三元，共 43 处，无遗漏。'
          % len(PLAN))
    return 0


if __name__ == '__main__':
    sys.exit(main())