import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/admin_dashboard_stats.dart';
import '../models/support_request.dart';
import 'admin_data_source.dart';

enum AdminAccessStatus { loading, signedOut, denied, error, allowed }

class AdminAccess {
  const AdminAccess(this.status, {this.uid});
  final AdminAccessStatus status;
  final String? uid;
}

/// Claims control the UI; Firestore rules independently authorize every read.
/// No method in this service writes profiles, claims or operational data.
class AdminService {
  AdminService({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore, AdminDataSource? dataSource})
    : _providedAuth = firebaseAuth,
      _dataSource = dataSource ?? FirestoreAdminDataSource(firestore: firestore);
  final FirebaseAuth? _providedAuth;
  final AdminDataSource _dataSource;
  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  static bool hasAdminClaim(Map<String, dynamic>? claims) => claims?['admin'] == true;

  Future<AdminAccess> readAccess({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return const AdminAccess(AdminAccessStatus.signedOut);
    try {
      final token = await user.getIdTokenResult(forceRefresh).timeout(const Duration(seconds: 15));
      if (_auth.currentUser?.uid != user.uid) return const AdminAccess(AdminAccessStatus.denied);
      return AdminAccess(hasAdminClaim(token.claims) ? AdminAccessStatus.allowed : AdminAccessStatus.denied,
        uid: user.uid);
    } catch (_) {
      return const AdminAccess(AdminAccessStatus.error);
    }
  }

  Stream<AdminAccess> watchAccess() => Stream<AdminAccess>.multi((controller) {
    var generation = 0;
    var cancelled = false;
    final subscription = _auth.idTokenChanges().listen((user) async {
      final current = ++generation;
      controller.add(const AdminAccess(AdminAccessStatus.loading));
      final access = user == null ? const AdminAccess(AdminAccessStatus.signedOut) : await readAccess();
      if (!cancelled && current == generation) controller.add(access);
    }, onError: (Object error) {
      generation++;
      if (!cancelled) controller.add(const AdminAccess(AdminAccessStatus.error));
    });
    controller.onCancel = () async {
      cancelled = true;
      generation++;
      await subscription.cancel();
    };
  });

  /// Exposes the actual query definitions for focused tests; this does not run reads.
  Map<String, AdminCountQuery> overviewQueries() {
    return {
      'totalUsers': const AdminCountQuery('users'),
      'totalDrivers': const AdminCountQuery('users', field: 'accountType', equals: 'driver'),
      'totalTourists': const AdminCountQuery('users', field: 'accountType', equals: 'tourist'),
      'totalTrips': const AdminCountQuery('trip_posts'),
      'openTrips': const AdminCountQuery('trip_posts', field: 'status', equals: 'open'),
      'activeTrips': const AdminCountQuery('trip_posts', field: 'status', whereIn: AdminDashboardStats.activeStatuses),
      'completedTrips': const AdminCountQuery('trip_posts', field: 'status', equals: 'completed'),
      'openSupportRequests': const AdminCountQuery('support_requests', field: 'status', equals: 'open'),
    };
  }

  Future<AdminDashboardData> loadDashboard() async {
    final before = await readAccess();
    if (before.status != AdminAccessStatus.allowed) throw StateError('Admin access required.');
    final queries = overviewQueries();
    final counts = <String, int>{};
    List<SupportRequest> recent = [];
    await Future.wait<void>([
      ...queries.entries.map((entry) async {
        counts[entry.key] = await _dataSource.count(entry.value).timeout(const Duration(seconds: 20));
      }),
      (() async {
        recent = await _dataSource.loadSupport(orderBy: 'createdAt', descending: true,
          limit: 5, source: Source.server).timeout(const Duration(seconds: 20));
      })(),
    ]);
    final after = await readAccess();
    if (after.status != AdminAccessStatus.allowed || before.uid != after.uid) {
      throw StateError('Admin session changed.');
    }
    return AdminDashboardData(stats: AdminDashboardStats(
      totalUsers: counts['totalUsers']!, totalDrivers: counts['totalDrivers']!,
      totalTourists: counts['totalTourists']!, totalTrips: counts['totalTrips']!,
      openTrips: counts['openTrips']!, activeTrips: counts['activeTrips']!,
      completedTrips: counts['completedTrips']!, openSupportRequests: counts['openSupportRequests']!),
      recentSupport: recent);
  }
}
