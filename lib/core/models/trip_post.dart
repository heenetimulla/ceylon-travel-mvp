import 'package:cloud_firestore/cloud_firestore.dart';

class TripPost {
  const TripPost({
    required this.id,
    required this.creatorId,
    required this.creatorType,
    required this.creatorName,
    required this.postType,
    required this.postOrigin,
    this.touristId,
    this.driverId,
    required this.pickupLocationText,
    required this.dropLocationText,
    required this.scheduledAt,
    required this.adultsCount,
    required this.kidsCount,
    required this.baggageCount,
    required this.vehiclePreference,
    required this.notes,
    required this.status,
    this.acceptedBidId,
    this.acceptedDriverId,
    this.excludedDriverIds = const [],
    this.cancellationCount = 0,
    this.lastCancellationBy,
    this.lastCancellationReason,
    this.lastCancellationAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String creatorId;
  final String creatorType;
  final String creatorName;
  final String postType;
  final String postOrigin;
  final String? touristId;
  final String? driverId;
  final String pickupLocationText;
  final String dropLocationText;
  final DateTime scheduledAt;
  final int adultsCount;
  final int kidsCount;
  final int baggageCount;
  final String vehiclePreference;
  final String notes;
  final String status;
  final String? acceptedBidId;
  final String? acceptedDriverId;
  final List<String> excludedDriverIds;
  final int cancellationCount;
  final String? lastCancellationBy;
  final String? lastCancellationReason;
  final DateTime? lastCancellationAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get pickup => pickupLocationText;
  String get drop => dropLocationText;
  int get adults => adultsCount;
  int get kids => kidsCount;
  String get passengers {
    final text = '$adultsCount ${adultsCount == 1 ? 'adult' : 'adults'}';
    return kidsCount == 0
        ? text
        : '$text, $kidsCount ${kidsCount == 1 ? 'kid' : 'kids'}';
  }

  String get baggage => '$baggageCount ${baggageCount == 1 ? 'bag' : 'bags'}';
  String get creatorTypeLabel =>
      creatorType.toLowerCase() == 'driver' ? 'Driver' : 'Tourist/User';
  String get postedByLabel => 'Posted by $creatorTypeLabel';

  String get dateTime {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final local = scheduledAt.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '${local.day} ${months[local.month - 1]} ${local.year} - $hour:$minute $period';
  }

  // Pending server timestamps may be null; invalid dates are never invented.
  static DateTime? _readDate(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    throw const FormatException('Invalid trip timestamp.');
  }

  factory TripPost.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) throw const FormatException('Trip post does not exist.');
    return TripPost.fromMap(doc.id, data);
  }

  factory TripPost.fromMap(String id, Map<String, dynamic> data) {
    final scheduledAt = _readDate(data['scheduledAt']);
    if (scheduledAt == null) {
      throw const FormatException('Trip schedule is missing.');
    }
    return TripPost(
      id: id,
      creatorId: data['creatorId'] as String,
      creatorType: data['creatorType'] as String,
      creatorName: data['creatorName'] as String,
      postType: data['postType'] as String,
      postOrigin:
          data['postOrigin'] as String? ??
          (data['creatorType'] == 'driver' ? 'partner' : 'direct'),
      touristId: data['touristId'] as String?,
      driverId: data['driverId'] as String?,
      pickupLocationText: data['pickupLocationText'] as String,
      dropLocationText: data['dropLocationText'] as String,
      scheduledAt: scheduledAt,
      adultsCount: data['adultsCount'] as int,
      kidsCount: data['kidsCount'] as int,
      baggageCount: data['baggageCount'] as int,
      vehiclePreference: data['vehiclePreference'] as String,
      notes: data['notes'] as String? ?? '',
      status: data['status'] as String,
      acceptedBidId: data['acceptedBidId'] as String?,
      acceptedDriverId: data['acceptedDriverId'] as String?,
      excludedDriverIds: List<String>.from(
        data['excludedDriverIds'] ?? const [],
      ),
      cancellationCount: data['cancellationCount'] as int? ?? 0,
      lastCancellationBy: data['lastCancellationBy'] as String?,
      lastCancellationReason: data['lastCancellationReason'] as String?,
      lastCancellationAt: _readDate(data['lastCancellationAt']),
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'id': id,
    'creatorId': creatorId,
    'creatorType': creatorType,
    'creatorName': creatorName,
    'postType': postType,
    'postOrigin': postOrigin,
    'touristId': touristId,
    'driverId': driverId,
    'pickupLocationText': pickupLocationText,
    'dropLocationText': dropLocationText,
    'scheduledAt': Timestamp.fromDate(scheduledAt),
    'adultsCount': adultsCount,
    'kidsCount': kidsCount,
    'baggageCount': baggageCount,
    'vehiclePreference': vehiclePreference,
    'notes': notes,
    'status': status,
    'acceptedBidId': acceptedBidId,
    'acceptedDriverId': acceptedDriverId,
    'excludedDriverIds': excludedDriverIds,
    'cancellationCount': cancellationCount,
    'lastCancellationBy': lastCancellationBy,
    'lastCancellationReason': lastCancellationReason,
    'lastCancellationAt': lastCancellationAt == null
        ? null
        : Timestamp.fromDate(lastCancellationAt!),
    'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
  };
}
