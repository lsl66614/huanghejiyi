// Commons 图搜：按遗址关键词搜 Wikimedia Commons，输出候选清单（标题/许可/作者/缩略地址）
// 供人工挑选后由 fetch_real_images.cjs 下载转 webp。用法: node tools/search_commons.cjs
// 网络说明: commons API 直连可用；图片二进制经 wsrv.nl 代取（upload CDN 本机直连不通）。
const fs = require('fs');

const SUBJECTS = [
  { key: 'erlitou', q: ['Erlitou site', 'Erlitou Zhen'] },
  { key: 'hanwei_luoyangcheng', q: ['Han-Wei Luoyang city', 'Yongning temple Luoyang', 'Luoyang ancient city site'] },
  { key: 'dongjing_zhouqiao', q: ['Zhou Bridge Kaifeng', 'Kaifeng excavation'] },
  { key: 'song_ling', q: ['Song tombs Gongyi', 'Gongyi Songling'] },
  { key: 'gongxian_yao', q: ['Gongyi kiln', 'Gongxian kiln porcelain'] },
  { key: 'yangshao_village', q: ['Yangshao village site', 'Yangshao culture site Mianchi'] },
  { key: 'miaodigou', q: ['Miaodigou'] },
  { key: 'duling_fangding', q: ['Duling fangding', 'Du Ling ding Zhengzhou'] },
  { key: 'zhengzhou_shangcheng', q: ['Zhengzhou Shang city', 'Shang city wall Zhengzhou'] },
  { key: 'xishuipo', q: ['Xishuipo', 'Puyang dragon clam'] },
  { key: 'dahecun', q: ['Dahe village site Zhengzhou'] },
  { key: 'wangchenggang', q: ['Wangchenggang'] }
];

const API = 'https://commons.wikimedia.org/w/api.php';
const UA = 'HuangHeMemoryAppResearch/1.0 (competition entry research; contact via project repo)';

async function search(q) {
  const u = API + '?' + new URLSearchParams({
    action: 'query', generator: 'search', gsrsearch: q, gsrnamespace: '6',
    gsrlimit: '8', prop: 'imageinfo', iiprop: 'url|mime|size|extmetadata',
    iiurlwidth: '1024', format: 'json'
  });
  const r = await fetch(u, { headers: { 'User-Agent': UA } });
  const j = await r.json();
  const pages = (j.query && j.query.pages) || {};
  return Object.values(pages).map(p => {
    const ii = p.imageinfo && p.imageinfo[0];
    if (!ii) return null;
    const em = ii.extmetadata || {};
    const strip = s => String(s || '').replace(/<[^>]*>/g, '').trim().slice(0, 60);
    return {
      title: p.title,
      mime: ii.mime,
      w: ii.width, h: ii.height,
      license: (em.LicenseShortName && em.LicenseShortName.value) || '?',
      artist: strip(em.Artist && em.Artist.value),
      descUrl: ii.descriptionurl || '',
      thumb: ii.thumburl || ''
    };
  }).filter(Boolean);
}

async function main() {
  const out = {};
  for (const s of SUBJECTS) {
    out[s.key] = [];
    for (const q of s.q) {
      try {
        const cands = await search(q);
        out[s.key].push({ q, cands });
      } catch (e) {
        out[s.key].push({ q, error: String(e) });
      }
      await new Promise(r => setTimeout(r, 400));
    }
  }
  fs.writeFileSync(__dirname + '/commons_candidates.json', JSON.stringify(out, null, 1));
  for (const k of Object.keys(out)) {
    console.log('==== ' + k + ' ====');
    for (const blk of out[k]) {
      for (const c of blk.cands || []) {
        if (!/image\/(jpeg|png)/.test(c.mime)) continue;
        if (c.w < 640) continue;
        console.log('  [' + c.license + '] ' + c.title + ' | ' + c.w + 'x' + c.h + ' | ' + c.artist);
      }
    }
  }
}
main().catch(e => { console.error(e); process.exit(1); });
