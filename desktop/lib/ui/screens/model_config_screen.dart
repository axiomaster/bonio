import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../models/server_config.dart';
import '../../providers/app_state.dart';

class ModelConfigScreen extends StatefulWidget {
  final VoidCallback onBack;
  const ModelConfigScreen({super.key, required this.onBack});

  @override
  State<ModelConfigScreen> createState() => _ModelConfigScreenState();
}

class _ModelConfigScreenState extends State<ModelConfigScreen> {
  List<ModelConfig> _models = [];
  String _defaultModel = '';
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final config = context.read<AppState>().runtime.serverConfig;
    if (config != null) {
      _models = List.from(config.models);
      _defaultModel = config.defaultModel;
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final runtime = context.read<AppState>().runtime;
    await runtime.updateServerConfig(
      defaultModel: _defaultModel,
      models: _models,
    );
    setState(() {
      _saving = false;
      _dirty = false;
    });
  }

  void _addModel() {
    setState(() {
      _models = [
        ..._models,
        const ModelConfig(id: '', provider: ''),
      ];
      _dirty = true;
    });
  }

  void _removeModel(int index) {
    setState(() {
      _models = List.from(_models)..removeAt(index);
      _dirty = true;
    });
  }

  void _updateModel(int index, ModelConfig updated) {
    setState(() {
      _models = List.from(_models)..[index] = updated;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final config = appState.runtime.serverConfig;
    final providers = config?.providers ?? [];
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 8),
              Text(S.current.modelConfigTitle,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_dirty)
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(S.current.modelSave),
                ),
            ],
          ),
          const SizedBox(height: 20),

          // Default model
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Text(S.current.modelDefaultModel,
                      style: theme.textTheme.titleSmall),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _models.any((m) => m.id == _defaultModel)
                          ? _defaultModel
                          : null,
                      items: _models
                          .where((m) => m.id.isNotEmpty)
                          .map((m) => DropdownMenuItem(
                                value: m.id,
                                child: Text(m.id),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _defaultModel = v;
                            _dirty = true;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        hintText: S.current.modelSelectDefault,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Model list
          Row(
            children: [
              Text(S.current.modelModels, style: theme.textTheme.titleMedium),
              const Spacer(),
              FilledButton.tonal(
                onPressed: _addModel,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add, size: 18),
                    const SizedBox(width: 4),
                    Text(S.current.modelAddModel),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _models.isEmpty
                ? Center(
                    child: Text(
                      S.current.modelNoModels,
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _models.length,
                    itemBuilder: (context, index) {
                      return _ModelEditor(
                        model: _models[index],
                        providers: providers,
                        onChanged: (m) => _updateModel(index, m),
                        onRemove: () => _removeModel(index),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ModelEditor extends StatelessWidget {
  final ModelConfig model;
  final List<ProviderInfo> providers;
  final ValueChanged<ModelConfig> onChanged;
  final VoidCallback onRemove;

  const _ModelEditor({
    required this.model,
    required this.providers,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: model.id,
                    decoration: const InputDecoration(labelText: 'Model ID'),
                    onChanged: (v) => onChanged(model.copyWith(id: v)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: providers.isNotEmpty
                      ? DropdownButtonFormField<String>(
                          value: providers.any((p) => p.id == model.provider)
                              ? model.provider
                              : null,
                          items: providers
                              .map((p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(p.displayName),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              onChanged(model.copyWith(provider: v));
                            }
                          },
                          decoration:
                              const InputDecoration(labelText: 'Provider'),
                        )
                      : TextFormField(
                          initialValue: model.provider,
                          decoration:
                              const InputDecoration(labelText: 'Provider'),
                          onChanged: (v) =>
                              onChanged(model.copyWith(provider: v)),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: colorScheme.error, size: 20),
                  onPressed: onRemove,
                  tooltip: S.current.modelRemove,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: model.baseUrl ?? '',
                    decoration: const InputDecoration(
                        labelText: 'Base URL (optional)'),
                    onChanged: (v) => onChanged(
                        model.copyWith(baseUrl: v.isEmpty ? null : v)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: model.modelId ?? '',
                    decoration: const InputDecoration(
                        labelText: 'Model ID Override (optional)'),
                    onChanged: (v) => onChanged(
                        model.copyWith(modelId: v.isEmpty ? null : v)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: model.apiKey ?? '',
              decoration:
                  const InputDecoration(labelText: 'API Key (optional)'),
              obscureText: true,
              onChanged: (v) =>
                  onChanged(model.copyWith(apiKey: v.isEmpty ? null : v)),
            ),
          ],
        ),
      ),
    );
  }
}
