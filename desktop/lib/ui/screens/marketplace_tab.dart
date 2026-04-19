import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../models/clawhub_models.dart';
import '../../providers/app_state.dart';
import '../../plugins/plugin_manifest.dart';
import '../../services/clawhub_client.dart';

class MarketplaceTab extends StatefulWidget {
  const MarketplaceTab({super.key});

  @override
  State<MarketplaceTab> createState() => _MarketplaceTabState();
}

class _MarketplaceTabState extends State<MarketplaceTab>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.dividerColor, width: 1),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor:
                theme.colorScheme.onSurface.withOpacity(0.6),
            indicatorColor: theme.colorScheme.primary,
            tabs: [
              Tab(text: S.current.marketPlugins),
              Tab(text: S.current.marketSkills),
              Tab(text: S.current.marketModels),
              Tab(text: S.current.marketThemes),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _PluginMarketContent(),
              _SkillMarketplaceContent(),
              _ProviderMarketContent(),
              _ThemeMarketContent(),
            ],
          ),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Skill Marketplace (ClawHub)
// ════════════════════════════════════════════════════════════════

class _SkillMarketplaceContent extends StatefulWidget {
  const _SkillMarketplaceContent();

  @override
  State<_SkillMarketplaceContent> createState() =>
      _SkillMarketplaceContentState();
}

class _SkillMarketplaceContentState extends State<_SkillMarketplaceContent> {
  final _searchController = TextEditingController();
  final _client = ClawHubClient();

  List<ClawHubSearchResult> _results = [];
  bool _loading = false;
  String? _error;
  ClawHubSkillDetail? _selectedDetail;
  String? _installProgress;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _client.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _client.search(query);
      if (mounted) setState(() => _results = results);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDetail(String slug) async {
    try {
      final detail = await _client.getSkillDetail(slug);
      if (mounted) setState(() => _selectedDetail = detail);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load detail: $e')),
        );
      }
    }
  }

  Future<void> _install(ClawHubSkillDetail detail) async {
    final appState = context.read<AppState>();
    if (!appState.runtime.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.current.marketNotConnected)),
      );
      return;
    }

    setState(() => _installProgress = 'downloading');
    try {
      final version = detail.latestVersion?.version ?? '';
      final content =
          await _client.downloadSkillContent(detail.skill.slug, version);

      if (!mounted) return;
      setState(() => _installProgress = 'installing');

      await appState.runtime.skillRepository.installSkill(
        detail.skill.slug,
        content,
      );

      if (mounted) {
        setState(() => _installProgress = 'success');
        appState.runtime.refreshSkills();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _installProgress = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Install failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: S.current.marketSearchHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _search('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            onSubmitted: (q) {
              if (q.trim().isNotEmpty) _search(q.trim());
            },
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!,
                  style: TextStyle(color: theme.colorScheme.error)),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty && _searchController.text.isEmpty
                  ? _buildEmptyState(theme)
                  : _results.isEmpty
                      ? Center(
                          child: Text(
                            S.current.marketNoSkills(_searchController.text),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.6),
                            ),
                          ),
                        )
                      : _buildResultsList(theme),
        ),
        if (_selectedDetail != null)
          _SkillDetailOverlay(
            detail: _selectedDetail!,
            installProgress: _installProgress,
            onInstall: () => _install(_selectedDetail!),
            onDismiss: () => setState(() {
              _selectedDetail = null;
              _installProgress = null;
            }),
          ),
      ],
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.store_outlined, size: 48,
              color: theme.colorScheme.onSurface.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text(S.current.marketTitle,
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            S.current.marketSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(ThemeData theme) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final r = _results[index];
        return _SkillCard(
          result: r,
          onTap: () => _loadDetail(r.slug),
        );
      },
    );
  }
}

class _SkillCard extends StatelessWidget {
  final ClawHubSearchResult result;
  final VoidCallback onTap;

  const _SkillCard({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.displayName.isNotEmpty
                    ? result.displayName
                    : result.slug,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (result.summary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  result.summary,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SkillDetailOverlay extends StatelessWidget {
  final ClawHubSkillDetail detail;
  final String? installProgress;
  final VoidCallback onInstall;
  final VoidCallback onDismiss;

  const _SkillDetailOverlay({
    required this.detail,
    required this.installProgress,
    required this.onInstall,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  detail.skill.displayName.isNotEmpty
                      ? detail.skill.displayName
                      : detail.skill.slug,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (detail.skill.summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              detail.skill.summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              _StatBadge(Icons.star_outline, '${detail.skill.stats.stars}'),
              const SizedBox(width: 16),
              _StatBadge(
                  Icons.download_outlined, _formatNumber(detail.skill.stats.downloads)),
              if (detail.latestVersion != null) ...[
                const SizedBox(width: 16),
                _StatBadge(Icons.new_releases_outlined,
                    'v${detail.latestVersion!.version}'),
              ],
            ],
          ),
          if (detail.owner.handle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.person_outline, size: 14,
                    color: theme.colorScheme.onSurface.withOpacity(0.5)),
                const SizedBox(width: 4),
                Text(
                  detail.owner.displayName.isNotEmpty
                      ? detail.owner.displayName
                      : detail.owner.handle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _buildActionRow(theme),
        ],
      ),
    );
  }

  Widget _buildActionRow(ThemeData theme) {
    switch (installProgress) {
      case 'downloading':
      case 'installing':
        return Row(
          children: [
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              installProgress == 'downloading'
                  ? S.current.marketDownloading
                  : S.current.marketInstalling,
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      case 'success':
        return Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(S.current.marketInstallSuccess,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.green.shade700)),
            const Spacer(),
            TextButton(onPressed: onDismiss, child: Text(S.current.done)),
          ],
        );
      default:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onDismiss, child: Text(S.current.cancel)),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onInstall,
              icon: const Icon(Icons.download, size: 18),
              label: Text(S.current.install),
            ),
          ],
        );
    }
  }

  static String _formatNumber(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final String text;
  const _StatBadge(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withOpacity(0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Model/Provider Marketplace
// ════════════════════════════════════════════════════════════════

class _ProviderMarketContent extends StatefulWidget {
  const _ProviderMarketContent();
  @override
  State<_ProviderMarketContent> createState() => _ProviderMarketContentState();
}

class _ProviderMarketContentState extends State<_ProviderMarketContent> {
  static const _url =
      'https://axiomaster.github.io/boji-market/releases/providers.json';

  List<Map<String, dynamic>> _providers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _fetchJson(_url);
      final list = (data['providers'] as List<dynamic>?) ?? [];
      if (mounted) {
        setState(() {
          _providers = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _MarketErrorView(
        icon: Icons.storage_outlined,
        error: _error!,
        onRetry: _fetch,
      );
    }
    if (_providers.isEmpty) {
      return Center(
        child: Text(S.current.marketModelPlaceholder,
            style: theme.textTheme.bodyMedium),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _providers.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final p = _providers[i];
          final id = p['id'] as String? ?? '';
          final name = p['name'] as String? ?? id;
          final baseUrl = p['base_url'] as String?;
          return Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              dense: true,
              leading: Icon(_providerIcon(id),
                  color: theme.colorScheme.primary, size: 24),
              title: Text(name, style: theme.textTheme.titleSmall),
              subtitle: baseUrl != null
                  ? Text(baseUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.5)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)
                  : null,
              trailing: Text(id,
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.4))),
            ),
          );
        },
      ),
    );
  }

  static IconData _providerIcon(String id) {
    switch (id) {
      case 'openai':
      case 'openai-codex':
        return Icons.auto_awesome;
      case 'anthropic':
        return Icons.psychology;
      case 'google':
        return Icons.diamond_outlined;
      case 'ollama':
      case 'vllm':
        return Icons.computer;
      case 'github-copilot':
        return Icons.code;
      case 'openrouter':
        return Icons.router;
      default:
        return Icons.cloud_outlined;
    }
  }
}

// ════════════════════════════════════════════════════════════════
//  Theme Marketplace
// ════════════════════════════════════════════════════════════════

class _ThemeMarketContent extends StatefulWidget {
  const _ThemeMarketContent();
  @override
  State<_ThemeMarketContent> createState() => _ThemeMarketContentState();
}

class _ThemeMarketContentState extends State<_ThemeMarketContent> {
  static const _url = 'https://axiomaster.github.io/boji-market/themes.json';

  List<Map<String, dynamic>> _themes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _fetchJson(_url);
      final list = (data['themes'] as List<dynamic>?) ?? [];
      if (mounted) {
        setState(() {
          _themes = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _MarketErrorView(
        icon: Icons.palette_outlined,
        error: _error!,
        onRetry: _fetch,
      );
    }
    if (_themes.isEmpty) {
      return Center(
        child: Text(S.current.marketThemePlaceholder,
            style: theme.textTheme.bodyMedium),
      );
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _themes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, i) {
          final t = _themes[i];
          final id = t['id'] as String? ?? '';
          final name = t['name'] as String? ?? id;
          final desc = t['description'] as String? ?? '';
          final downloadUrl = t['downloadUrl'] as String?;
          return Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            child: ListTile(
              dense: true,
              leading: Icon(Icons.palette_outlined,
                  color: theme.colorScheme.primary, size: 24),
              title: Text(name, style: theme.textTheme.titleSmall),
              subtitle: desc.isNotEmpty
                  ? Text(desc,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withOpacity(0.5)),
                      maxLines: 2, overflow: TextOverflow.ellipsis)
                  : null,
              trailing: downloadUrl != null && downloadUrl.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.download_outlined, size: 20),
                      tooltip: S.current.install,
                      onPressed: () => _openDownload(downloadUrl),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  Future<void> _openDownload(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri);
  }
}

// ════════════════════════════════════════════════════════════════
//  Shared helpers
// ════════════════════════════════════════════════════════════════

Future<Map<String, dynamic>> _fetchJson(String url) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close(force: false);
  }
}

class _MarketErrorView extends StatelessWidget {
  final IconData icon;
  final String error;
  final VoidCallback onRetry;
  const _MarketErrorView({
    required this.icon,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48,
              color: theme.colorScheme.onSurface.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text(error,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(S.current.chatRefresh),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Plugins marketplace
// =============================================================================

class _PluginMarketContent extends StatefulWidget {
  const _PluginMarketContent();

  @override
  State<_PluginMarketContent> createState() => _PluginMarketContentState();
}

class _PluginMarketContentState extends State<_PluginMarketContent> {
  List<Map<String, dynamic>>? _catalog;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchCatalog();
  }

  Future<void> _fetchCatalog() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = HttpClient();
      final req = await client.getUrl(
          Uri.parse('https://axiomaster.github.io/boji-market/plugins.json'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final plugins = (json['plugins'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      if (mounted) setState(() => _catalog = plugins);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final s = S.current;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48,
                color: cs.error.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _fetchCatalog,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(s.pluginRefresh),
            ),
          ],
        ),
      );
    }

    final plugins = _catalog;
    if (plugins == null || plugins.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.extension_outlined, size: 64,
                color: cs.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 16),
            Text(s.marketPluginsPlaceholder,
                style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.5))),
          ],
        ),
      );
    }

    final appState = context.watch<AppState>();
    final installed = appState.runtime.pluginManager.registry
        .entries.map((e) => e.id).toSet();

    return RefreshIndicator(
      onRefresh: _fetchCatalog,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: plugins.length,
        itemBuilder: (context, index) {
          final p = plugins[index];
          final id = p['id'] as String? ?? '';
          final name = I18nString.fromJson(p['name']).current;
          final desc = I18nString.fromJson(p['description']).current;
          final version = p['version'] as String? ?? '';
          final author = p['author'] as String? ?? '';
          final isInstalled = installed.contains(id);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.extension, size: 32),
              title: Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (version.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text('v$version',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurface.withValues(alpha: 0.4))),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (desc.isNotEmpty)
                    Text(desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.6))),
                  if (author.isNotEmpty)
                    Text(author,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.4),
                            fontSize: 11)),
                ],
              ),
              trailing: isInstalled
                  ? Chip(
                      label: Text(s.pluginInstalled,
                          style: const TextStyle(fontSize: 12)),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    )
                  : FilledButton.tonal(
                      onPressed: () => _installPlugin(p),
                      child: Text(s.pluginInstall),
                    ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _installPlugin(Map<String, dynamic> pluginData) async {
    final downloadUrls = pluginData['download_url'] as Map<String, dynamic>?;
    if (downloadUrls == null) return;

    final platform = Platform.isWindows ? 'windows' : 'macos';
    final url = downloadUrls[platform] as String?;
    if (url == null || url.isEmpty) return;

    final s = S.current;
    final messenger = ScaffoldMessenger.of(context);
    final appState = context.read<AppState>();

    messenger.showSnackBar(
      SnackBar(content: Text('${s.pluginInstall}...')),
    );

    try {
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      final tempDir = await Directory.systemTemp.createTemp('boji_plugin_');
      final zipFile = File('${tempDir.path}${Platform.pathSeparator}plugin.zip');
      final sink = zipFile.openWrite();
      await resp.pipe(sink);
      client.close();

      await appState.runtime.pluginManager.installFromZip(zipFile.path);

      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(s.pluginInstalled),
            backgroundColor: Colors.green.shade700,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Install failed: $e')),
        );
      }
    }
  }
}
