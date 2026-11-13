# 只读：按 dumpLayout 里的 Text bounds 裁剪截图，统计墨量与非白像素。
#
# 用途：字重是否真的在屏上拉开了，看字形说不准，只能数墨。
# 收敛前 Courier New 的替代方案、WT_MEDIUM(500) 是否可见、选中位
# 700/400 的对比，都靠这个判。
#
# 不写任何源文件，也不碰设备，只读截图。

import json
import os
import sys

try:
    from PIL import Image
except ImportError:
    print('需要 Pillow：pip install pillow')
    sys.exit(2)


def texts(path):
    with open(path, encoding='utf-8') as fh:
        doc = json.load(fh)
    out = []

    def parse_bounds(b):
        """uitest 的 bounds 是对角点：[x1,y1][x2,y2]。"""
        import re
        pts = re.findall(r'\[(-?[0-9]+),(-?[0-9]+)\]', b)
        if len(pts) != 2:
            return None
        (x1, y1), (x2, y2) = [(int(a), int(b)) for a, b in pts]
        return x1, y1, x2 - x1, y2 - y1

    def walk(node):
        if isinstance(node, dict):
            attrs = node.get('attributes', {})
            if attrs.get('type') == 'Text':
                txt = attrs.get('text', '')
                box = parse_bounds(attrs.get('bounds', ''))
                if txt and box:
                    out.append({'text': txt, 'box': box})
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(doc)
    return out


def ink(img, box, pad=0):
    x, y, w, h = box
    x = max(0, x - pad)
    y = max(0, y - pad)
    crop = img.crop((x, y, x + w + 2 * pad, y + h + 2 * pad)).convert('L')
    px = list(crop.getdata())
    nonwhite = sum(1 for v in px if v < 200)
    # 墨量：以 255-v 为权重，累加出「覆盖浓淡」，比非白像素更抗锯齿噪声
    return sum(255 - v for v in px), nonwhite, len(px)


def main():
    layout, shot = sys.argv[1], sys.argv[2]
    needle = sys.argv[3] if len(sys.argv) > 3 else ''
    img = Image.open(shot)
    rows = texts(layout)
    if needle:
        rows = [r for r in rows if needle in r['text']]
    if not rows:
        print('没匹配到文本：%r（共 %d 个 Text）' % (needle, len(texts(layout))))
        return 1
    print('%-28s %10s %8s %8s   %s' % ('文本', '墨量', '非白', '占比', 'bounds'))
    print('-' * 84)
    for r in rows:
        m, nw, tot = ink(img, r['box'])
        print('%-28s %10d %8d %7.2f%%   %s'
              % (r['text'][:26], m, nw, 100.0 * nw / max(1, tot), r['box']))
    return 0


if __name__ == '__main__':
    sys.exit(main())