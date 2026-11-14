/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, common, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { accessibility } from '@kit.AccessibilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, UIContext } from '@kit.ArkUI';
import { onReduceMotionChanged, syncReduceMotion } from '../common/Motion';
import { AutoSync } from '../service/sync/AutoSync';

const DOMAIN = 0x0000;

// 必须用具名函数：SDK 明确要求，匿名函数每次调用都是新对象，
// offAnimationReduceStateChange 取消不掉，会在 Ability 销毁后崩溃。
function onReduceChanged(reduced: boolean): void {
  onReduceMotionChanged(reduced);
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      // 锁定浅色：全站页面底色与文字色都是硬编码纸墨令牌（#F5F1E8 / #2B2622 等），
      // 未定义深色资源；跟随系统切深色会让文字压在变暗后的启动底色上消失。
      // 若日后要做深色版，须先补齐 resources/dark 下的色板，再改回 COLOR_MODE_NOT_SET。
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    // 读系统的「减弱动画」偏好。必须在首个页面的 aboutToAppear 之前完成，
    // 否则首屏动效会按未减弱播放一次。
    syncReduceMotion();
    try {
      accessibility.onAnimationReduceStateChange(onReduceChanged);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'watch reduce-motion fail. %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    try {
      accessibility.offAnimationReduceStateChange(onReduceChanged);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'unwatch reduce-motion fail. %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    try {
      const ctx: UIContext = windowStage.getMainWindowSync().getUIContext();
      hilog.info(DOMAIN, 'testTag', 'font registration moved to Index.aboutToAppear');
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'window ctx error. Cause: %{public}s', JSON.stringify(err));
    }

    // 网络恢复自动同步（赛题「恢复后自动同步」条款）：
    // 监听 netAvailable，掉线恢复后自动跑一次分布式合并。
    //
    // 首屏不再等数据库：loadContent 立刻执行，模式恢复放到后台。首页的
    // 骨架与语料（rawfile）本来就不依赖 RDB，没理由跟着迁移一起卡住。
    // 模式恢复仍需先于任何数据库读写——这道顺序由 BootGate 保证：
    // UserDataRepo.get() 会先等闸门，页面因此看不到「主库数据被仿真档案替换」的中间态。
    this.loadIndex(windowStage);
    const abilityCtx: common.UIAbilityContext = this.context as common.UIAbilityContext;
    const t0: number = Date.now();
    AutoSync.prepare(abilityCtx).then(() => {
      hilog.info(DOMAIN, 'testTag', 'AutoSync.prepare done in %{public}d ms', Date.now() - t0);
    }).catch((err: Object) => {
      hilog.error(DOMAIN, 'testTag', 'AutoSync.prepare failed. Cause: %{public}s', JSON.stringify(err));
    });
  }

  private loadIndex(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
    // 注销网络监听，避免 Ability 销毁后回调打到已释放的上下文
    AutoSync.stop();
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // 后台期间可能恢复过网络而没收到 netAvailable，回前台补一次。
    AutoSync.onForeground();
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
