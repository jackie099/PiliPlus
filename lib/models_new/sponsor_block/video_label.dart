class VideoLabelModel {
  final String category;
  final int? votes;
  final bool locked;

  const VideoLabelModel({
    required this.category,
    this.votes,
    this.locked = false,
  });

  factory VideoLabelModel.fromJson(Map<String, dynamic> json) =>
      VideoLabelModel(
        category: json['category'] ?? '',
        votes: json['votes'],
        locked: json['locked'] == 1,
      );
}
