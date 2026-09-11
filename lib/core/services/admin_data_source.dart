import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/support_request.dart';

class AdminCountQuery {
  const AdminCountQuery(this.collection, {this.field, this.equals, this.whereIn});
  final String collection;
  final String? field, equals;
  final List<String>? whereIn;
}

/// Read-only boundary: tests supply ordinary Dart objects, not Firebase subtypes.
abstract interface class AdminDataSource {
  Future<int> count(AdminCountQuery query);
  Future<List<SupportRequest>> loadSupport({required String orderBy,
    required bool descending, required int limit, required Source source});
}

class FirestoreAdminDataSource implements AdminDataSource {
  FirestoreAdminDataSource({FirebaseFirestore? firestore}) : _providedFirestore = firestore;
  final FirebaseFirestore? _providedFirestore;
  FirebaseFirestore get _db => _providedFirestore ?? FirebaseFirestore.instance;

  @override
  Future<int> count(AdminCountQuery definition) async {
    Query<Map<String, dynamic>> query = _db.collection(definition.collection);
    if (definition.field != null) {
      query = definition.whereIn == null
        ? query.where(definition.field!, isEqualTo: definition.equals)
        : query.where(definition.field!, whereIn: definition.whereIn);
    }
    final result = await query.count().get();
    final value = result.count;
    if (value == null) throw StateError('Count unavailable.');
    return value;
  }

  @override
  Future<List<SupportRequest>> loadSupport({required String orderBy,
    required bool descending, required int limit, required Source source}) async {
    final snapshot = await _db.collection('support_requests').orderBy(orderBy, descending: descending)
      .limit(limit).get(GetOptions(source: source));
    return snapshot.docs.map((doc) => SupportRequest.fromMap(doc.data())).toList();
  }
}
