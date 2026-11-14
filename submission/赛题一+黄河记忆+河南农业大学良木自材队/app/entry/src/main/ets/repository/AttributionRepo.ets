// entry/src/main/ets/repository/AttributionRepo.ets
import { util } from '@kit.ArkTS';
import { AttributionData, parseAttribution } from '../service/content/Attribution';

const ATTRIBUTION_FILE = 'attribution.json';

export class AttributionRepo {
  private static cache: AttributionData | null = null;

  static async load(context: Context): Promise<AttributionData> {
    const cached = AttributionRepo.cache;
    if (cached !== null) { return cached; }
    const bytes: Uint8Array = await context.resourceManager.getRawFileContent(ATTRIBUTION_FILE);
    const data = parseAttribution(util.TextDecoder.create('utf-8').decodeToString(bytes));
    AttributionRepo.cache = data;
    return data;
  }
}
