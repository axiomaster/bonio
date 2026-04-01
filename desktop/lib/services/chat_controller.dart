import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/chat_models.dart';
import 'gateway_session.dart';

class ChatController extends ChangeNotifier {
  final GatewaySession session;
  static const _uuid = Uuid();

  String _sessionKey = 'main';
  String? _sessionId;
  List<ChatMessage> _messages = [];
  String? _errorText;
  bool _healthOk = false;
  String _thinkingLevel = 'off';
  int _pendingRunCount = 0;
  String? _streamingAssistantText;
  List<ChatPendingToolCall> _pendingToolCalls = [];
  List<ChatSessionEntry> _sessions = [];

  final Set<String> _pendingRuns = {};
  final Map<String, Timer> _pendingRunTimeouts = {};
  final Map<String, ChatPendingToolCall> _pendingToolCallsById = {};
  static const _pendingRunTimeoutMs = 120000;
  int? _lastHealthPollAtMs;

  String get sessionKey => _sessionKey;
  String? get sessionId => _sessionId;
  List<ChatMessage> get messages => _messages;
  String? get errorText => _errorText;
  bool get healthOk => _healthOk;
  String get thinkingLevel => _thinkingLevel;
  int get pendingRunCount => _pendingRunCount;
  String? get streamingAssistantText => _streamingAssistantText;
  List<ChatPendingToolCall> get pendingToolCalls => _pendingToolCalls;
  List<ChatSessionEntry> get sessions => _sessions;
  bool get isStreaming => _pendingRunCount > 0;

  ChatController({required this.session});

  void onDisconnected(String message) {
    _healthOk = false;
    _errorText = null;
    _clearPendingRuns();
    _pendingToolCallsById.clear();
    _pendingToolCalls = [];
    _streamingAssistantText = null;
    _sessionId = null;
    notifyListeners();
  }

  Future<void> load(String sessionKey) async {
    final key = sessionKey.trim().isEmpty ? 'main' : sessionKey.trim();
    _sessionKey = key;
    notifyListeners();
    await _bootstrap(forceHealth: true);
  }

  void applyMainSessionKey(String mainSessionKey) {
    final trimmed = mainSessionKey.trim();
    if (trimmed.isEmpty || _sessionKey == trimmed) return;
    if (_sessionKey != 'main') return;
    _sessionKey = trimmed;
    notifyListeners();
    _bootstrap(forceHealth: true);
  }

  Future<void> refresh() => _bootstrap(forceHealth: true);

  void setThinkingLevel(String level) {
    final normalized = _normalizeThinking(level);
    if (normalized == _thinkingLevel) return;
    _thinkingLevel = normalized;
    notifyListeners();
  }

  Future<void> switchSession(String sessionKey) async {
    final key = sessionKey.trim();
    if (key.isEmpty || key == _sessionKey) return;
    _sessionKey = key;
    notifyListeners();
    await _bootstrap(forceHealth: true);
  }

  Future<void> sendMessage(String message,
      {List<OutgoingAttachment> attachments = const []}) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    if (!_healthOk) {
      _errorText = 'Gateway health not OK; cannot send';
      notifyListeners();
      return;
    }

    final runId = _uuid.v4();
    final text =
        trimmed.isEmpty && attachments.isNotEmpty ? 'See attached.' : trimmed;

    final userContent = <ChatMessageContent>[
      ChatMessageContent(type: 'text', text: text),
      ...attachments.map((a) => ChatMessageContent(
            type: a.type,
            mimeType: a.mimeType,
            fileName: a.fileName,
            base64: a.base64,
            durationMs: a.durationMs,
          )),
    ];

    _messages = [
      ..._messages,
      ChatMessage(
        id: _uuid.v4(),
        role: 'user',
        content: userContent,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];

    _armPendingRunTimeout(runId);
    _pendingRuns.add(runId);
    _pendingRunCount = _pendingRuns.length;
    _errorText = null;
    _streamingAssistantText = null;
    _pendingToolCallsById.clear();
    _pendingToolCalls = [];
    notifyListeners();

    try {
      final params = <String, dynamic>{
        'sessionKey': _sessionKey,
        'message': text,
        'thinking': _thinkingLevel,
        'timeoutMs': 30000,
        'idempotencyKey': runId,
      };
      if (attachments.isNotEmpty) {
        params['attachments'] = attachments
            .map((a) => {
                  'type': a.type,
                  'mimeType': a.mimeType,
                  'fileName': a.fileName,
                  'content': a.base64,
                  if (a.durationMs != null) 'durationMs': a.durationMs,
                })
            .toList();
      }

      final res = await session.request('chat.send', jsonEncode(params));
      final resObj = _tryParseJson(res);
      final actualRunId = resObj?['runId'] as String?;

      if (actualRunId != null) {
        if (actualRunId != runId) {
          _clearPendingRun(runId);
          _armPendingRunTimeout(actualRunId);
          _pendingRuns.add(actualRunId);
          _pendingRunCount = _pendingRuns.length;
          notifyListeners();
        }
      } else {
        final content =
            resObj?['content'] as String? ?? resObj?['text'] as String?;
        if (content != null) {
          _messages = [
            ..._messages,
            ChatMessage(
              id: _uuid.v4(),
              role: 'assistant',
              content: [ChatMessageContent(type: 'text', text: content)],
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ];
        }
        _clearPendingRun(runId);
        notifyListeners();
      }
    } catch (err) {
      _clearPendingRun(runId);
      _errorText = err.toString();
      notifyListeners();
    }
  }

  Future<void> abort() async {
    final runIds = _pendingRuns.toList();
    if (runIds.isEmpty) return;
    for (final runId in runIds) {
      try {
        final params = jsonEncode({
          'sessionKey': _sessionKey,
          'runId': runId,
        });
        await session.request('chat.abort', params);
      } catch (_) {}
    }
  }

  void handleGatewayEvent(String event, String? payloadJson) {
    switch (event) {
      case 'tick':
        _pollHealthIfNeeded(force: false);
        break;
      case 'health':
        _healthOk = true;
        notifyListeners();
        break;
      case 'seqGap':
        _errorText = 'Event stream interrupted; try refreshing.';
        _clearPendingRuns();
        notifyListeners();
        break;
      case 'chat':
        if (payloadJson != null) _handleChatEvent(payloadJson);
        break;
      case 'agent':
        if (payloadJson != null) _handleAgentEvent(payloadJson);
        break;
    }
  }

  Future<void> deleteSession(String key) async {
    try {
      await session.request(
          'sessions.delete', jsonEncode({'sessionKey': key}));
      _sessions = _sessions.where((s) => s.key != key).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshSessions({int? limit}) => _fetchSessions(limit: limit);

  // -- Internal --

  Future<void> _bootstrap({required bool forceHealth}) async {
    _errorText = null;
    _healthOk = false;
    _clearPendingRuns();
    _pendingToolCallsById.clear();
    _pendingToolCalls = [];
    _streamingAssistantText = null;
    _sessionId = null;
    notifyListeners();

    try {
      final historyJson = await session.request(
          'chat.history', jsonEncode({'sessionKey': _sessionKey}));
      final history = _parseHistory(historyJson);
      if (history.messages.isNotEmpty) {
        _messages = history.messages;
        _sessionId = history.sessionId;
        if (history.thinkingLevel != null &&
            history.thinkingLevel!.trim().isNotEmpty) {
          _thinkingLevel = history.thinkingLevel!;
        }
      }
      _healthOk = true;
      notifyListeners();
      _pollHealthIfNeeded(force: forceHealth);
      _fetchSessions(limit: 50);
    } catch (err) {
      _errorText = err.toString();
      notifyListeners();
    }
  }

  Future<void> _fetchSessions({int? limit}) async {
    try {
      final params = <String, dynamic>{
        'includeGlobal': true,
        'includeUnknown': false,
      };
      if (limit != null && limit > 0) params['limit'] = limit;
      final res =
          await session.request('sessions.list', jsonEncode(params));
      _sessions = _parseSessions(res);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _pollHealthIfNeeded({required bool force}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _lastHealthPollAtMs != null && now - _lastHealthPollAtMs! < 10000) {
      return;
    }
    _lastHealthPollAtMs = now;
    try {
      await session.request('health', null);
      _healthOk = true;
      notifyListeners();
    } catch (err) {
      if (err.toString().contains('UNKNOWN_METHOD')) {
        // Server doesn't support health; keep existing status
      } else {
        _healthOk = false;
        notifyListeners();
      }
    }
  }

  void _handleChatEvent(String payloadJson) {
    final payload = _tryParseJson(payloadJson);
    if (payload == null) return;
    final sessionKey = payload['sessionKey'] as String?;
    if (sessionKey != null &&
        sessionKey.trim().isNotEmpty &&
        sessionKey != _sessionKey) return;

    final runId = payload['runId'] as String?;
    final state = payload['state'] as String?;

    switch (state) {
      case 'delta':
        final text = _parseAssistantDeltaText(payload);
        if (text != null && text.isNotEmpty) {
          _streamingAssistantText =
              (_streamingAssistantText ?? '') + text;
          notifyListeners();
        }
        break;
      case 'final':
      case 'aborted':
      case 'error':
        if (state == 'error') {
          _errorText =
              payload['errorMessage'] as String? ?? 'Chat failed';
        }
        if (runId != null) {
          _clearPendingRun(runId);
        } else {
          _clearPendingRuns();
        }
        _pendingToolCallsById.clear();
        _pendingToolCalls = [];
        notifyListeners();

        _fetchHistoryAndMerge();
        break;
    }
  }

  void _handleAgentEvent(String payloadJson) {
    final payload = _tryParseJson(payloadJson);
    if (payload == null) return;
    final sessionKey = payload['sessionKey'] as String?;
    if (sessionKey != null &&
        sessionKey.trim().isNotEmpty &&
        sessionKey != _sessionKey) return;

    final stream = payload['stream'] as String?;
    final data = payload['data'] as Map<String, dynamic>?;

    switch (stream) {
      case 'assistant':
        final text =
            _parseAssistantDeltaText(payload) ?? data?['text'] as String?;
        if (text != null && text.isNotEmpty) {
          _streamingAssistantText =
              (_streamingAssistantText ?? '') + text;
          notifyListeners();
        }
        break;
      case 'tool':
        final phase = data?['phase'] as String?;
        final name = data?['name'] as String?;
        final toolCallId = data?['toolCallId'] as String?;
        if (phase == null || name == null || toolCallId == null) return;

        final ts = (payload['ts'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch;
        if (phase == 'start') {
          _pendingToolCallsById[toolCallId] = ChatPendingToolCall(
            toolCallId: toolCallId,
            name: name,
            args: data?['args'] as Map<String, dynamic>?,
            startedAtMs: ts,
          );
          _pendingToolCalls =
              _pendingToolCallsById.values.toList()
                ..sort((a, b) => a.startedAtMs.compareTo(b.startedAtMs));
          notifyListeners();
        } else if (phase == 'result') {
          _pendingToolCallsById.remove(toolCallId);
          _pendingToolCalls =
              _pendingToolCallsById.values.toList()
                ..sort((a, b) => a.startedAtMs.compareTo(b.startedAtMs));
          notifyListeners();
        }
        break;
      case 'error':
        _errorText = 'Event stream interrupted; try refreshing.';
        _clearPendingRuns();
        _pendingToolCallsById.clear();
        _pendingToolCalls = [];
        _streamingAssistantText = null;
        notifyListeners();
        break;
    }
  }

  Future<void> _fetchHistoryAndMerge() async {
    try {
      final historyJson = await session.request(
          'chat.history', jsonEncode({'sessionKey': _sessionKey}));
      final history = _parseHistory(historyJson);
      final streamingText = _streamingAssistantText;

      if (history.messages.isNotEmpty &&
          history.messages.length >= _messages.length) {
        _messages = history.messages;
        _sessionId = history.sessionId;
        if (history.thinkingLevel != null &&
            history.thinkingLevel!.trim().isNotEmpty) {
          _thinkingLevel = history.thinkingLevel!;
        }
        _streamingAssistantText = null;
      } else {
        if (streamingText != null && streamingText.isNotEmpty) {
          _messages = [
            ..._messages,
            ChatMessage(
              id: _uuid.v4(),
              role: 'assistant',
              content: [ChatMessageContent(type: 'text', text: streamingText)],
              timestampMs: DateTime.now().millisecondsSinceEpoch,
            ),
          ];
        }
        _streamingAssistantText = null;
      }
      notifyListeners();
    } catch (_) {
      _streamingAssistantText = null;
      notifyListeners();
    }
  }

  String? _parseAssistantDeltaText(Map<String, dynamic> payload) {
    final message = payload['message'] as Map<String, dynamic>?;
    if (message == null) return null;
    if (message['role'] != 'assistant') return null;
    final content = message['content'] as List<dynamic>?;
    if (content == null) return null;
    for (final item in content) {
      if (item is Map<String, dynamic> && item['type'] == 'text') {
        final text = item['text'] as String?;
        if (text != null && text.isNotEmpty) return text;
      }
    }
    return null;
  }

  ChatHistory _parseHistory(String historyJson) {
    final root = _tryParseJson(historyJson);
    if (root == null) {
      return ChatHistory(sessionKey: _sessionKey);
    }
    final sid = root['sessionId'] as String?;
    final thinkingLevel = root['thinkingLevel'] as String?;
    final array = root['messages'] as List<dynamic>? ?? [];
    final messages = array
        .whereType<Map<String, dynamic>>()
        .map((obj) {
          final role = obj['role'] as String?;
          if (role == null) return null;
          final contentJson = obj['content'];
          List<ChatMessageContent> content;
          if (contentJson is List) {
            content = contentJson
                .whereType<Map<String, dynamic>>()
                .map(_parseMessageContent)
                .toList();
          } else if (contentJson is String) {
            content = [ChatMessageContent(type: 'text', text: contentJson)];
          } else {
            content = [];
          }
          return ChatMessage(
            id: _uuid.v4(),
            role: role,
            content: content,
            timestampMs: (obj['timestamp'] as num?)?.toInt(),
          );
        })
        .whereType<ChatMessage>()
        .toList();
    return ChatHistory(
      sessionKey: _sessionKey,
      sessionId: sid,
      thinkingLevel: thinkingLevel,
      messages: messages,
    );
  }

  ChatMessageContent _parseMessageContent(Map<String, dynamic> obj) {
    final type = obj['type'] as String? ?? 'text';
    if (type == 'text') {
      return ChatMessageContent(type: 'text', text: obj['text'] as String?);
    }
    return ChatMessageContent(
      type: type,
      mimeType: obj['mimeType'] as String?,
      fileName: obj['fileName'] as String?,
      base64: obj['content'] as String?,
    );
  }

  List<ChatSessionEntry> _parseSessions(String jsonString) {
    final root = _tryParseJson(jsonString);
    if (root == null) return [];
    final sessions = root['sessions'] as List<dynamic>? ?? [];
    return sessions
        .whereType<Map<String, dynamic>>()
        .map((obj) {
          final key = (obj['key'] as String?)?.trim() ?? '';
          if (key.isEmpty) return null;
          return ChatSessionEntry(
            key: key,
            updatedAtMs: (obj['updatedAt'] as num?)?.toInt(),
            displayName: (obj['displayName'] as String?)?.trim(),
          );
        })
        .whereType<ChatSessionEntry>()
        .toList();
  }

  void _armPendingRunTimeout(String runId) {
    _pendingRunTimeouts[runId]?.cancel();
    _pendingRunTimeouts[runId] = Timer(
      const Duration(milliseconds: _pendingRunTimeoutMs),
      () {
        if (_pendingRuns.contains(runId)) {
          _clearPendingRun(runId);
          _errorText = 'Timed out waiting for a reply; try again or refresh.';
          notifyListeners();
        }
      },
    );
  }

  void _clearPendingRun(String runId) {
    _pendingRunTimeouts.remove(runId)?.cancel();
    _pendingRuns.remove(runId);
    _pendingRunCount = _pendingRuns.length;
  }

  void _clearPendingRuns() {
    for (final timer in _pendingRunTimeouts.values) {
      timer.cancel();
    }
    _pendingRunTimeouts.clear();
    _pendingRuns.clear();
    _pendingRunCount = 0;
  }

  String _normalizeThinking(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'low':
        return 'low';
      case 'medium':
        return 'medium';
      case 'high':
        return 'high';
      default:
        return 'off';
    }
  }

  Map<String, dynamic>? _tryParseJson(String s) {
    try {
      return jsonDecode(s.trim()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
