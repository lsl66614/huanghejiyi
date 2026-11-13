// entry/src/ohosTest/ets/test/List.test.ets —— Hypium 测试套件聚合入口
import { describe } from '@ohos/hypium';
import mergeEngineTest from './MergeEngine.test';
import recommendTest from './Recommend.test';

export default function testsuite() {
  mergeEngineTest();
  recommendTest();
}