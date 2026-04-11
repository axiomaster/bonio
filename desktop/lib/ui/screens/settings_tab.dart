import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../providers/app_state.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final camera = appState.cameraService;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.current.settingsTitle,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(S.current.settingsAbout,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SettingsRow(
                      label: S.current.settingsAppVersion,
                      value: '1.0.0',
                    ),
                    const SizedBox(height: 8),
                    _SettingsRow(
                      label: S.current.settingsPlatform,
                      value: Platform.operatingSystem,
                    ),
                    const SizedBox(height: 8),
                    _SettingsRow(
                      label: S.current.settingsOsVersion,
                      value: Platform.operatingSystemVersion,
                    ),
                    const SizedBox(height: 8),
                    _SettingsRow(
                      label: S.current.settingsGatewayProtocol,
                      value: 'v3',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.pets,
                            size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(S.current.settingsAvatar,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.current.settingsAvatarDesc,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurface.withOpacity(0.65),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(S.current.settingsShowFloating),
                      subtitle: Text(
                        S.current.settingsShowFloatingSub,
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: appState.showAvatarOverlay,
                      onChanged: (v) => appState.setShowAvatarOverlay(v),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(S.current.settingsSpeakReplies),
                      subtitle: Text(
                        S.current.settingsSpeakRepliesSub,
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: appState.speakAssistantReplies,
                      onChanged: (v) => appState.setSpeakAssistantReplies(v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.language, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(S.current.settingsLanguage,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.current.settingsLanguageSub,
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurface.withOpacity(0.65), height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<AppLocale>(
                      segments: AppLocale.values.map((l) => ButtonSegment(value: l, label: Text(l.label))).toList(),
                      selected: {appState.locale},
                      onSelectionChanged: (s) => appState.setLocale(s.first),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.keyboard,
                            size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(S.current.settingsKeyboard,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SettingsRow(
                      label: S.current.settingsSendMessage,
                      value: 'Enter',
                    ),
                    const SizedBox(height: 8),
                    _SettingsRow(
                      label: S.current.settingsNewLine,
                      value: 'Shift + Enter',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.build_outlined,
                            size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text(S.current.settingsCapabilities,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _CapabilityRow(
                      icon: Icons.chat,
                      label: S.current.capChat,
                      status: _CapabilityStatus.supported,
                    ),
                    const SizedBox(height: 8),
                    _CapabilityRow(
                      icon: Icons.pets,
                      label: S.current.capAvatar,
                      status: _CapabilityStatus.supported,
                    ),
                    const SizedBox(height: 8),
                    _CapabilityRow(
                      icon: Icons.settings,
                      label: S.current.capConfig,
                      status: _CapabilityStatus.supported,
                    ),
                    const SizedBox(height: 8),
                    _CapabilityRow(
                      icon: Icons.history,
                      label: S.current.capSession,
                      status: _CapabilityStatus.supported,
                    ),
                    const SizedBox(height: 8),
                    _CapabilityRow(
                      icon: Icons.vpn_key,
                      label: S.current.capDeviceAuth,
                      status: _CapabilityStatus.supported,
                    ),
                    const SizedBox(height: 8),
                    _CapabilityRow(
                      icon: Icons.devices,
                      label: S.current.capDeviceInfo,
                      status: _CapabilityStatus.supported,
                    ),
                    const SizedBox(height: 8),
                    _CapabilityRow(
                      icon: Icons.camera_alt,
                      label: camera.available
                          ? S.current.capCamera(camera.cameraCount)
                          : camera.initialized
                              ? S.current.capCameraNone
                              : S.current.capCameraDetecting,
                      status: camera.available
                          ? _CapabilityStatus.supported
                          : camera.initialized
                              ? _CapabilityStatus.unavailable
                              : _CapabilityStatus.detecting,
                      onRefresh: () => camera.refresh(),
                    ),
                    const SizedBox(height: 8),
                    _CapabilityRow(
                      icon: Icons.location_on,
                      label: S.current.capLocation,
                      status: _CapabilityStatus.unsupported,
                    ),
                    const SizedBox(height: 8),
                    _CapabilityRow(
                      icon: Icons.sms,
                      label: S.current.capSms,
                      status: _CapabilityStatus.unsupported,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;
  const _SettingsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 160,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

enum _CapabilityStatus { supported, unavailable, unsupported, detecting }

class _CapabilityRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final _CapabilityStatus status;
  final VoidCallback? onRefresh;

  const _CapabilityRow({
    required this.icon,
    required this.label,
    required this.status,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = status == _CapabilityStatus.supported;
    final isDetecting = status == _CapabilityStatus.detecting;

    return Row(
      children: [
        Icon(icon,
            size: 18,
            color: isActive
                ? colorScheme.primary
                : colorScheme.onSurface.withOpacity(0.3)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isActive
                  ? colorScheme.onSurface
                  : colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ),
        if (onRefresh != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.refresh, size: 14,
                    color: colorScheme.onSurface.withOpacity(0.4)),
              ),
            ),
          ),
        if (isDetecting)
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          )
        else
          Icon(
            isActive ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: isActive
                ? Colors.green
                : status == _CapabilityStatus.unavailable
                    ? Colors.orange.withOpacity(0.6)
                    : colorScheme.onSurface.withOpacity(0.2),
          ),
      ],
    );
  }
}
