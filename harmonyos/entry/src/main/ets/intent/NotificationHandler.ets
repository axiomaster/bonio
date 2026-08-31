/**
 * NotificationHandler — important-notification avatar reactions.
 *
 * Port of hiclaw's notification_handler.cpp into ArkTS. Filters notifications
 * from important apps/categories (WeChat, SMS, DingTalk, calls, emails...) and
 * triggers an avatar.command sequence (watching + bubble) so the pet
 * reacts to what matters without a hiclaw backend.
 */

import { AvatarStep, paramsOf, stepOf, sequencePayload } from './AvatarCommand';

interface NotificationInfo {
  packageName?: string;
  category?: string;
  title?: string;
  text?: string;
}

const IMPORTANT_PACKAGES: string[] = [
  'com.tencent.mm',              // WeChat
  'com.tencent.mobileqq',        // QQ
  'com.huawei.message',          // Huawei SMS
  'com.android.mms',             // SMS (AOSP)
  'com.alibaba.android.rimet',   // DingTalk
  'com.eg.android.AlipayGphone', // Alipay
  'com.ss.android.lark',         // Feishu/Lark
];

const IMPORTANT_CATEGORIES: string[] = ['msg', 'call', 'alarm', 'email', 'social'];
const MESSAGING_SUBSTRINGS: string[] = ['sms', 'mms', 'messaging', 'message'];

export class NotificationHandler {
  private cb: (payloadJson: string) => void;

  constructor(cb: (payloadJson: string) => void) {
    this.cb = cb;
  }

  private isImportant(info: NotificationInfo): boolean {
    const pkg = info.packageName ?? '';
    const category = info.category ?? '';
    if (IMPORTANT_PACKAGES.includes(pkg)) return true;
    if (IMPORTANT_CATEGORIES.includes(category)) return true;
    const lower = pkg.toLowerCase();
    for (const sub of MESSAGING_SUBSTRINGS) {
      if (lower.includes(sub)) return true;
    }
    return false;
  }

  /** Handle a notifications.changed payload; returns true when it reacted. */
  onNotificationChanged(payloadJson: string): boolean {
    try {
      const payload = JSON.parse(payloadJson) as Record<string, Object>;
      if (payload.change === 'removed') return false;
      const info: NotificationInfo = {
        packageName: payload.packageName as string,
        category: payload.category as string,
        title: payload.title as string,
        text: payload.text as string,
      };
      if (!this.isImportant(info)) return false;

      let display = '';
      if (info.title && info.title.length > 0) {
        display = `${info.title}: ${info.text ?? ''}`.trim();
      } else if (info.text && info.text.length > 0) {
        display = info.text;
      } else {
        display = 'new notification';
      }
      if (display.length > 60) display = display.slice(0, 57) + '...';

      const steps: AvatarStep[] = [
        stepOf('setState', paramsOf(['state', 'temporary'], ['watching', true]), 0),
        stepOf('setBubble', paramsOf(['text'], [`💡 ${display}`]), 0),
      ];
      this.cb(sequencePayload(steps));
      return true;
    } catch {
      return false;
    }
  }
}
