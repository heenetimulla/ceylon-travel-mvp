import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/account_attention.dart';
import '../models/admin_user_summary.dart';
import 'admin_service.dart';

class RegistrationQueueRow {
  RegistrationQueueRow(this.user, this.revision, this.submittedAt);
  factory RegistrationQueueRow.fromMap(String uid, Map<String, dynamic> data) {
    final submittedAt = data['applicationSubmittedAt'];
    return RegistrationQueueRow(AdminUserSummary.fromMap(uid, data),
      data['applicationRevision'] is int ? data['applicationRevision'] as int : null,
      submittedAt is Timestamp ? submittedAt.toDate().toUtc() : null);
  }
  final AdminUserSummary user;
  final int? revision;
  final DateTime? submittedAt;
}
class RegistrationQueuePage {
  RegistrationQueuePage(this.rows, this.nextUid);
  final List<RegistrationQueueRow> rows;
  final String? nextUid;
}
class RegistrationQueueCounts {
  const RegistrationQueueCounts(this.identity, this.payment, this.activation);
  final int identity, payment, activation;
}

/// Queries authoritative accounts; private submissions are fetched only in detail.
class AdminRegistrationQueueService {
  AdminRegistrationQueueService({required this.admin, FirebaseFirestore? firestore}) : _providedDb = firestore;
  final AdminService admin;
  final FirebaseFirestore? _providedDb;
  FirebaseFirestore get _db => _providedDb ?? FirebaseFirestore.instance;
  static const reviewStates = ['pending_review', 'correction_required', 'rejected'];
  Query<Map<String, dynamic>> _query(RegistrationQueueFilter filter) {
    Query<Map<String, dynamic>> query = _db.collection('users');
    if (filter == RegistrationQueueFilter.payment) {
      // Four disjuncts share the two equality fields. Each uses one existing
      // users composite: accountType, registrationStatus, branch field, __name__
      // (all ascending). Both paymentStatus values use the same index.
      return query.where('registrationStatus', isEqualTo: 'approved').where('accountType', isEqualTo: 'driver')
        .where(Filter.or(Filter('paymentStatus', isEqualTo: 'pending'), Filter('paymentStatus', isEqualTo: 'rejected'),
          Filter('accountStatus', isEqualTo: 'pending_approval'), Filter('membershipStatus', isEqualTo: 'pending')));
    }
    query = filter == RegistrationQueueFilter.correction
      ? query.where('registrationStatus', isEqualTo: 'correction_required')
      : query.where('registrationStatus', whereIn: reviewStates);
    if (filter == RegistrationQueueFilter.tourist || filter == RegistrationQueueFilter.driver) {
      query = query.where('accountType', isEqualTo: filter == RegistrationQueueFilter.driver ? 'driver' : 'tourist');
    }
    return query;
  }
  Future<String> _authorize() async {
    final access = await admin.readAccess();
    if (access.status != AdminAccessStatus.allowed || access.uid == null) { throw StateError('Admin access required.'); }
    return access.uid!;
  }
  Future<RegistrationQueueCounts> counts() async {
    final actor = await _authorize();
    final approvedDrivers = _db.collection('users').where('registrationStatus', isEqualTo: 'approved').where('accountType', isEqualTo: 'driver');
    final results = await Future.wait([
      _query(RegistrationQueueFilter.all).count().get(),
      approvedDrivers.where('paymentStatus', isEqualTo: 'pending').count().get(),
      approvedDrivers.where('paymentStatus', isEqualTo: 'verified').where('membershipStatus', isEqualTo: 'pending').count().get(),
    ]).timeout(const Duration(seconds: 20));
    if (await _authorize() != actor) { throw StateError('Admin session changed.'); }
    return RegistrationQueueCounts(results[0].count ?? 0, results[1].count ?? 0, results[2].count ?? 0);
  }
  Future<RegistrationQueuePage> page(RegistrationQueueFilter filter, {String? afterUid}) async {
    final actor = await _authorize();
    var query = _query(filter).orderBy(FieldPath.documentId).limit(30);
    if (afterUid != null) { query = query.startAfter([afterUid]); }
    final result = await query.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 20));
    if (await _authorize() != actor) { throw StateError('Admin session changed.'); }
    final rows = result.docs.map((doc) => RegistrationQueueRow.fromMap(doc.id, doc.data())).toList();
    return RegistrationQueuePage(rows, rows.length == 30 ? rows.last.user.uid : null);
  }
}
