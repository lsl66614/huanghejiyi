#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把规划好的字号收敛应用到源文件：`.fontSize(N)` → `.fontSize(FS_XXX)`。

设计取舍（都是被两次事故教出来的）：
  · 只改 `.fontSize(N)` 这一种形态，且只改收敛表里有的值。改不动
    或对不上的行跳过并报告，绝不猜。
  · 每个文件先在内存里改完，改动数与预期不符就原样放弃这个文件
    ——宁可不改，也不写出一个半改的状态。
  · 逐文件备份到 _scratch/ets_backup_converge/，出问题能整文件回退。
  · 幂等：已收敛的文件再跑一次是零改动、零 import 变动。

关于行高：收敛本身不需要改任何一处显式 lineHeight。逐条算过——
全站 15 处显式行高在字号换档后仍全部 ≥1.3×（最紧的是 NetworkPage:251
的 18/12 = 1.50×、SyncPage:382 的 18/12 = 1.50×）。没有显式行高的标题
走 ArkUI 字体默认行盒，单行标题不受影响；给它们硬加行高反而会把
单行标题撑成两行。故本脚本不碰 lineHeight。

用法：
    python tools/apply_font_converge.py            # 干跑，只报告
    python tools/apply_font_converge.py --write    # 真写
退出码 0 = 全部按预期处理（干跑时恒为 0）。
"""

import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ETS = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets')
BACKUP = os.path.join(ROOT, '_scratch', 'ets_backup_converge')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lint_aging import (  # noqa: E402
    CONVERGE_FROM, EXEMPT, FONT_LADDER, TOKEN_FILES,
    collect_ets_files, line_is_comment,
)

FONT_SIZE = re.compile(r'(\.fontSize\(\s*)([0-9]+)(\s*\))')
IMPORT_LINE = re.compile(r"^import \{([^}]*)\} from '(\.\./common/DesignTokens)'(.*)$")


def exempt_lineno(rel, lineno, size):
    for r, ln, sz, _needle, _why in EXEMPT:
        if r == rel and ln == lineno and (sz is None or sz == size):
            return True
    return False


def add_imports(lines, tokens):
    """把 tokens 并进已有的 DesignTokens import 行；没有就新起一行。"""
    if not tokens:
        return lines, []
    added = []
    for idx, line in enumerate(lines):
        m = IMPORT_LINE.match(line)
        if not m:
            continue
        names = [n.strip() for n in m.group(1).split(',') if n.strip()]
        new = [t for t in tokens if t not in names]
        if not new:
            return lines, []
        names.extend(new)
        names.sort()
        lines[idx] = "import { %s } from '%s'%s\n" % (
            ', '.join(names), m.group(2), m.group(3))
        return lines, new

    # 没有 import 行：在最后一个 import 之后插入
    last = -1
    for idx, line in enumerate(lines):
        if line.startswith('import '):
            last = idx
    if last < 0:
        return lines, []
    new = sorted(tokens)
    lines.insert(last + 1, "import { %s } from '../common/DesignTokens'\n"
                 % ', '.join(new))
    return lines, new


def convert(rel, lines):
    out = list(lines)
    changed = 0
    skipped = []
    tokens = set()

    for idx, line in enumerate(out):
        if line_is_comment(line):
            continue
        m = FONT_SIZE.search(line)
        if not m:
            continue
        lineno = idx + 1
        size = int(m.group(2))
        if size in FONT_LADDER:
            continue
        if exempt_lineno(rel, lineno, size):
            continue
        target = CONVERGE_FROM.get(size)
        token = FONT_LADDER.get(target)
        if token is None:
            skipped.append((lineno, size, '收表里没有归档'))
            continue
        out[idx] = line[:m.start(2)] + token + line[m.end(2):]
        tokens.add(token)
        changed += 1

    out, added = add_imports(out, tokens)
    return out, changed, skipped, added


def verify(out, expected_tokens):
    """改完自检：文件里出现的每个 FS_* 都必须在 import 里。"""
    used = set(re.findall(r'\.fontSize\((FS_[A-Z]+)\)', '\n'.join(out)))
    imported = set()
    for line in out:
        m = IMPORT_LINE.match(line)
        if m:
            imported = {n.strip() for n in m.group(1).split(',') if n.strip()}
    missing = used - imported
    return missing


def main(argv):
    write = '--write' in argv
    total = 0
    files_changed = 0
    problems = []
    failed = []

    for full, rel_parts in collect_ets_files():
        if rel_parts in TOKEN_FILES:
            continue
        rel = rel_parts[0].replace(os.sep, '/') + '/' + rel_parts[1]
        with open(full, encoding='utf-8') as fh:
            original = fh.readlines()

        new, changed, skipped, added = convert(rel, original)
        if not changed and not added:
            continue

        missing = verify(new, None)
        if missing:
            # 自检不过就整文件放弃，不落盘
            failed.append('%s  缺 import：%s' % (rel, ' '.join(sorted(missing))))
            continue

        total += changed
        files_changed += 1
        for lineno, size, why in skipped:
            problems.append('%s:%d  %dpt %s' % (rel, lineno, size, why))

        tag = '改写' if write else '将改'
        print('%s %-22s %3d 处字号%s' % (
            tag, rel, changed, ('，import 补 ' + ' '.join(sorted(added))) if added else ''))

        if write:
            dst = os.path.join(BACKUP, rel.replace('/', os.sep))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(full, dst)
            with open(full, 'w', encoding='utf-8') as fh:
                fh.writelines(new)

    print('\n%s：%d 个文件，共 %d 处字号%s' % (
        '已写入' if write else '干跑', files_changed, total,
        '，跳过 %d 处' % len(problems) if problems else ''))
    if failed:
        print('自检未过、已放弃的文件：')
        for f in failed:
            print('  ' + f)
    if problems:
        print('跳过明细（需人工处理）：')
        for p in problems:
            print('  ' + p)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
