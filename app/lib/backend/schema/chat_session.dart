/// One chat thread with Omi (the backend's `/v2/chat-sessions`): what Past chats lists.
class ChatSessionSummary {
  const ChatSessionSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.preview,
    this.messageCount = 0,
  });

  final String id;

  /// The server's title; "New Chat" until one is generated from the first exchange.
  final String title;
  final String? preview;
  final DateTime updatedAt;
  final int messageCount;

  /// The title the server gives a session before one is generated.
  static const String untitled = 'New Chat';

  bool get hasTitle => title.trim().isNotEmpty && title.trim() != untitled;

  static ChatSessionSummary? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    final updated = DateTime.tryParse('${json['updated_at'] ?? json['created_at'] ?? ''}');
    return ChatSessionSummary(
      id: id,
      title: (json['title'] as String?) ?? untitled,
      preview: json['preview'] as String?,
      updatedAt: (updated ?? DateTime.now()).toLocal(),
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
    );
  }
}
