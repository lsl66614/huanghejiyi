"""tools/fetch_commons_images.py —— 按清单从 upload.wikimedia.org 分段拉图并转 webp 落 rawfile。

为什么不用 tools/fetch_commons_images.mjs：
  · mjs 版自己拼 thumb 路径，对带空格/Unicode 的文件名推不出来（PITFALLS #41）；
  · 本机 commons.wikimedia.org 的 API 直连超时，但 upload.wikimedia.org 可直连，
    所以检索走云端代理拿 URL，下载在本地做（本脚本只吃现成的 URL）。
口径（docs/IMAGES.md）：长边 1024、WebP q78、单图 ≤200KB；文件名必须 real_ 前缀。

用法：
  python tools/fetch_commons_images.py <清单.json> [--out <目录>] [--dry-run]
清单 JSON = 数组，每项 {"site":"kaita","name":"real_kaita_tashen",
  "url":"https://upload.wikimedia.org/...","file":"File:xxx.jpg",
  "licence":"CC BY-SA 4.0","author":"...","desc":"..."}
"""
import argparse
import io
import json
import os
import sys
import time

from PIL import Image

CHUNK = 1024 * 1024
UA = 'HuangHeMemoryAppResearch/1.0 (competition entry; contact via project repo)'
MAX_SIDE = 1024
QUALITY = 78
MAX_BYTES = 200 * 1024


def http_get(url, start=None, end=None):
    import urllib.error
    import urllib.request
    headers = {'User-Agent': UA}
    if start is not None:
        headers['Range'] = 'bytes=%d-%d' % (start, end)
    last = None
    # 链路抖动表现为 TLS 握手挂满超时（实测连拒 3 次后第 4 次 200），
    # 所以短超时 + 多次尝试优于长超时 + 少次尝试（PITFALLS #62 续）。
    for attempt in range(8):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=20) as r:
                return r.status, r.read(), dict(r.headers)
        except urllib.error.HTTPError as e:
            last = e
            # 429 = 并发/频率触发 robot policy，退避后重试；其余只重试一次
            time.sleep(30 * (attempt + 1) if e.code == 429 else 3 * (attempt + 1))
        except Exception as e:  # noqa: BLE001 - 网络异常一律重试
            last = e
            time.sleep(4 * (attempt + 1))
    raise last


def download(url):
    """分段 Range 拉取：整文件长连接会被中间链路掐断（PITFALLS #42）。"""
    status, head, headers = http_get(url, 0, CHUNK - 1)
    if status not in (206, 200):
        raise RuntimeError('http %s' % status)
    total = None
    cr = headers.get('Content-Range') or headers.get('content-range') or ''
    if '/' in cr:
        total = int(cr.rsplit('/', 1)[1])
    buf = bytearray(head)
    if total is None:  # 服务端不支持 Range，head 就是全部
        return bytes(buf)
    while len(buf) < total:
        s = len(buf)
        st, part, _ = http_get(url, s, min(s + CHUNK, total) - 1)
        if st not in (206, 200) or not part:
            raise RuntimeError('截断于 %d/%d (http %s)' % (s, total, st))
        buf += part
    return bytes(buf)


def sniff(raw):
    if raw[:3] == b'\xff\xd8\xff':
        return 'jpeg'
    if raw[:8] == b'\x89PNG\r\n\x1a\n':
        return 'png'
    if raw[:4] == b'RIFF' and raw[8:12] == b'WEBP':
        return 'webp'
    return None


def convert(raw, out_path):
    im = Image.open(io.BytesIO(raw))
    im.load()
    im = im.convert('RGB')
    w, h = im.size
    if max(w, h) > MAX_SIDE:
        scale = MAX_SIDE / float(max(w, h))
        im = im.resize((int(round(w * scale)), int(round(h * scale))), Image.LANCZOS)
    q = QUALITY
    while True:
        im.save(out_path, 'WEBP', quality=q, method=6)
        if os.path.getsize(out_path) <= MAX_BYTES or q <= 40:
            break
        q -= 8
    return im.size, os.path.getsize(out_path), q


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('plan')
    # 默认落在 tools/staging_unmounted，不直接进 rawfile：
    # 下载后要经过人工/视觉核图才决定挂不挂，而 rawfile 里的任何文件
    # 都会被 hvigor 一路打进 HAP（PITFALLS #63，实测白背 3.40 MB）。
    stage = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                         'staging_unmounted')
    ap.add_argument('--out', default=stage)
    ap.add_argument('--dry-run', action='store_true')
    a = ap.parse_args()
    items = json.load(open(a.plan, encoding='utf-8'))
    ok, fail, skip = [], [], []
    for it in items:
        site, name, url = it['site'], it['name'], it['url']
        if not name.startswith('real_'):
            fail.append((name, 'name 必须 real_ 前缀'))
            continue
        out_dir = os.path.join(a.out, site)
        out_path = os.path.join(out_dir, name + '.webp')
        if os.path.exists(out_path):
            skip.append((name, '已存在'))
            continue
        if a.dry_run:
            ok.append((name, 'dry-run'))
            continue
        try:
            raw = download(url)
            kind = sniff(raw)
            if kind is None:
                fail.append((name, '非图片字节（可能被限流返回 HTML），前 16 字节=%s' % raw[:16].hex()))
                continue
            os.makedirs(out_dir, exist_ok=True)
            size, nbytes, q = convert(raw, out_path)
            ok.append((name, '%s %dx%d → %dKB q%d' % (kind, size[0], size[1], nbytes // 1024, q)))
        except Exception as e:  # noqa: BLE001
            fail.append((name, repr(e)[:120]))
        time.sleep(0.6)  # 同进程连拉会累积 TLS 状态（PITFALLS #43）
    for n, why in ok:
        print('OK   %s | %s' % (n, why))
    for n, why in skip:
        print('SKIP %s | %s' % (n, why))
    for n, why in fail:
        print('FAIL %s | %s' % (n, why))
    print('合计 ok=%d skip=%d fail=%d' % (len(ok), len(skip), len(fail)))
    return 1 if fail and not ok else 0


if __name__ == '__main__':
    sys.exit(main())
