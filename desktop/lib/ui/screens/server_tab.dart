import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/gateway_profile.dart';
import '../../models/skill_models.dart';
import '../../providers/app_state.dart';
import 'model_config_screen.dart';

class ServerTab extends StatefulWidget {
  const ServerTab({super.key});

  @override
  State<ServerTab> createState() => _ServerTabState();
}

class _ServerTabState extends State<ServerTab> {
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _tokenController;
  bool _showModelConfig = false;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _hostController = TextEditingController(text: appState.host);
    _portController = TextEditingController(text: appState.port.toString());
    _tokenController = TextEditingController(text: appState.token);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showModelConfig) {
      return ModelConfigScreen(
        onBack: () => setState(() => _showModelConfig = false),
      );
    }

    final appState = context.watch<AppState>();
    final runtime = appState.runtime;
    final isConnected = runtime.isConnected;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),

            // Connection card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.link,
                            size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Gateway Connection',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: _StatusChip(
                              label: runtime.connectionStatus,
                              isConnected: isConnected,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Gateway',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<GatewayProfile>(
                      segments: const [
                        ButtonSegment<GatewayProfile>(
                          value: GatewayProfile.openclaw,
                          label: Text('OpenClaw'),
                          tooltip:
                              'OpenClaw-compatible gateway (default port 18789)',
                        ),
                        ButtonSegment<GatewayProfile>(
                          value: GatewayProfile.hiclaw,
                          label: Text('HiClaw'),
                          tooltip: 'HiClaw server (default port 10724)',
                        ),
                      ],
                      emptySelectionAllowed: false,
                      showSelectedIcon: false,
                      selected: {appState.gatewayProfile},
                      onSelectionChanged:
                          (Set<GatewayProfile> selection) async {
                        if (isConnected) return;
                        final app = context.read<AppState>();
                        await app.updateConnectionSettings(
                          gatewayProfile: selection.first,
                        );
                        if (!context.mounted) return;
                        setState(() {
                          _hostController.text = app.host;
                          _portController.text = app.port.toString();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      appState.gatewayProfile == GatewayProfile.openclaw
                          ? 'Uses OpenClaw v3 connect scopes and UI client mode; default 127.0.0.1:18789.'
                          : 'HiClaw server with OpenClaw-aligned protocol; default port 10724.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.65),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _hostController,
                            decoration:
                                const InputDecoration(labelText: 'Host'),
                            enabled: !isConnected,
                            onChanged: (v) => appState.updateConnectionSettings(
                                host: v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _portController,
                            decoration:
                                const InputDecoration(labelText: 'Port'),
                            enabled: !isConnected,
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final port = int.tryParse(v);
                              if (port != null) {
                                appState.updateConnectionSettings(port: port);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _tokenController,
                      decoration: const InputDecoration(
                        labelText: 'Token (optional)',
                      ),
                      obscureText: true,
                      enabled: !isConnected,
                      onChanged: (v) =>
                          appState.updateConnectionSettings(token: v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Switch(
                          value: appState.tls,
                          onChanged: isConnected
                              ? null
                              : (v) =>
                                  appState.updateConnectionSettings(tls: v),
                        ),
                        const SizedBox(width: 8),
                        Text('TLS', style: theme.textTheme.bodyMedium),
                        const Spacer(),
                        if (isConnected)
                          FilledButton.tonal(
                            onPressed: appState.disconnectFromGateway,
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  colorScheme.error.withOpacity(0.15),
                              foregroundColor: colorScheme.error,
                            ),
                            child: const Text('Disconnect'),
                          )
                        else
                          FilledButton(
                            onPressed: appState.host.trim().isEmpty
                                ? null
                                : appState.connectToGateway,
                            child: const Text('Connect'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Model config card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.model_training,
                            size: 20, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Text('Model Configuration',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (runtime.serverConfig != null) ...[
                      _InfoRow(
                        label: 'Default Model',
                        value: runtime.serverConfig!.defaultModel.isEmpty
                            ? '(not set)'
                            : runtime.serverConfig!.defaultModel,
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'Configured Models',
                        value:
                            '${runtime.serverConfig!.models.length} model(s)',
                      ),
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'Providers',
                        value:
                            '${runtime.serverConfig!.providers.length} provider(s)',
                      ),
                    ] else ...[
                      Text(
                        isConnected
                            ? 'Loading configuration...'
                            : 'Connect to view configuration',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonal(
                        onPressed: isConnected
                            ? () => setState(() => _showModelConfig = true)
                            : null,
                        child: const Text('Configure Models'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Skills card
            _SkillsSectionCard(
              isConnected: isConnected,
            ),
            const SizedBox(height: 16),

            // Server info card
            if (isConnected && runtime.serverName != null)
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
                          Text('Server Info',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _InfoRow(
                          label: 'Server',
                          value: runtime.serverName ?? 'Unknown'),
                      const SizedBox(height: 8),
                      _InfoRow(
                          label: 'Address',
                          value: runtime.remoteAddress ?? 'Unknown'),
                      const SizedBox(height: 8),
                      _InfoRow(
                        label: 'Node Session',
                        value:
                            runtime.nodeConnected ? 'Connected' : 'Offline',
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

class _StatusChip extends StatelessWidget {
  final String label;
  final bool isConnected;
  const _StatusChip({required this.label, required this.isConnected});

  @override
  Widget build(BuildContext context) {
    final color = isConnected ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 140,
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

// ════════════════════════════════════════════════════════════════
//  Skills Section Card (installed skill management)
// ════════════════════════════════════════════════════════════════

class _SkillsSectionCard extends StatefulWidget {
  final bool isConnected;
  const _SkillsSectionCard({required this.isConnected});

  @override
  State<_SkillsSectionCard> createState() => _SkillsSectionCardState();
}

class _SkillsSectionCardState extends State<_SkillsSectionCard> {
  bool _expanded = false;
  bool _builtinExpanded = true;
  bool _customExpanded = true;

  @override
  void didUpdateWidget(covariant _SkillsSectionCard old) {
    super.didUpdateWidget(old);
    if (widget.isConnected && !old.isConnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AppState>().runtime.refreshSkills();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final runtime = appState.runtime;
    final skills = runtime.skills;
    final skillsLoading = runtime.skillsLoading;
    final skillsError = runtime.skillsError;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.extension, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Skills',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Text('${skills.length} total',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.5))),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() => _expanded = !_expanded);
                    if (_expanded && widget.isConnected) {
                      runtime.refreshSkills();
                    }
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: widget.isConnected && !skillsLoading
                        ? () => runtime.refreshSkills()
                        : null,
                    tooltip: 'Refresh',
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.add, size: 20),
                    onPressed: widget.isConnected
                        ? () => _showInstallDialog(context)
                        : null,
                    tooltip: 'Install Skill',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (skillsError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(skillsError,
                        style: TextStyle(
                            color: colorScheme.error, fontSize: 13)),
                  ),
                ),
              if (!widget.isConnected)
                Text('Not connected to server',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.5)))
              else if (skillsLoading && skills.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (skills.isEmpty)
                Text('No skills found',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.5)))
              else
                _buildSkillsList(context, skills, runtime),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSkillsList(
      BuildContext context, List<SkillInfo> skills, dynamic runtime) {
    final builtins = skills.where((s) => s.builtin).toList();
    final custom = skills.where((s) => !s.builtin).toList();
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (builtins.isNotEmpty) ...[
          _CollapsibleHeader(
            title: 'Built-in',
            count: builtins.length,
            expanded: _builtinExpanded,
            onToggle: () =>
                setState(() => _builtinExpanded = !_builtinExpanded),
          ),
          if (_builtinExpanded)
            ...builtins.map((s) => _SkillTile(
                  skill: s,
                  onToggle: () => runtime.toggleSkill(s.id, !s.enabled),
                  onRemove: null,
                )),
        ],
        if (custom.isNotEmpty) ...[
          _CollapsibleHeader(
            title: 'Installed',
            count: custom.length,
            expanded: _customExpanded,
            onToggle: () =>
                setState(() => _customExpanded = !_customExpanded),
          ),
          if (_customExpanded)
            ...custom.map((s) => _SkillTile(
                  skill: s,
                  onToggle: () => runtime.toggleSkill(s.id, !s.enabled),
                  onRemove: () => _confirmRemove(context, s, runtime),
                )),
        ],
      ],
    );
  }

  void _confirmRemove(
      BuildContext context, SkillInfo skill, dynamic runtime) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Skill'),
        content: Text(
            'Remove "${skill.name.isNotEmpty ? skill.name : skill.id}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              runtime.removeSkill(skill.id);
            },
            child:
                Text('Remove', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _showInstallDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _InstallSkillDialog(
        onInstall: (id, content) {
          context.read<AppState>().runtime.installSkill(id, content);
        },
      ),
    );
  }
}

class _CollapsibleHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  const _CollapsibleHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(title,
                style: theme.textTheme.labelMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            ),
            const Spacer(),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              size: 20,
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  final SkillInfo skill;
  final VoidCallback onToggle;
  final VoidCallback? onRemove;

  const _SkillTile({
    required this.skill,
    required this.onToggle,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.extension,
                size: 20,
                color: skill.enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withOpacity(0.3)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    skill.name.isNotEmpty ? skill.name : skill.id,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (skill.description.isNotEmpty)
                    Text(
                      skill.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.6)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18,
                    color: theme.colorScheme.error.withOpacity(0.7)),
                onPressed: onRemove,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove',
              ),
            Switch(
              value: skill.enabled,
              onChanged: (_) => onToggle(),
            ),
          ],
        ),
      ),
    );
  }
}

class _InstallSkillDialog extends StatefulWidget {
  final void Function(String id, String content) onInstall;
  const _InstallSkillDialog({required this.onInstall});

  @override
  State<_InstallSkillDialog> createState() => _InstallSkillDialogState();
}

class _InstallSkillDialogState extends State<_InstallSkillDialog> {
  final _idController = TextEditingController();
  final _contentController = TextEditingController();

  @override
  void dispose() {
    _idController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Install Skill'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _idController,
              decoration: const InputDecoration(labelText: 'Skill ID'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              decoration:
                  const InputDecoration(labelText: 'SKILL.md Content'),
              minLines: 4,
              maxLines: 8,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _idController.text.trim().isNotEmpty &&
                  _contentController.text.trim().isNotEmpty
              ? () {
                  widget.onInstall(
                    _idController.text.trim(),
                    _contentController.text.trim(),
                  );
                  Navigator.of(context).pop();
                }
              : null,
          child: const Text('Install'),
        ),
      ],
    );
  }
}
