import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/admin_user_summary.dart';

/// A bounded, read-only query. ID ordering includes legacy accounts without dates.
class AdminUserQuery {
  const AdminUserQuery({this.accountType, this.afterUid, this.uid});
  static const pageSize = 50;
  final String? accountType, afterUid, uid;
  int get limit => uid == null ? pageSize : 1;
  Object get orderBy => FieldPath.documentId;
  Source get source => Source.server;
}

abstract interface class AdminUserDataSource {
  Future<List<AdminUserSummary>> loadUsers(AdminUserQuery definition);
}

class FirestoreAdminUserDataSource implements AdminUserDataSource {
  FirestoreAdminUserDataSource({FirebaseFirestore? firestore})
    : _providedFirestore = firestore;
  final FirebaseFirestore? _providedFirestore;

  @override
  Future<List<AdminUserSummary>> loadUsers(AdminUserQuery definition) async {
    final db = _providedFirestore ?? FirebaseFirestore.instance;
    Query<Map<String, dynamic>> query = db.collection('users');
    if (definition.uid != null) {
      // Uses the existing trusted-admin list permission; no new get grant.
      query = query.where(FieldPath.documentId, isEqualTo: definition.uid);
    }
    if (definition.accountType != null) {
      query = query.where('accountType', isEqualTo: definition.accountType);
    }
    query = query.orderBy(definition.orderBy);
    if (definition.afterUid != null) query = query.startAfter([definition.afterUid]);
    final snapshot = await query.limit(definition.limit)
      .get(GetOptions(source: definition.source));
    return snapshot.docs.map((doc) => AdminUserSummary.fromMap(doc.id, doc.data())).toList();
  }
}
