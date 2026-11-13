// entry/src/main/ets/service/content/Attribution.ets —— 纯函数，禁 @kit
//
// 为什么需要这一层：随包发布的 76 张实拍里有 61 张是 CC BY-SA（4.0/3.0），
// 该许可要求「署名 + 说明修改」。数据在 rawfile/attribution.json
// （由 tools/build_attribution.py 从 tools/commons_manifest.json 与 docs/IMAGES.md 生成），
// 这里只负责解析与展示口径，不做任何网络或文件访问。

const CC_BY = 'CC BY';
const CC0 = 'CC0';
const PUBLIC_DOMAIN = 'Public domain';

export class AttributionRecord {
  path: string = '';      // images/<遗址>/real_x.webp
  file: string = '';      // Commons 原文件名
  author: string = '';
  licence: string = '';
  source: string = '';    // Commons 文件页，署名要求可点回来源
  adapted: string = '';   // 对原图做了什么改动（BY-SA 4.0 第 3.b 条）
}

export class AiIllustration {
  era: string = '';
  path: string = '';
  note: string = '';
}

export class FontRecord {
  file: string = '';
  family: string = '';
  designer: string = '';
  licence: string = '';
  licenceUrl: string = '';
  source: string = '';
  licenceFile: string = '';
  copyright: string = '';
  adapted: string = '';
}

export class AttributionData {
  policy: string = '';
  images: AttributionRecord[] = [];
  aiIllustrations: AiIllustration[] = [];
  fonts: FontRecord[] = [];
}

export class LicenceGroup {
  licence: string = '';
  requiresCredit: boolean = false;
  records: AttributionRecord[] = [];
}

function str(o: Record<string, Object>, k: string): string {
  const v = o[k];
  return typeof v === 'string' ? v as string : '';
}

function arr(o: Record<string, Object>, k: string): Record<string, Object>[] {
  const v = o[k];
  return Array.isArray(v) ? v as Record<string, Object>[] : [];
}

/** 灯箱逐张图注：与 images 同序，无记录（非实拍/示意图）给空串，
 *  由调用方决定是否留出行高。放在纯函数层，页面不把 Map 传进组件。 */
export function creditsFor(paths: string[], records: AttributionRecord[]): string[] {
  const out: string[] = [];
  for (const p of paths) {
    const r = findByPath(records, p);
    out.push(r === null ? '' : creditLine(r));
  }
  return out;
}

/** 该许可是否强制署名。CC0 / 公有领域不强制，但本项目仍全部列出，
 *  一是可追溯，二是防止评审误以为"没标许可的图都是自摄"。 */
export function requiresCredit(licence: string): boolean {
  const l = licence.trim().toUpperCase();
  if (l.startsWith(CC0.toUpperCase()) || l.indexOf(PUBLIC_DOMAIN.toUpperCase()) >= 0) { return false; }
  return l.indexOf(CC_BY) >= 0;   // 覆盖 "CC BY 4.0" 与 "CC BY-SA 4.0"
}

export function parseAttribution(text: string): AttributionData {
  const d = new AttributionData();
  if (text === '') { return d; }
  const root = JSON.parse(text) as Record<string, Object>;
  d.policy = str(root, 'policy');
  for (const rj of arr(root, 'images')) {
    const r = new AttributionRecord();
    r.path = str(rj, 'path'); r.file = str(rj, 'file'); r.author = str(rj, 'author');
    r.licence = str(rj, 'licence'); r.source = str(rj, 'source'); r.adapted = str(rj, 'adapted');
    if (r.path !== '' && r.author !== '' && r.licence !== '') { d.images.push(r); }
  }
  for (const aj of arr(root, 'ai_illustrations')) {
    const a = new AiIllustration();
    a.era = str(aj, 'era'); a.path = str(aj, 'path'); a.note = str(aj, 'note');
    if (a.path !== '') { d.aiIllustrations.push(a); }
  }
  for (const fj of arr(root, 'fonts')) {
    const f = new FontRecord();
    f.file = str(fj, 'file'); f.family = str(fj, 'family'); f.designer = str(fj, 'designer');
    f.licence = str(fj, 'licence'); f.licenceUrl = str(fj, 'licence_url');
    f.source = str(fj, 'source'); f.licenceFile = str(fj, 'licence_file');
    f.copyright = str(fj, 'copyright'); f.adapted = str(fj, 'adapted');
    if (f.file !== '') { d.fonts.push(f); }
  }
  return d;
}

/** 一行图注：作者 · 许可。CC0 也标出来，读者才知道不是"来源不明"。 */
export function creditLine(r: AttributionRecord): string {
  if (r.author === '') { return r.licence; }
  return r.licence === '' ? r.author : `${r.author} · ${r.licence}`;
}

export function findByPath(list: AttributionRecord[], path: string): AttributionRecord | null {
  for (const r of list) {
    if (r.path === path) { return r; }
  }
  return null;
}

/** 版权页按许可分组，需署名的排前面——先给义务，再给自愿。
 *  组内按文件名排序，保证每次进入顺序一致（不做随机排布）。 */
export function groupByLicence(list: AttributionRecord[]): LicenceGroup[] {
  const order: string[] = [];
  const bucket: Map<string, AttributionRecord[]> = new Map<string, AttributionRecord[]>();
  for (const r of list) {
    let got = bucket.get(r.licence);
    if (got === undefined) {
      got = [];
      bucket.set(r.licence, got);
      order.push(r.licence);
    }
    got.push(r);
  }
  order.sort((a: string, b: string): number => {
    const ra = requiresCredit(a) ? 0 : 1;
    const rb = requiresCredit(b) ? 0 : 1;
    if (ra !== rb) { return ra - rb; }
    return a < b ? -1 : (a > b ? 1 : 0);
  });
  const out: LicenceGroup[] = [];
  for (const lic of order) {
    const recs = (bucket.get(lic) as AttributionRecord[]).slice();
    recs.sort((x: AttributionRecord, y: AttributionRecord): number =>
      (x.file < y.file ? -1 : (x.file > y.file ? 1 : 0)));
    const g = new LicenceGroup();
    g.licence = lic; g.requiresCredit = requiresCredit(lic); g.records = recs;
    out.push(g);
  }
  return out;
}

/** BY-SA 4.0 第 3.a 条要求给出所依许可的名称与链接。
 *  许可串来自 Commons，形如 "CC BY-SA 4.0" / "CC0 1.0" / "CC BY 4.0"，
 *  这里解析前缀 + 版本号拼规范链接；认不出来就返回空，页面不显示链接，
 *  绝不猜一个可能错的 URL。 */
export function licenceUrl(licence: string): string {
  const l = licence.trim().toUpperCase();
  let family = '';
  if (l.indexOf('CC BY-SA') === 0) { family = 'by-sa'; }
  else if (l.indexOf('CC BY-NC-SA') === 0) { family = 'by-nc-sa'; }
  else if (l.indexOf('CC BY') === 0) { family = 'by'; }
  else if (l.indexOf('CC0') === 0) { family = 'zero'; }
  if (family === '') { return ''; }
  const m = /\d+\.\d+/.exec(l);
  // Commons 的 CC0 标记只有 "CC0" 没有版本号，而 CC0 只发布过 1.0 一个版本。
  if (m === null && family === 'zero') { return 'https://creativecommons.org/publicdomain/zero/1.0/'; }
  if (m === null) { return ''; }
  // CC0 不在 licenses 路径下，规范地址是 publicdomain/zero。
  if (family === 'zero') { return `https://creativecommons.org/publicdomain/zero/${m[0]}/`; }
  return `https://creativecommons.org/licenses/${family}/${m[0]}/`;
}

/** BY-SA 4.0 第 3.b 条要求"说明修改"。本批 76 张的改动口径完全一致，
 *  所以在页面上讲一次即可，不必逐张重复；这里去重取值，避免以后
 *  新增不同处理（如裁切）时声明漏掉。 */
export function changeStatement(list: AttributionRecord[]): string {
  const seen: string[] = [];
  for (const r of list) {
    if (r.adapted !== '' && seen.indexOf(r.adapted) < 0) { seen.push(r.adapted); }
  }
  return seen.join('；');
}

/** 首页年代卡的 AI 示意图声明文案——屏上已挂「示意图」角标，
 *  这里补的是"它不是考古照片"的成文说明。 */
export function aiStatement(list: AiIllustration[]): string {
  if (list.length === 0) { return ''; }
  return `首页年代块封面共 ${list.length} 张为 AI 生成示意图，非考古现场照片，仅用于视觉引导，不表示发掘实况。`;
}
