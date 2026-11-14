#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""出包前总门禁：一条命令跑完十三道脚本校验与单测。

为什么要这个聚合器（而不是"文档里写了要跑哪几条"）：
设计方案.md 长期声称"八道脚本门禁全部随构建执行，任一非 0 退出码即阻断出包"，
但 build-oh.bat 里只有 hvigor——也就是说这句话一直是空的。门禁靠人记得跑，
就等于没有门禁：漏跑一次，红的那条恰好是这次改的东西。
现在 build-oh.bat 在 assembleHap 之前调本脚本，声明与实现同一份。

约定：
  · 每条门禁都是独立子进程，退出码非 0 即该条红；
  · 通过的条目只回显最后一行摘要（失败条目全文打出来，不用再去手跑一遍）；
  · 单跑某条：python tools/run_gates.py --only contrast
  · 临时跳过（仅限排障）：环境变量 SKIP_GATES=1，build-oh.bat 会认。

用法：
    python tools/run_gates.py            # 全跑
    python tools/run_gates.py --only a,b # 只跑名字含 a/b 的
    python tools/run_gates.py --list     # 列出门禁清单
退出码 0 = 全绿，1 = 至少一条红。
"""
import glob
import os
import subprocess
import sys

# build-oh.bat 在 cmd 里跑本脚本：门禁输出混着 node 的 ℹ、表格里 ×/− 等
# 字符，控制台默认 GBK 码页下 print 会 UnicodeEncodeError 崩掉出包流程。
# 统一按 UTF-8 输出（bat 里先 chcp 65001），编不出的字符换成 ?，绝不再崩。
try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, 'tools')
SITES = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'sites')

PY = sys.executable
NODE = 'node'


def node_tests():
    return [NODE, '--test'] + sorted(glob.glob(os.path.join(TOOLS, 'merge-tests', '*.test.mjs')))


# (名字, 说明, 命令)。顺序即依赖顺序：内容校验在样式门禁之前，
# 因为 JSON 结构错时后面的视觉门禁只会跟着误报。
GATES = [
    ('validate', '内容 JSON：schema + 图片引用制式/存在性 + 反向差集',
     [PY, os.path.join(TOOLS, 'validate_sites.py'), SITES, '--no-out']),
    ('validate-src', '母本 sites-src 一致性（与 rawfile 同 schema）',
     [PY, os.path.join(TOOLS, 'validate_sites.py'),
      os.path.join(TOOLS, 'sites-src'), os.path.join(TOOLS, 'sites-out')]),
    ('attribution', '署名完整性：每张在包实拍都有版权记录',
     [PY, os.path.join(TOOLS, 'check_attribution.py')]),
    ('poems', '诗词层完备性：42 址每条 ≥1 首且三要素齐全',
     [NODE, os.path.join(TOOLS, 'check_poems.mjs')]),
    ('contrast', '文本/底色对比度',
     [PY, os.path.join(TOOLS, 'check_contrast.py')]),
    ('tokens', '设计令牌裸值（含未启用规则）',
     [PY, os.path.join(TOOLS, 'lint_tokens.py'), '--all']),
    ('visual', '跨页间距档位漂移',
     [PY, os.path.join(TOOLS, 'lint_visual_consistency.py')]),
    ('aging', '字号收敛表 + 豁免失效',
     [PY, os.path.join(TOOLS, 'lint_aging.py')]),
    ('a11y', '无障碍：符号控件命名 + 动效时长走令牌',
     [PY, os.path.join(TOOLS, 'lint_a11y.py')]),
    ('motion', '按压反馈与页面转场钩子',
     [PY, os.path.join(TOOLS, 'lint_motion.py')]),
    ('font', '字体搭配（字族/字重档位）',
     [PY, os.path.join(TOOLS, 'check_font_pairing.py')]),
    ('tsbuild', '纯函数 .ets → .ts 供 Node 执行',
     [NODE, os.path.join(TOOLS, 'merge-tests', 'run.mjs')]),
    ('unittest', 'Node 单测', node_tests),
]


def run_one(name, desc, cmd):
    """跑一条门禁，返回 (是否通过, 回显行)。"""
    real_cmd = cmd() if callable(cmd) else cmd
    env = dict(os.environ)
    env['PYTHONIOENCODING'] = 'utf-8'
    try:
        p = subprocess.run(real_cmd, cwd=ROOT, env=env, capture_output=True, text=True,
                           encoding='utf-8', errors='replace', timeout=600)
    except FileNotFoundError as e:
        return False, ['FAIL  %s：命令不存在 %s' % (name, e)]
    except subprocess.TimeoutExpired:
        return False, ['FAIL  %s：超过 600s' % name]
    out = (p.stdout or '') + (p.stderr or '')
    lines = [l for l in out.splitlines() if l.strip()]
    if p.returncode == 0:
        tail = lines[-1] if lines else '（无输出）'
        return True, ['ok    %-14s %s' % (name, tail[:110])]
    return False, ['FAIL  %s（退出码 %d）' % (name, p.returncode)] + ['      ' + l for l in lines[:60]]


def main(argv):
    if os.environ.get('SKIP_GATES') == '1':
        print('[run_gates] SKIP_GATES=1 —— 本次不出包，门禁全部跳过')
        return 0
    only = None
    for i, a in enumerate(argv):
        if a == '--only' and i + 1 < len(argv):
            only = {x.strip() for x in argv[i + 1].split(',') if x.strip()}
    if '--list' in argv:
        for name, desc, _ in GATES:
            print('%-14s %s' % (name, desc))
        return 0
    selected = [g for g in GATES if only is None or g[0] in only]
    if only and not selected:
        print('[run_gates] --only 没匹配到任何门禁：%s' % ','.join(sorted(only)))
        return 1
    bad = []
    for name, desc, cmd in selected:
        ok, echo = run_one(name, desc, cmd)
        print('\n'.join(echo))
        if not ok:
            bad.append(name)
    print('-' * 72)
    print('[run_gates] %d/%d 通过%s'
          % (len(selected) - len(bad), len(selected),
             '' if not bad else '；红：%s' % ' '.join(bad)))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
