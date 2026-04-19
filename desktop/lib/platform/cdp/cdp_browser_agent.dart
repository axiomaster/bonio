import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../gui_agent.dart';
import 'cdp_client.dart';

/// [BrowserAgent] implementation using Chrome DevTools Protocol.
///
/// Can either launch a new Chrome/Edge instance with remote debugging enabled,
/// or connect to an already-running instance whose debug port is known.
class CdpBrowserAgent implements BrowserAgent {
  CdpClient? _client;
  Process? _browserProcess;
  int? _debugPort;

  @override
  bool get isConnected => _client?.isConnected ?? false;

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  @override
  Future<void> ensureConnected() async {
    if (isConnected) return;
    await _launchAndConnect();
  }

  @override
  Future<bool> tryConnectToExisting() async {
    if (isConnected) return true;

    // Strategy 1: Read DevToolsActivePort from default user data dir
    final userDataDir = _getDefaultUserDataDir();
    if (userDataDir != null) {
      final portFile = File(
          '$userDataDir${Platform.pathSeparator}DevToolsActivePort');
      try {
        if (await portFile.exists()) {
          final lines = await portFile.readAsLines();
          if (lines.isNotEmpty) {
            final port = int.tryParse(lines.first.trim());
            if (port != null) {
              try {
                await _connectToPort(port);
                debugPrint(
                    'CdpBrowserAgent: connected to existing browser on port $port');
                return true;
              } catch (_) {}
            }
          }
        }
      } catch (_) {}
    }

    // Strategy 2: Try common default port 9222
    try {
      final client = HttpClient();
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:9222/json/version'));
      final resp = await req.close();
      client.close();
      if (resp.statusCode == 200) {
        await _connectToPort(9222);
        debugPrint(
            'CdpBrowserAgent: connected to existing browser on port 9222');
        return true;
      }
    } catch (_) {}

    debugPrint('CdpBrowserAgent: no existing debugging-enabled browser found');
    return false;
  }

  /// Launch Chrome/Edge with `--remote-debugging-port` and connect via CDP.
  Future<void> _launchAndConnect() async {
    final exe = _findBrowserExecutable();
    if (exe == null) {
      throw StateError('No Chrome or Edge browser found');
    }

    final tempDir = await Directory.systemTemp.createTemp('boji_cdp_');
    final portFile = File('${tempDir.path}${Platform.pathSeparator}DevToolsActivePort');

    // Port 0 = OS picks a free port; Chrome writes the actual port to
    // DevToolsActivePort inside the user-data-dir.
    final userDataDir = _getDefaultUserDataDir();
    final args = [
      '--remote-debugging-port=0',
      if (userDataDir != null) '--user-data-dir=$userDataDir',
      '--no-first-run',
      '--no-default-browser-check',
      '--remote-allow-origins=*',
    ];

    debugPrint('CdpBrowserAgent: launching $exe');
    _browserProcess = await Process.start(exe, args);

    // Wait for Chrome to write the port file (or detect from existing profile)
    _debugPort = await _waitForDebugPort(userDataDir, portFile);
    if (_debugPort == null) {
      throw StateError('Could not determine Chrome debug port');
    }

    debugPrint('CdpBrowserAgent: debug port = $_debugPort');
    await _connectToPort(_debugPort!);
  }

  /// Connect to an already-running Chrome at the given port.
  Future<void> connectToRunning(int port) async {
    _debugPort = port;
    await _connectToPort(port);
  }

  Future<void> _connectToPort(int port) async {
    // GET /json to list targets
    final client = HttpClient();
    try {
      final req = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/json'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      final targets = (jsonDecode(body) as List)
          .cast<Map<String, dynamic>>();

      // Find a page target (prefer the first visible page)
      final page = targets.firstWhere(
        (t) => t['type'] == 'page',
        orElse: () => targets.first,
      );

      final wsUrl = page['webSocketDebuggerUrl'] as String?;
      if (wsUrl == null || wsUrl.isEmpty) {
        throw StateError('No WebSocket debugger URL for target');
      }

      _client = CdpClient();
      await _client!.connect(wsUrl);

      // Enable required domains
      await _client!.sendCommand('Page.enable');
      await _client!.sendCommand('Runtime.enable');
    } finally {
      client.close();
    }
  }

  Future<int?> _waitForDebugPort(
      String? userDataDir, File portFile) async {
    // Strategy 1: read DevToolsActivePort from the user-data-dir
    final searchDir = userDataDir ?? portFile.parent.path;
    final activePortFile =
        File('$searchDir${Platform.pathSeparator}DevToolsActivePort');

    for (var i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      try {
        if (await activePortFile.exists()) {
          final lines = await activePortFile.readAsLines();
          if (lines.isNotEmpty) {
            return int.tryParse(lines.first.trim());
          }
        }
      } catch (_) {}

      // Strategy 2: check if portFile was written (temp dir)
      try {
        if (await portFile.exists()) {
          final lines = await portFile.readAsLines();
          if (lines.isNotEmpty) {
            return int.tryParse(lines.first.trim());
          }
        }
      } catch (_) {}
    }

    // Strategy 3: try common default port
    try {
      final client = HttpClient();
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:9222/json/version'));
      final resp = await req.close();
      if (resp.statusCode == 200) {
        client.close();
        return 9222;
      }
      client.close();
    } catch (_) {}

    return null;
  }

  // ---------------------------------------------------------------------------
  // Browser executable discovery
  // ---------------------------------------------------------------------------

  static String? _findBrowserExecutable() {
    if (Platform.isWindows) {
      final candidates = [
        _expandEnv(r'%ProgramFiles%\Google\Chrome\Application\chrome.exe'),
        _expandEnv(r'%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe'),
        _expandEnv(r'%LocalAppData%\Google\Chrome\Application\chrome.exe'),
        _expandEnv(
            r'%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe'),
        _expandEnv(r'%ProgramFiles%\Microsoft\Edge\Application\msedge.exe'),
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) return path;
      }
    } else if (Platform.isMacOS) {
      const candidates = [
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
        '/Applications/Chromium.app/Contents/MacOS/Chromium',
      ];
      for (final path in candidates) {
        if (File(path).existsSync()) return path;
      }
    }
    return null;
  }

  static String? _getDefaultUserDataDir() {
    if (Platform.isWindows) {
      return _expandEnv(r'%LocalAppData%\Google\Chrome\User Data');
    } else if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '';
      return '$home/Library/Application Support/Google/Chrome';
    }
    return null;
  }

  static String _expandEnv(String path) {
    return path.replaceAllMapped(RegExp(r'%([^%]+)%'), (m) {
      return Platform.environment[m.group(1)!] ?? m.group(0)!;
    });
  }

  // ---------------------------------------------------------------------------
  // BrowserAgent interface
  // ---------------------------------------------------------------------------

  CdpClient get _cdp {
    final c = _client;
    if (c == null || !c.isConnected) {
      throw StateError('CDP not connected. Call ensureConnected() first.');
    }
    return c;
  }

  @override
  Future<String> getCurrentUrl() async {
    final result = await _cdp.sendCommand('Runtime.evaluate', {
      'expression': 'window.location.href',
      'returnByValue': true,
    });
    return _extractValue(result) as String? ?? '';
  }

  @override
  Future<String> getPageTitle() async {
    final result = await _cdp.sendCommand('Runtime.evaluate', {
      'expression': 'document.title',
      'returnByValue': true,
    });
    return _extractValue(result) as String? ?? '';
  }

  @override
  Future<PageContent> extractPageContent({int maxLength = 50000}) async {
    final js = '''
      (() => {
        const headings = [...document.querySelectorAll('h1,h2,h3,h4,h5,h6')].map(h => ({
          level: parseInt(h.tagName[1]),
          text: h.innerText.trim(),
          id: h.id || (h.closest('[id]') ? h.closest('[id]').id : '')
        })).filter(h => h.text.length > 0);

        const article = document.querySelector('article') ||
                        document.querySelector('[role="main"]') ||
                        document.querySelector('main') ||
                        document.querySelector('.post-content') ||
                        document.querySelector('.article-content') ||
                        document.querySelector('.entry-content') ||
                        document.body;
        const text = article ? article.innerText.substring(0, $maxLength) : '';
        const title = document.title || '';
        const url = window.location.href || '';
        return JSON.stringify({ headings, text, title, url });
      })()
    ''';

    final result = await _cdp.sendCommand('Runtime.evaluate', {
      'expression': js,
      'returnByValue': true,
    });

    final jsonStr = _extractValue(result) as String? ?? '{}';
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    final headingsList = data['headings'] as List<dynamic>? ?? [];
    return PageContent(
      title: data['title'] as String? ?? '',
      url: data['url'] as String? ?? '',
      text: data['text'] as String? ?? '',
      headings: headingsList
          .map((h) => HeadingInfo.fromJson(h as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  Future<List<HeadingInfo>> extractHeadings() async {
    final content = await extractPageContent(maxLength: 0);
    return content.headings;
  }

  @override
  Future<dynamic> executeScript(String js) async {
    final result = await _cdp.sendCommand('Runtime.evaluate', {
      'expression': js,
      'returnByValue': true,
      'awaitPromise': true,
    });
    return _extractValue(result);
  }

  @override
  Future<void> navigate(String url) async {
    await _cdp.sendCommand('Page.navigate', {'url': url});
    // Wait for load event
    final completer = Completer<void>();
    late StreamSubscription<CdpEvent> sub;
    sub = _cdp.events.listen((e) {
      if (e.method == 'Page.loadEventFired') {
        if (!completer.isCompleted) completer.complete();
        sub.cancel();
      }
    });
    await completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => sub.cancel(),
    );
  }

  @override
  Future<Uint8List?> takeScreenshot() async {
    final result = await _cdp.sendCommand('Page.captureScreenshot', {
      'format': 'png',
    });
    final data = result['data'] as String?;
    if (data == null || data.isEmpty) return null;
    return base64Decode(data);
  }

  @override
  Future<void> close() async {
    await _client?.disconnect();
    _client = null;
    _browserProcess?.kill();
    _browserProcess = null;
    _debugPort = null;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  dynamic _extractValue(Map<String, dynamic> result) {
    final r = result['result'] as Map<String, dynamic>?;
    if (r == null) return null;
    return r['value'];
  }
}
