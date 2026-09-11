class UserReputation {
  const UserReputation({this.completedTripsCount = 0, this.ratingsCount = 0,
    this.ratingStarsTotal = 0, this.averageRating = 0, this.cancellationCount,
    this.cancellationRate});
  final int completedTripsCount;
  final int ratingsCount;
  final int ratingStarsTotal;
  final double averageRating;
  final int? cancellationCount;
  final double? cancellationRate;
  factory UserReputation.fromMap(Map<String, dynamic> data) => UserReputation(
    completedTripsCount: (data['completedTripsCount'] as num?)?.toInt() ?? 0,
    ratingsCount: (data['ratingsCount'] as num?)?.toInt() ?? 0,
    ratingStarsTotal: (data['ratingStarsTotal'] as num?)?.toInt() ?? 0,
    averageRating: (data['averageRating'] as num?)?.toDouble() ?? 0,
    cancellationCount: (data['cancellationCount'] as num?)?.toInt(),
    cancellationRate: (data['cancellationRate'] as num?)?.toDouble(),
  );
  Map<String, dynamic> toMap() => {
    'completedTripsCount': completedTripsCount, 'ratingsCount': ratingsCount,
    'ratingStarsTotal': ratingStarsTotal, 'averageRating': averageRating,
    'cancellationCount': cancellationCount, 'cancellationRate': cancellationRate,
  };
  UserReputation completed() => UserReputation(
    completedTripsCount: completedTripsCount + 1, ratingsCount: ratingsCount,
    ratingStarsTotal: ratingStarsTotal, averageRating: averageRating,
    cancellationCount: cancellationCount, cancellationRate: cancellationRate,
  );
  UserReputation rated(int stars) => UserReputation(
    completedTripsCount: completedTripsCount, ratingsCount: ratingsCount + 1,
    ratingStarsTotal: ratingStarsTotal + stars,
    averageRating: (ratingStarsTotal + stars) / (ratingsCount + 1),
    cancellationCount: cancellationCount, cancellationRate: cancellationRate,
  );
}
