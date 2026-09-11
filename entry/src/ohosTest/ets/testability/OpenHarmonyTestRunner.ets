/**
 * hypium 的测试运行器（`hdc shell aa test` 通过它驱动用例）。
 *
 * 为什么不走 `hvigorw onDeviceTest`：那条路要求 hvigor 自己完成签名
 * （否则报 00507001，且无 signingConfig 时它会把我们手工放入的已签名包清掉）。
 * 与其把密钥库口令写进 build-profile.json5（违反本项目「口令不进文件」的纪律），
 * 不如手工装已签名测试包 + `aa test` 直接驱动 —— 效果相同，且不引入口令泄露面。
 */

import { abilityDelegatorRegistry } from '@kit.TestKit';
import { Hypium } from '@ohos/hypium';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TestRunner } from '@ohos.application.testRunner';

import testsuite from '../test/List.test';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhotoDeleteTest';

export default class OpenHarmonyTestRunner implements TestRunner {
  onPrepare(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'OpenHarmonyTestRunner onPrepare');
  }

  onRun(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'OpenHarmonyTestRunner onRun');
    const delegator = abilityDelegatorRegistry.getAbilityDelegator();
    const args = abilityDelegatorRegistry.getArguments();
    Hypium.hypiumTest(delegator, args, testsuite);
    hilog.info(DOMAIN, TAG, '%{public}s', 'OpenHarmonyTestRunner dispatched');
  }
}
