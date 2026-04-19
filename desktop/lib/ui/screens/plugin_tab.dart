import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_strings.dart';
import '../../plugins/plugin_manifest.dart';
import '../../plugins/plugin_registry.dart';
import '../../providers/app_state.dart';

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
}

class _PluginCard extends StatelessWidget {
  final PluginRegistryEntry entry;
  final PluginManifest? manifest;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onRemove;

  const _PluginCard({
    super.key,
    required this.entry,
    this.manifest,
    required this.onToggle,
    this.onRemove,
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
