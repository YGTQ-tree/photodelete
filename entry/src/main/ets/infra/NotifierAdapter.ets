/**
 * 通知适配层（T05）。
 *
 * 设计要点：
 *  - 通知**只做提醒**，不承担正确性 —— 到期整理的正确性由惰性物化保证（AGENTS.md 硬约束 5）；
 *  - 点击通知直达待删除页：用 WantAgent 带 `page` 参数，EntryAbility 的白名单路由会接受它；
 *  - 基础通知**不需要申请权限**，但需要用户开启通知；被拒时 `requestEnableNotification` 返回
 *    1600004 且不再弹窗（API 26 调研结论），所以必须给兜底引导。
 */

import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'PhotoDeleteNotify';
const BUNDLE: string = 'com.dsh.photodelete';
/** 同一批到期只提醒一次：固定 id，重复 publish 会覆盖而不是叠加 */
const NOTIFY_ID: number = 1001;

export class NotifierAdapter {
  /** 发「有照片到期」通知，点击进待删除页。返回是否发出 */
  static async notifyPending(context: common.Context, count: number, bytesText: string): Promise<boolean> {
    try {
      const agentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: BUNDLE,
            abilityName: 'EntryAbility',
            parameters: { 'page': 'pages/TrashPage' } as Record<string, Object>
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: WantAgent = await wantAgent.getWantAgent(agentInfo);

      const content: notificationManager.NotificationContent = {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: '有照片等待清理',
          text: count.toString() + ' 张照片已到期' + (bytesText.length > 0 ? '（' + bytesText + '）' : '')
            + '，点开一键清理'
        }
      };
      const request: notificationManager.NotificationRequest = {
        id: NOTIFY_ID,
        content: content,
        wantAgent: agent
      };
      await notificationManager.publish(request);
      hilog.info(DOMAIN, TAG, 'published, count=%{public}d', count);
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'publish failed: %{public}s', e.message);
      return false;
    }
  }

  /** 系统层面是否允许通知 */
  static async isEnabled(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      return false;
    }
  }

  /**
   * 请求开启通知。**必须由 UI 触发**（需要 UIAbilityContext）。
   * 被拒时返回 false，调用方负责引导用户去设置页（1600004 后不会再弹窗）。
   */
  static async requestEnable(context: common.UIAbilityContext): Promise<boolean> {
    try {
      await notificationManager.requestEnableNotification(context);
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      hilog.warn(DOMAIN, TAG, 'requestEnableNotification failed: %{public}s', e.message);
      return false;
    }
  }
}
