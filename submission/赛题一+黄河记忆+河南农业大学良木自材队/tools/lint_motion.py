"""动效门禁：把 Phase 2 的硬规矩逐条机械化。

判据（共 6 条，全部可静态判定）：

1. **时长不许写数字。** `.animation({duration: 240})` 里的 240 是字面量，
   绕开了 Motion.dur()，系统「减弱动画」开关对它无效。必须写 dur*()。
   （这一条 lint_a11y 已守，此处重复守是刻意的：两个文件都可能在某次
   重构中被拆分掉，动效规则不该只挂在 a11y 名下。）

2. **曲线不许用 Curve.* 字面量。** 统一后的动效若仍有一处写死
   Curve.EaseInOut，就是全站质感不一致的开始。

3. **按压反馈不许漏。** 有 onClick 的组件应挂按下态实现。
   历史遗留 57 处 onClick 只有 1 处有反馈——用户点下去看不出是否命中，
   于是重复点击。
   注意实现形式：目前全站用 stateStyles，但 2026-10-09 真机实测它
   **抓不到按下态**（详见 Motion.ets 顶部注释），所以本条只保证「挂了
   某种按下态声明」，不保证它在屏幕上有效。唯一被验证有效的是
   Index 年代卡那套手写 @State + onTouch。

4. **路由转场十页齐备。** 每个 @Entry 页都要有 pageTransition() 钩子，
   且钩子内的时长/曲线/位移三项必须与 DesignTokens 的令牌一致。
   漏一页 = 该页走系统默认转场，与其余九页质感不同。

5. **stateStyles 与 .animation() 不能同链。** 两者同时出现在一条链上时，
   编译器报 10905203（与书写顺序无关），不是运行期抖动。

6. **stateStyles 必须是逐字的内联字面量。** 它的参数是 UI 语法，编译期
   要能提取：函数调用、跨模块 const、同文件 const 三种写法实测全报
   10905203。能编译的只有直接写字面量，于是「56 处各写一遍」带来漂移
   风险——本条把两种合法形态钉死，有人写成 0.8 而非 PRESS_OPACITY 会被拦下。

只读，不写任何文件。
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets')
PAGES = os.path.join(ETS, 'pages')

# 时长字段：值必须是 dur*() 调用或已知的 0 缩减量
DURATION = re.compile(r'duration\s*:\s*([^,}]+)')
# 曲线字段
CURVE = re.compile(r'curve\s*:\s*([A-Za-z_.]+)')
CURVE_OK = {'curveOut', 'curveIn', 'curveInOut', 'curveOut()', 'curveIn()',
            'curveInOut()'}

# 转场钩子里必须逐字出现的三样
TRANSITION_TOKENS = [
    'PageTransitionEnter({ duration: durRouteIn(), curve: curveOut() })',
    'PageTransitionExit({ duration: durRouteOut(), curve: curveIn() })',
    '.translate({ x: ROUTE_SHIFT_VP, y: 0 })',
    '.opacity(ROUTE_FADE_MIN);',
]

# 规则 6：stateStyles 的两种合法内联形态（有底色缩放 / 无底色压暗）
PRESS_LITERAL_SCALE = \
    '{ pressed: { scale: { x: PRESS_SCALE, y: PRESS_SCALE } } }'
PRESS_LITERAL_TEXT = '{ pressed: { opacity: PRESS_OPACITY } }'

def line_comment(line):
    return line.strip().startswith('//')


def find_close(lines, start):
    if not lines[start].rstrip().endswith('{'):
        return None
    depth = 0
    for k in range(start, len(lines)):
        if line_comment(lines[k]):
            continue
        for ch in lines[k]:
            if ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
        if depth == 0:
            return k
    return None


def scan_file(path, rel):
    """返回该文件的 (规则, 行号, 说明) 列表。"""
    with open(path, encoding='utf-8') as fh:
        lines = fh.read().split('\n')
    out = []
    for i, line in enumerate(lines, 1):
        if line_comment(line):
            continue
        if '.stateStyles(' in line and in_block_comment(lines, i - 1):
            continue

        # 规则 1：时长字面量
        # 豁免业务字段：`duration: string`（路线时长文案）不是动画时长，
        # 2026-10-28 实测 ContentModels/RouteListPage/RoutePage 三处被误伤。
        for m in DURATION.finditer(line):
            v = m.group(1).strip()
            if v.startswith('string'):
                continue
            if not re.match(r'^(dur\w*\(\)|durRouteIn\(\)|durRouteOut\(\))', v):
                out.append(('时长字面量', i,
                            'duration: %s 不是 dur*()，减弱动画开关对其无效' % v))

        # 规则 2：曲线字面量
        for m in CURVE.finditer(line):
            v = m.group(1).strip()
            if v.startswith('Curve.'):
                out.append(('曲线字面量', i,
                            'curve: %s 应改用 CURVE_* 令牌（Motion.curveOut/In/InOut）' % v))

        # 规则 5：stateStyles 与 animation 同挂
        # 只查真正的调用点；Motion.ets 注释里提到 .animation 不是调用。
        if '.stateStyles(' in line:
            chain = []
            for k in range(i - 1, min(i + 30, len(lines))):
                chain.append(lines[k])
                if k > i - 1 and lines[k].strip().startswith(('.onClick', '.onTouch')):
                    break
            if any('.animation(' in c for c in chain):
                out.append(('互斥', i,
                            'stateStyles 与 .animation() 同时挂在一条链上，'
                            '编译器报 10905203（与书写顺序无关）'))

        # 规则 6：stateStyles 必须是逐字的内联字面量且取自令牌。
        # 之所以要守：stateStyles 的参数是 UI 语法，编译期要能提取，
        # 写成函数调用 / 跨模块 const / 同文件 const 都报 10905203。
        # 能编译的唯一形态就是直接写字面量——于是「56 处各写一遍」必然
        # 带来漂移风险（有人图省事写成 0.8 而不是 PRESS_OPACITY）。
        # 这里把两种合法形态逐字钉死。
        if '.stateStyles(' in line:
            body = line[line.index('.stateStyles('):]
            if PRESS_LITERAL_SCALE not in body and PRESS_LITERAL_TEXT not in body:
                out.append(('按压态字面量', i,
                            'stateStyles 只能是 { pressed: { scale: { x: PRESS_SCALE,'
                            ' y: PRESS_SCALE } } } 或 { pressed: { opacity:'
                            ' PRESS_OPACITY } }；其余形态编译期报 10905203'))
    return out


COMPONENT_CALL = re.compile(
    r'\b(Button|Text|Image|Row|Column|Stack|Flex|SymbolGlyph)\s*\(')


def host_start(lines, at):
    """onClick 所在组件链的**内层**起点。

    与 lint_a11y.chain_start 的区别：那个一路回退到最外层容器（那里才是
    整条链的修饰符挂载点）；本函数要的是「谁自己挂着这个 onClick」。
    必须停在内层，否则同层兄弟会互相串味——Text 甲 挂了反馈、隔两行的
    Text 乙 会被误判为已覆盖（回退到外层 Row 时窗口把甲也包进去了）。

    两条规则：
      1. onClick 那一行本身带组件构造（`Text('乙').onClick(...)`），
         宿主就是本行——这一步不能省，否则会一路退到上一个兄弟节点。
      2. 否则按花括号深度回退，遇到第一个 depth==0 的非修饰符行即停。
    """
    if COMPONENT_CALL.search(lines[at]):
        return at
    i = at
    depth = 0
    while i > 0:
        i -= 1
        t = lines[i].strip()
        if not t or line_comment(lines[i]):
            continue
        depth -= brace_delta(lines[i])
        if depth != 0:
            continue
        if t.startswith(('.', '}', ')')):
            continue
        return i
    return at


def in_block_comment(lines, idx):
    """该行是否落在 /** */ 文档注释里。

    Motion.ets 顶部刻意列了三种**不可用**的写法做反例，那些行字面上
    含有 .stateStyles(...)，会被规则 5/6 当成真调用点。
    """
    open_at = None
    for k in range(idx + 1):
        t = lines[k].strip()
        if t.startswith('/*'):
            open_at = k
        elif t.endswith('*/') and open_at is not None and k >= open_at:
            if k == idx:
                return True
            open_at = None
    return open_at is not None and idx > open_at


def brace_delta(line):
    return line.count('{') - line.count('}')


def check_press(path, rel):
    """规则 3：onClick 宿主应挂按压反馈。"""
    with open(path, encoding='utf-8') as fh:
        lines = fh.read().split('\n')
    out = []
    for i, line in enumerate(lines, 1):
        if line_comment(line) or '.onClick(' not in line:
            continue
        end = find_close(lines, i - 1)
        body_end = end if end is not None else i + 3
        # 窗口 = 内层宿主起点 → onClick 收尾 + 后续修饰符。
        # 往前要盖住 Index 年代卡那种把 .onTouch + .animation 写在 onClick
        # **之前**的既有实现；往后留 30 行盖住 .stateStyles / .focusBox。
        start = host_start(lines, i - 1)
        window = lines[start:min(body_end + 30, len(lines))]
        if any('.stateStyles(' in w or 'pressState' in w or '.onTouch(' in w
               for w in window):
            continue
        # 挂到 PressScale / PressFade 包装器上的节点：反馈在包装器内部，
        # 调用方的链上看不到 onTouch。这里认「祖先里有 Press* 包裹」——
        # 向上找宿主起点之前先扫整段文件代价太高，改用「同层上文 12 行
        # 内出现过 PressScale(/PressFade( 且 onClick 之后紧跟 content/」
        # 收尾」这一结构性事实来判定。
        if in_press_wrapper(lines, i - 1):
            continue
        out.append(('缺按压反馈', i,
                    '.onClick 无按压反馈；套 PressScale()/PressFade() 包装器'))
    return out


# 包装器的两种收尾标记：@BuilderParam 内容段的结束，紧跟 onClick 之后。
PRESS_WRAPPER_END = ('}', '          }')


def in_press_wrapper(lines, at):
    """onClick 是否落在某个 PressScale/PressFade 包装器的内容段里。

    判据用花括号配平，不用「向上找最近的关键字」：包装器内容里常嵌套
    Row/Column/If 等节点，向上扫关键字会被这些内层节点截断，误判成
    「不在包装器里」。改成「找出所有 Press* 块的起止区间，看 onClick
    落在哪个区间内」，与书写方式无关。
    """
    for start, end in press_wrapper_blocks(lines):
        if start < at <= end:
            return True
    return False


def press_wrapper_blocks(lines):
    """所有 PressScale/PressFade 内容段的 (起始行, 结束行) 区间。"""
    blocks = []
    for i, line in enumerate(lines):
        t = line.strip()
        if not (t.startswith('PressScale(') or t.startswith('PressFade(')):
            continue
        if not t.endswith('{'):
            continue
        depth = 0
        for k in range(i, len(lines)):
            depth += brace_delta(lines[k])
            if depth == 0:
                blocks.append((i, k))
                break
    return blocks


def check_transition(path, rel):
    """规则 4：每个 @Entry 页都要有 pageTransition，且四样令牌齐备。

    为什么不能像其它公共件那样抽成 common/PageMotion.ets：2026-11-05 实测，
    PageTransitionEnter/Exit 被 ArkUI 编译器限定在 @Entry 页组件的方法体里，
    写成普通模块函数会直接 CompileArkTS 失败（
    "UI component 'PageTransitionEnter' cannot be used in this place"）。
    因此这四行在 21 个页里逐字重复是平台强制，不是欠抽件——门禁仍按逐字判。
    """
    with open(path, encoding='utf-8') as fh:
        src = fh.read()
    if '@Entry' not in src:
        return []
    m = re.search(r'pageTransition\(\): void \{', src)
    if m is None:
        return [('缺转场', 0, '本页无 pageTransition() 钩子')]
    start = m.start()
    end = src.find('\n  }', start)
    body = src[start:end if end > 0 else start + 600]
    out = []
    for tok in TRANSITION_TOKENS:
        if tok not in body:
            out.append(('转场令牌', 0, '钩子内缺 %s' % tok))
    return out


def main():
    findings = []
    scanned = 0
    files = []
    for d in (ETS, PAGES):
        for dirpath, _, fns in os.walk(d):
            for fn in sorted(fns):
                if fn.endswith('.ets'):
                    files.append(os.path.join(dirpath, fn))
    for full in sorted(set(files)):
        rel = os.path.relpath(full, ROOT)
        scanned += 1
        findings += [(k, rel, n, m) for k, n, m in scan_file(full, rel)]
        if full.startswith(PAGES):
            findings += [(k, rel, n, m) for k, n, m in check_press(full, rel)]
            findings += [(k, rel, n, m) for k, n, m in check_transition(full, rel)]

    by = {}
    for k, rel, n, m in findings:
        by.setdefault(k, []).append((rel, n, m))
    for k in sorted(by):
        rows = by[k]
        print('[%s] %d 处' % (k, len(rows)))
        for rel, n, m in rows:
            print('  %s %s  %s' % (rel, ('第 %d 行' % n) if n else '', m))

    print('\n' + '-' * 78)
    print('扫描 %d 个文件，缺陷 %d 处' % (scanned, len(findings)))
    return 1 if findings else 0


if __name__ == '__main__':
    sys.exit(main())