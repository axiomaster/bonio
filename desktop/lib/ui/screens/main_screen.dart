import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_strings.dart';
import '../../providers/app_state.dart';
import 'chat_tab.dart';
import 'marketplace_tab.dart';
import 'memory_tab.dart';
import 'plugin_tab.dart';
import 'server_tab.dart';
import 'settings_tab.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isConnected = appState.runtime.isConnected;

    final destinations = [
      NavigationRailDestination(
        icon: Icon(Icons.chat_outlined),
        selectedIcon: Icon(Icons.chat),
        label: Text(S.current.tabChat),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.dns_outlined),
        selectedIcon: Icon(Icons.dns),
        label: Text(S.current.tabServer),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.collections_bookmark_outlined),
        selectedIcon: Icon(Icons.collections_bookmark),
        label: Text(S.current.tabMemory),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.store_outlined),
        selectedIcon: Icon(Icons.store),
        label: Text(S.current.tabMarket),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.extension_outlined),
        selectedIcon: Icon(Icons.extension),
        label: Text(S.current.marketPlugins),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text(S.current.tabSettings),
      ),
    ];

    return Scaffold(
      body: Row(
        children: [
          FocusTraversalGroup(
            child: NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.smart_toy,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      S.current.appNameShort,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _ConnectionIndicator(isConnected: isConnected),
                  ),
                ),
              ),
              destinations: destinations,
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: FocusTraversalGroup(
              child: IndexedStack(
                index: _selectedIndex,
                children: const [
                  ChatTab(),
                  ServerTab(),
                  MemoryTab(),
                  MarketplaceTab(),
                  PluginTab(),
                  SettingsTab(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionIndicator extends StatelessWidget {
  final bool isConnected;
  const _ConnectionIndicator({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isConnected ? Colors.green : Colors.grey,
        boxShadow: isConnected
            ? [
                BoxShadow(
                  color: Colors.green.withOpacity(0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}
