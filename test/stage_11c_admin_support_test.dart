import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taxi_app/core/models/admin_dashboard_stats.dart';
import 'package:taxi_app/core/models/admin_support_data.dart';
import 'package:taxi_app/core/models/support_message.dart';
import 'package:taxi_app/core/models/support_request.dart';
import 'package:taxi_app/core/services/admin_service.dart';
import 'package:taxi_app/core/services/admin_support_data_source.dart';
import 'package:taxi_app/core/services/admin_support_service.dart';
import 'package:taxi_app/screens/admin/admin_dashboard_screen.dart';
import 'package:taxi_app/screens/admin/admin_support_inbox_screen.dart';
import 'package:taxi_app/screens/admin/admin_support_detail_screen.dart';

const _staff = AdminAccess(AdminAccessStatus.allowed, uid: 'staff-uid');
SupportRequest _request(String id, String status, {bool trip = false}) => SupportRequest(
  id: id, supportReference: 'SUP-260918-$id', userId: 'requester', userName: 'Amal', userRole: 'driver',
  category: trip ? 'complaint' : 'question', subCategory: trip ? 'payment_incomplete' : null,
  contactNumber: '+94 77 123 4567', tripReference: trip ? 'CT-260918-ABC234' : null,
  subject: 'Please help $id', message: 'Original request $id', status: status,
  createdAt: DateTime.utc(2026, 9, 18), updatedAt: DateTime.utc(2026, 9, 18, 1),
  lastMessageAt: DateTime.utc(2026, 9, 18, 2));
final _original = _request('ABC234', 'open', trip: true);
const _oldMessage = SupportMessage(id: 'old', senderId: 'requester', senderRole: 'user', message: 'Earlier reply');

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) { await tester.pump(); }
}
Future<void> _reveal(WidgetTester tester, Finder target, {double delta = 250}) async {
  final scroll = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;
  await tester.scrollUntilVisible(target, delta, scrollable: scroll, maxScrolls: 60);
  await tester.ensureVisible(target);
  await tester.pump();
}
void _noManagement() {
  for (final text in ['Edit message', 'Delete message', 'Delete request', 'Suspend account', 'Grant admin', 'Approve driver']) {
    expect(find.text(text, skipOffstage: false), findsNothing);
  }
}

void main() {
  test('Only the boolean supportAdmin claim grants staff access', () async {
    final auth = _Auth();
    final service = AdminSupportService(firebaseAuth: auth, dataSource: _Data());
    expect((await service.readAccess()).status, AdminAccessStatus.signedOut);
    for (final claims in <Map<String, dynamic>>[{}, {'admin': true}, {'supportAdmin': 'true'},
      {'supportAdmin': false}, {'accountType': 'admin'}]) {
      auth.currentUser = _User(claims);
      expect((await service.readAccess()).status, AdminAccessStatus.denied);
    }
    for (final claims in [{'supportAdmin': true}, {'admin': true, 'supportAdmin': true}]) {
      auth.currentUser = _User(claims);
      expect((await service.readAccess()).status, AdminAccessStatus.allowed);
    }
  });

  test('Denied service cannot read, reply or update status', () async {
    final db = _Data();
    final service = _Service(db)..access = const AdminAccess(AdminAccessStatus.denied);
    await expectLater(service.loadRequests(), throwsStateError);
    await expectLater(service.loadDetail('ABC234'), throwsStateError);
    await expectLater(service.reply('ABC234', 'Reply', operationId: 'op'), throwsStateError);
    await expectLater(service.changeStatus('ABC234', 'open', 'closed', operationId: 'op'), throwsStateError);
    expect(db.reads, 0); expect(db.replies, isEmpty); expect(db.transitions, isEmpty);
  });

  test('Reply uses authenticated UID, existing schema and only append/parent metadata payloads', () async {
    final db = _Data();
    await _Service(db).reply('ABC234', '  Staff response  ', operationId: 'new');
    expect(db.replies.single, ['ABC234', 'new', 'staff-uid', 'Staff response']);
    final message = SupportStaffWrites.reply('new', 'staff-uid', 'Staff response');
    expect(message.keys.toSet(), {'id', 'senderId', 'senderRole', 'message', 'createdAt'});
    expect(message['senderRole'], 'admin'); expect(message['senderId'], 'staff-uid');
    expect(message['createdAt'], isA<FieldValue>());
    final before = {..._original.toFirestore(), 'lastMessageId': 'old'};
    final after = {...before, ...SupportStaffWrites.replyParent('new')};
    expect(SupportStaffWrites.replyParent('new').keys.toSet(), {'updatedAt', 'lastMessageAt', 'lastMessageId'});
    for (final key in ['id', 'userId', 'supportReference', 'contactNumber', 'category', 'tripReference', 'message', 'status']) {
      expect(after[key], before[key]);
    }
    expect(_oldMessage.message, 'Earlier reply');
  });

  test('Status whitelist and audit payload preserve immutable request fields', () async {
    final db = _Data(), service = _Service(_Data());
    final allowed = _Service(db);
    for (final status in ['in_review', 'resolved', 'closed']) {
      await allowed.changeStatus('ABC234', 'open', status, operationId: status);
    }
    expect(db.transitions.length, 3);
    for (final status in ['in_progress', 'suspended', 'deleted', 'open']) {
      await expectLater(service.changeStatus('ABC234', 'open', status, operationId: 'bad'), throwsArgumentError);
    }
    await expectLater(service.reply('ABC234', '   ', operationId: 'bad'), throwsArgumentError);
    await expectLater(service.reply('ABC234', List.filled(4001, 'a').join(), operationId: 'bad'), throwsArgumentError);
    final update = SupportStaffWrites.statusParent('event', 'in_review');
    expect(update.keys.toSet(), {'status', 'updatedAt', 'lastStatusEventId'});
    final before = _original.toFirestore(), after = {..._original.toFirestore(), ...update};
    for (final key in before.keys.where((key) => !['status', 'updatedAt'].contains(key))) {
      expect(after[key], before[key]);
    }
    final event = SupportStaffWrites.event('event', 'staff-uid', 'open', 'in_review');
    expect(event.keys.toSet(), {'id', 'actorId', 'fromStatus', 'toStatus', 'createdAt'});
    expect(event['actorId'], 'staff-uid'); expect(event['fromStatus'], 'open');
    expect(event['toStatus'], 'in_review'); expect(event['createdAt'], isA<FieldValue>());
  });

  test('Bounded query definitions retain filter/cursor and stale reads are rejected', () async {
    final db = _Data(), cursor = SupportCursor(Timestamp(10, 5), 'tie-id');
    final service = _Service(db);
    await service.loadRequests(filter: SupportInboxFilter.completed, cursor: cursor);
    expect(db.queries.single.filter.statuses, ['resolved', 'closed']);
    expect(db.queries.single.cursor, same(cursor)); expect(SupportReadQuery.pageSize, 50);
    final pending = Completer<SupportPage<SupportRequest>>(), started = Completer<void>();
    db.listLoad = (_) { started.complete(); return pending.future; };
    final result = service.loadRequests();
    final rejected = expectLater(result, throwsStateError);
    await started.future;
    service.access = const AdminAccess(AdminAccessStatus.allowed, uid: 'different-staff');
    pending.complete(SupportPage([_original]));
    await rejected;
  });

  test('Tolerant projection, optional trip and practical loaded search', () {
    final legacy = AdminSupportParser.request('legacy', {'contactNumber': null, 'createdAt': false});
    expect(legacy.tripReference, isNull); expect(legacy.createdAt, isNull);
    expect(legacy.contactNumber, 'Not available');
    for (final query in ['sup-260918', 'CT-260918', '771234567', 'AMAL', 'payment incomplete', 'complaint']) {
      expect(supportMatchesSearch(_original, query), isTrue, reason: query);
    }
    expect(supportMatchesSearch(_original, 'unrelated'), isFalse);
  });

  for (final status in [AdminAccessStatus.signedOut, AdminAccessStatus.denied, AdminAccessStatus.error]) {
    testWidgets('Inbox and detail reject $status without reads', (tester) async {
      final db = _Data(), service = _Service(_Data());
      service.access = AdminAccess(status);
      final denied = _Service(db)..access = service.access;
      await tester.pumpWidget(MaterialApp(home: AdminSupportInboxScreen(service: denied)));
      await _pump(tester);
      expect(find.text('Check access again'), findsOneWidget);
      await tester.pumpWidget(MaterialApp(home: AdminSupportDetailScreen(requestId: 'ABC234', service: denied)));
      await _pump(tester);
      expect(find.text('Check access again'), findsOneWidget); expect(db.reads, 0);
    });
  }

  testWidgets('Support-only Account entry opens inbox', (tester) async {
    final db = _Data();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminSupportEntry(service: _Service(db)))));
    await _pump(tester);
    await tester.tap(find.byKey(const Key('support_staff_entry')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminSupportInboxScreen), findsOneWidget);
    expect(db.queries, isNotEmpty);
  });

  testWidgets('Dashboard retains Users & Drivers and overview while opening support', (tester) async {
    await tester.pumpWidget(MaterialApp(home: AdminDashboardScreen(service: _Overview(), supportService: _Service(_Data()))));
    await _pump(tester);
    expect(find.byKey(const Key('admin_users_entry')), findsOneWidget);
    expect(find.text('Operations overview'), findsOneWidget);
    await tester.tap(find.byKey(const Key('admin_support_entry')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminSupportInboxScreen), findsOneWidget);
  });

  testWidgets('Inbox loading, safe failure, retry and empty state', (tester) async {
    final pending = Completer<SupportPage<SupportRequest>>();
    final db = _Data()..listLoad = (_) => pending.future;
    await tester.pumpWidget(MaterialApp(home: AdminSupportInboxScreen(service: _Service(db))));
    await _pump(tester);
    expect(find.bySemanticsLabel('Loading support requests'), findsOneWidget);
    pending.completeError(StateError('private details'));
    await _pump(tester);
    expect(find.text('private details'), findsNothing);
    db.listLoad = (_) async => SupportPage([]);
    await _reveal(tester, find.text('Retry inbox'));
    await tester.tap(find.text('Retry inbox'));
    await _pump(tester);
    expect(find.text('No support requests'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Filters and search apply to loaded requests without extra search queries', (tester) async {
    final db = _Data();
    await tester.pumpWidget(MaterialApp(home: AdminSupportInboxScreen(service: _Service(db))));
    await _pump(tester);
    for (final filter in SupportInboxFilter.values) {
      await tester.tap(find.byKey(ValueKey('support_filter_${filter.name}')));
      await _pump(tester);
      expect(db.queries.last.filter, filter);
      final expected = filter == SupportInboxFilter.all ? 4 : filter == SupportInboxFilter.completed ? 2 : 1;
      expect(find.text('$expected matching · $expected loaded'), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('support_filter_all')));
    await _pump(tester);
    final reads = db.reads;
    await tester.enterText(find.byKey(const Key('support_inbox_search')), 'CT-260918');
    await _pump(tester);
    expect(find.text('1 matching · 4 loaded'), findsOneWidget);
    expect(db.reads, reads);
    await tester.enterText(find.byKey(const Key('support_inbox_search')), 'no match');
    await _pump(tester);
    expect(find.text('No matching loaded requests'), findsOneWidget);
  });

  testWidgets('New filter discards an obsolete list response', (tester) async {
    final old = Completer<SupportPage<SupportRequest>>();
    final db = _Data()..listLoad = (q) => q.filter == SupportInboxFilter.all ? old.future : Future.value(SupportPage([]));
    await tester.pumpWidget(MaterialApp(home: AdminSupportInboxScreen(service: _Service(db))));
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('support_filter_open')));
    await _pump(tester);
    old.complete(SupportPage([_original]));
    await _pump(tester);
    expect(find.text('0 matching · 0 loaded'), findsOneWidget);
    expect(find.text(_original.supportReference), findsNothing);
  });

  testWidgets('Inbox pagination remains available with no loaded search match', (tester) async {
    final cursor = SupportCursor(Timestamp(1, 0), 'last');
    final db = _Data()..listLoad = (q) async => q.cursor == null
      ? SupportPage([_request('OTHER2', 'open')], next: cursor) : SupportPage([_original]);
    await tester.pumpWidget(MaterialApp(home: AdminSupportInboxScreen(service: _Service(db))));
    await _pump(tester);
    await tester.enterText(find.byKey(const Key('support_inbox_search')), 'CT-260918');
    await _pump(tester);
    await _reveal(tester, find.text('Load more requests'));
    await tester.tap(find.text('Load more requests'));
    await _pump(tester);
    expect(db.queries.last.cursor, same(cursor));
    expect(find.text('1 matching · 2 loaded'), findsOneWidget);
  });

  testWidgets('Exact inbox button navigates to protected conversation', (tester) async {
    final db = _Data()..rows = [_original];
    await tester.pumpWidget(MaterialApp(home: AdminSupportInboxScreen(service: _Service(db))));
    await _pump(tester);
    final button = find.widgetWithText(TextButton, 'Open request');
    await _reveal(tester, button);
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(AdminSupportDetailScreen), findsOneWidget);
    expect(find.text('Contact snapshot: +94 77 123 4567'), findsOneWidget);
  });

  for (final width in [360.0, 1400.0]) {
    testWidgets('Support details and immutable history render at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1800); tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: AdminSupportDetailScreen(requestId: 'ABC234', service: _Service(_Data()))));
      await _pump(tester);
      for (final text in [_original.supportReference, 'Contact snapshot: +94 77 123 4567',
        'Trip: CT-260918-ABC234', 'Original request ABC234', 'Automatic acknowledgement', 'Earlier reply', 'Status history']) {
        await _reveal(tester, find.text(text));
        expect(find.text(text), findsOneWidget);
      }
      _noManagement(); expect(tester.takeException(), isNull);
    });
  }

  testWidgets('General support needs no trip; reply uses only a new message operation', (tester) async {
    final db = _Data()..detail = _request('ABC234', 'open');
    await tester.pumpWidget(MaterialApp(home: AdminSupportDetailScreen(requestId: 'ABC234', service: _Service(db))));
    await _pump(tester);
    expect(find.textContaining('Trip:'), findsNothing);
    await _reveal(tester, find.byKey(const Key('admin_support_reply')));
    await tester.enterText(find.byKey(const Key('admin_support_reply')), 'Staff response');
    await _reveal(tester, find.byKey(const Key('admin_support_send')));
    await tester.tap(find.byKey(const Key('admin_support_send')));
    await _pump(tester);
    expect(db.replies.single, ['ABC234', 'operation-1', 'staff-uid', 'Staff response']);
    expect(db.messagesRows.first, same(_oldMessage));
    expect(db.transitions, isEmpty); _noManagement(); expect(tester.takeException(), isNull);
  });

  testWidgets('Conversation and audit pages load fully and a failed page retries its cursor', (tester) async {
    final messageCursor = SupportCursor(Timestamp(1, 0), 'old');
    final historyCursor = SupportCursor(Timestamp(2, 0), 'event-old');
    var failPage = true;
    final db = _Data();
    db.messageLoad = (query) async {
      if (query.cursor == null) return SupportPage([_oldMessage], next: messageCursor);
      if (failPage) { failPage = false; throw StateError('private page failure'); }
      return SupportPage([const SupportMessage(id: 'new', senderId: 'staff-uid',
        senderRole: 'admin', message: 'Newest reply')]);
    };
    db.historyLoad = (query) async => query.cursor == null ? SupportPage([], next: historyCursor)
      : SupportPage([const SupportStatusEvent(id: 'event-new', actorId: 'another-staff',
        fromStatus: 'open', toStatus: 'in_review')]);
    await tester.pumpWidget(MaterialApp(home: AdminSupportDetailScreen(requestId: 'ABC234', service: _Service(db))));
    await _pump(tester);
    await _reveal(tester, find.text('Load more messages'));
    await tester.tap(find.text('Load more messages'));
    await _pump(tester);
    expect(find.text('private page failure'), findsNothing);
    await tester.tap(find.text('Load more messages'));
    await _pump(tester);
    expect(db.messageQueries.last.cursor, same(messageCursor));
    await _reveal(tester, find.text('Newest reply'));
    expect(find.text('Newest reply'), findsOneWidget);
    await _reveal(tester, find.text('Load more history'));
    await tester.tap(find.text('Load more history'));
    await _pump(tester);
    expect(db.historyQueries.last.cursor, same(historyCursor));
    await _reveal(tester, find.text('Staff UID: another-staff'));
    expect(find.text('Staff UID: another-staff'), findsOneWidget);
    _noManagement(); expect(tester.takeException(), isNull);
  });

  testWidgets('Reply retry retains draft and operation ID until confirmed', (tester) async {
    final db = _Data()..failReply = true;
    await tester.pumpWidget(MaterialApp(home: AdminSupportDetailScreen(requestId: 'ABC234', service: _Service(db))));
    await _pump(tester);
    await _reveal(tester, find.byKey(const Key('admin_support_reply')));
    await tester.enterText(find.byKey(const Key('admin_support_reply')), 'Retry text');
    await _reveal(tester, find.byKey(const Key('admin_support_send')));
    await tester.tap(find.byKey(const Key('admin_support_send')));
    await _pump(tester);
    db.failReply = false;
    await tester.tap(find.byKey(const Key('admin_support_send')));
    await _pump(tester);
    expect(db.replies.length, 2); expect(db.replies[0], db.replies[1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Status selection sends existing stored state and records audit', (tester) async {
    final db = _Data();
    await tester.pumpWidget(MaterialApp(home: AdminSupportDetailScreen(requestId: 'ABC234', service: _Service(db))));
    await _pump(tester);
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await _reveal(tester, dropdown);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('In Progress').last);
    await tester.pumpAndSettle();
    final update = find.byKey(const Key('admin_support_status'));
    await _reveal(tester, update);
    await tester.tap(update);
    await _pump(tester);
    expect(db.transitions.single, ['ABC234', 'operation-1', 'staff-uid', 'open', 'in_review']);
    expect(db.detail!.contactNumber, _original.contactNumber);
    expect(db.detail!.tripReference, _original.tripReference);
    expect(db.events.single.actorId, 'staff-uid'); _noManagement();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Closed requests hide reply composer', (tester) async {
    final db = _Data()..detail = _request('ABC234', 'closed');
    await tester.pumpWidget(MaterialApp(home: AdminSupportDetailScreen(requestId: 'ABC234', service: _Service(db))));
    await _pump(tester);
    await _reveal(tester, find.text('This request is closed. Reopen it to reply.'));
    expect(find.byKey(const Key('admin_support_send')), findsNothing);
  });

  testWidgets('Detail failure retries and missing request renders safely', (tester) async {
    final db = _Data()..failDetail = true;
    final service = _Service(db);
    await tester.pumpWidget(MaterialApp(home: AdminSupportDetailScreen(requestId: 'ABC234', service: service)));
    await _pump(tester);
    expect(find.text('Retry conversation'), findsOneWidget);
    db.failDetail = false; db.detail = null;
    await tester.tap(find.text('Retry conversation'));
    await _pump(tester);
    expect(find.text('Request not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Gate disposal ignores late detail results after sign-out', (tester) async {
    final changes = StreamController<AdminAccess>.broadcast(sync: true);
    final pending = Completer<SupportRequest?>();
    final db = _Data()..detailLoad = () => pending.future;
    final service = _Service(db)..changes = changes.stream;
    await tester.pumpWidget(MaterialApp(home: AdminSupportDetailScreen(requestId: 'ABC234', service: service)));
    changes.add(_staff); await _pump(tester);
    expect(find.bySemanticsLabel('Loading support conversation'), findsOneWidget);
    service.access = const AdminAccess(AdminAccessStatus.signedOut);
    changes.add(service.access); await _pump(tester);
    pending.complete(_original); await _pump(tester);
    expect(find.text('Contact snapshot: +94 77 123 4567'), findsNothing);
    expect(find.text('Check access again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); await changes.close();
    expect(tester.takeException(), isNull);
  });
}

class _Service extends AdminSupportService {
  _Service(AdminSupportDataSource source) : super(dataSource: source);
  AdminAccess access = _staff;
  Stream<AdminAccess>? changes;
  @override
  Future<AdminAccess> readAccess({bool forceRefresh = false}) async => access;
  @override
  Stream<AdminAccess> watchAccess() => changes ?? Stream.value(access);
  @override
  void checkActor(String actor) {
    if (access.status != AdminAccessStatus.allowed || actor != access.uid) throw StateError('Changed session');
  }
}

class _Data implements AdminSupportDataSource {
  List<SupportRequest> rows = [_original, _request('BCD345', 'in_review'), _request('CDE456', 'resolved'), _request('DEF567', 'closed')];
  SupportRequest? detail = _original;
  final messagesRows = <SupportMessage>[_oldMessage];
  final events = <SupportStatusEvent>[];
  final queries = <SupportReadQuery>[];
  final messageQueries = <SupportReadQuery>[], historyQueries = <SupportReadQuery>[];
  final replies = <List<String>>[], transitions = <List<String>>[];
  int reads = 0, operations = 0;
  bool failReply = false, failDetail = false;
  Future<SupportPage<SupportRequest>> Function(SupportReadQuery)? listLoad;
  Future<SupportRequest?> Function()? detailLoad;
  Future<SupportPage<SupportMessage>> Function(SupportReadQuery)? messageLoad;
  Future<SupportPage<SupportStatusEvent>> Function(SupportReadQuery)? historyLoad;
  @override
  String newOperationId() => 'operation-${++operations}';
  @override
  Future<SupportPage<SupportRequest>> requests(SupportReadQuery query) async {
    reads++; queries.add(query);
    if (listLoad != null) return listLoad!(query);
    return SupportPage(rows.where((r) => query.filter.statuses.isEmpty || query.filter.statuses.contains(r.status)).toList());
  }
  @override
  Future<SupportRequest?> request(String id) async {
    reads++;
    if (failDetail) throw StateError('private detail error');
    return detailLoad == null ? detail : await detailLoad!();
  }
  @override
  Future<SupportPage<SupportMessage>> messages(String id, SupportReadQuery query) async {
    messageQueries.add(query);
    return messageLoad == null ? SupportPage(messagesRows) : await messageLoad!(query);
  }
  @override
  Future<SupportPage<SupportStatusEvent>> history(String id, SupportReadQuery query) async {
    historyQueries.add(query);
    return historyLoad == null ? SupportPage(events) : await historyLoad!(query);
  }
  @override
  Future<void> reply(String id, String operationId, String actor, String text, void Function() checkSession) async {
    checkSession(); replies.add([id, operationId, actor, text]);
    if (failReply) throw StateError('Unconfirmed');
    messagesRows.add(SupportMessage(id: operationId, senderId: actor, senderRole: 'admin', message: text));
  }
  @override
  Future<void> changeStatus(String id, String operationId, String actor, String from, String to, void Function() checkSession) async {
    checkSession(); transitions.add([id, operationId, actor, from, to]);
    detail = AdminSupportParser.request(id, {...detail!.toFirestore(), ...SupportStaffWrites.statusParent(operationId, to)});
    events.add(SupportStatusEvent(id: operationId, actorId: actor, fromStatus: from, toStatus: to));
  }
}

class _Overview extends AdminService {
  @override
  Stream<AdminAccess> watchAccess() => Stream.value(_staff);
  @override
  Future<AdminDashboardData> loadDashboard() async => const AdminDashboardData(
    stats: AdminDashboardStats(totalUsers: 2, totalDrivers: 1, totalTourists: 1,
      totalTrips: 0, openTrips: 0, activeTrips: 0, completedTrips: 0, openSupportRequests: 1), recentSupport: []);
}
class _Auth implements FirebaseAuth {
  @override
  User? currentUser;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
class _User implements User {
  _User(this.claims);
  final Map<String, dynamic> claims;
  @override
  String get uid => 'staff-uid';
  @override
  Future<IdTokenResult> getIdTokenResult([bool forceRefresh = false]) async => _Token(claims);
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
