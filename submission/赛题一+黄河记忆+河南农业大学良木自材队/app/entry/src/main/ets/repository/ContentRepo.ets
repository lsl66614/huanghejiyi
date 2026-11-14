// entry/src/main/ets/repository/ContentRepo.ets
import { util } from '@kit.ArkTS';
import { SiteInfo } from '../model/ContentModels';
import { parseAllReport } from '../service/content/ContentParse';

const SITE_DIR = 'sites';

// 一次语料装载的完整结果：成功条目 + 失败文件名 + 文件总数。
// 页面要区分「全空」和「坏了 1 份」，只返回 SiteInfo[] 是分不出来的。
export class ContentLoadResult {
  sites: SiteInfo[] = [];
  failed: string[] = [];
  total: number = 0;
}

export class ContentRepo {
  private static report: ContentLoadResult | null = null;

  // 兼容旧调用：只要条目。失败信息在 loadReport() 里。
  static async load(context: Context): Promise<SiteInfo[]> {
    const r = await ContentRepo.loadReport(context);
    return r.sites;
  }

  static async loadReport(context: Context): Promise<ContentLoadResult> {
    const cached = ContentRepo.report;
    if (cached !== null) { return cached; }
    const rm = context.resourceManager;
    const names: string[] = await rm.getRawFileList(SITE_DIR) as string[];
    const files: string[] = [];
    const raws: string[] = [];
    for (const n of names) {
      if (!n.endsWith('.json')) { continue; }
      // 单个文件读取失败也要留下名字，不能让整批 load 直接 reject。
      try {
        const bytes: Uint8Array = await rm.getRawFileContent(`${SITE_DIR}/${n}`);
        raws.push(util.TextDecoder.create('utf-8').decodeToString(bytes));
        files.push(n);
      } catch (e) {
        files.push(n);
        raws.push('');
      }
    }
    const parsed = parseAllReport(raws, files);
    const out = new ContentLoadResult();
    out.sites = parsed.sites;
    out.failed = parsed.failed;
    out.total = files.length;
    ContentRepo.report = out;
    return out;
  }

  // 重试入口：清缓存后重新读 rawfile。
  static invalidate(): void {
    ContentRepo.report = null;
  }
}
