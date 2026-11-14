"""列出所有 onClick 站点及其宿主组件，供逐处选择按压样式时对照。

为什么需要它：pressStyles()（缩放）适合有底色的卡片/按钮，
pressTextStyles()（压暗）适合无底色的文字项与符号按钮。选错的直接后果
是文字类点下去整块底色一起变暗，看起来像出了错。57 处如果凭印象选，
迟早有三四处选错——而这三四处只有真机点得出来，静态检查看不出来。

用法：python tools/plan_press.py            只读表
      python tools/plan_press.py --json     便于脚本消费
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGES = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets', 'pages')

# 一行里出现即视为「无底色文字/符号按钮」的信号
TEXTISH = re.compile(
    r"Text\(\s*['\"]|SymbolGlyph\(|ic_[a-z_]*\.svg")
# 有底色的容器信号
BOXISH = re.compile(
    r'backgroundColor\(|SilhouettePlate\(|\.border\(')

COMPONENT = re.compile(r'\b(Button|Text|Image|Row|Column|Stack|Flex|SymbolGlyph)\s*\(')


def host_of(lines, at):
    """从 onClick 行往上找所属组件的起始行（按花括号深度回退）。"""
    i = at
    depth = 0
    while i > 0:
        i -= 1
        t = lines[i].strip()
        if not t or t.startswith('//'):
            continue
        depth -= t.count('{') - t.count('}')
        if depth != 0:
            continue
        if t.startswith(('.', '}', ')')):
            continue
        break
    # 从组件行往下找到 onClick 之前，取这一段作为宿主形态描述
    seg = lines[i:at]
    comp = None
    for l in seg:
        m = COMPONENT.search(l)
        if m:
            comp = m.group(1)
    joined = '\n'.join(seg + lines[at:at + 2])
    if TEXTISH.search(joined) and not BOXISH.search(joined):
        kind = 'TEXT'
    elif comp == 'Text':
        kind = 'TEXT'
    else:
        kind = 'BOX'
    return i + 1, comp, kind


def main():
    rows = []
    for fn in sorted(os.listdir(PAGES)):
        if not fn.endswith('.ets'):
            continue
        path = os.path.join(PAGES, fn)
        with open(path, encoding='utf-8') as fh:
            lines = fh.read().split('\n')
        for i, line in enumerate(lines):
            if line.strip().startswith('//') or '.onClick(' not in line:
                continue
            ln, comp, kind = host_of(lines, i)
            # 找一点文本来辨认
            text = ''
            for k in range(max(0, ln - 1), min(len(lines), i + 1)):
                m = re.search(r"Text\(\s*'([^']*)'", lines[k])
                if m:
                    text = m.group(1)
                    break
            if not text:
                m = re.search(r"Text\(\s*`([^`]*)'", '\n'.join(lines[ln - 1:i]))
                if m:
                    text = m.group(1)
            rows.append({'file': fn, 'line': i + 1, 'host': comp,
                         'kind': kind, 'text': text[:14]})
    if '--json' in sys.argv:
        print(json.dumps(rows, ensure_ascii=False, indent=1))
        return
    for r in rows:
        print('%-18s %4d  %-12s %-5s %s' % (r['file'], r['line'],
                                            r['host'], r['kind'], r['text']))
    print('\n合计 %d 处（TEXT %d / BOX %d）' % (
        len(rows), sum(1 for r in rows if r['kind'] == 'TEXT'),
        sum(1 for r in rows if r['kind'] == 'BOX')))


if __name__ == '__main__':
    main()