import 'package:cloud_firestore/cloud_firestore.dart';
class SupportMessage {
  const SupportMessage({required this.id, required this.senderId, required this.senderRole, required this.message, this.createdAt});
  final String id, senderId, senderRole, message;
  final DateTime? createdAt;
  factory SupportMessage.fromMap(Map<String, dynamic> d) => SupportMessage(
    id: d['id'], senderId: d['senderId'], senderRole: d['senderRole'], message: d['message'],
    createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
  );
}
