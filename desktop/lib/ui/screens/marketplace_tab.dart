import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/clawhub_models.dart';
import '../../providers/app_state.dart';
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
    _tabController = TabController(length: 3, vsync: this);
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
            tabs: const [
              Tab(text: 'Skills'),
              Tab(text: 'Models'),
              Tab(text: 'Themes'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _SkillMarketplaceContent(),
              _ModelProviderPlaceholder(),
              _ThemePlaceholder(),
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
        const SnackBar(content: Text('Not connected to server')),
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
              hintText: 'Search skills on ClawHub...',
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
                            'No skills found for "${_searchController.text}"',
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
          Text('ClawHub Marketplace',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Search for community skills to extend your agent',
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
                  ? 'Downloading...'
                  : 'Installing...',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
      case 'success':
        return Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text('Installed successfully!',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Colors.green.shade700)),
            const Spacer(),
            TextButton(onPressed: onDismiss, child: const Text('Done')),
          ],
        );
      default:
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: onDismiss, child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: onInstall,
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Install'),
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
//  Model/Provider Marketplace (placeholder)
// ════════════════════════════════════════════════════════════════

class _ModelProviderPlaceholder extends StatelessWidget {
  const _ModelProviderPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storage_outlined, size: 48,
              color: theme.colorScheme.onSurface.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text('Model & Provider Marketplace',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Browse and add OpenAI, Anthropic, and other providers.\nComing soon.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  Theme Marketplace (placeholder)
// ════════════════════════════════════════════════════════════════

class _ThemePlaceholder extends StatelessWidget {
  const _ThemePlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.palette_outlined, size: 48,
              color: theme.colorScheme.onSurface.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text('Theme Marketplace', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Browse themes from designers.\nReplace the cat avatar with custom styles.\nComing soon.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
