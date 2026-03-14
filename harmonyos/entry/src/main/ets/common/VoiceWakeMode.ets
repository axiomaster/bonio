/**
 * Voice Wake mode enum matching Android's VoiceWakeMode.
 * - Off: Voice wake disabled
 * - Foreground: Active only when app is in foreground
 * - Always: Active even when app is in background
 */
export enum VoiceWakeMode {
  Off = 'off',
  Foreground = 'foreground',
  Always = 'always'
}

export function voiceWakeModeFromRaw(raw: string | undefined): VoiceWakeMode {
  const trimmed = (raw || '').trim().toLowerCase();
  if (trimmed === 'off') return VoiceWakeMode.Off;
  if (trimmed === 'always') return VoiceWakeMode.Always;
  return VoiceWakeMode.Foreground;
}
