"""tools/mount_real_images.py —— 把已落盘的 real_ 实拍图挂进 rawfile/sites/*.json。

口径（docs/IMAGES.md、PITFALLS #57）：
  · 遗址 `images[0]` 是头图/列表缩略图 → 只挂外景或现场遗迹；
  · 文物 `images[0]` 是文物卡图 → 只挂同器类同出处的实拍；
  · 其余占位引用保留在后面，不删；
  · 幂等：已在列表里就不重复插。

用法：python tools/mount_real_images.py <挂载计划.json> [--dry-run]
计划 JSON = [{"site_id":"kaita","hero":"real_kaita_tashen",
              "relics":[{"relic_id":"xx","real":"real_xx_yy"}]}]

图源两处：已进包的 rawfile/images/…，以及 fetch_commons_images.py 的默认落点
tools/staging_unmounted/…（待核图区）。挂谁就把谁从暂存区复制进 rawfile，
所以 rawfile 里只会出现"已经被决定要挂"的图（PITFALLS #63）。
"""
import argparse
import json
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, 'app', 'entry', 'src', 'main', 'resources', 'rawfile')
SITES = os.path.join(RAW, 'sites')
STAGE = os.path.join(ROOT, 'tools', 'staging_unmounted')


def locate(site_rel_dir, name):
    """找 real_ 图。已核可的在 rawfile 里，刚下载待核的在 tools 暂存区。
    暂存区的根等同 fetch_commons_images.py 的 --out，即 rel 去掉开头 'images/'
    那一层（staging_unmounted/<遗址>/<name>.webp）。
    返回 (rawfile 相对路径, 缺失说明, 需提升的源路径或 None)。"""
    rel = (site_rel_dir + '/' + name + '.webp').replace('\\', '/')
    win = rel.replace('/', os.sep)
    if os.path.exists(os.path.join(RAW, win)):
        return rel, None, None
    src = os.path.join(STAGE, win[len('images/'):] if win.startswith('images' + os.sep) else win)
    if os.path.exists(src):
        return rel, None, src
    return rel, '磁盘上没有 %s（rawfile 与暂存区都找过）' % rel, None


def promote(src, rel):
    dst = os.path.join(RAW, rel.replace('/', os.sep))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)


def site_dir(site, site_id):
    for lst in [site.get('images', [])] + [r.get('images', []) for r in site.get('relics', [])]:
        for p in lst:
            if p.startswith('images/'):
                return p.rsplit('/', 1)[0]
    return 'images/' + site_id


def put(lst, path):
    """把 path 放到列表首位；返回 'added' | 'moved' | 'exists'。"""
    if path in lst:
        if lst[0] == path:
            return 'exists'
        lst.remove(path)
        lst.insert(0, path)
        return 'moved'
    lst.insert(0, path)
    return 'added'


def append_gallery(site, lst, path):
    """器物图只进图集（排在头图之后）。没有实拍头图时不能进——
    UI 取的是 images 里**第一张** real_ 图（ImagePolicy.firstRealImage），
    没有外景时器物就会顶当头图，正是本轮已修过的错配类型。"""
    if not [p for p in lst if os.path.basename(p).startswith('real_')]:
        return 'blocked（该址无实拍头图，器物图会顶成头图）'
    if path in lst:
        return 'exists'
    lst.append(path)
    return 'added'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('plan')
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    plan = json.load(open(a.plan, encoding='utf-8'))
    touched, report, problems = {}, [], []

    for entry in plan:
        sid = entry['site_id']
        fp = os.path.join(SITES, sid + '.json')
        if not os.path.exists(fp):
            problems.append('%s: 站点 JSON 不存在' % sid)
            continue
        site = touched.get(sid) or json.load(open(fp, encoding='utf-8'))
        d = site_dir(site, sid)
        if entry.get('hero'):
            name = entry['hero']
            rel, miss, src = locate(d, name)
            if miss:
                problems.append('%s hero: %s' % (sid, miss))
            else:
                if src and not a.dry_run:
                    promote(src, rel)
                report.append('%s hero %s → %s' % (sid, put(site.setdefault('images', []), rel), name))
        for g in entry.get('gallery', []):
            rel, miss, src = locate(d, g)
            if miss:
                problems.append('%s gallery: %s' % (sid, miss))
                continue
            verdict = append_gallery(site, site.setdefault('images', []), rel)
            if verdict == 'added' and src and not a.dry_run:
                promote(src, rel)
            report.append('%s 图集 %s → %s' % (sid, verdict, g))
        for r in entry.get('relics', []):
            rid, name = r['relic_id'], r['real']
            rel, miss, src = locate(d, name)
            if miss:
                problems.append('%s/%s: %s' % (sid, rid, miss))
                continue
            hit = [x for x in site.get('relics', []) if x['id'] == rid]
            if not hit:
                problems.append('%s: 找不到文物 %s' % (sid, rid))
                continue
            verdict = put(hit[0].setdefault('images', []), rel)
            if verdict in ('added', 'moved') and src and not a.dry_run:
                promote(src, rel)
            report.append('%s/%s %s → %s' % (sid, rid, verdict, name))
        touched[sid] = site

    for line in report:
        print('  ' + line)
    for line in problems:
        print('PROBLEM ' + line)
    if not a.dry_run:
        for sid, site in touched.items():
            with open(os.path.join(SITES, sid + '.json'), 'w', encoding='utf-8') as f:
                f.write(json.dumps(site, ensure_ascii=False, indent=2))
    print('%s：改动站点 %d 个，问题 %d 条' % ('dry-run' if a.dry_run else '已写入', len(touched), len(problems)))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
