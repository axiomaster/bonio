export interface ChatMessage {
  id: string;
  role: string;
  content: ChatMessageContent[];
  timestampMs: number | undefined;
}

export interface ChatMessageContent {
  type: string;
  text?: string;
  mimeType?: string;
  fileName?: string;
  base64?: string;
}

export interface ChatPendingToolCall {
  toolCallId: string;
  name: string;
  args: Record<string, Object> | undefined;
  startedAtMs: number;
  isError: boolean | undefined;
}

export interface ChatSessionEntry {
  key: string;
  updatedAtMs: number | undefined;
  displayName: string | undefined;
}

export interface ChatHistory {
  sessionKey: string;
  sessionId: string | undefined;
  thinkingLevel: string | undefined;
  messages: ChatMessage[];
}

export interface OutgoingAttachment {
  type: string;
  mimeType: string;
  fileName: string;
  base64: string;
}
