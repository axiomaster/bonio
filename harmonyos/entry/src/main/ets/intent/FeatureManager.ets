/**
 * FeatureManager — on-device feature coordination (phase 4).
 *
 * Owns the local feature set that previously lived in hiclaw:
 *   - IntentRouter: classify STT transcripts (Chat / ScreenCapture / Summarize)
 *   - HealthMonitor: screen-time + late-night wellness nags
 *   - NotificationHandler: important-notification avatar reactions
 *
 * Avatar reactions flow through sendAvatarCommand() into the same
 * avatar.command channel the bridge/chat layer uses.
 */

import { IntentRouter, Intent } from './IntentRouter';
import { HealthMonitor } from './HealthMonitor';
import { NotificationHandler } from './NotificationHandler';

export class FeatureManager {
  readonly intentRouter: IntentRouter = new IntentRouter();
  readonly healthMonitor: HealthMonitor;
  readonly notificationHandler: NotificationHandler;

  /** Called by the avatar layer to execute an avatar.command payload. */
  onAvatarCommand: ((payloadJson: string) => void) | undefined = undefined;

  /** Called with a chat transcript when intent is Chat (falls through). */
  onChatRequest: ((text: string) => void) | undefined = undefined;

  /** Called when a ScreenCapture or Summarize intent fires. */
  onNonChatIntent: ((intent: Intent, text: string) => void) | undefined = undefined;

  constructor() {
    const sendAvatar = (payloadJson: string) => {
      if (this.onAvatarCommand) this.onAvatarCommand(payloadJson);
    };
    this.healthMonitor = new HealthMonitor(sendAvatar);
    this.notificationHandler = new NotificationHandler(sendAvatar);
  }

  /** Route a final STT transcript to the right feature. Returns the intent. */
  classifyAndRoute(text: string): Intent {
    const intent = this.intentRouter.classify(text);
    if (intent === Intent.Chat) {
      if (this.onChatRequest) this.onChatRequest(text);
    } else {
      if (this.onNonChatIntent) this.onNonChatIntent(intent, text);
    }
    return intent;
  }

  /** Feed periodic device status (screen on/off + hour) for health nags. */
  feedDeviceStatus(screenOn: boolean, hour: number, enabled: boolean): void {
    this.healthMonitor.onDeviceStatus(screenOn, hour, enabled);
  }

  /** Feed a notifications.changed payload; returns true if reacted. */
  feedNotification(payloadJson: string): boolean {
    return this.notificationHandler.onNotificationChanged(payloadJson);
  }
}
