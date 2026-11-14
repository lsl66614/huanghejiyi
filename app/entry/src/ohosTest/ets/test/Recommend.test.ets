// entry/src/ohosTest/ets/test/Recommend.test.ets —— T8：RecommendService 纯函数用例
// 评分口径（设计方案 §4.5）：0.4·同年代 + 0.3·同类型 + 0.2·同城市 + 0.1·标签Jaccard + 行为加权(≤0.15)
import { describe, it, expect } from '@ohos/hypium';
import { recommend, RecoInput, RecoResult } from '../../main/ets/service/recommend/RecommendService';

function inp(id: string, era: string, siteType: string, city: string, tags: string[]): RecoInput {
  const x = new RecoInput();
  x.id = id;
  x.era = era;
  x.siteType = siteType;
  x.city = city;
  x.tags = tags;
  return x;
}

export default function recommendTest() {
  describe('RecommendService', () => {
    it('excludes_self_and_excluded_ids', 0, () => {
      const src = inp('site:1', 'han', 'city_site', 'luoyang', ['world']);
      const cands: RecoInput[] = [
        inp('site:1', 'han', 'city_site', 'luoyang', []),        // 自身 → 排除
        inp('site:2', 'han', 'city_site', 'luoyang', []),
        inp('site:3', 'han', 'city_site', 'luoyang', [])         // 已收藏 → 排除
      ];
      const out: RecoResult[] = recommend(src, cands, ['site:3'], [], 10);
      expect(out.length).assertEqual(1);
      expect(out[0].id).assertEqual('site:2');
    })

    it('full_dimension_hits_score_090', 0, () => {
      const src = inp('site:1', 'han', 'city_site', 'luoyang', []);
      const cands: RecoInput[] = [inp('site:2', 'han', 'city_site', 'luoyang', [])];
      const out: RecoResult[] = recommend(src, cands, [], [], 10);
      // 0.4 + 0.3 + 0.2 = 0.9（服务内部 round 到三位小数）
      expect(out[0].score).assertClose(0.9, 0.0001);
      expect(out[0].reasons.length).assertEqual(3);
    })

    it('tag_jaccard_partial_score', 0, () => {
      const src = inp('site:1', 'han', 'city_site', 'luoyang', ['a', 'b']);
      const cands: RecoInput[] = [inp('site:2', 'han', 'city_site', 'luoyang', ['b', 'c'])];
      const out: RecoResult[] = recommend(src, cands, [], [], 10);
      // Jaccard = 1/3 → 0.9 + 0.1·(1/3) = 0.933
      expect(out[0].score).assertClose(0.933, 0.001);
    })

    it('behavior_bonus_capped_at_015', 0, () => {
      const src = inp('site:1', 'han', 'city_site', 'luoyang', []);
      // 历史命中 4 个维度（超出 0.15 封顶）
      const history: RecoInput[] = [
        inp('site:9', 'han', 'city_site', 'luoyang', []),
        inp('site:8', 'han', 'city_site', 'luoyang', [])
      ];
      const cands: RecoInput[] = [inp('site:2', 'han', 'city_site', 'luoyang', [])];
      const out: RecoResult[] = recommend(src, cands, [], history, 10);
      // 0.9 + 0.15 = 1.05
      expect(out[0].score).assertClose(1.05, 0.0001);
    })

    it('topn_truncates_and_stable_sort_by_id', 0, () => {
      const src = inp('site:1', 'han', 'city_site', 'luoyang', []);
      const cands: RecoInput[] = [
        inp('site:5', 'han', 'city_site', 'luoyang', []),
        inp('site:4', 'han', 'city_site', 'luoyang', []),
        inp('site:3', 'han', 'city_site', 'luoyang', [])
      ];
      const out: RecoResult[] = recommend(src, cands, [], [], 2);
      expect(out.length).assertEqual(2);
      // 同分按 id 字典序升序
      expect(out[0].id).assertEqual('site:3');
      expect(out[1].id).assertEqual('site:4');
    })
  })
}