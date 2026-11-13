// entry/src/main/ets/common/Labels.ets
export const ERA_ALIAS: Map<string, string> = new Map([
  ['yangshao', '彩陶'], ['longshan', '黑陶'], ['xiashang', '青铜'],
  ['zhou', '礼玉'], ['hantang', '釉陶'], ['song', '瓷青']
]);

const CITY_NAMES: Map<string, string> = new Map([
  ['sanmenxia', '三门峡'], ['luoyang', '洛阳'], ['zhengzhou', '郑州'],
  ['kaifeng', '开封'], ['puyang', '濮阳']
]);

const TYPE_NAMES: Map<string, string> = new Map([
  ['capital', '都城遗址'], ['burial', '墓葬群'], ['kiln', '窑址'], ['ancient_arch', '古建筑']
]);

export function cityName(city: string): string {
  const n = CITY_NAMES.get(city);
  return n !== undefined ? n : city;
}

export function typeName(t: string): string {
  const n = TYPE_NAMES.get(t);
  return n !== undefined ? n : t;
}
