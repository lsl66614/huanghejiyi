#!/usr/bin/env python3
"""跨页一致性门禁：间距档位漂移审计。

为什么单独一个门禁（而不是塞进 lint_tokens）：
lint_tokens 的 'spacing' 规则是**逐处卡值**（非档值即违规），
而间距迁移要翻九个页面、每页都要装机回归，只能分批做。
本门禁的职责是把「分批」这件事机制化：

  1. **旧账冻结**：基线 EXEMPT 表登记了当前所有非档值（134→127 处）的
     (文件, 行号, 值) 三元组。迁移一处，删一条；表清空之日即可以
     lint_tokens 打开 'spacing' 规则收口。
  2. **新账立判**：表外任何非档值（新写的 18、新捡的 22……）立即判
     违规，exit 1。跨页一致性漂移从这里开始就是「有记录的旧账」和
     「无记录的新账」两类，不再混谈。
  3. **快照自检**：EXEMPT 条目按行号 + 值双锚定（仿 lint_aging 的
     文本碎片自检，但间距行没有稳定文本，锚 (行号, 值)）。条目过期
     （该行值已变）不算违规——那是迁移完成的信号，只在输出里提示
     「请顺手删除过期条目」。

档位依据（common/DesignTokens.ets）：
  0（无间距）/ 1 发丝 / 3 标签内衬 / 4 发丝内衬 / 6 微 / 8 同组 /
  10 紧凑 / 12 卡片内 / 16 卡片内边距 / 24 页面级 / 32 大分区 /
  40（PAGE_PAD 扩展档）/ 80 沉浸头图。
  2,5,7,9,13,14,15,18,20,22,26,28,30,44 全部是非档「差一档」值。

建议吸附（--plan 输出用，非强制）：
  2→4  5→4  7→8  9→10  13→12  14→12  15→16  18→16  20→24
  22→24  26→24  28→32  30→32  44→40

扫描对象与 lint_tokens 相同（排除令牌定义文件）：
  .padding({ left: N ... }) / .padding(N) / .margin({...}) / .margin(N)
  Row/Column/Flex 的 { space: N }
  注释行（// 、* 、/* 开头）跳过；对象字面量里 %、fontSize、lineHeight、
  letterSpacing、duration 键上的数字跳过（那是字号/动效，不是间距）。

只读，不写任何文件。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets')

TOKEN_FILES = ('DesignTokens.ets', 'EraTheme.ets')

# 间距档位（DesignTokens 间距段的数值集合 + 0「无间距」）
LADDER = {0, 1, 3, 4, 6, 8, 10, 12, 16, 24, 32, 40, 80}

# 非档值 → 建议吸附档（就近，同距取大）
SNAP = {2: 4, 5: 4, 7: 8, 9: 10, 13: 12, 14: 12, 15: 16, 18: 16,
        20: 24, 22: 24, 26: 24, 28: 32, 30: 32, 44: 40}


def suggest(v: int) -> int:
    """非档值的建议吸附档。已知值查 SNAP，未知值取最近档（同距取大）。"""
    if v in SNAP:
        return SNAP[v]
    if v in LADDER:
        return v
    return min(LADDER, key=lambda x: (abs(x - v), -x))

# 对象字面量里不是间距的数字键
SKIP_KEYS = re.compile(r'%|fontSize|lineHeight|letterSpacing|duration')

PAD_OBJ = re.compile(r'\.(?:padding|margin)\(\{([^}]*)\}\)')
PAD_DIRECT = re.compile(r'\.(?:padding|margin)\(\s*(\d{1,3})\s*\)')
SPACE_OBJ = re.compile(r'\bspace:\s*(\d{1,3})\b')

# ---------------------------------------------------------------- 基线豁免表
# (文件相对 ETS/, 行号, 值)。生成方式：python tools/lint_visual_consistency.py --emit-exempt
# 迁移一处删一行。
#
# 2026-10-24：最后 6 条（基线冻结于 2026-10-20）全部过期——对应的非档值
# 已随本轮按压反馈重写与令牌清理一并消除，本表已清空。全站间距现已全部
# 落在档位上，lint_tokens 的 'spacing' 规则可以常开（见下）。
EXEMPT: list = []

# ---------------------------------------------------------------- 扫描


def line_is_comment(line: str) -> bool:
    s = line.strip()
    return s.startswith('//') or s.startswith('*') or s.startswith('/*')


def collect_hits():
    """返回 [(rel, line_no, value, snap_hint)]，只含非档值。rel 统一正斜杠。"""
    hits = []
    for dirpath, _, files in os.walk(ETS):
        for fn in sorted(files):
            if not fn.endswith('.ets') or fn in TOKEN_FILES:
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), ETS).replace('\\', '/')
            with open(os.path.join(dirpath, fn), encoding='utf-8') as fh:
                for no, line in enumerate(fh, 1):
                    if line_is_comment(line):
                        continue
                    for m in PAD_OBJ.finditer(line):
                        if SKIP_KEYS.search(m.group(0)):
                            continue
                        for v in re.findall(r':\s*(\d{1,3})\b', m.group(1)):
                            if int(v) not in LADDER:
                                hits.append((rel, no, int(v)))
                    for m in PAD_DIRECT.finditer(line):
                        if int(m.group(1)) not in LADDER:
                            hits.append((rel, no, int(m.group(1))))
                    for m in SPACE_OBJ.finditer(line):
                        if int(m.group(1)) not in LADDER:
                            hits.append((rel, no, int(m.group(1))))
    return hits


def exempt_key(rel: str, no: int, v: int) -> str:
    return f'{rel}:{no}:{v}'


# ---------------------------------------------------------------- 制式硬规则
# 这两条来自《视觉制式整改清单》§1.1 与 §5 的 grep 判据，本轮补成门禁，
# 防止整改完又被写回去（清单 §0：漂移是逐页手写的必然结果）。

# 规则 A：未选中态不许上 ACCENT。清单 §1.1 的违规写法是**无条件**描边
# `border({ width: 1, color: ACCENT })`——它让每个 chip 都像被选中。
# 三元 `color: cond ? ACCENT : X` 是合法的选中态语法（选中才上色），不拦。
BORDER_ACCENT = re.compile(r'\.border\(\{([^}]*)\}\)')
ACCENT_UNCOND = re.compile(r'color:\s*(?:[^,?]*\b)?ACCENT\b(?!\s*:)[^,?]*$')

# 规则 B：borderRadius(0) 一律禁止——直角填充块是全站唯一的例外语法，
# 输入框统一「透明底 + 下沿发丝」，卡片统一圆角。
RADIUS_ZERO = re.compile(r'\.borderRadius\(\s*0\s*\)')

# 规则 C：标题短杠不许用 ACCENT（清单 C1）。
# 短杠的语义是「这一节属于哪一层」，所以只能用层色或 INK；
# 用 ACCENT 会让它读成装饰，且与年代色抢同一套语汇。
# 判据：`.width(40)` + `.height(4)` 的短杠块，其 backgroundColor 为 ACCENT。
SHORT_BAR_ACCENT = re.compile(r'\.backgroundColor\(\s*ACCENT\s*\)')

# 规则 B 的豁免：需要「贴边通栏」的块。目前为空——若将来确需通栏色带，
# 在这里登记 (文件相对 ETS/, 行号, 原因)，并写进 spec。
RADIUS_EXEMPT: list = []

# 规则 A 的豁免：ACCENT 作为**图形本体**而非状态色的地方。
# (文件相对 ETS/, 原因)。按行号豁免会随编辑漂移，这里按文件 + 片段匹配。
#   HuangheSeal：四字印的印面就是赭红框，它就是 logo 本身，不是可选中态。
GRAPHIC_ACCENT = ('common/HuangheSeal.ets',)


def collect_style_hits():
    """返回 [(rel, no, kind, snippet)]：制式硬规则违规。"""
    hits = []
    for dirpath, _, files in os.walk(ETS):
        for fn in sorted(files):
            if not fn.endswith('.ets') or fn in TOKEN_FILES:
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), ETS).replace('\\', '/')
            with open(os.path.join(dirpath, fn), encoding='utf-8') as fh:
                lines = fh.readlines()
            for no, line in enumerate(lines, 1):
                if line_is_comment(line):
                    continue
                for m in BORDER_ACCENT.finditer(line):
                    body = m.group(1)
                    # 只拦「无条件 ACCENT 描边」：body 里出现 ACCENT，
                    # 且该行 border 内没有三元条件（无 '?'）。
                    if 'ACCENT' in body and '?' not in body:
                        if rel in GRAPHIC_ACCENT:
                            continue
                        hits.append((rel, no, 'accent-border', m.group(0).strip()))
                for m in RADIUS_ZERO.finditer(line):
                    key = (rel, no)
                    if any(e[0] == rel and e[1] == no for e in RADIUS_EXEMPT):
                        continue
                    hits.append((rel, no, 'radius-zero', m.group(0).strip()))
                # 规则 C：宽 40 / 高 4 的短杠块用 ACCENT 填色。
                # 短杠由连续几行组成，故以「本行是 ACCENT 填色」为锚，
                # 向上看 6 行内是否同时出现 width(40) 与 height(4)。
                if SHORT_BAR_ACCENT.search(line):
                    lo = max(0, no - 7)
                    ctx = ''.join(lines[lo:no])
                    if '.width(40)' in ctx and '.height(4)' in ctx:
                        hits.append((rel, no, 'accent-bar',
                                     '短杠 .width(40)/.height(4) 填 ACCENT'))
    return hits


def report_style_hits(hits) -> bool:
    """打印制式违规明细，返回是否通过。"""
    if not hits:
        print('跨页制式审计：ACCENT 描边 / 直角块 0 处')
        return True
    print(f'-- 制式违规 {len(hits)} 处（改代码，不要加豁免）')
    for rel, no, kind, snippet in hits:
        if kind == 'accent-border':
            why = '未选中态上 ACCENT 描边（§1.1）'
        elif kind == 'accent-bar':
            why = '标题短杠用 ACCENT（C1：短杠只能是层色或 INK）'
        else:
            why = '直角填充块 borderRadius(0)（§5）'
        print(f'  {rel}:{no}  {why}  {snippet}')
    return False


def main(argv):
    from collections import Counter
    off_ladder = collect_hits()
    exempt_set = {exempt_key(*e) for e in EXEMPT}

    fresh = [h for h in off_ladder if exempt_key(*h) not in exempt_set]
    hit_keys = {exempt_key(*h) for h in off_ladder}
    stale = [e for e in EXEMPT if exempt_key(*e) not in hit_keys]

    if '--emit-exempt' in argv:
        # 只打印基线条目（正斜杠、按 (文件,行,值) 去重、保持扫描顺序）
        seen = set()
        for rel, no, v in off_ladder:
            k = f'{rel}:{no}:{v}'
            if k in seen:
                continue
            seen.add(k)
            print(f"('{rel}', {no}, {v}),")
        return 0

    print('=' * 78)
    print(f'跨页间距一致性审计：非档值 {len(off_ladder)} 处'
          f'（基线豁免 {len(exempt_set)}，其中过期 {len(stale)}），'
          f'新增漂移 {len(fresh)} 处')
    print('档位：' + ' / '.join(str(x) for x in sorted(LADDER)))
    print('=' * 78)

    if '--plan' in argv:
        # 按 值→建议档 汇总迁移量
        plan = Counter()
        for h in off_ladder:
            plan[f'{h[2]}→{suggest(h[2])}'] += 1
        for k in sorted(plan, key=lambda s: int(s.split('→')[0])):
            print(f'  {k}: {plan[k]} 处')

    if fresh:
        byfile = Counter(h[0] for h in fresh)
        print(f'-- 新增漂移（表外 {len(fresh)} 处，需改代码而不是加豁免）')
        for rel in sorted(byfile):
            print(f'  {rel}（{byfile[rel]} 处）')
            for rel2, no, v in sorted(h for h in fresh if h[0] == rel):
                print(f'    L{no}: 间距 {v} → 建议 {suggest(v)}')
    if stale:
        print(f'（过期豁免条目 {len(stale)} 条：对应行值已变，迁移完成，'
              f'请顺手删除。示例：{stale[:8]}{"…" if len(stale) > 8 else ""}）')

    print('-' * 78)
    style_ok = report_style_hits(collect_style_hits())
    print('-' * 78)
    if fresh:
        print(f'FAIL：{len(fresh)} 处表外新增非档值（新写的间距必须落档）')
        return 1
    if not style_ok:
        print('FAIL：制式硬规则违规（ACCENT 描边 / borderRadius(0)）')
        return 1
    print('PASS：基线内 0 新增漂移，制式 0 违规')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
