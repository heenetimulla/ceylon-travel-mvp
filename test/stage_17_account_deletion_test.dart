import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/driver_administration.dart';
import 'package:taxi_app/core/models/registration_application.dart';
import 'package:taxi_app/core/services/account_deletion_service.dart';
import 'package:taxi_app/core/services/admin_service.dart';
import 'package:taxi_app/core/services/auth_service.dart';
import 'package:taxi_app/screens/admin/admin_deletion_requests_screen.dart';
import 'package:taxi_app/screens/auth/account_deletion_screen.dart';
import 'package:taxi_app/screens/auth/registration_application_screen.dart';
import 'package:taxi_app/screens/auth/session_navigation.dart';

typedef Data = Map<String, dynamic>;

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 180, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pump();
}

void main() {
  late _Store store;
  late _Auth auth;
  late _User user;
  late AccountDeletionService service;
  setUp(() {
    store = _Store();
    user = _User('owner');
    auth = _Auth(user);
    service = AccountDeletionService(firestore: store, auth: auth);
  });
  tearDown(() async {
    await auth.changes.close();
    await store.changes.close();
  });

  test('submission reauthenticates and refreshes token before creating own pending request', () async {
    await service.submit('owner', 'password', ' Optional reason ');
    expect(user.events, ['reauthenticate', 'refresh']);
    expect(store.writes.single.$1, 'account_deletion_requests/owner');
    expect(store.writes.single.$2, containsPair('requesterUid', 'owner'));
    expect(store.writes.single.$2, containsPair('status', 'pending'));
    expect(store.writes.single.$2, containsPair('reason', 'Optional reason'));
    expect(store.writes.single.$2['reviewedBy'], isNull);
    expect(store.writes.single.$2['completionAt'], isNull);
  });
  test('wrong password, switched session and another UID cannot submit', () async {
    user.failReauthentication = true;
    await expectLater(service.submit('owner', 'wrong', ''), throwsA(isA<AuthServiceException>()));
    expect(store.writes, isEmpty);
    user.failReauthentication = false;
    user.afterReauthentication = () { auth.currentUser = _User('other'); };
    await expectLater(service.submit('owner', 'password', ''), throwsA(isA<AuthServiceException>()));
    expect(store.writes, isEmpty);
    await expectLater(service.submit('owner', 'password', ''), throwsStateError);
    expect(store.writes, isEmpty);
  });
  for (final status in ['pending', 'approved', 'completed']) {
    test('existing $status request cannot be replaced by submission', () async {
      store.records['account_deletion_requests/owner'] = {'status': status, 'revision': 2};
      await expectLater(service.submit('owner', 'password', ''), throwsStateError);
      expect(store.writes, isEmpty);
      expect(store.records['account_deletion_requests/owner']!['status'], status);
    });
  }
  test('support-only staff and self-review cannot enqueue privileged commands', () async {
    for (final action in ['approve', 'reject', 'request_clarification', 'complete']) {
      auth.currentUser = _User('support', claims: {'supportAdmin': true});
      await expectLater(service.review('owner', 1, action, '', 'Explanation'), throwsStateError);
      auth.currentUser = _User('owner', claims: {'admin': true});
      await expectLater(service.review('owner', 1, action, '', 'Explanation'), throwsStateError);
    }
    expect(store.writes, isEmpty);
  });
  test('primary admin enqueues review without directly approving the request', () async {
    auth.currentUser = _User('admin', claims: {'admin': true});
    store.records['account_deletion_requests/owner'] = {'status': 'pending', 'revision': 1};
    await service.review('owner', 1, 'approve', 'Private note', '');
    expect(store.writes.single.$1, startsWith('account_deletion_requests/owner/operations/'));
    expect(store.writes.single.$2, containsPair('actorUid', 'admin'));
    expect(store.writes.single.$2, containsPair('action', 'approve'));
    expect(store.writes.single.$2, containsPair('status', 'pending'));
    expect(store.records['account_deletion_requests/owner']!['status'], 'pending');
  });
  testWidgets('user must explicitly confirm before submission and sees pending status', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AccountDeletionScreen(service: service)));
    await _pump(tester);
    expect(find.text('Delete Account'), findsOneWidget);
    final submit = find.widgetWithText(FilledButton, 'Request account deletion');
    await _reveal(tester, submit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    expect(user.events, isEmpty);
    expect(store.writes, isEmpty);
    final password = find.byWidgetPredicate((w) => w is TextField && w.obscureText);
    await _reveal(tester, password);
    await tester.enterText(password, 'password');
    await _reveal(tester, find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await _reveal(tester, submit);
    await tester.tap(submit);
    await _pump(tester);
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await _pump(tester);
    expect(find.text(deletionStatusLabel('pending')), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Request account deletion'), findsNothing);
    expect(store.writes, hasLength(1));
    expect(user.events, ['reauthenticate', 'refresh']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('signed-out direct deletion entry cannot expose a submission form', (tester) async {
    auth.currentUser = null;
    await tester.pumpWidget(MaterialApp(home: AccountDeletionScreen(service: service)));
    await _pump(tester);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(store.reads, 0);
    await tester.pumpWidget(const SizedBox());
  });
  for (final status in ['pending', 'approved', 'completed']) {
    testWidgets('$status status hides duplicate request controls', (tester) async {
      store.records['account_deletion_requests/owner'] = {'status': status, 'revision': 1};
      await tester.pumpWidget(MaterialApp(home: AccountDeletionScreen(service: service)));
      await _pump(tester);
      expect(find.text(deletionStatusLabel(status)), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(store.writes, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('support-only direct admin route never loads deletion queue or controls', (tester) async {
    auth.currentUser = _User('support', claims: {'supportAdmin': true});
    await tester.pumpWidget(MaterialApp(home: AdminDeletionRequestsScreen(
      admin: AdminService(firebaseAuth: auth), service: service)));
    await _pump(tester);
    expect(find.text('Access denied. An administrator account is required.'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Complete after trusted cleanup'), findsNothing);
    expect(store.reads, 0);
    expect(store.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('primary admin can navigate queue and see pending review controls', (tester) async {
    auth.currentUser = _User('admin', claims: {'admin': true});
    store.records['account_deletion_requests/owner'] = {
      'requesterUid': 'owner', 'status': 'pending', 'revision': 1, 'reason': '',
    };
    await tester.pumpWidget(MaterialApp(home: AdminDeletionRequestsScreen(
      admin: AdminService(firebaseAuth: auth), service: service)));
    await _pump(tester);
    await tester.tap(find.text('Account: owner'));
    await tester.pumpAndSettle();
    await _reveal(tester, find.widgetWithText(FilledButton, 'Approve'));
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);
    expect(find.text('Request clarification'), findsOneWidget);
    expect(store.writes, isEmpty);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(find.text('Approve account deletion?'), findsOneWidget);
    expect(store.writes, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(store.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('even a primary admin cannot see completion controls on their own request', (tester) async {
    auth.currentUser = _User('owner', claims: {'admin': true});
    store.records['account_deletion_requests/owner'] = {
      'requesterUid': 'owner', 'status': 'approved', 'processingStage': 'manual_cleanup_required', 'revision': 2,
    };
    await tester.pumpWidget(MaterialApp(home: AdminDeletionRequestsScreen(
      admin: AdminService(firebaseAuth: auth), service: service)));
    await _pump(tester);
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(deletionStatusLabel('approved')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account: owner'));
    await tester.pumpAndSettle();
    expect(find.text('Complete after trusted cleanup'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(store.writes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  test('approved/completed deletion profile never routes to operational dashboards', () {
    for (final type in ['tourist', 'driver']) {
      for (final deletionStatus in ['approved', 'completed']) {
        final profile = <String, dynamic>{
          'accountType': type, 'status': 'blocked', 'accountStatus': 'deleted',
          'registrationStatus': 'deleted', 'deletionStatus': deletionStatus,
          'membershipStatus': 'inactive', 'identityVerificationStatus': 'not_verified',
          'paymentStatus': 'verified', 'membershipPlan': 'founding_lifetime',
        };
        expect(applicationOperational(profile), isFalse);
        expect(driverCanBid(profile), isFalse);
        expect(sessionDestination('owner', profile), isA<RegistrationApplicationScreen>());
      }
    }
  });
}

// Test doubles exercise Flutter boundaries, not backend rules or cleanup behavior.
class _Auth implements FirebaseAuth {
  _Auth(this.currentUser);
  @override
  User? currentUser;
  final changes = StreamController<User?>.broadcast();
  @override
  Stream<User?> authStateChanges() async* { yield currentUser; yield* changes.stream; }
  @override
  Stream<User?> idTokenChanges() => authStateChanges();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _User implements User {
  _User(this.uid, {this.claims = const {}});
  @override
  final String uid;
  final Data claims;
  final events = <String>[];
  bool failReauthentication = false;
  void Function()? afterReauthentication;
  @override
  String get email => 'owner@example.test';
  @override
  List<UserInfo> get providerData => [_Provider()];
  @override
  Future<UserCredential> reauthenticateWithCredential(AuthCredential credential) async {
    events.add('reauthenticate');
    expect(credential.providerId, 'password');
    if (failReauthentication) { throw FirebaseAuthException(code: 'wrong-password'); }
    afterReauthentication?.call();
    return _Credential();
  }
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async {
    if (forceRefresh) { events.add('refresh'); }
    return _Token(claims);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Provider implements UserInfo {
  @override
  String get providerId => 'password';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Credential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Token implements IdTokenResult {
  _Token(this.claims);
  @override
  final Data claims;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Store implements FirebaseFirestore {
  final records = <String, Data>{};
  final writes = <(String, Data)>[];
  final changes = StreamController<void>.broadcast();
  int reads = 0, sequence = 0;
  @override
  CollectionReference<Data> collection(String path) => _Collection(this, path);
  @override
  Future<T> runTransaction<T>(TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30), int maxAttempts = 5,
  }) async {
    final tx = _Transaction(this);
    final result = await transactionHandler(tx);
    for (final entry in tx.pending) { save(entry.$1, entry.$2); }
    return result;
  }
  void save(String path, Data data) {
    writes.add((path, Map.of(data)));
    records[path] = Map.of(data);
    changes.add(null);
  }
  Stream<DocumentSnapshot<Data>> watch(String path) async* {
    reads++;
    yield _Snapshot(path, records[path]);
    await for (final _ in changes.stream) { yield _Snapshot(path, records[path]); }
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Transaction implements Transaction {
  _Transaction(this.store);
  final _Store store;
  final pending = <(String, Data)>[];
  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(DocumentReference<T> documentReference) async =>
    _Snapshot(documentReference.path, store.records[documentReference.path]) as DocumentSnapshot<T>;
  @override
  Transaction set<T>(DocumentReference<T> documentReference, T data, [SetOptions? options]) {
    pending.add((documentReference.path, Map<String, dynamic>.from(data as Map)));
    return this;
  }
  @override
  Transaction update(DocumentReference documentReference, Map<Object, Object?> data) {
    pending.add((documentReference.path, {
      ...store.records[documentReference.path]!, ...data.map((key, value) => MapEntry(key as String, value)),
    }));
    return this;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Doc implements DocumentReference<Data> {
  _Doc(this.store, this.path);
  final _Store store;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  CollectionReference<Data> collection(String collectionPath) => _Collection(store, '$path/$collectionPath');
  @override
  Future<void> set(Data data, [SetOptions? options]) async {
    store.save(path, data);
    // Simulated worker acknowledgement only; no request state is changed by the fake.
    if (path.contains('/operations/')) { store.records[path] = {...data, 'status': 'succeeded'}; }
  }
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #snapshots) { return store.watch(path); }
    return super.noSuchMethod(invocation);
  }
}
class _Snapshot implements DocumentSnapshot<Data> {
  _Snapshot(this.path, this.value);
  final String path;
  final Data? value;
  @override
  String get id => path.split('/').last;
  @override
  bool get exists => value != null;
  @override
  Data? data() => value == null ? null : Map.of(value!);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _QueryDoc extends _Snapshot implements QueryDocumentSnapshot<Data> {
  _QueryDoc(String path, Data value) : super(path, value);
  @override
  Data data() => Map.of(value!);
}
class _QuerySnapshot implements QuerySnapshot<Data> {
  _QuerySnapshot(this.docs);
  @override
  final List<QueryDocumentSnapshot<Data>> docs;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _Collection implements CollectionReference<Data> {
  _Collection(this.store, this.path, [this.status]);
  final _Store store;
  @override
  final String path;
  final String? status;
  @override
  DocumentReference<Data> doc([String? path]) => _Doc(store, '${this.path}/${path ?? 'op${++store.sequence}'}');
  Stream<QuerySnapshot<Data>> watch() async* {
    store.reads++;
    yield _QuerySnapshot([
      for (final entry in store.records.entries)
        if (entry.key.startsWith('$path/') && entry.key.split('/').length == path.split('/').length + 1 &&
            (status == null || entry.value['status'] == status))
          _QueryDoc(entry.key, entry.value),
    ]);
  }
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #where) {
      return _Collection(store, path, invocation.namedArguments[#isEqualTo] as String?);
    }
    if ([#orderBy, #limit, #startAfterDocument].contains(invocation.memberName)) { return this; }
    if (invocation.memberName == #snapshots) { return watch(); }
    return super.noSuchMethod(invocation);
  }
}
