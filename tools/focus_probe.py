"""用截图像素差判断焦点环是否真的画出来了。

为什么不能只看「有没有赭红」：首页的年代卡本身就是赭红块，
未聚焦时就有几十万赭红像素。真正的判据是「按 Tab 前后多出来的那一圈
赭红，且它构成一个矩形边框」。所以这里取差分，再找新增像素的包围盒。

用法: python tools/focus_probe.py <按Tab前> <按Tab后>
"""
import sys
from PIL import Image

ACCENT = (0x9C, 0x4A, 0x2F)
TOL = 40


def is_accent(px):
    return (abs(px[0] - ACCENT[0]) < TOL and abs(px[1] - ACCENT[1]) < TOL
            and abs(px[2] - ACCENT[2]) < TOL)


def load(p):
    return Image.open(p).convert('RGB')


def main():
    a = load(sys.argv[1])
    b = load(sys.argv[2])
    if a.size != b.size:
        print('尺寸不同 %s vs %s，无法差分' % (a.size, b.size))
        return 1
    pa, pb = a.load(), b.load()
    w, h = a.size

    added = []
    for y in range(h):
        for x in range(w):
            if is_accent(pb[x, y]) and not is_accent(pa[x, y]):
                added.append((x, y))
    print('新增赭红像素: %d' % len(added))
    if not added:
        print('未检出焦点环')
        return 1

    xs = [p[0] for p in added]
    ys = [p[1] for p in added]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    bw, bh = x1 - x0 + 1, y1 - y0 + 1
    area = bw * bh
    fill = len(added) / area if area else 0

    # 边框的填充率低：矩形周长 2*(w+h) 远小于面积
    print('包围盒 x[%d..%d] y[%d..%d]  %dx%d  填充率 %.2f' %
          (x0, x1, y0, y1, bw, bh, fill))
    # 每行/每列的新增像素分布：边框在四边都会出现，中间空
    rows = {}
    cols = {}
    for x, y in added:
        rows[y] = rows.get(y, 0) + 1
        cols[x] = cols.get(x, 0) + 1
    dense_rows = sum(1 for v in rows.values() if v > bw * 0.5)
    dense_cols = sum(1 for v in cols.values() if v > bh * 0.5)
    print('横向实边行数 %d / %d   纵向实边列数 %d / %d' %
          (dense_rows, bh, dense_cols, bw))
    verdict = fill < 0.45 and dense_rows >= 2 and dense_cols >= 2
    print('判定: %s' % ('成环' if verdict else '不像边框'))
    return 0 if verdict else 1


if __name__ == '__main__':
    sys.exit(main())