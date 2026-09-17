import 'package:firebase_auth/firebase_auth.dart';
import '../models/admin_support_data.dart';
import '../models/support_message.dart';
import '../models/support_request.dart';
import 'admin_service.dart';
import 'admin_support_data_source.dart';

/// Reuses the claim watcher/gate lifecycle, with a separate support-staff policy.
/// Primary admin alone never inherits conversation or write powers.
class AdminSupportService extends AdminService {
  AdminSupportService({super.firebaseAuth, AdminSupportDataSource? dataSource})
    : _providedAuth = firebaseAuth, _source = dataSource ?? FirestoreAdminSupportDataSource();
  final FirebaseAuth? _providedAuth;
  final AdminSupportDataSource _source;
  FirebaseAuth get _supportAuth => _providedAuth ?? FirebaseAuth.instance;
  static bool hasSupportClaim(Map<String, dynamic>? claims) => claims?['supportAdmin'] == true;

  @override
  Future<AdminAccess> readAccess({bool forceRefresh = false}) async {
    final user = _supportAuth.currentUser;
    if (user == null) return const AdminAccess(AdminAccessStatus.signedOut);
    try {
      final token = await user.getIdTokenResult(forceRefresh).timeout(const Duration(seconds: 15));
      if (_supportAuth.currentUser?.uid != user.uid) return const AdminAccess(AdminAccessStatus.denied);
      return AdminAccess(hasSupportClaim(token.claims) ? AdminAccessStatus.allowed : AdminAccessStatus.denied,
        uid: user.uid);
    } catch (_) {
      return const AdminAccess(AdminAccessStatus.error);
    }
  }

  void checkActor(String actor) {
    if (_supportAuth.currentUser?.uid != actor) throw StateError('Support session changed.');
  }

  Future<String> _actor() async {
    final access = await readAccess();
    if (access.status != AdminAccessStatus.allowed || access.uid == null) {
      throw StateError('Support staff access required.');
    }
    return access.uid!;
  }
  Future<T> _read<T>(Future<T> Function() load) async {
    final actor = await _actor();
    final result = await load().timeout(const Duration(seconds: 20));
    if (actor != await _actor()) throw StateError('Support session changed.');
    return result;
  }
  void _id(String id) {
    if (id.isEmpty || id.contains('/')) throw ArgumentError('Invalid support ID.');
  }

  String newOperationId() => _source.newOperationId();
  Future<SupportPage<SupportRequest>> loadRequests({SupportInboxFilter filter = SupportInboxFilter.all,
    SupportCursor? cursor}) => _read(() => _source.requests(SupportReadQuery(filter: filter, cursor: cursor)));

  Future<SupportDetail?> loadDetail(String id) {
    _id(id);
    return _read(() async {
      final request = await _source.request(id);
      if (request == null) return null;
      final messages = await _source.messages(id, const SupportReadQuery());
      final history = await _source.history(id, const SupportReadQuery());
      return SupportDetail(request: request, messages: messages, history: history);
    });
  }
  Future<SupportPage<SupportMessage>> loadMessages(String id, SupportCursor cursor) {
    _id(id);
    return _read(() => _source.messages(id, SupportReadQuery(cursor: cursor)));
  }
  Future<SupportPage<SupportStatusEvent>> loadHistory(String id, SupportCursor cursor) {
    _id(id);
    return _read(() => _source.history(id, SupportReadQuery(cursor: cursor)));
  }

  Future<void> reply(String id, String text, {required String operationId}) async {
    _id(id); _id(operationId);
    final message = text.trim();
    if (message.isEmpty || message.length > 4000) throw ArgumentError('Write 1 to 4000 characters.');
    final actor = await _actor();
    checkActor(actor);
    // No client timeout/retry loop around writes: the same operation ID can be
    // retried explicitly after an uncertain outcome without duplicating a reply.
    await _source.reply(id, operationId, actor, message, () => checkActor(actor));
    if (actor != await _actor()) throw StateError('Support session changed.');
  }
  Future<void> changeStatus(String id, String from, String to, {required String operationId}) async {
    _id(id); _id(operationId);
    if (!supportStatuses.containsKey(from) || !supportStatuses.containsKey(to) || from == to) {
      throw ArgumentError('Choose a different supported status.');
    }
    final actor = await _actor();
    checkActor(actor);
    await _source.changeStatus(id, operationId, actor, from, to, () => checkActor(actor));
    if (actor != await _actor()) throw StateError('Support session changed.');
  }
}
