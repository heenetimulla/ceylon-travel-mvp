import 'package:cloud_firestore/cloud_firestore.dart';
import 'support_message.dart';
import 'support_request.dart';

const supportStatuses = {
  'open': 'Open', 'in_review': 'In Progress', 'resolved': 'Resolved', 'closed': 'Closed',
};

enum SupportInboxFilter {
  all('All', []), open('Open', ['open']), inReview('In Progress', ['in_review']),
  completed('Resolved / Closed', ['resolved', 'closed']);
  const SupportInboxFilter(this.label, this.statuses);
  final String label;
  final List<String> statuses;
}

String supportCategoryLabel(SupportRequest request) {
  final category = supportCategories[request.category] ?? request.category;
  final sub = request.subCategory;
  if (sub == null) return category;
  return '$category · ${driverComplaintCategories[sub] ?? creatorComplaintCategories[sub] ?? sub}';
}

bool supportMatchesSearch(SupportRequest request, String search) {
  final text = search.trim().toLowerCase();
  if (text.isEmpty) return true;
  final fields = [request.supportReference, request.tripReference ?? '', request.contactNumber,
    request.userName, request.userId, supportCategoryLabel(request), request.subject];
  if (fields.any((field) => field.toLowerCase().contains(text))) return true;
  final digits = text.replaceAll(RegExp(r'\D'), '');
  return RegExp(r'^[+\d\s().-]+$').hasMatch(text) && digits.isNotEmpty &&
    request.contactNumber.replaceAll(RegExp(r'\D'), '').contains(digits);
}

/// Retains the exact Firestore timestamp (including nanoseconds) for paging ties.
class SupportCursor {
  const SupportCursor(this.createdAt, this.id);
  final Object? createdAt;
  final String id;
}

class SupportPage<T> {
  SupportPage(List<T> items, {this.next}) : items = List.unmodifiable(items);
  final List<T> items;
  final SupportCursor? next;
}

class SupportStatusEvent {
  const SupportStatusEvent({required this.id, required this.actorId,
    required this.fromStatus, required this.toStatus, this.createdAt});
  final String id, actorId, fromStatus, toStatus;
  final DateTime? createdAt;
}

class SupportDetail {
  const SupportDetail({required this.request, required this.messages, required this.history});
  final SupportRequest request;
  final SupportPage<SupportMessage> messages;
  final SupportPage<SupportStatusEvent> history;
}

/// Admin-only tolerant projection; existing customer models/read behavior stay intact.
class AdminSupportParser {
  static String text(Object? value, [String fallback = 'Not available']) =>
    value is String && value.trim().isNotEmpty ? value : fallback;
  static String? optional(Object? value) => value is String && value.trim().isNotEmpty ? value : null;
  static DateTime? date(Object? value) => value is Timestamp ? value.toDate().toUtc()
    : value is DateTime ? value.toUtc() : null;

  static SupportRequest request(String id, Map<String, dynamic> data) => SupportRequest(
    id: id, supportReference: text(data['supportReference'], id),
    userId: text(data['userId']), userRole: text(data['userRole']), userName: text(data['userName']),
    contactNumber: text(data['contactNumber']), category: text(data['category'], 'other'),
    subCategory: optional(data['subCategory']), tripId: optional(data['tripId']),
    tripReference: optional(data['tripReference']), subject: text(data['subject']),
    message: text(data['message']), status: text(data['status'], 'unknown'),
    createdAt: date(data['createdAt']), updatedAt: date(data['updatedAt']),
    lastMessageAt: date(data['lastMessageAt']),
  );

  static SupportMessage message(String id, Map<String, dynamic> data) => SupportMessage(
    id: id, senderId: text(data['senderId']), senderRole: text(data['senderRole'], 'unknown'),
    message: text(data['message']), createdAt: date(data['createdAt']),
  );

  static SupportStatusEvent event(String id, Map<String, dynamic> data) => SupportStatusEvent(
    id: id, actorId: text(data['actorId']), fromStatus: text(data['fromStatus']),
    toStatus: text(data['toStatus']), createdAt: date(data['createdAt']),
  );
}
