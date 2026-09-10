import { hilog } from '@kit.PerformanceAnalysisKit';
import { batteryInfo } from '@kit.BasicServicesKit';
import { GatewaySession } from '../gateway/GatewaySession';

/**
 * ChargingTriggeredScheduler listens to battery charging status.
 * With modern fast charging (快充), users plug in for quick bursts of power.
 * Whenever charging is detected, the device has no power constraints,
 * so we immediately trigger background incremental memory summarization
 * and vectorization without waiting for nighttime.
 */
class IncrementalSyncParams {
  reason: string = '';
  soc: number = 0;
  timestamp: number = 0;
}

export class ChargingTriggeredScheduler {
  private static readonly DOMAIN = 0x3D00;
  private static readonly TAG = 'ChargingScheduler';

  private readonly session: GatewaySession;
  private readonly isConnected: () => boolean;
  private timerId: number = -1;
  private wasCharging: boolean = false;
  private lastTriggerTime: number = 0;
  private readonly CHECK_INTERVAL_MS = 30000; // 30s check
  private readonly MIN_TRIGGER_COOLDOWN_MS = 5 * 60 * 1000; // 5 min cooldown

  constructor(session: GatewaySession, isConnected: () => boolean) {
    this.session = session;
    this.isConnected = isConnected;
  }

  start(): void {
    this.stop();
    this.checkCharging();
    this.timerId = setInterval(() => {
      this.checkCharging();
    }, this.CHECK_INTERVAL_MS);
    hilog.info(ChargingTriggeredScheduler.DOMAIN, ChargingTriggeredScheduler.TAG, 'ChargingTriggeredScheduler started');
  }

  stop(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  private isCurrentlyCharging(): boolean {
    try {
      const status = batteryInfo.chargingStatus;
      return status === batteryInfo.BatteryChargeState.ENABLE ||
             status === batteryInfo.BatteryChargeState.FULL;
    } catch (e) {
      hilog.warn(ChargingTriggeredScheduler.DOMAIN, ChargingTriggeredScheduler.TAG,
        'failed to read battery status: %{public}s', e instanceof Error ? e.message : String(e));
      return false;
    }
  }

  private checkCharging(): void {
    const isCharging = this.isCurrentlyCharging();
    const now = Date.now();

    // Trigger on transition from not charging to charging, or if charging and cooldown expired
    const justPluggedIn = !this.wasCharging && isCharging;
    const cooldownExpired = (now - this.lastTriggerTime) > this.MIN_TRIGGER_COOLDOWN_MS;

    if (isCharging && (justPluggedIn || cooldownExpired)) {
      this.triggerIncrementalSync(justPluggedIn ? 'plugged_in' : 'periodic_charging');
    }

    this.wasCharging = isCharging;
  }

  private triggerIncrementalSync(reason: string): void {
    if (!this.isConnected()) {
      hilog.info(ChargingTriggeredScheduler.DOMAIN, ChargingTriggeredScheduler.TAG,
        'charging detected (%{public}s) but gateway not connected; skip', reason);
      return;
    }

    this.lastTriggerTime = Date.now();
    hilog.info(ChargingTriggeredScheduler.DOMAIN, ChargingTriggeredScheduler.TAG,
      'device charging detected (%{public}s, SOC=%{public}d%%); triggering incremental vectorization & digest',
      reason, batteryInfo.batterySOC);

    const params = new IncrementalSyncParams();
    params.reason = reason;
    params.soc = batteryInfo.batterySOC;
    params.timestamp = Date.now();

    this.session.request('memory.incremental_sync', params, 15000).then((res) => {
      hilog.info(ChargingTriggeredScheduler.DOMAIN, ChargingTriggeredScheduler.TAG,
        'incremental memory sync result: ok=%{public}s', String(res.ok));
    }).catch((err: Error) => {
      hilog.warn(ChargingTriggeredScheduler.DOMAIN, ChargingTriggeredScheduler.TAG,
        'incremental memory sync RPC failed: %{public}s', err.message);
    });
  }
}
