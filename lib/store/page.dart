class AnamnePage {
  const AnamnePage({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.parentId,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String body;
  final String? parentId;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  String get label => title.trim().isEmpty ? 'Untitled' : title.trim();

  AnamnePage copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
    String? parentId,
    bool clearParent = false,
    DateTime? deletedAt,
    bool restore = false,
  }) => AnamnePage(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    updatedAt: updatedAt ?? this.updatedAt,
    parentId: clearParent ? null : parentId ?? this.parentId,
    deletedAt: restore ? null : deletedAt ?? this.deletedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'parentId': parentId,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };

  factory AnamnePage.fromJson(Map<String, Object?> json) => AnamnePage(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    parentId: json['parentId'] as String?,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    deletedAt: json['deletedAt'] == null
        ? null
        : DateTime.parse(json['deletedAt'] as String),
  );
}
