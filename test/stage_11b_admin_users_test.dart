import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/admin_dashboard_stats.dart';
import 'package:taxi_app/core/models/admin_user_summary.dart';
import 'package:taxi_app/core/services/admin_service.dart';
import 'package:taxi_app/core/services/admin_user_data_source.dart';
import 'package:taxi_app/screens/admin/admin_dashboard_screen.dart';
import 'package:taxi_app/screens/admin/admin_users_screen.dart';
import 'package:taxi_app/screens/admin/admin_user_detail_screen.dart';

const _allowed = AdminAccess(AdminAccessStatus.allowed, uid: 'staff');
final _tourist = AdminUserSummary.fromMap('a', {
  'fullName': 'Amal Tourist', 'accountType': 'tourist', 'email': 'amal@example.com',
  'phoneNumber': '+94 77 123 4567', 'status': 'active', 'city': 'Kandy',
  'completedTripsCount': 12, 'cancelledTripsCount': 2, 'cancellationRate': 14.3,
  'averageRating': 4.5, 'ratingsCount': 8, 'verificationStatus': 'verified',
  'profilePhotoPath': 'profiles/a/photo.jpg',
  'createdAt': DateTime(2026, 1, 2, 10), 'updatedAt': DateTime(2026, 2, 3, 11),
});
final _driver = AdminUserSummary.fromMap('b', {
  'fullName': 'Bimal Driver', 'accountType': 'driver',
  'verification': {'status': 'pending'},
});

Future<void> _pump(WidgetTester tester) async {
  // Drain the finite gate, service pre/post authorization and widget futures.
  for (var i = 0; i < 8; i++) { await tester.pump(); }
}

void _expectReadOnly() {
  for (final label in ['Delete user', 'Reset password', 'Change account type',
    'Grant admin', 'Suspend account', 'Edit profile', 'Approve driver', 'Reject driver']) {
    expect(find.text(label, skipOffstage: false), findsNothing);
  }
  expect(find.byType(FloatingActionButton), findsNothing);
  expect(find.byType(PopupMenuButton<String>), findsNothing);
}

void main() {
  test('Optional fields tolerate absent, null and malformed legacy data', () {
    for (final data in <Map<String, dynamic>>[{}, {
      'uid': 'untrusted-field', 'fullName': null, 'email': 123, 'phoneNumber': [],
      'completedTripsCount': -1, 'cancelledTripsCount': 1.5, 'cancellationRate': double.nan,
      'averageRating': double.infinity, 'ratingsCount': '8', 'verification': false,
      'createdAt': 'invalid', 'updatedAt': null,
    }]) {
      final user = AdminUserSummary.fromMap('canonical-id', data);
      expect(user.uid, 'canonical-id');
      expect(user.displayName, 'Unnamed account');
      expect(user.accountTypeLabel, 'Unknown');
      expect(user.completedTripsCount, isNull);
      expect(user.cancelledTripsCount, isNull);
      expect(user.cancellationRateLabel, 'Not available');
      expect(user.averageRatingLabel, 'Not available');
      expect(user.ratingsCount, isNull);
      expect(user.createdAt, isNull);
      expect(user.updatedAt, isNull);
      expect(user.matchesSearch('someone'), isFalse);
    }
    expect(_driver.verificationStatus, 'pending');
    expect(AdminUserSummary.fromMap('zero', {'completedTripsCount': 0}).completedTripsCount, 0);
    final date = DateTime.utc(2026, 1, 1);
    expect(AdminUserSummary.fromMap('date', {'createdAt': Timestamp.fromDate(date)}).createdAt, date);
  });

  test('Firestore timestamps and legacy date values normalize to UTC without shifting the instant', () {
    final instant = DateTime.utc(2026, 1, 1, 0, 0, 0, 123, 456);
    final timestamp = Timestamp.fromDate(instant);
    for (final value in <Object>[
      timestamp, instant, instant.toLocal(),
      '2026-01-01T00:00:00.123456Z',
      '2026-01-01T05:30:00.123456+05:30',
      '2025-12-31T19:00:00.123456-05:00',
    ]) {
      final user = AdminUserSummary.fromMap('date', {'createdAt': value, 'updatedAt': value});
      for (final parsed in [user.createdAt, user.updatedAt]) {
        expect(parsed, instant, reason: '$value');
        expect(parsed!.isUtc, isTrue);
        expect(parsed.microsecondsSinceEpoch, timestamp.microsecondsSinceEpoch);
      }
    }
  });

  test('Zone-less legacy strings retain local-time semantics before UTC normalization', () {
    for (final entry in {
      '2026-01-01': DateTime(2026, 1, 1),
      ' 2026-01-01T05:30:00 ': DateTime(2026, 1, 1, 5, 30),
      '2024-02-29T12:00:00': DateTime(2024, 2, 29, 12),
    }.entries) {
      final parsed = AdminUserSummary.fromMap('date', {'createdAt': entry.key}).createdAt;
      expect(parsed, entry.value.toUtc());
      expect(parsed!.isUtc, isTrue);
    }
  });

  test('Missing, null, malformed and overflowing legacy dates are unavailable', () {
    expect(AdminUserSummary.fromMap('missing', {}).createdAt, isNull);
    expect(AdminUserSummary.fromMap('missing', {}).updatedAt, isNull);
    for (final value in <Object?>[
      null, '', '   ', 'invalid', 123, false, [], {},
      '2026-02-30T00:00:00Z', '2026-02-29', '2026-13-01', '2026-01-00',
      '2026-01-01T24:00:00Z', '2026-01-01T00:60:00Z',
      '2026-01-01T00:00:60Z', '2026-01-01T00:00:00+05:99',
    ]) {
      final user = AdminUserSummary.fromMap('date', {'createdAt': value, 'updatedAt': value});
      expect(user.createdAt, isNull, reason: '$value');
      expect(user.updatedAt, isNull, reason: '$value');
    }
  });

  test('Search is case insensitive and supports email and formatted phones', () {
    for (final text in [' AMAL ', 'EXAMPLE.COM', '+94 77', '771234567', '']) {
      expect(_tourist.matchesSearch(text), isTrue, reason: text);
    }
    expect(_tourist.matchesSearch('missing'), isFalse);
    expect(_tourist.matchesSearch('---'), isFalse);
  });

  for (final status in [AdminAccessStatus.signedOut, AdminAccessStatus.denied, AdminAccessStatus.error]) {
    test('Service rejects $status before both list and detail reads', () async {
      final db = _Users();
      final service = _Service(db)..access = AdminAccess(status);
      await expectLater(service.loadUsers(), throwsStateError);
      await expectLater(service.loadUser('a'), throwsStateError);
      expect(db.queries, isEmpty);
    });
    testWidgets('Both direct routes reject $status without private reads', (tester) async {
      final db = _Users();
      final service = _Service(db)..access = AdminAccess(status);
      await tester.pumpWidget(MaterialApp(home: AdminUsersScreen(service: service)));
      await _pump(tester);
      expect(find.text('Check access again'), findsOneWidget);
      expect(db.queries, isEmpty);
      await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(uid: 'a', service: service)));
      await _pump(tester);
      expect(find.text('Check access again'), findsOneWidget);
      expect(db.queries, isEmpty);
      expect(find.text('amal@example.com'), findsNothing);
    });
  }

  test('Production service uses bounded server queries, cursor and exact account types', () async {
    final db = _Users()..rows = List.generate(50, (i) => AdminUserSummary(uid: 'id-$i', accountType: 'driver'));
    final service = _Service(db);
    final page = await service.loadUsers(filter: AdminUserFilter.driver);
    expect(page.users.length, 50);
    expect(page.nextUid, 'id-49');
    final query = db.queries.single;
    expect(query.limit, 50);
    expect(query.accountType, 'driver');
    expect(query.orderBy, FieldPath.documentId);
    expect(query.source, Source.server);
    db.rows = [];
    final last = await service.loadUsers(filter: AdminUserFilter.driver, afterUid: page.nextUid);
    expect(last.nextUid, isNull);
    expect(db.queries.last.afterUid, 'id-49');
    await service.loadUsers(filter: AdminUserFilter.tourist);
    expect(db.queries.last.accountType, 'tourist');
    await service.loadUsers();
    expect(db.queries.last.accountType, isNull);
    db.rows = [_tourist];
    expect((await service.loadUser('a'))?.uid, 'a');
    expect(db.queries.last.uid, 'a');
    expect(db.queries.last.limit, 1);
    expect(db.queries.last.source, Source.server);
    db.rows = [];
    expect(await service.loadUser('missing'), isNull);
  });

  test('Session changes discard in-flight list and detail results', () async {
    for (final detail in [false, true]) {
      final db = _Users();
      final pending = Completer<List<AdminUserSummary>>();
      final started = Completer<void>();
      db.load = (_) { started.complete(); return pending.future; };
      final service = _Service(db);
      final future = detail ? service.loadUser('a') : service.loadUsers();
      final rejected = expectLater(future, throwsStateError);
      await started.future;
      service.access = const AdminAccess(AdminAccessStatus.allowed, uid: 'different-admin');
      pending.complete([_tourist]);
      await rejected;
    }
  });

  testWidgets('Admin opens management from the existing dashboard', (tester) async {
    final service = _Service(_Users());
    await tester.pumpWidget(MaterialApp(home: AdminDashboardScreen(service: service)));
    await _pump(tester);
    expect(find.text('Operations overview'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin_users_entry')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminUsersScreen), findsOneWidget);
    expect(find.text('Amal Tourist'), findsOneWidget);
    _expectReadOnly();
  });

  testWidgets('Loading is explicit and sign-out removes data before pending results', (tester) async {
    final changes = StreamController<AdminAccess>.broadcast(sync: true);
    final pending = Completer<List<AdminUserSummary>>();
    final db = _Users()..load = (_) => pending.future;
    final service = _Service(db)..changes = changes.stream;
    await tester.pumpWidget(MaterialApp(home: AdminUsersScreen(service: service)));
    changes.add(_allowed);
    await _pump(tester);
    expect(find.bySemanticsLabel('Loading accounts'), findsOneWidget);
    expect(find.text('Amal Tourist'), findsNothing);
    service.access = const AdminAccess(AdminAccessStatus.signedOut);
    changes.add(service.access);
    await _pump(tester);
    pending.complete([_tourist]);
    await _pump(tester);
    expect(find.text('Amal Tourist'), findsNothing);
    expect(find.text('Check access again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await changes.close();
  });

  testWidgets('List renders both types, all filters and scoped search work', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = _Users();
    await tester.pumpWidget(MaterialApp(home: AdminUsersScreen(service: _Service(db))));
    await _pump(tester);
    expect(find.text('Amal Tourist'), findsOneWidget);
    expect(find.text('Bimal Driver'), findsOneWidget);
    expect(find.text('Completed trips: 12'), findsOneWidget);
    expect(find.text('Cancelled trips: 2'), findsOneWidget);
    expect(find.text('Cancellation rate: 14.3%'), findsOneWidget);
    for (final filter in [AdminUserFilter.tourist, AdminUserFilter.driver, AdminUserFilter.all]) {
      await tester.tap(find.byKey(ValueKey('filter_${filter.name}')));
      await _pump(tester);
      expect(find.text('Amal Tourist'), filter == AdminUserFilter.driver ? findsNothing : findsOneWidget);
      expect(find.text('Bimal Driver'), filter == AdminUserFilter.tourist ? findsNothing : findsOneWidget);
    }
    for (final text in ['AMAL', 'example.com', '771234567']) {
      await tester.enterText(find.byType(TextField), text);
      await _pump(tester);
      expect(find.text('Amal Tourist'), findsOneWidget);
      expect(find.text('Bimal Driver'), findsNothing);
    }
    await tester.enterText(find.byType(TextField), 'no match');
    await _pump(tester);
    expect(find.text('No matching loaded accounts'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await _pump(tester);
    expect(find.text('Bimal Driver'), findsOneWidget);
    _expectReadOnly();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Filter change ignores an obsolete page response', (tester) async {
    final pending = Completer<List<AdminUserSummary>>();
    final db = _Users()..load = (query) => query.accountType == null
      ? pending.future : Future.value([_driver]);
    await tester.pumpWidget(MaterialApp(home: AdminUsersScreen(service: _Service(db))));
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('filter_driver')));
    await _pump(tester);
    pending.complete([_tourist]);
    await _pump(tester);
    expect(find.text('Amal Tourist'), findsNothing);
    expect(find.text('Bimal Driver'), findsOneWidget);
  });

  testWidgets('Pagination remains available during search and retries the same cursor', (tester) async {
    final db = _Users();
    var failNext = true;
    db.load = (query) async {
      if (query.afterUid == null) return List.generate(50, (i) => AdminUserSummary(uid: 'id-$i'));
      if (failNext) { failNext = false; throw StateError('private backend error'); }
      return [_tourist];
    };
    await tester.pumpWidget(MaterialApp(home: AdminUsersScreen(service: _Service(db))));
    await _pump(tester);
    await tester.enterText(find.byType(TextField), 'Amal');
    await _pump(tester);
    await tester.ensureVisible(find.text('Load more accounts'));
    await tester.tap(find.text('Load more accounts'));
    await _pump(tester);
    expect(find.text('private backend error'), findsNothing);
    await tester.ensureVisible(find.text('Retry accounts'));
    await tester.tap(find.text('Retry accounts'));
    await _pump(tester);
    expect(db.queries.last.afterUid, 'id-49');
    expect(find.text('Amal Tourist'), findsOneWidget);
    expect(find.text('1 matching · 51 loaded'), findsOneWidget);
  });

  testWidgets('Empty collection and initial read failure have distinct states', (tester) async {
    final db = _Users()..rows = [];
    await tester.pumpWidget(MaterialApp(home: AdminUsersScreen(service: _Service(db))));
    await _pump(tester);
    expect(find.text('No accounts found'), findsOneWidget);
    db.load = (_) async => throw StateError('sensitive diagnostics');
    await tester.tap(find.byTooltip('Refresh accounts'));
    await _pump(tester);
    expect(find.text('Retry accounts'), findsOneWidget);
    expect(find.text('No accounts found'), findsNothing);
    expect(find.text('sensitive diagnostics'), findsNothing);
    db.load = null;
    await tester.tap(find.text('Retry accounts'));
    await _pump(tester);
    expect(find.text('No accounts found'), findsOneWidget);
  });

  testWidgets('View account navigates to protected read-only details', (tester) async {
    final db = _Users()..rows = [_tourist];
    await tester.pumpWidget(MaterialApp(home: AdminUsersScreen(service: _Service(db))));
    await _pump(tester);
    final viewAccount = find.ancestor(
      of: find.text('View account'),
      matching: find.byWidgetPredicate((widget) => widget is TextButton),
    );
    expect(viewAccount, findsOneWidget);
    // A built card can still be outside the viewport. Reveal the actual button
    // and settle the resulting layout before checking its tap target.
    await tester.ensureVisible(viewAccount);
    await tester.pumpAndSettle();
    expect(viewAccount.hitTestable(), findsOneWidget);
    await tester.tap(viewAccount);
    await tester.pumpAndSettle();
    expect(find.byType(AdminUserDetailScreen), findsOneWidget);
    expect(db.queries.last.uid, 'a');
    _expectReadOnly();
  });

  for (final width in [360.0, 1400.0]) {
    testWidgets('Detail fields render at $width and contain no management actions', (tester) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(uid: 'a', service: _Service(_Users()))));
      await _pump(tester);
      for (final label in ['Full name', 'UID', 'Account type', 'Email', 'Phone number',
        'City', 'Status', 'Created', 'Updated', 'Completed trips', 'Cancelled trips',
        'Cancellation rate', 'Average rating', 'Rating count', 'Verification status',
        'Profile photo status', 'Profile photo path']) {
        await tester.ensureVisible(find.text(label));
        expect(find.text(label), findsOneWidget);
      }
      for (final value in ['a', 'Tourist/User', 'amal@example.com', '+94 77 123 4567',
        'Kandy', 'active', '12', '2', '14.3%', '4.5', '8', 'verified', 'profiles/a/photo.jpg']) {
        expect(find.text(value), findsOneWidget);
      }
      // Assert each actual date value beside its label, including the year and
      // local time, rather than counting a year substring anywhere in the tree.
      final format = MaterialLocalizations.of(tester.element(find.byType(AdminUserDetailScreen)));
      for (final entry in {'Created': _tourist.createdAt!, 'Updated': _tourist.updatedAt!}.entries) {
        final field = find.byWidgetPredicate((widget) => widget is Column &&
          widget.children.any((child) => child is Text && child.data == entry.key));
        final value = find.descendant(of: field, matching: find.byType(SelectableText));
        expect(value, findsOneWidget);
        await tester.ensureVisible(value);
        await tester.pump();
        final local = entry.value.toLocal();
        final expected = '${format.formatFullDate(local)} ${format.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
        expect(tester.widget<SelectableText>(value).data, expected);
        expect(tester.widget<SelectableText>(value).data, contains('2026'));
      }
      _expectReadOnly();
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Legacy list and detail tolerate all missing optional values', (tester) async {
    final db = _Users()..rows = [AdminUserSummary.fromMap('legacy', {'fullName': null})];
    final service = _Service(db);
    await tester.pumpWidget(MaterialApp(home: AdminUsersScreen(service: service)));
    await _pump(tester);
    expect(find.text('Unnamed account'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(uid: 'legacy', service: service)));
    await _pump(tester);
    expect(find.text('Not available'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Detail supports loading, safe failure, retry and missing account', (tester) async {
    final pending = Completer<List<AdminUserSummary>>();
    final db = _Users()..load = (_) => pending.future;
    await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(uid: 'a', service: _Service(db))));
    await _pump(tester);
    expect(find.bySemanticsLabel('Loading account details'), findsOneWidget);
    pending.completeError(StateError('private detail'));
    await _pump(tester);
    expect(find.text('Retry account'), findsOneWidget);
    expect(find.text('private detail'), findsNothing);
    final retry = Completer<List<AdminUserSummary>>();
    db.load = (_) => retry.future;
    await tester.tap(find.text('Retry account'));
    await _pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Loading account details'), findsOneWidget);
    expect(find.text('Retry account'), findsNothing);
    expect(db.queries.length, 2);
    retry.complete([]);
    await _pump(tester);
    expect(find.text('Account not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Detail retry can recover an account and refresh ignores an obsolete response', (tester) async {
    final db = _Users()..load = (_) async => throw StateError('initial failure');
    await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(uid: 'a', service: _Service(db))));
    await _pump(tester);
    db.load = null;
    await tester.tap(find.text('Retry account'));
    await _pump(tester);
    expect(find.text('amal@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final older = Completer<List<AdminUserSummary>>();
    final newer = Completer<List<AdminUserSummary>>();
    db.load = (_) => older.future;
    final refreshButton = find.descendant(
      of: find.byType(AdminUserDetailScreen),
      matching: find.widgetWithIcon(IconButton, Icons.refresh),
    );
    expect(refreshButton, findsOneWidget);
    final refresh = tester.widget<IconButton>(refreshButton).onPressed!;
    await tester.ensureVisible(refreshButton);
    await tester.pumpAndSettle();
    expect(refreshButton.hitTestable(), findsOneWidget);
    await tester.tap(refreshButton);
    await _pump(tester);
    expect(find.bySemanticsLabel('Loading account details'), findsOneWidget);
    expect(find.text('amal@example.com'), findsNothing);
    expect(tester.takeException(), isNull);

    // Simulate a queued refresh callback replacing the pending request. Keep the
    // real FutureBuilder and service so late-response protection is exercised.
    db.load = (_) => newer.future;
    refresh();
    await _pump(tester);
    newer.complete([const AdminUserSummary(uid: 'a', fullName: 'Latest account')]);
    await _pump(tester);
    expect(find.text('Latest account'), findsWidgets);
    older.complete([_tourist]);
    await _pump(tester);
    expect(find.text('Latest account'), findsWidgets);
    expect(find.text('amal@example.com'), findsNothing);
    expect(tester.takeException(), isNull);
    _expectReadOnly();
  });

  testWidgets('Detail completion after disposal does not update the departed route', (tester) async {
    final pending = Completer<List<AdminUserSummary>>();
    final db = _Users()..load = (_) => pending.future;
    await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(uid: 'a', service: _Service(db))));
    await _pump(tester);
    await tester.pumpWidget(const SizedBox());
    pending.complete([_tourist]);
    await _pump(tester);
    expect(find.text('amal@example.com'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Losing admin access removes already rendered private details', (tester) async {
    final changes = StreamController<AdminAccess>.broadcast(sync: true);
    final service = _Service(_Users())..changes = changes.stream;
    await tester.pumpWidget(MaterialApp(home: AdminUserDetailScreen(uid: 'a', service: service)));
    changes.add(_allowed);
    await _pump(tester);
    expect(find.text('amal@example.com'), findsOneWidget);
    service.access = const AdminAccess(AdminAccessStatus.denied);
    changes.add(service.access);
    await _pump(tester);
    expect(find.text('amal@example.com'), findsNothing);
    expect(find.text('Check access again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await changes.close();
  });
}

/// Retains production service authorization, query construction and pagination.
class _Service extends AdminService {
  _Service(AdminUserDataSource db) : super(userDataSource: db);
  AdminAccess access = _allowed;
  Stream<AdminAccess>? changes;
  @override
  Future<AdminAccess> readAccess({bool forceRefresh = false}) async => access;
  @override
  Stream<AdminAccess> watchAccess() => changes ?? Stream.value(access);
  @override
  Future<AdminDashboardData> loadDashboard() async => const AdminDashboardData(
    stats: AdminDashboardStats(totalUsers: 2, totalDrivers: 1, totalTourists: 1,
      totalTrips: 0, openTrips: 0, activeTrips: 0, completedTrips: 0, openSupportRequests: 0),
    recentSupport: []);
}

class _Users implements AdminUserDataSource {
  List<AdminUserSummary> rows = [_tourist, _driver];
  final queries = <AdminUserQuery>[];
  Future<List<AdminUserSummary>> Function(AdminUserQuery)? load;
  @override
  Future<List<AdminUserSummary>> loadUsers(AdminUserQuery query) async {
    queries.add(query);
    if (load != null) return load!(query);
    return rows.where((user) => (query.accountType == null || user.accountType == query.accountType) &&
      (query.uid == null || user.uid == query.uid)).take(query.limit).toList();
  }
}
