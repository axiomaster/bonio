/**
 * HealthScheduler — periodic screen-status polling for the HealthMonitor.
 *
 * A minimal driver that feeds the on-device HealthMonitor with screen-on
 * state and the current hour on a fixed interval. Screen state is derived
 * from the app's foreground state as a pragmatic MVP proxy; a future
 * integration can wire the real display API (e.g. @ohos.display or a
 * screen-lock callback) without changing the HealthMonitor contract.
 */

import { FeatureManager } from './FeatureManager';
import { SecurePrefs } from '../common/SecurePrefs';

export class HealthScheduler {
  private timer: number = -1;
  private screenOn: boolean = true;

  private featureManager: FeatureManager;
  private prefs: SecurePrefs;
  private isForeground: () => boolean;

  constructor(
    featureManager: FeatureManager,
    prefs: SecurePrefs,
    isForeground: () => boolean,
  ) {
    this.featureManager = featureManager;
    this.prefs = prefs;
    this.isForeground = isForeground;
  }

  /** Start periodic health monitoring (every 30s). */
  start(): void {
    if (this.timer !== -1) return;
    this.timer = setInterval(() => {
      this.tick();
    }, 30000);
    // Feed immediately so late-night detection starts right away.
    this.tick();
  }

  stop(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  /** Called when app foreground/background changes. */
  setForeground(foreground: boolean): void {
    this.screenOn = foreground;
  }

  private tick(): void {
    const now = new Date();
    const hour = now.getHours();
    const enabled = this.prefs.getHealthNagEnabled();
    this.featureManager.feedDeviceStatus(this.screenOn, hour, enabled);
  }
}
