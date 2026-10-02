import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/account_attention.dart';
import '../models/admin_user_summary.dart';
import 'admin_service.dart';

class RegistrationQueueRow {
  RegistrationQueueRow(this.user, this.revision, this.submittedAt, {this.purpose = 'registration', this.applicationState});
  factory RegistrationQueueRow.fromMap(String uid, Map<String, dynamic> data, {String? purpose}) {
    final upgrade = purpose == 'driver_upgrade' || (purpose == null && data['driverUpgradeStatus'] is String);
    final submittedAt = data[upgrade ? 'driverUpgradeSubmittedAt' : 'applicationSubmittedAt'];
    return RegistrationQueueRow(AdminUserSummary.fromMap(uid, data),
      data['applicationRevision'] is int ? data['applicationRevision'] as int : null,
      submittedAt is Timestamp ? submittedAt.toDate().toUtc() : null,
      purpose: upgrade ? 'driver_upgrade' : 'registration',
      applicationState: data[upgrade ? 'driverUpgradeStatus' : 'registrationStatus'] is String
        ? data[upgrade ? 'driverUpgradeStatus' : 'registrationStatus'] as String : null);
  }
  final AdminUserSummary user;
  final int? revision;
  final DateTime? submittedAt;
  final String purpose;
  final String? applicationState;
  String get purposeLabel => purpose == 'driver_upgrade' ? 'Driver Upgrade'
    : user.accountType == 'driver' ? 'New Driver / Partner registration' : 'New Tourist registration';
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

/// Queries current accounts and head purpose; immutable submissions stay in detail.
class AdminRegistrationQueueService {
  AdminRegistrationQueueService({required this.admin, FirebaseFirestore? firestore}) : _providedDb = firestore;
  final AdminService admin;
  final FirebaseFirestore? _providedDb;
  FirebaseFirestore get _db => _providedDb ?? FirebaseFirestore.instance;
  static const reviewStates = ['pending_review', 'correction_required', 'rejected'];
  Query<Map<String, dynamic>> _query(RegistrationQueueFilter filter) {
    final query = _db.collection('users');
    if (filter == RegistrationQueueFilter.payment) {
      // Four disjuncts share the two equality fields. Each uses one existing
      // users composite: accountType, registrationStatus, branch field, __name__
      // (all ascending). Both paymentStatus values use the same index.
      return query.where(Filter.and(
        Filter('registrationStatus', isEqualTo: 'approved'),
        Filter('accountType', isEqualTo: 'driver'),
        Filter.or(Filter('paymentStatus', isEqualTo: 'pending'), Filter('paymentStatus', isEqualTo: 'rejected'),
          Filter('accountStatus', isEqualTo: 'pending_approval'), Filter('membershipStatus', isEqualTo: 'pending'))));
    }
    if (filter == RegistrationQueueFilter.upgrade) {
      // Keep approved upgrades identifiable after the server changes accountType.
      return query.where('driverUpgradeStatus', whereIn: [...reviewStates, 'approved']);
    }
    final attention = filter == RegistrationQueueFilter.correction
      ? Filter.or(Filter('registrationStatus', isEqualTo: 'correction_required'),
          Filter('driverUpgradeStatus', isEqualTo: 'correction_required'))
      : Filter.or(Filter('registrationStatus', whereIn: reviewStates),
          Filter('driverUpgradeStatus', whereIn: reviewStates));
    if (filter == RegistrationQueueFilter.tourist || filter == RegistrationQueueFilter.driver) {
      return query.where(Filter.and(attention,
        Filter('accountType', isEqualTo: filter == RegistrationQueueFilter.driver ? 'driver' : 'tourist')));
    }
    return query.where(attention);
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
    // Bounded join for the existing trusted purpose, never retained as raw private data.
    final purposes = <String, String>{};
    if (result.docs.isNotEmpty) {
      // Application listing is deliberately denied by rules; use authorized gets.
      final heads = await Future.wait(result.docs.map((doc) => _db.collection('registration_applications')
        .doc(doc.id).get(const GetOptions(source: Source.server)))).timeout(const Duration(seconds: 20));
      for (final head in heads) {
        final purpose = head.data()?['purpose'];
        if (purpose is String) { purposes[head.id] = purpose; }
      }
    }
    if (await _authorize() != actor) { throw StateError('Admin session changed.'); }
    final rows = result.docs.map((doc) => RegistrationQueueRow.fromMap(doc.id, doc.data(), purpose: purposes[doc.id])).toList();
    return RegistrationQueuePage(rows, rows.length == 30 ? rows.last.user.uid : null);
  }
}
