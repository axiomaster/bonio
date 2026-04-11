import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_strings.dart';
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

  /// Locally-sent image attachments indexed by message text digest.
  /// Server history doesn't return raw image data, so we preserve them here
  /// and re-attach when merging server history.
  final Map<String, List<ChatMessageContent>> _localImageAttachments = {};
  List<ChatPendingToolCall> _pendingToolCalls = [];
  List<ChatSessionEntry> _sessions = [];

  final Set<String> _pendingRuns = {};
  final Map<String, Timer> _pendingRunTimeouts = {};
  final Map<String, ChatPendingToolCall> _pendingToolCallsById = {};
  static const _pendingRunTimeoutMs = 120000;

  /// RunIds that arrived in a `final`/`aborted`/`error` event before the
  /// `chat.send` RPC response mapped them into [_pendingRuns].
  final Set<String> _completedRunIds = {};

  /// Client-side runIds whose `chat.send` RPC is still in flight.
  /// Prevents duplicate sends and allows early-final cleanup.
  final Set<String> _inflightClientRunIds = {};

  int? _lastHealthPollAtMs;

  /// Spoken when the assistant finishes a reply (OpenClaw may not send `avatar.command` tts).
  final void Function(String plainText)? onAssistantReplyForTts;

  String? _lastAssistantTtsDigest;
  bool _ttsAfterChatFinal = false;

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

  ChatController({
    required this.session,
    this.onAssistantReplyForTts,
  });

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
    if (key != _sessionKey) {
      _clearPendingRuns();
      _pendingToolCallsById.clear();
      _pendingToolCalls = [];
      _streamingAssistantText = null;
    }
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
    _clearPendingRuns();
    _pendingToolCallsById.clear();
    _pendingToolCalls = [];
    _streamingAssistantText = null;
    _sessionKey = key;
    notifyListeners();
    await _bootstrap(forceHealth: true);
  }

  Future<void> sendMessage(String message,
      {List<OutgoingAttachment> attachments = const []}) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    if (!_healthOk) {
      _errorText = S.current.chatGatewayNotReady;
      notifyListeners();
      return;
    }

    final runId = _uuid.v4();
    // Guard: skip if another send is already in flight with the same text
    if (_inflightClientRunIds.isNotEmpty) {
      debugPrint('ChatController: send skipped — another send is in flight');
      return;
    }
    _inflightClientRunIds.add(runId);

    final text =
        trimmed.isEmpty && attachments.isNotEmpty ? 'See attached.' : trimmed;

    final imageContents = attachments
        .where((a) => a.type == 'image' || a.mimeType.startsWith('image/'))
        .map((a) => ChatMessageContent(
              type: a.type,
              mimeType: a.mimeType,
              fileName: a.fileName,
              base64: a.base64,
              durationMs: a.durationMs,
            ))
        .toList();

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

    if (imageContents.isNotEmpty) {
      _localImageAttachments[text] = imageContents;
    }

    _messages = [
      ..._messages,
      ChatMessage(
        id: _uuid.v4(),
        role: 'user',
        content: userContent,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
      ),
    ];
    _lastAssistantTtsDigest = null;

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

      final rpcTimeout = attachments.isNotEmpty ? 30000 : 15000;
      final res = await session.request('chat.send', jsonEncode(params),
          timeoutMs: rpcTimeout);
      _inflightClientRunIds.remove(runId);
      final resObj = _tryParseJson(res);
      final actualRunId = resObj?['runId'] as String?;

      if (actualRunId != null) {
        if (actualRunId != runId) {
          // Server assigned a different runId. Swap the tracking.
          _pendingRunTimeouts.remove(runId)?.cancel();
          _pendingRuns.remove(runId);

          if (_completedRunIds.remove(actualRunId)) {
            // The final event already arrived — run is done.
            debugPrint('ChatController: runId $actualRunId already completed');
            _pendingRunCount = _pendingRuns.length;
          } else {
            _armPendingRunTimeout(actualRunId);
            _pendingRuns.add(actualRunId);
            _pendingRunCount = _pendingRuns.length;
          }
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
      _inflightClientRunIds.remove(runId);
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
        _errorText = S.current.chatStreamInterrupted;
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
    // Do not clear _pendingRuns/_messages here: refresh/bootstrap runs while a
    // chat.send is in flight would wipe the user's message and streaming state.

    try {
      final historyJson = await session.request(
          'chat.history', jsonEncode({'sessionKey': _sessionKey}));
      final history = _parseHistory(historyJson);
      final inFlight = _pendingRuns.isNotEmpty ||
          (_streamingAssistantText != null &&
              _streamingAssistantText!.trim().isNotEmpty);
      if (history.messages.isNotEmpty) {
        if (!inFlight) {
          _messages = _reattachLocalImages(history.messages);
          _sessionId = history.sessionId;
          if (history.thinkingLevel != null &&
              history.thinkingLevel!.trim().isNotEmpty) {
            _thinkingLevel = history.thinkingLevel!;
          }
        } else {
          // Keep local tail (user bubble + streaming); still sync ids when server is ahead
          _sessionId = history.sessionId ?? _sessionId;
          if (history.messages.length > _messages.length) {
            _messages = _reattachLocalImages(history.messages);
            if (history.thinkingLevel != null &&
                history.thinkingLevel!.trim().isNotEmpty) {
              _thinkingLevel = history.thinkingLevel!;
            }
          }
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

  /// True when [eventKey] refers to the same chat session as [_sessionKey].
  /// OpenClaw often canonicalizes `main` to `agent:main:main` in events while
  /// connect may omit `snapshot.sessionDefaults.mainSessionKey`.
  bool _sessionKeyMatchesEvent(String? eventKey) {
    if (eventKey == null || eventKey.trim().isEmpty) return true;
    final a = eventKey.trim();
    final b = _sessionKey.trim();
    if (a == b) return true;
    if ((a == 'main' && b == 'agent:main:main') ||
        (b == 'main' && a == 'agent:main:main')) {
      return true;
    }
    return false;
  }

  void _handleChatEvent(String payloadJson) {
    final payload = _tryParseJson(payloadJson);
    if (payload == null) return;
    final sessionKey = payload['sessionKey'] as String?;
    if (!_sessionKeyMatchesEvent(sessionKey)) return;

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
              payload['errorMessage'] as String? ?? S.current.chatFailed;
        }
        _ttsAfterChatFinal = state == 'final';
        if (runId != null) {
          if (_pendingRuns.contains(runId)) {
            // Normal path: clear this specific run. Don't trigger the
            // delayed _fetchHistoryAndMerge inside _clearPendingRun —
            // we call it explicitly below.
            _pendingRunTimeouts.remove(runId)?.cancel();
            _pendingRuns.remove(runId);
            _pendingRunCount = _pendingRuns.length;
          } else {
            // Race: final event arrived before chat.send RPC response.
            // Record the runId so the RPC response handler won't re-add it.
            // Do NOT call _clearPendingRuns() — that destroys _completedRunIds.
            _completedRunIds.add(runId);
            debugPrint('ChatController: early final for runId $runId, '
                'inflight=${_inflightClientRunIds.length}');
            // If no RPC is in flight, the client-side runId is already in
            // _pendingRuns; clear it since the server is done.
            if (_inflightClientRunIds.isEmpty) {
              _clearPendingRuns();
            }
          }
        } else {
          _clearPendingRuns();
        }
        _pendingToolCallsById.clear();
        _pendingToolCalls = [];
        notifyListeners();

        unawaited(_fetchHistoryAndMerge());
        break;
    }
  }

  void _handleAgentEvent(String payloadJson) {
    final payload = _tryParseJson(payloadJson);
    if (payload == null) return;
    final sessionKey = payload['sessionKey'] as String?;
    if (!_sessionKeyMatchesEvent(sessionKey)) return;

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
        _errorText = S.current.chatStreamInterrupted;
        _clearPendingRuns();
        _pendingToolCallsById.clear();
        _pendingToolCalls = [];
        _streamingAssistantText = null;
        notifyListeners();
        break;
    }
  }

  Future<void> _fetchHistoryAndMerge() async {
    final streamingText = _streamingAssistantText;
    try {
      final historyJson = await session.request(
          'chat.history', jsonEncode({'sessionKey': _sessionKey}));
      final history = _parseHistory(historyJson);

      if (history.messages.isNotEmpty &&
          history.messages.length >= _messages.length) {
        _messages = _reattachLocalImages(history.messages);
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
      _maybeSpeakAssistantAfterMerge();
    } catch (e) {
      debugPrint('ChatController: _fetchHistoryAndMerge failed: $e');
      // Still attempt TTS with whatever streaming text we captured.
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
      notifyListeners();
      _maybeSpeakAssistantAfterMerge();
    }
  }

  void _maybeSpeakAssistantAfterMerge() {
    if (!_ttsAfterChatFinal) {
      debugPrint('ChatController: TTS skipped (_ttsAfterChatFinal=false)');
      return;
    }
    _ttsAfterChatFinal = false;
    final text = _lastAssistantPlainText();
    if (text.isEmpty) {
      debugPrint('ChatController: TTS skipped (empty assistant text)');
      return;
    }
    if (text == _lastAssistantTtsDigest) {
      debugPrint('ChatController: TTS skipped (duplicate digest)');
      return;
    }
    _lastAssistantTtsDigest = text;
    debugPrint('ChatController: triggering TTS (${text.length} chars)');
    onAssistantReplyForTts?.call(text);
  }

  String _lastAssistantPlainText() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == 'assistant') {
        return _messages[i].textContent.trim();
      }
    }
    return '';
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

  /// Re-attach locally cached image attachments to server-fetched messages.
  /// Server history only returns text content; we match by user message text.
  List<ChatMessage> _reattachLocalImages(List<ChatMessage> messages) {
    if (_localImageAttachments.isEmpty) return messages;
    return messages.map((m) {
      if (m.role != 'user') return m;
      final text = m.textContent;
      final images = _localImageAttachments[text];
      if (images == null || images.isEmpty) return m;
      final hasImage = m.content.any((c) =>
          c.type == 'image' && c.base64 != null && c.base64!.isNotEmpty);
      if (hasImage) return m;
      return ChatMessage(
        id: m.id,
        role: m.role,
        content: [...m.content, ...images],
        timestampMs: m.timestampMs,
      );
    }).toList();
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
          // If there's unsaved streaming text, merge it before timing out.
          if (_streamingAssistantText != null &&
              _streamingAssistantText!.trim().isNotEmpty) {
            _ttsAfterChatFinal = true;
            unawaited(_fetchHistoryAndMerge());
          } else {
            _errorText = 'Timed out waiting for a reply; try again or refresh.';
          }
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
    _completedRunIds.clear();
    _inflightClientRunIds.clear();
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
