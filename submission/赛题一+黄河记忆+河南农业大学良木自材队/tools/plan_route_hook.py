"""把路由转场钩子铺到还没写的页面上。只读+打印补丁，本脚本自身不写文件。

为什么用脚本而不是手改：十页要插入的是**逐字符相同**的 8 行。手工复制
最容易出的错是某一页少一行、或者把 ROUTE_SHIFT_VP 写成 24。一旦不一致，
动效就只在部分页面成立，而这种差异肉眼很难发现——lint_motion.py 能查，
但先有一致的基线才有意义。

安全性：脚本只做「打印」，写入一律由调用方逐页 Edit 完成。
"""
import os
import re

ROOT = os.path.join('app', 'entry', 'src', 'main', 'ets', 'pages')

HOOK = """  pageTransition(): void {
    PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
    PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })
      .translate({ x: ROUTE_SHIFT_VP, y: 0 })
      .opacity(ROUTE_FADE_MIN);
  }
"""

ANCHOR = re.compile(r'^\s*aboutToAppear\(\): void \{$')

MOTION_IMPORT = "import { curveIn, curveOut, durRouteIn, durRouteOut } from '../common/Motion';"
TOKEN_IMPORT = 'ROUTE_FADE_MIN, ROUTE_SHIFT_VP'


def patch(fn):
    path = os.path.join(ROOT, fn)
    with open(path, encoding='utf-8') as fh:
        src = fh.read()
    notes = []
    if 'pageTransition(): void' in src:
        notes.append('已有钩子，跳过')
        return notes

    lines = src.split('\n')
    at = None
    for i, l in enumerate(lines):
        if ANCHOR.match(l):
            at = i
            break
    if at is None:
        notes.append('未找到 aboutToAppear，需人工处理')
        return notes
    notes.append('插入位置：第 %d 行前' % (at + 1))

    if MOTION_IMPORT not in src:
        notes.append('需加 import：%s' % MOTION_IMPORT)
    if TOKEN_IMPORT not in src:
        notes.append('需在 DesignTokens import 内补 %s' % TOKEN_IMPORT)
    return notes


def main():
    for fn in sorted(os.listdir(ROOT)):
        if not fn.endswith('.ets'):
            continue
        notes = patch(fn)
        print('%s: %s' % (fn, ' / '.join(notes)))


if __name__ == '__main__':
    main()