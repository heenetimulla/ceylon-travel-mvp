import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/admin_dashboard_stats.dart';
import 'package:taxi_app/core/models/support_request.dart';
import 'package:taxi_app/core/services/admin_service.dart';
import 'package:taxi_app/core/services/admin_data_source.dart';
import 'package:taxi_app/core/widgets/admin_stat_card.dart';
import 'package:taxi_app/screens/admin/admin_dashboard_screen.dart';

const stats = AdminDashboardStats(totalUsers: 6, totalDrivers: 3, totalTourists: 2,
  totalTrips: 10, openTrips: 2, activeTrips: 4, completedTrips: 3, openSupportRequests: 2);
final preview = SupportRequest(id: 'support-1', supportReference: 'SUP-260911-ABC234',
  userId: 'request-owner', userRole: 'tourist', userName: 'Customer', contactNumber: '+94771234567',
  category: 'question', subject: 'Help', message: 'A question', status: 'open',
  createdAt: DateTime.utc(2026, 9, 11, 12), lastMessageAt: DateTime.utc(2026, 9, 11, 13));

Future<void> pumpAdmin(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  test('Only boolean admin custom claim authorizes; supportAdmin and profile-like roles do not', () {
    for (final claims in [null, <String, dynamic>{}, {'admin': false}, {'admin': 'true'},
      {'supportAdmin': true}, {'accountType': 'admin'}]) {
      expect(AdminService.hasAdminClaim(claims), isFalse);
    }
    expect(AdminService.hasAdminClaim({'admin': true}), isTrue);
  });

  test('Signed out, non-admin, admin and token errors fail closed as appropriate', () async {
    final auth = _Auth();
    final service = AdminService(firebaseAuth: auth);
    expect((await service.readAccess()).status, AdminAccessStatus.signedOut);
    auth.currentUser = _User('normal', {});
    expect((await service.readAccess()).status, AdminAccessStatus.denied);
    auth.currentUser = _User('admin', {'admin': true});
    expect((await service.readAccess()).status, AdminAccessStatus.allowed);
    auth.currentUser = _User('admin', {'admin': true}, fail: true);
    expect((await service.readAccess()).status, AdminAccessStatus.error);
  });

  test('Non-admin cannot trigger overview reads', () async {
    final db = _DataSource();
    await expectLater(AdminService(firebaseAuth: _Auth(), dataSource: db).loadDashboard(), throwsStateError);
    expect(db.reads, 0);
    await expectLater(AdminService(firebaseAuth: _Auth()..currentUser = _User('normal', {}),
      dataSource: db).loadDashboard(), throwsStateError);
    expect(db.reads, 0);
  });

  test('Token result from an old signed-in user cannot authorize a new session', () async {
    final pending = Completer<IdTokenResult>();
    final auth = _Auth()..currentUser = _User('old-admin', {'admin': true}, token: pending.future);
    final result = AdminService(firebaseAuth: auth).readAccess();
    auth.currentUser = _User('normal', {});
    pending.complete(_Token({'admin': true}));
    expect((await result).status, AdminAccessStatus.denied);
  });

  test('Authorization watcher clears access and ignores an obsolete claim result', () async {
    final changes = StreamController<User?>.broadcast(sync: true);
    final pending = Completer<AdminAccess>();
    final auth = _Auth()..changes = changes.stream;
    final service = _PendingClaimService(auth, pending.future);
    final events = StreamIterator(service.watchAccess());
    Future<void> expectNext(AdminAccessStatus status) async {
      expect(await events.moveNext(), isTrue);
      expect(events.current.status, status);
    }
    try {
      // StreamIterator is lazy: moveNext installs the watcher/auth subscription.
      // A broadcast event sent before this point would be dropped permanently.
      final firstEvent = events.moveNext();
      expect(changes.hasListener, isTrue);
      auth.currentUser = _User('admin', {'admin': true});
      changes.add(auth.currentUser);
      expect(await firstEvent, isTrue);
      expect(events.current.status, AdminAccessStatus.loading);
      expect(service.reads, 1);
      auth.currentUser = null;
      changes.add(null);
      await expectNext(AdminAccessStatus.loading);
      await expectNext(AdminAccessStatus.signedOut);

      // The watcher already awaits this exact future. Its continuation runs
      // before ours; resolving it must not publish an obsolete allowed state.
      pending.complete(const AdminAccess(AdminAccessStatus.allowed, uid: 'admin'));
      await pending.future;
      // A second signed-out event is a delivery barrier. Any stale result would
      // be queued ahead of it and fail these exact next-event expectations.
      changes.add(null);
      await expectNext(AdminAccessStatus.loading);
      await expectNext(AdminAccessStatus.signedOut);
      expect(service.reads, 1);
    } finally {
      if (!pending.isCompleted) pending.complete(const AdminAccess(AdminAccessStatus.denied));
      // Resolve the fake lookup before cancelling the watcher or closing auth.
      await pending.future;
      await events.cancel();
      await changes.close();
    }
  });

  test('Service query definitions count exact account types/statuses and limit server support preview', () async {
    final db = _DataSource();
    final service = AdminService(firebaseAuth: _Auth()..currentUser = _User('admin', {'admin': true}), dataSource: db);
    final data = await service.loadDashboard();
    expect(data.stats.cards, stats.cards);
    expect(data.recentSupport.single.supportReference, preview.supportReference);
    expect(db.reads, 9); // Eight count aggregations and one five-document preview.
    expect(db.previewLimit, 5);
    expect(db.previewOrder, ['createdAt', true]);
    expect(db.previewSource, Source.server);
    expect(AdminDashboardStats.activeStatuses,
      ['accepted', 'start_requested', 'in_progress', 'end_requested']);
  });

  testWidgets('Admin navigation is hidden for signed out/non-admin/errors and visible for admin', (tester) async {
    for (final status in [AdminAccessStatus.signedOut, AdminAccessStatus.denied, AdminAccessStatus.error,
      AdminAccessStatus.loading, AdminAccessStatus.allowed]) {
      final service = _UiService(Stream.value(AdminAccess(status, uid: 'admin')));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminDashboardEntry(key: ValueKey(status), service: service))));
      await pumpAdmin(tester);
      expect(find.byKey(const Key('admin_dashboard_entry')),
        status == AdminAccessStatus.allowed ? findsOneWidget : findsNothing);
      expect(service.loads, 0);
    }
  });

  for (final status in [AdminAccessStatus.signedOut, AdminAccessStatus.denied, AdminAccessStatus.error]) {
    testWidgets('Direct admin screen rejects $status without loading data', (tester) async {
      final service = _UiService(Stream.value(AdminAccess(status)));
      await tester.pumpWidget(MaterialApp(home: AdminDashboardScreen(service: service)));
      await pumpAdmin(tester);
      expect(service.loads, 0);
      expect(find.byType(AdminStatCard), findsNothing);
      expect(find.text('Check access again'), findsOneWidget);
    });
  }

  testWidgets('Authorization and overview loading states do not show fabricated counts', (tester) async {
    final access = StreamController<AdminAccess>.broadcast(sync: true);
    final result = Completer<AdminDashboardData>();
    final service = _UiService(access.stream, load: () => result.future);
    Future<void> cleanup() async {
      await tester.pumpWidget(const SizedBox());
      if (!result.isCompleted) result.complete(const AdminDashboardData(stats: stats, recentSupport: []));
      final closed = access.close();
      await pumpAdmin(tester);
      await closed;
    }
    try {
      await tester.pumpWidget(MaterialApp(home: AdminDashboardScreen(service: service)));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(service.loads, 0);
      access.add(const AdminAccess(AdminAccessStatus.allowed, uid: 'admin'));
      await pumpAdmin(tester);
      expect(service.loads, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AdminStatCard), findsNothing);
      result.complete(const AdminDashboardData(stats: stats, recentSupport: []));
      await pumpAdmin(tester);
      expect(find.byType(AdminStatCard), findsWidgets);
      access.add(const AdminAccess(AdminAccessStatus.signedOut));
      await pumpAdmin(tester);
      expect(find.byType(AdminStatCard), findsNothing);
    } finally {
      await cleanup();
    }
  });

  for (final width in [360.0, 1400.0]) {
    testWidgets('Overview stats, support snapshot and responsive layout at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = _UiService(Stream.value(const AdminAccess(AdminAccessStatus.allowed, uid: 'admin')),
        load: () async => AdminDashboardData(stats: stats, recentSupport: [preview]));
      await tester.pumpWidget(MaterialApp(home: AdminDashboardScreen(service: service)));
      await pumpAdmin(tester);
      for (final entry in stats.cards.entries) {
        final card = find.byWidgetPredicate((widget) => widget is AdminStatCard && widget.label == entry.key);
        await tester.scrollUntilVisible(card, 250, scrollable: find.byType(Scrollable).first);
        final widget = tester.widget<AdminStatCard>(card);
        expect(widget.value, entry.value);
        expect(tester.getSize(card).width, lessThanOrEqualTo(width));
      }
      await tester.scrollUntilVisible(find.text(preview.supportReference), 250, scrollable: find.byType(Scrollable).first);
      expect(find.text('Ask a Question'), findsOneWidget);
      expect(find.text('User ID: request-owner'), findsOneWidget);
      expect(find.text('Contact: +94771234567'), findsOneWidget);
      expect(find.textContaining('Last message:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Empty support preview and load failure are explicit', (tester) async {
    final service = _UiService(Stream.value(const AdminAccess(AdminAccessStatus.allowed, uid: 'admin')));
    await tester.pumpWidget(MaterialApp(home: AdminDashboardScreen(service: service)));
    await pumpAdmin(tester);
    await tester.scrollUntilVisible(find.text('No support requests yet'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('No support requests yet'), findsOneWidget);
    final failed = _UiService(Stream.value(const AdminAccess(AdminAccessStatus.allowed, uid: 'admin')),
      load: () async => throw StateError('private error'));
    await tester.pumpWidget(MaterialApp(home: AdminDashboardScreen(key: const Key('failed'), service: failed)));
    await pumpAdmin(tester);
    expect(find.text('Retry overview'), findsOneWidget);
    expect(find.text('private error'), findsNothing);
    expect(find.byType(AdminStatCard), findsNothing);
  });
}

class _UiService extends AdminService {
  _UiService(this.access, {this.load});
  final Stream<AdminAccess> access;
  final Future<AdminDashboardData> Function()? load;
  int loads = 0;
  @override
  Stream<AdminAccess> watchAccess() => access;
  @override
  Future<AdminDashboardData> loadDashboard() async {
    loads++;
    return load == null ? const AdminDashboardData(stats: stats, recentSupport: []) : await load!();
  }
}

// Retain the production watcher/generation guard; control only the claim read.
class _PendingClaimService extends AdminService {
  _PendingClaimService(FirebaseAuth auth, this.result) : super(firebaseAuth: auth);
  final Future<AdminAccess> result;
  int reads = 0;
  @override
  Future<AdminAccess> readAccess({bool forceRefresh = false}) {
    reads++;
    return result;
  }
}

class _Auth implements FirebaseAuth {
  @override
  User? currentUser;
  Stream<User?> changes = const Stream.empty();
  @override
  Stream<User?> idTokenChanges() => changes;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _User implements User {
  _User(this.uid, this.claims, {this.fail = false, this.token});
  @override
  final String uid;
  final Map<String, dynamic> claims;
  final bool fail;
  final Future<IdTokenResult>? token;
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    if (fail) throw StateError('Token read failed');
    return token == null ? _Token(claims) : await token!;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Token implements IdTokenResult {
  _Token(this.claims);
  @override
  final Map<String, dynamic> claims;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Pure Dart data-source fake exercises the service's query definitions/counts.
// Firebase SDK classes are not subclassed; rules/network behavior remains manual.
class _DataSource implements AdminDataSource {
  int reads = 0;
  int? previewLimit;
  List<Object>? previewOrder;
  Source? previewSource;
  final rows = <String, List<Map<String, dynamic>>>{
    'users': [for (final type in ['driver', 'driver', 'driver', 'tourist', 'tourist', 'legacy']) {'accountType': type}],
    'trip_posts': [for (final status in ['open', 'open', 'accepted', 'start_requested', 'in_progress',
      'end_requested', 'completed', 'completed', 'completed', 'cancelled']) {'status': status}],
    'support_requests': [for (final status in ['open', 'open', 'in_review', 'resolved']) {'status': status}],
  };
  @override
  Future<int> count(AdminCountQuery query) async {
    reads++;
    final documents = rows[query.collection]!;
    if (query.field == null) return documents.length;
    return documents.where((row) => query.whereIn == null
      ? row[query.field] == query.equals : query.whereIn!.contains(row[query.field])).length;
  }

  @override
  Future<List<SupportRequest>> loadSupport({required String orderBy,
    required bool descending, required int limit, required Source source}) async {
    reads++;
    previewOrder = [orderBy, descending];
    previewLimit = limit;
    previewSource = source;
    return [preview];
  }
}
