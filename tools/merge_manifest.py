"""tools/merge_manifest.py —— 把 tools/.sync_probe/plan_*.json 的下载项并入 tools/commons_manifest.json。

台账口径（docs/IMAGES.md）：每条记 site/name/file/licence/author/desc，按 name 去重、后写覆盖前写。
用法：python tools/merge_manifest.py tools/.sync_probe/plan_hero.json [plan_*.json ...]
"""
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAN = os.path.join(ROOT, 'tools', 'commons_manifest.json')


def main(paths):
    man = json.load(open(MAN, encoding='utf-8'))
    by_name = {it['name']: dict(it) for it in man['items']}
    added, updated = 0, 0
    for p in paths:
        for it in json.load(open(p, encoding='utf-8')):
            row = {k: it[k] for k in ('site', 'name', 'file') if k in it}
            for k in ('licence', 'author', 'desc'):
                row[k] = it.get(k, '')
            if 'url' in it:
                row['source'] = it['url'].split('?')[0]
            if row['name'] in by_name:
                by_name[row['name']].update({k: v for k, v in row.items() if v})
                updated += 1
            else:
                by_name[row['name']] = row
                added += 1
    man['items'] = [by_name[k] for k in sorted(by_name)]
    with open(MAN, 'w', encoding='utf-8') as f:
        f.write(json.dumps(man, ensure_ascii=False, indent=1))
    print('台账条目 %d（新增 %d，更新 %d）' % (len(man['items']), added, updated))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
