"""按压反馈探针：按住一个可点区域，比较按下前后的截图差异。

为什么要有它：stateStyles 的按压态是编译期展开的，静态检查只能证明
「写法合法」，证明不了「真机上按下去确实变了」。而两种按压态的视觉
特征完全不同——缩放会让元素**边界内缩**（bbox 变小），压暗会让元素
**变暗但边界不动**。用这两条区分，就能在截图上判定是哪一种生效。

用法：
    python tools/press_probe.py base.jpeg press.jpeg x1 y1 x2 y2

    python tools/press_probe.py --locate layout.json "<文本>"
        在 uitest dumpLayout 的 JSON 里找文本匹配的节点，打印
        "目标X 目标Y 框x1 框y1 框x2 框y2"。
        采样框取该节点 bounds 外扩 PAD 像素。

为什么要它：手写坐标一旦落空（页面已被上一次探针的点击跳走），
探针会给出干净的 0%，看起来像「按压态没生效」，实则根本没按到东西。
"""
import json
import re
import sys

from PIL import Image

PAD = 12
_BOUNDS_RE = re.compile(r'\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]')


def diff_report(base_path, press_path, box):
    base = Image.open(base_path).convert('RGB')
    press = Image.open(press_path).convert('RGB')
    if base.size != press.size:
        raise SystemExit('两次截图尺寸不同：%s vs %s' % (base.size, press.size))
    x1, y1, x2, y2 = box
    region = (x1, y1, x2, y2)
    b = base.crop(region)
    p = press.crop(region)
    bw, bh = b.size
    px = b.load()
    px2 = p.load()
    changed = 0
    darker = 0
    lighter = 0
    for y in range(bh):
        for x in range(bw):
            r1, g1, b1 = px[x, y]
            r2, g2, b2 = px2[x, y]
            d = abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2)
            if d > 24:
                changed += 1
                lum1 = 0.299 * r1 + 0.587 * g1 + 0.114 * b1
                lum2 = 0.299 * r2 + 0.587 * g2 + 0.114 * b2
                if lum2 < lum1:
                    darker += 1
                elif lum2 > lum1:
                    lighter += 1
    total = bw * bh
    print('区域 %s  共 %d 像素' % (region, total))
    print('变化像素 %d (%.1f%%)' % (changed, 100.0 * changed / total))
    if changed == 0:
        print('结论：无变化 —— 按压态没有生效')
        return 1
    print('其中变暗 %d / 变亮 %d' % (darker, lighter))
    if darker > lighter * 1.5:
        print('结论：压暗型（PRESS_TEXT_STYLES）生效')
    else:
        print('结论：几何型或混合 —— 需再看边界是否内缩（缩放型 PRESS_STYLES）')
    return 0


def collect_text_nodes(node, out):
    if not isinstance(node, dict):
        return
    attrs = node.get('attributes') or {}
    text = (attrs.get('text') or '').strip()
    bounds = attrs.get('bounds') or ''
    if text and bounds:
        out.append((text, bounds))
    for child in node.get('children') or []:
        collect_text_nodes(child, out)


def locate(layout_path, want):
    with open(layout_path, encoding='utf-8') as fh:
        root = json.load(fh)
    nodes = []
    collect_text_nodes(root, nodes)
    exact = [n for n in nodes if n[0] == want]
    partial = [n for n in nodes if want in n[0] and n[0] != want]
    hit = exact or partial
    if not hit:
        return 3
    text, bounds = hit[0]
    m = _BOUNDS_RE.search(bounds)
    if not m:
        return 3
    x1, y1, x2, y2 = (int(v) for v in m.groups())
    cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
    print('%d %d %d %d %d %d' % (cx, cy, x1 - PAD, y1 - PAD, x2 + PAD, y2 + PAD))
    return 0


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == '--locate':
        if len(sys.argv) != 4:
            print('用法: press_probe.py --locate <layout.json> "<文本>"')
            return 2
        return locate(sys.argv[2], sys.argv[3])
    if len(sys.argv) != 7:
        print(__doc__)
        return 2
    base, press = sys.argv[1], sys.argv[2]
    box = tuple(int(v) for v in sys.argv[3:7])
    return diff_report(base, press, box)


if __name__ == '__main__':
    sys.exit(main())
