// 下载 Commons 真实照片 → sharp 转 webp(1024/q78) → real_ 命名入 rawfile/images/<site>/
// → 在 sites-src 与 rawfile/sites 两份 JSON 的 images 数组置顶追加 real 路径（总数守 schema ≤4）
// → 打印 IMAGES.md 台账行。用法: node tools/apply_real_images.cjs
// 网络说明: 元数据走 commons API；图片二进制经 wsrv.nl 代取（本机直连 upload.wikimedia.org 不通）。
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const sharp = require('sharp');

const ROOT = path.join(__dirname, '..');
const RAW_SITES = path.join(ROOT, 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'sites');
const SRC_SITES = path.join(__dirname, 'sites-src');
const RAW_IMG = path.join(ROOT, 'app', 'entry', 'src', 'main', 'resources', 'rawfile', 'images');
const API = 'https://commons.wikimedia.org/w/api.php';
const UA = 'HuangHeMemoryAppResearch/1.0 (competition entry research; contact via project repo)';
const LICENSE_OK = /^(cc0|public domain|cc by(-sa)?( [1-4](\.0|\.5)?)?)$/i;

// 选定清单：site 目录 → Commons 文件标题 → 入仓 slug
const PICKS = [
  { site: 'erlitou', files: [
    { title: 'File:20240815 Erlitou Site 01.jpg', slug: 'real_yizhi_01' },
    { title: 'File:20240815 Erlitou Site 04.jpg', slug: 'real_yizhi_02' }
  ] },
  { site: 'hanwei_luoyangcheng', files: [
    { title: 'File:20240815 Site of Luoyang City from Han to Wei Dynasty - Site of the Pagoda of Yongning Temple 01.jpg', slug: 'real_yongning_tabji' },
    { title: 'File:20251018 Han-Wei Luoyang Ancient City Site Museum.jpg', slug: 'real_yizhi_bowuguan' }
  ] },
  { site: 'dongjing', files: [
    { title: 'File:20251109 Site of Zhou Bridge 01.jpg', slug: 'real_zhouqiao_01' },
    { title: 'File:20251109 Site of Zhou Bridge 03.jpg', slug: 'real_zhouqiao_02' }
  ] },
  { site: 'song_ling', files: [
    { title: 'File:20130405 Yongzhao Mausoleum.jpg', slug: 'real_yongzhaoling' },
    { title: 'File:Northern Song Imperial Family Tomb - 3.jpg', slug: 'real_songling_shengshan' }
  ] },
  { site: 'gongxian_yao', files: [
    { title: 'File:20240914 Gongyi Kiln Site.jpg', slug: 'real_yaokui_yizhi' }
  ] },
  { site: 'yangshao_village', files: [
    { title: 'File:Yangshao Culture Original Excavation Site- Yangshao & Longshan Strata.jpg', slug: 'real_yangshao_diceng' },
    { title: 'File:Yangshao Village.jpg', slug: 'real_yangshaocun' }
  ] },
  { site: 'miaodigou', files: [
    { title: 'File:Pots from the Yangshao Culture (3900-3600 BC), Miaodigou site, Sanmenxia, Henan.jpg', slug: 'real_miaodigou_taogi' },
    { title: 'File:20251026 Painted Pottery Bowl from Miaodigou.jpg', slug: 'real_caitao_pen' }
  ] },
  { site: 'duling_fangding', files: [
    { title: 'File:20260520 Nipple-Nailed Square Ding with Beast Face Patterns 01.jpg', slug: 'real_ruding_fangding' }
  ] },
  { site: 'zhengzhou_shangcheng', files: [
    { title: 'File:20240817 Zhengzhou Shang City Site 01.jpg', slug: 'real_shangcheng_qiang' },
    { title: 'File:Shang Dynasty City Wall, Zhengzhou 01.jpg', slug: 'real_chengqiang_02' }
  ] },
  { site: 'wangchenggang', files: [
    { title: 'File:Dengfeng Wangchenggang Yizhi 20181218 085045.jpg', slug: 'real_wangchenggang_yizhi' },
    { title: 'File:20241018 Grey Pottery Ding with Net Design, Wangchenggang Site 01.jpg', slug: 'real_wangwen_taoding' }
  ] },
  { site: 'xishuipo', files: [
    { title: 'File:Human Burial and shell mosaics.National Museum, Beijing .JPG', slug: 'real_bansu_longhu' }
  ] }
];

// node fetch 在本机连 commons 超时（IPv6 策略差异），统一走 curl；网络间歇抖动，重试 4 次
function sleepMs(ms) { Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms); }

function httpGet(url, dest) {
  let lastErr;
  for (let i = 0; i < 4; i++) {
    try {
      cp.execSync(`curl -s -L -m 60 --retry 2 -A "${UA}" "${url}" -o "${dest}"`, { stdio: 'pipe' });
      if (fs.existsSync(dest) && fs.statSync(dest).size > 100) return fs.readFileSync(dest);
    } catch (e) { lastErr = e; }
    fs.rmSync(dest, { force: true });
    sleepMs(1500);
  }
  throw lastErr || new Error('httpGet failed');
}

async function infoFor(title) {
  const u = API + '?' + new URLSearchParams({
    action: 'query', titles: title, prop: 'imageinfo',
    iiprop: 'url|mime|extmetadata', iiurlwidth: '1024', format: 'json'
  });
  const tmp = path.join(__dirname, '_meta_tmp.json');
  httpGet(u, tmp);
  const j = JSON.parse(fs.readFileSync(tmp, 'utf8'));
  const pages = Object.values(j.query.pages);
  const ii = pages[0].imageinfo && pages[0].imageinfo[0];
  if (!ii) throw new Error('no imageinfo for ' + title);
  const em = ii.extmetadata || {};
  const strip = s => String(s || '').replace(/<[^>]*>/g, '').trim();
  return {
    thumb: ii.thumburl, mime: ii.mime,
    license: (em.LicenseShortName && em.LicenseShortName.value) || '?',
    licenseUrl: (em.LicenseUrl && em.LicenseUrl.value) || '',
    artist: strip(em.Artist && em.Artist.value).slice(0, 80),
    descUrl: ii.descriptionurl
  };
}

async function download(url, dest) {
  const proxied = 'https://wsrv.nl/?url=' + encodeURIComponent(url.replace(/^https?:\/\//, '')) + '&w=1024';
  const tmpJpg = dest + '.dl';
  httpGet(proxied, tmpJpg);
  return fs.readFileSync(tmpJpg);
}

async function main() {
  const ledger = [];
  for (const pick of PICKS) {
    for (const f of pick.files) {
      const info = await infoFor(f.title);
      if (!LICENSE_OK.test(info.license.trim())) {
        console.log('SKIP(license) ' + f.title + ' [' + info.license + ']');
        continue;
      }
      const outRel = 'images/' + pick.site + '/' + f.slug + '.webp';
      const outFile = path.join(RAW_IMG, pick.site, f.slug + '.webp');
      const tmp = path.join(RAW_IMG, pick.site, "_tmp_dl.jpg");
      fs.mkdirSync(path.dirname(outFile), { recursive: true });
      const buf = await download(info.thumb, tmp);
      await sharp(buf).resize({ width: 1024, withoutEnlargement: true }).webp({ quality: 78 }).toFile(outFile);
      fs.rmSync(tmp, { force: true });
      // 更新两份 JSON：real 路径置顶、去重、总数 ≤4
      for (const base of [RAW_SITES, SRC_SITES]) {
        const jf = path.join(base, pick.site + '.json');
        if (!fs.existsSync(jf)) { console.log('WARN no json: ' + jf); continue; }
        const j = JSON.parse(fs.readFileSync(jf, 'utf8'));
        const obj = Array.isArray(j) ? j[0] : j;
        obj.images = obj.images || [];
        obj.images = obj.images.filter(p => p !== outRel);
        obj.images.unshift(outRel);
        if (obj.images.length > 4) obj.images = obj.images.slice(0, 4);
        fs.writeFileSync(jf, JSON.stringify(j, null, 2) + '\n');
      }
      ledger.push('| ' + outRel + ' | ' + f.title.replace('File:', '') + ' | ' + info.artist + ' | ' + info.license + ' | ' + info.descUrl + ' |');
      console.log('OK ' + outRel + ' [' + info.license + ']');
      await new Promise(r => setTimeout(r, 500));
    }
  }
  console.log('\n==== IMAGES.md 台账行 ====');
  console.log(ledger.join('\n'));
}
main().catch(e => { console.error(e); process.exit(1); });
