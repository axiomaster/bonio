class ChatMessage {
  final String id;
  final String role;
  final List<ChatMessageContent> content;
  final int? timestampMs;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.timestampMs,
  });

  String get textContent =>
      content.where((c) => c.type == 'text').map((c) => c.text ?? '').join();
}

class ChatMessageContent {
  final String type;
  final String? text;
  final String? mimeType;
  final String? fileName;
  final String? base64;
  final int? durationMs;

  const ChatMessageContent({
    this.type = 'text',
    this.text,
    this.mimeType,
    this.fileName,
    this.base64,
    this.durationMs,
  });
}

class ChatPendingToolCall {
  final String toolCallId;
  final String name;
  final Map<String, dynamic>? args;
  final int startedAtMs;
  final bool? isError;

  const ChatPendingToolCall({
    required this.toolCallId,
    required this.name,
    this.args,
    required this.startedAtMs,
    this.isError,
  });
}

class ChatSessionEntry {
  final String key;
  final int? updatedAtMs;
  final String? displayName;

  const ChatSessionEntry({
    required this.key,
    this.updatedAtMs,
    this.displayName,
  });
}

class ChatHistory {
  final String sessionKey;
  final String? sessionId;
  final String? thinkingLevel;
  final List<ChatMessage> messages;

  const ChatHistory({
    required this.sessionKey,
    this.sessionId,
    this.thinkingLevel,
    this.messages = const [],
  });
}

class OutgoingAttachment {
  final String type;
  final String mimeType;
  final String fileName;
  final String base64;
  final int? durationMs;

  const OutgoingAttachment({
    required this.type,
    required this.mimeType,
    required this.fileName,
    required this.base64,
    this.durationMs,
  });
}
