class Rating {
  const Rating({
    required this.id,
    required this.tripId,
    required this.fromUserName,
    required this.toUserName,
    required this.ratingValue,
    required this.comment,
    required this.createdAtText,
  });

  final String id;
  final String tripId;
  final String fromUserName;
  final String toUserName;
  final double ratingValue;
  final String comment;
  final String createdAtText;
}
