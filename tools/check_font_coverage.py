#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""扫全站中文字面量，查两个字体的子集是否覆盖。

为什么要这个脚本：真机上字体子集缺字会渲染成豆腐块（■），
但那只在真机暴露，模拟器有系统字体兜底、看不出来。这里用 fontTools
直接读子集的 cmap 与 glyf，把"屏上会缺哪些字"提前算出来。

判据：
  cmap 里有映射 = 有该字的编码；
  glyf 里 contours=0 = 空字形（有编码但画不出来，同样是豆腐块）。
两个都过才算覆盖。

（2026-11-06 补记：还有第三类坏字——有映射、有轮廓，但轮廓绕向错到内白被填死，
屏上是纯黑方块。ZCOOLXiaoWei-Sub 的「回」(U+56DE) 就是这种。它绕过了上面两条判据，
所以本脚本放行、13/13 门禁全绿，直到导回标题在模拟器上渲成「把带走的档案放■来」。
检测它的判据试过两版都不可靠：包围盒判嵌套误报 729 字（「日」「田」这类多笔画字
全中招），字心绕数采样误报 251 处（「细」「发」「水」的笔画穿过字心）。
可靠做法是"与参考字体逐字比对洞面积"，但那要引入 PIL 栅格化，成本高于本门禁定位，
故不并入；改为在文案层绕开该字，并把这一条记进 PITFALLS 78。）
"""
import glob
import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8', errors='replace')
from fontTools.ttLib import TTFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets')
FONTS = {
    'NotoSerifSC': os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'font', 'NotoSerifSC-Head800.ttf'),
    'ZCOOLXiaoWei': os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'font', 'ZCOOLXiaoWei-Sub.ttf'),
}

CJK = re.compile('[一-鿿]')
# 单引号字符串字面量（ArkUI 里中文文案都是这种形态）
LITERAL = re.compile(r"'([^'\\]*)'")


def load(path):
    t = TTFont(path)
    cmap = t.getBestCmap()
    glyf = t.get('glyf')
    empty = set()
    for name in cmap:
        if name in glyf and glyf[name].numberOfContours == 0:
            empty.add(name)
    return cmap, empty


def covered(cmap, empty, ch):
    g = cmap.get(ord(ch))
    if g is None:
        return False, '无映射'
    if g in empty:
        return False, '空字形'
    return True, ''


def main():
    data = {}
    for k, p in FONTS.items():
        data[k] = load(p)

    bad = []
    scanned = 0
    for path in sorted(glob.glob(os.path.join(ETS, '**', '*.ets'), recursive=True)):
        rel = os.path.relpath(path, ETS).replace(os.sep, '/')
        with open(path, encoding='utf-8') as fh:
            src = fh.read()
        for m in LITERAL.finditer(src):
            s = m.group(1)
            if not CJK.search(s):
                continue
            # 排除含 ASCII 的串（路径、标识符、格式串）
            if re.search('[A-Za-z0-9]', s):
                continue
            scanned += 1
            miss = {}
            for k, (cmap, empty) in data.items():
                gone = []
                for ch in s:
                    ok, why = covered(cmap, empty, ch)
                    if not ok:
                        gone.append(ch)
                if gone:
                    miss[k] = ''.join(sorted(set(gone)))
            if miss:
                bad.append((rel, miss, s[:40]))

    print('扫描中文字面量 %d 条' % scanned)
    if not bad:
        print('结论：两个字体的子集能覆盖全部中文字面量，无豆腐块风险')
        return 0
    print('缺口 %d 处：' % len(bad))
    for rel, miss, s in bad:
        parts = ' | '.join('%s缺:%s' % (k, v) for k, v in miss.items())
        print('  %-28s %-22s %s' % (rel, parts, s))
    return 1


if __name__ == '__main__':
    sys.exit(main())
