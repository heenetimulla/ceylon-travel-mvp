import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_support_data.dart';
import '../models/support_message.dart';
import '../models/support_request.dart';

class SupportReadQuery {
  const SupportReadQuery({this.filter = SupportInboxFilter.all, this.cursor});
  static const pageSize = 50;
  final SupportInboxFilter filter;
  final SupportCursor? cursor;
}

/// Exact write allowlists shared by the production transactions and unit tests.
class SupportStaffWrites {
  static Map<String, dynamic> reply(String id, String actor, String text) => {
    'id': id, 'senderId': actor, 'senderRole': 'admin', 'message': text,
    'createdAt': FieldValue.serverTimestamp(),
  };
  static Map<String, dynamic> replyParent(String id) => {
    'updatedAt': FieldValue.serverTimestamp(), 'lastMessageAt': FieldValue.serverTimestamp(), 'lastMessageId': id,
  };
  static Map<String, dynamic> event(String id, String actor, String from, String to) => {
    'id': id, 'actorId': actor, 'fromStatus': from, 'toStatus': to, 'createdAt': FieldValue.serverTimestamp(),
  };
  static Map<String, dynamic> statusParent(String id, String status) => {
    'status': status, 'updatedAt': FieldValue.serverTimestamp(), 'lastStatusEventId': id,
  };
}

abstract interface class AdminSupportDataSource {
  String newOperationId();
  Future<SupportPage<SupportRequest>> requests(SupportReadQuery query);
  Future<SupportRequest?> request(String id);
  Future<SupportPage<SupportMessage>> messages(String id, SupportReadQuery query);
  Future<SupportPage<SupportStatusEvent>> history(String id, SupportReadQuery query);
  Future<void> reply(String id, String operationId, String actor, String text, void Function() checkSession);
  Future<void> changeStatus(String id, String operationId, String actor, String from, String to,
    void Function() checkSession);
}

class FirestoreAdminSupportDataSource implements AdminSupportDataSource {
  FirestoreAdminSupportDataSource({FirebaseFirestore? firestore}) : _provided = firestore;
  final FirebaseFirestore? _provided;
  FirebaseFirestore get _db => _provided ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _requests => _db.collection('support_requests');
  @override
  String newOperationId() => _requests.doc().id;

  Future<SupportPage<T>> _page<T>(Query<Map<String, dynamic>> query, SupportReadQuery definition,
      T Function(String, Map<String, dynamic>) parse, {bool descending = false}) async {
    query = query.orderBy('createdAt', descending: descending)
      .orderBy(FieldPath.documentId, descending: descending);
    final cursor = definition.cursor;
    if (cursor != null) query = query.startAfter([cursor.createdAt, cursor.id]);
    final result = await query.limit(SupportReadQuery.pageSize).get(const GetOptions(source: Source.server));
    return SupportPage(result.docs.map((doc) => parse(doc.id, doc.data())).toList(),
      next: result.docs.length == SupportReadQuery.pageSize
        ? SupportCursor(result.docs.last.data()['createdAt'], result.docs.last.id) : null);
  }

  @override
  Future<SupportPage<SupportRequest>> requests(SupportReadQuery query) {
    Query<Map<String, dynamic>> requestQuery = _requests;
    if (query.filter.statuses.isNotEmpty) {
      requestQuery = requestQuery.where('status', whereIn: query.filter.statuses);
    }
    return _page(requestQuery, query, AdminSupportParser.request, descending: true);
  }
  @override
  Future<SupportRequest?> request(String id) async {
    final doc = await _requests.doc(id).get(const GetOptions(source: Source.server));
    final data = doc.data();
    return data == null ? null : AdminSupportParser.request(doc.id, data);
  }
  @override
  Future<SupportPage<SupportMessage>> messages(String id, SupportReadQuery query) =>
    _page(_requests.doc(id).collection('messages'), query, AdminSupportParser.message);
  @override
  Future<SupportPage<SupportStatusEvent>> history(String id, SupportReadQuery query) =>
    _page(_requests.doc(id).collection('status_history'), query, AdminSupportParser.event);

  @override
  Future<void> reply(String id, String operationId, String actor, String text, void Function() checkSession) async {
    final parent = _requests.doc(id), message = parent.collection('messages').doc(operationId);
    await _db.runTransaction((tx) async {
      final existing = (await tx.get(message)).data();
      final request = (await tx.get(parent)).data();
      checkSession();
      if (existing != null) {
        if (existing['senderId'] == actor && existing['senderRole'] == 'admin' && existing['message'] == text) return;
        throw StateError('Reply operation conflict.');
      }
      if (request == null || request['status'] == 'closed') throw StateError('Request unavailable or closed.');
      tx.set(message, SupportStaffWrites.reply(operationId, actor, text));
      tx.update(parent, SupportStaffWrites.replyParent(operationId));
    });
  }

  @override
  Future<void> changeStatus(String id, String operationId, String actor, String from, String to,
      void Function() checkSession) async {
    final parent = _requests.doc(id), event = parent.collection('status_history').doc(operationId);
    await _db.runTransaction((tx) async {
      final existing = (await tx.get(event)).data();
      final request = (await tx.get(parent)).data();
      checkSession();
      if (existing != null) {
        if (existing['actorId'] == actor && existing['fromStatus'] == from && existing['toStatus'] == to) return;
        throw StateError('Status operation conflict.');
      }
      if (request == null || request['status'] != from) throw StateError('Status changed. Refresh the request.');
      tx.set(event, SupportStaffWrites.event(operationId, actor, from, to));
      tx.update(parent, SupportStaffWrites.statusParent(operationId, to));
    });
  }
}
