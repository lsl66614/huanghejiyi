// entry/src/ohosTest/ets/testability/TestRunner.ts —— ohosTest 标准测试执行器
// TestRunner 接口已核对本机 d.ts：onPrepare() + onRun()（onStop 可选）
import TestRunner from '@ohos.application.testRunner';
import { abilityDelegatorRegistry } from '@kit.TestKit';

let abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();

export default class UserTestRunner implements TestRunner {
  onPrepare(): void {
    console.info('[testTag] UserTestRunner onPrepare');
  }

  onRun(): void {
    console.info('[testTag] UserTestRunner onRun');
    abilityDelegator.run();
  }
}