#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""署名完整性门禁：包里每张实拍都得有可核验的版权记录。

为什么需要（而不是"写完 build_attribution.py 就完事"）：
rawfile/attribution.json 是一次性生成的快照，而图是分批挂进来的。
第五轮之后每轮都在动 images/，只要有一张 CC BY-SA 的图进了包却没有
记录，就是实打实的许可违约——而且屏上看不出来，评审问到才暴露。
本门禁把"生成"与"进包"两侧钉在一起，缺一即红。

三段差集（方向不同，后果不同）：
  被引用/在盘 - 已记录  → FAIL：图在包里跑，版权页上没它
  已记录 - 在盘          → FAIL：版权页链向一张不存在的图
  EraTheme 兜底图 - AI 声明 → FAIL：示意图被当成照片展示， disclosure 漏了

字段侧规则：CC BY* 必须有作者与来源链接（署名三要素：谁、哪来的、改了啥），
CC0/公有领域允许无名，但仍要有 source，否则等于"来源不明"。

用法：
    python tools/check_attribution.py          # 校验
    python tools/check_attribution.py --json   # 机器可读汇总
退出码 0 = 通过，1 = 有缺陷。
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'resources', 'rawfile')
ATTR = os.path.join(RES, 'attribution.json')
SITES = os.path.join(RES, 'sites')
ETS = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'ets')

REAL_RE = re.compile(r'images/[A-Za-z0-9_]+/(real_[A-Za-z0-9_]+\.webp)')
IMG_FULL_RE = re.compile(r'images/[A-Za-z0-9_]+/[A-Za-z0-9_.-]+\.webp')


def files_on_disk():
    out = set()
    img_root = os.path.join(RES, 'images')
    for dirpath, _, fns in os.walk(img_root):
        for fn in fns:
            if fn.startswith('real_') and fn.endswith('.webp'):
                rel = os.path.relpath(os.path.join(dirpath, fn), RES).replace('\\', '/')
                out.add(rel)
    return out


def referenced_paths():
    out = set()
    for fn in sorted(os.listdir(SITES)):
        if not fn.endswith('.json'):
            continue
        with open(os.path.join(SITES, fn), encoding='utf-8') as fh:
            out.update(IMG_FULL_RE.findall(fh.read()))
    return out


def era_theme_images():
    """EraTheme.ets 里硬编码的年代兜底图——这是唯一不走 real_ 谓词的图面。"""
    out = set()
    for dirpath, _, fns in os.walk(ETS):
        for fn in fns:
            if fn.endswith('.ets'):
                with open(os.path.join(dirpath, fn), encoding='utf-8') as fh:
                    out.update(IMG_FULL_RE.findall(fh.read()))
    return {p for p in out if not p.split('/')[-1].startswith('real_')}


def font_files_on_disk():
    d = os.path.join(RES, 'font')
    if not os.path.isdir(d):
        return []
    return sorted(f for f in os.listdir(d)
                  if os.path.splitext(f)[1].lower() in ('.ttf', '.otf', '.woff', '.woff2'))


def check_fonts(data, fails):
    """字体与图片同罪：OFL 1.1 要求分发带上版权行与许可原文。
    这两个 ttf 是改名+取字面后的成品，许可只能按上游 OFL.txt 记，
    所以「原文是否真在包里」必须查，不能只看记录里写了什么。"""
    fonts = data.get('fonts', [])
    disk = font_files_on_disk()
    recs = {f.get('file', '') for f in fonts}
    for name in disk:
        if name not in recs:
            fails.append('在包字体无许可记录: font/%s' % name)
    for name in sorted(recs - set(disk)):
        fails.append('字体许可记录指向不在包的文件: %s' % name)
    for f in fonts:
        name = f.get('file', '')
        for k in ('family', 'licence', 'licence_url', 'source', 'copyright', 'licence_file'):
            if not (f.get(k) or '').strip():
                fails.append('字体 %s 缺字段 %s' % (name, k))
        lf = (f.get('licence_file') or '').replace('/', os.sep)
        p = os.path.join(RES, lf)
        if not os.path.exists(p):
            fails.append('字体 %s 的许可原文不在包: %s' % (name, f.get('licence_file')))
            continue
        head = open(p, encoding='utf-8', errors='replace').read(200)
        if 'Copyright' not in head:
            fails.append('许可原文 %s 首段不含 Copyright' % f.get('licence_file'))
        if not f.get('licence_url', '').startswith('https://') and not f.get('licence_url', '').startswith('http://'):
            fails.append('字体 %s 的许可链接不合法: %s' % (name, f.get('licence_url')))
    return len(disk), len(fonts)


def main(argv):
    as_json = '--json' in argv
    fails = []
    notes = []

    if not os.path.exists(ATTR):
        print('FAIL: rawfile/attribution.json 不存在，先跑 tools/build_attribution.py')
        return 1

    with open(ATTR, encoding='utf-8') as fh:
        data = json.load(fh)
    records = data.get('images', [])
    ai = data.get('ai_illustrations', [])
    recorded = {r.get('path', '') for r in records}
    disk = files_on_disk()
    refs = referenced_paths()

    lic = {}
    for r in records:
        p = r.get('path', '')
        if not p:
            fails.append('记录缺 path')
            continue
        licence = (r.get('licence') or '').strip()
        lic[licence] = lic.get(licence, 0) + 1
        if not licence:
            fails.append('%s 无许可字段' % p)
            continue
        if licence.upper().startswith('CC BY'):
            if not (r.get('author') or '').strip():
                fails.append('%s 是 %s，但无作者——BY 系列必须署名' % (p, licence))
            if not (r.get('source') or '').startswith('https://'):
                fails.append('%s 是 %s，但无 https 来源链接' % (p, licence))
            if not (r.get('adapted') or '').strip():
                fails.append('%s 是 %s，但未说明修改' % (p, licence))
        else:
            if not (r.get('source') or '').startswith('https://'):
                fails.append('%s（%s）无来源链接，等同来源不明' % (p, licence))

    dup = len(records) - len(recorded)
    if dup:
        fails.append('attribution.json 有 %d 条 path 重复' % dup)

    # 在盘是权威口径：被 validate_sites 保证"引用必在盘"，
    # 所以这里只需查「盘上的图是否都有记录」，引用侧缺文件另报一条 NOTE。
    missing_disk = sorted(disk - recorded)
    ghost = sorted(recorded - disk)
    for p in missing_disk:
        fails.append('在包实拍但无署名记录: %s' % p)
    for p in ghost:
        fails.append('署名记录指向的图不在包: %s' % p)
    for p in sorted(refs - disk):
        notes.append('被引用但盘上无文件（交给 validate_sites 判红）: %s' % p)

    # AI 示意图：EraTheme 引用的非 real_ 图必须逐张声明
    era = era_theme_images()
    declared = {a.get('path', '') for a in ai}
    for p in sorted(era - declared):
        fails.append('EraTheme 引用的示意图未在 ai_illustrations 声明: %s' % p)
    for p in sorted(declared - era):
        fails.append('ai_illustrations 声明的图已不被任何代码引用: %s' % p)
    for p in sorted(declared):
        if not os.path.exists(os.path.join(RES, p.replace('/', os.sep))):
            fails.append('声明的示意图不在包: %s' % p)

    n_font_disk, n_font_rec = check_fonts(data, fails)

    summary = {
        'records': len(records),
        'images_on_disk': len(disk),
        'images_referenced': len(refs),
        'ai_declared': len(declared),
        'fonts_on_disk': n_font_disk,
        'fonts_declared': n_font_rec,
        'licences': lic,
        'fails': len(fails),
    }
    if as_json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print('署名记录 %d 条 | 在包实拍 %d 张 | 被引用 %d 张 | AI 声明 %d 张 | 字体 %d/%d'
              % (len(records), len(disk), len(refs), len(declared), n_font_rec, n_font_disk))
        print('许可分布: ' + '  '.join('%s×%d' % (k or '(空)', v) for k, v in sorted(lic.items())))
        for n in notes:
            print('NOTE  %s' % n)
        for f in fails[:40]:
            print('FAIL  %s' % f)
        if len(fails) > 40:
            print('FAIL  …另有 %d 条' % (len(fails) - 40))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
