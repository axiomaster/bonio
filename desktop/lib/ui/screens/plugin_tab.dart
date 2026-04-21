import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../plugins/plugin_manifest.dart';
import '../../plugins/plugin_registry.dart';
import '../../providers/app_state.dart';
import '../../services/reading_template_store.dart';

/// Plugin management page: view installed plugins, enable/disable, reorder.
class PluginTab extends StatefulWidget {
  const PluginTab({super.key});

  @override
  State<PluginTab> createState() => _PluginTabState();
}

class _PluginTabState extends State<PluginTab> {
  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final pm = appState.runtime.pluginManager;
    if (!pm.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final registry = pm.registry;
    final entries = registry.entries.toList()
      ..sort((a, b) => a.menuOrder.compareTo(b.menuOrder));

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = S.current;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.pluginManageTitle),
        titleSpacing: 16,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: s.pluginRefresh,
            onPressed: () async {
              await pm.reload();
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: entries.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.extension_outlined,
                      size: 64, color: cs.onSurface.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text(s.pluginEmptyHint,
                      style: theme.textTheme.bodyLarge?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            )
          : ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: entries.length,
              onReorder: (oldIndex, newIndex) async {
                if (newIndex > oldIndex) newIndex--;
                final ids = entries.map((e) => e.id).toList();
                final moved = ids.removeAt(oldIndex);
                ids.insert(newIndex, moved);
                await registry.reorder(ids);
                appState.runtime.pushPluginMenuToAvatar();
                if (mounted) setState(() {});
              },
              itemBuilder: (context, index) {
                final entry = entries[index];
                final manifest = registry.getManifest(entry.id);
                return _PluginCard(
                  key: ValueKey(entry.id),
                  entry: entry,
                  manifest: manifest,
                  onToggle: (enabled) async {
                    await registry.setEnabled(entry.id, enabled);
                    appState.runtime.pushPluginMenuToAvatar();
                    if (mounted) setState(() {});
                  },
                  onRemove: manifest?.type == PluginType.sidecar
                      ? () => _confirmRemove(entry.id, manifest!)
                      : null,
                  onSettings: entry.id == 'builtin_reading_companion'
                      ? () => _openTemplateSettings(context)
                      : null,
                );
              },
            ),
    );
  }

  void _confirmRemove(String pluginId, PluginManifest manifest) {
    final s = S.current;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.pluginRemoveTitle),
        content: Text(s.pluginRemoveConfirm(manifest.name.current)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.pluginCancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final pm = context.read<AppState>().runtime.pluginManager;
              await pm.uninstall(pluginId);
              if (mounted) setState(() {});
            },
            child: Text(s.pluginRemove),
          ),
        ],
      ),
    );
  }

  void _openTemplateSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _TemplateSettingsPage()),
    );
  }
}

class _PluginCard extends StatelessWidget {
  final PluginRegistryEntry entry;
  final PluginManifest? manifest;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onRemove;
  final VoidCallback? onSettings;

  const _PluginCard({
    super.key,
    required this.entry,
    this.manifest,
    required this.onToggle,
    this.onRemove,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = S.current;
    final m = manifest;

    final title = m?.name.current ?? entry.id;
    final desc = m?.description.current ?? '';
    final isBuiltin = m?.type == PluginType.builtin;
    final version = m?.version ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(
          _iconForPlugin(m),
          color: entry.enabled
              ? cs.primary
              : cs.onSurface.withValues(alpha: 0.3),
          size: 28,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (version.isNotEmpty)
              Text('v$version',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.4))),
            if (isBuiltin)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Chip(
                  label: Text(s.pluginBuiltinLabel,
                      style: const TextStyle(fontSize: 10)),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        subtitle: desc.isNotEmpty
            ? Text(desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: entry.enabled,
              onChanged: onToggle,
            ),
            if (onRemove != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onRemove,
                tooltip: s.pluginRemove,
              ),
            if (onSettings != null)
              IconButton(
                icon: const Icon(Icons.settings_outlined, size: 20),
                onPressed: onSettings,
                tooltip: s.pluginSettings,
              ),
            const Icon(Icons.drag_handle, size: 20),
          ],
        ),
      ),
    );
  }

  IconData _iconForPlugin(PluginManifest? m) {
    final iconName = m?.menu?.icon ?? '';
    switch (iconName) {
      case 'note_add':
        return Icons.note_add;
      case 'crop':
        return Icons.crop;
      case 'image_search':
        return Icons.image_search;
      case 'auto_stories':
        return Icons.auto_stories;
      default:
        return Icons.extension;
    }
  }
}

class _TemplateSettingsPage extends StatefulWidget {
  const _TemplateSettingsPage();

  @override
  State<_TemplateSettingsPage> createState() => _TemplateSettingsPageState();
}

class _TemplateSettingsPageState extends State<_TemplateSettingsPage> {
  Map<String, String> _templates = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final t = await ReadingTemplateStore.loadTemplates();
    if (!mounted) return;
    setState(() {
      _templates = t;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.current;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.pluginSettings),
        actions: [
          TextButton.icon(
            onPressed: _resetToDefaults,
            icon: const Icon(Icons.restore, size: 18),
            label: Text(s.pluginSettingsReset),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _templates.length,
              itemBuilder: (context, index) {
                final category = _templates.keys.elementAt(index);
                final template = _templates[category]!;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.label_outline, size: 18,
                                color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(category,
                                style: theme.textTheme.titleSmall),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          initialValue: template,
                          maxLines: 8,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            isDense: true,
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerLow,
                          ),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: theme.colorScheme.onSurface,
                          ),
                          onChanged: (v) {
                            _templates[category] = v;
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _save,
        tooltip: s.pluginSettings,
        child: const Icon(Icons.save),
      ),
    );
  }

  Future<void> _save() async {
    await ReadingTemplateStore.saveTemplates(_templates);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.current.pluginSettings)),
      );
    }
  }

  void _resetToDefaults() {
    final s = S.current;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.pluginSettingsReset),
        content: Text(s.pluginSettingsResetConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.pluginCancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ReadingTemplateStore.resetToDefaults();
              await _loadTemplates();
            },
            child: Text(s.pluginSettingsReset),
          ),
        ],
      ),
    );
  }
}
