import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';

import testsuite from '../test/List.test';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhotoDeleteTest';

export default class TestAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'TestAbility onCreate');
    const abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
    const abilityDelegatorArguments = abilityDelegatorRegistry.getArguments();
    hilog.info(DOMAIN, TAG, '%{public}s', 'start run testcase');
    Hypium.hypiumTest(abilityDelegator, abilityDelegatorArguments, testsuite);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'TestAbility onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('testability/pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'loadContent succeeded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onBackground');
  }
}
