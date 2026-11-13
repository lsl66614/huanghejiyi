// entry/src/main/ets/repository/RouteRepo.ets
//
// 路线表只有一份、几十 KB，读完即缓存。与 ContentRepo 分开的理由：
// 遗址语料会因为「42 份里坏了一份」而需要汇报失败清单，路线表则是
// 单文件、要么读得到要么读不到，两者的错误态不一样，混在一起反而
// 会让首页在路线缺失时误报「语料加载失败」。
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { RouteInfo } from '../model/ContentModels';
import { parseRoutes } from '../service/content/RouteParse';

const DOMAIN = 0x0001;
const TAG = 'RouteRepo';

const ROUTE_FILE = 'routes.json';

export class RouteRepo {
  private static cache: RouteInfo[] | null = null;

  static async load(context: Context): Promise<RouteInfo[]> {
    const c = RouteRepo.cache;
    if (c !== null) { return c; }
    let out: RouteInfo[] = [];
    try {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent(ROUTE_FILE);
      out = parseRoutes(util.TextDecoder.create('utf-8').decodeToString(bytes));
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'routes load fail: %{public}s', JSON.stringify(e));
      out = [];
    }
    RouteRepo.cache = out;
    return out;
  }

  static invalidate(): void {
    RouteRepo.cache = null;
  }
}
