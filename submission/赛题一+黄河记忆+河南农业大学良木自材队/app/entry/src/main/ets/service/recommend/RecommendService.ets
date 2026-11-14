// entry/src/main/ets/service/recommend/RecommendService.ets —— 纯函数，禁 @kit
// 评分口径（设计方案 §4.5）：0.4·同年代 + 0.3·同类型 + 0.2·同城市 + 0.1·标签Jaccard + 行为加权(≤0.15)

export class RecoInput {
  id: string = '';
  era: string = '';
  siteType: string = '';
  city: string = '';
  tags: string[] = [];
}

export class RecoResult {
  id: string = '';
  score: number = 0;
  reasons: string[] = [];
}

function jaccard(a: string[], b: string[]): number {
  if (a.length === 0 || b.length === 0) { return 0; }
  let hit = 0;
  for (const t of a) {
    if (b.includes(t)) { hit++; }
  }
  const union: string[] = a.slice();
  for (const t of b) {
    if (!union.includes(t)) { union.push(t); }
  }
  return hit / union.length;
}

// history：近期行为条目（最多取 20 条，越近越在前），每个维度命中记 +0.05，上限 0.15
function behaviorBonus(cand: RecoInput, history: RecoInput[]): number {
  let hits = 0;
  const recent = history.slice(0, 20);
  for (const h of recent) {
    if (h.id === cand.id) { continue; }
    if (h.era === cand.era) { hits++; }
    if (h.siteType === cand.siteType) { hits++; }
    if (h.city === cand.city) { hits++; }
  }
  return Math.min(0.15, hits * 0.05);
}

export function recommend(src: RecoInput, candidates: RecoInput[],
  excludeIds: string[], history: RecoInput[], topN: number): RecoResult[] {
  const out: RecoResult[] = [];
  for (const c of candidates) {
    if (c.id === src.id || excludeIds.includes(c.id)) { continue; }
    const reasons: string[] = [];
    let score = 0;
    if (c.era === src.era) {
      score += 0.4;
      reasons.push('同年代');
    }
    if (c.siteType === src.siteType) {
      score += 0.3;
      reasons.push('同类型');
    }
    if (c.city === src.city) {
      score += 0.2;
      reasons.push('同城');
    }
    const j = jaccard(src.tags, c.tags);
    if (j > 0) {
      score += 0.1 * j;
      const shared: string[] = [];
      for (const t of src.tags) {
        if (c.tags.includes(t)) { shared.push(t); }
      }
      reasons.push(`共享标签 ${shared.join('、')}`);
    }
    const bonus = behaviorBonus(c, history);
    if (bonus > 0) {
      score += bonus;
      reasons.push(`近期行为加权 +${bonus.toFixed(2)}`);
    }
    // 零分候选不再进入结果：它和种子没有任何可解释的关联，
    // 排进列表只会让“理由”一栏空着，等于用数量冒充相关性。
    if (score <= 0) { continue; }
    const r = new RecoResult();
    r.id = c.id;
    r.score = Math.round(score * 1000) / 1000;
    r.reasons = reasons;
    out.push(r);
  }
  out.sort((x: RecoResult, y: RecoResult): number => {
    if (y.score !== x.score) { return y.score - x.score; }
    return x.id < y.id ? -1 : 1;
  });
  return out.slice(0, topN);
}

// 配额：同一类型 / 同一城市在最终列表里各自最多 cap 条。
// 先在分数序上按配额收，收不满 topN 再按分数序放宽补足——
// 语料只有 42 条，硬配额会把“洛阳 12 条”削成 5 条后补进一堆零相关项。
// 补的时候仍沿原分数序走，避免列表出现“低分排在高分前面”。
export function diversify(list: RecoResult[], candidates: RecoInput[],
  capType: number, capCity: number, topN: number): RecoResult[] {
  const byId: Map<string, RecoInput> = new Map();
  for (const c of candidates) { byId.set(c.id, c); }
  const kept: Set<string> = new Set();
  const typeCount: Map<string, number> = new Map();
  const cityCount: Map<string, number> = new Map();
  const out: RecoResult[] = [];
  for (const r of list) {
    if (out.length >= topN) { break; }
    const c = byId.get(r.id);
    if (c === undefined) { continue; }
    const t = typeCount.get(c.siteType);
    const ct = cityCount.get(c.city);
    const nt = t === undefined ? 0 : t;
    const nc = ct === undefined ? 0 : ct;
    if (nt >= capType || nc >= capCity) { continue; }
    out.push(r);
    kept.add(r.id);
    typeCount.set(c.siteType, nt + 1);
    cityCount.set(c.city, nc + 1);
  }
  if (out.length >= topN) { return out; }
  for (const r of list) {
    if (out.length >= topN) { break; }
    if (kept.has(r.id)) { continue; }
    out.push(r);
  }
  return out;
}
