class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderName,
    required this.message,
    required this.type,
    required this.time,
    required this.isMe,
  });

  final String id;
  final String senderName;
  final String message;
  final String type;
  final String time;
  final bool isMe;
}
