/**
 * HealthMonitor — screen-time wellness nags.
 *
 * Port of hiclaw's health_monitor.cpp into ArkTS. Accumulates screen-on time,
 * detects late-night usage (23:00–06:00) and continuous overuse, then sends
 * escalating avatar.command sequences (gentle then strong nag) through the
 * provided callback so the avatar reacts without a hiclaw backend.
 */



import { AvatarStep, paramsOf, stepOf, sequencePayload } from './AvatarCommand';

export class HealthMonitor {
  private enabled: boolean = false;
  private screenOnAccumMs: number = 0;
  private lastStatusAtMs: number = Date.now();
  private lastNagAtMs: number = 0;
  private nagLevel: number = 0;

  private readonly lateNightStartHour = 23;
  private readonly lateNightEndHour = 6;
  private readonly maxContinuousUseMs = 2 * 60 * 60 * 1000; // 2h
  private readonly nagCooldownMs = 15 * 60 * 1000;          // 15 min

  private cb: (payloadJson: string) => void;

  constructor(cb: (payloadJson: string) => void) {
    this.cb = cb;
  }

  /** Feed device status (screen on/off + current hour). */
  onDeviceStatus(screenOn: boolean, hour: number, enabled: boolean): void {
    const now = Date.now();
    const delta = Math.max(0, now - this.lastStatusAtMs);
    this.lastStatusAtMs = now;

    if (screenOn) {
      this.screenOnAccumMs += delta;
    } else {
      this.screenOnAccumMs = 0;
    }

    this.enabled = enabled;
    if (!enabled) {
      this.nagLevel = 0;
      return;
    }

    const isLate = hour >= 0 && (hour >= this.lateNightStartHour || hour < this.lateNightEndHour);
    const continuousOveruse = isLate && this.screenOnAccumMs >= this.maxContinuousUseMs;
    if (!isLate && !continuousOveruse) {
      this.nagLevel = 0;
      return;
    }

    if (now - this.lastNagAtMs < this.nagCooldownMs) return;

    this.nagLevel++;
    this.lastNagAtMs = now;
    if (this.nagLevel <= 1) this.sendGentleNag();
    else this.sendStrongNag();
  }

  private sendGentleNag(): void {
    const steps: AvatarStep[] = [
      stepOf('setState', paramsOf(['state'], ['sleeping']), 0),
      stepOf('setBubble', paramsOf(['text'], ['主人，好晚了喵…']), 5000),
      stepOf('clearBubble', paramsOf([], []), 0),
    ];
    this.cb(sequencePayload(steps));
  }

  private sendStrongNag(): void {
    const steps: AvatarStep[] = [
      stepOf('moveTo', paramsOf(['x', 'y', 'mode'], [450, 1000, 'run']), 2000),
      stepOf('setState', paramsOf(['state'], ['angry']), 0),
      stepOf('setBubble', paramsOf(['text'], ['还不睡觉！Bonio的毛都要掉光了！快关掉手机睡觉喵！']), 0),
      stepOf('tts', paramsOf(['text'], ['还不睡觉！快关掉手机睡觉喵！']), 5000),
      stepOf('setState', paramsOf(['state'], ['confused']), 0),
      stepOf('setBubble', paramsOf(['text'], ['唤…']), 2000),
      stepOf('clearBubble', paramsOf([], []), 0),
      stepOf('moveTo', paramsOf(['x', 'y', 'mode'], [60, 1700, 'walk']), 3000),
      stepOf('setState', paramsOf(['state'], ['sleeping']), 0),
    ];
    this.cb(sequencePayload(steps));
  }
}
