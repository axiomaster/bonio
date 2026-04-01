import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
                        Text('Gateway Connection',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        _StatusChip(
                          label: runtime.connectionStatus,
                          isConnected: isConnected,
                        ),
                      ],
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
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
