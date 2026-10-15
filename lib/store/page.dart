/// Anamne page model v2.
///
/// A page is either a plain block page (`type == 'page'`) or a canvas
/// (`type == 'canvas'` whose payload lives in [data]). `blocks` holds the
/// portable block list, `body` the markdown projection kept for portability
/// and full-text search. `serverVersion` is local sync metadata: the page
/// version the server last acknowledged for this record.
class AnamnePage {
  const AnamnePage({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    this.parentId,
    this.deletedAt,
    this.type = 'page',
    this.blocks = const [],
    this.data,
    this.serverVersion,
    this.properties = const {},
  });

  final String id;
  final String title;
  final String body;
  final String? parentId;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String type;
  final List<Map<String, Object?>> blocks;
  final Map<String, Object?>? data;
  final int? serverVersion;
  final Map<String, Object?> properties;

  bool get isDeleted => deletedAt != null;
  String get label => title.trim().isEmpty ? 'Untitled' : title.trim();
  bool get isCanvas => type == 'canvas';

  AnamnePage copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
    String? parentId,
    bool clearParent = false,
    DateTime? deletedAt,
    bool restore = false,
    String? type,
    List<Map<String, Object?>>? blocks,
    Map<String, Object?>? data,
    bool clearData = false,
    int? serverVersion,
    Map<String, Object?>? properties,
  }) =>
      AnamnePage(
        id: id,
        title: title ?? this.title,
        body: body ?? this.body,
        updatedAt: updatedAt ?? this.updatedAt,
        parentId: clearParent ? null : parentId ?? this.parentId,
        deletedAt: restore ? null : deletedAt ?? this.deletedAt,
        type: type ?? this.type,
        blocks: blocks ?? this.blocks,
        data: clearData ? null : data ?? this.data,
        serverVersion: serverVersion ?? this.serverVersion,
        properties: properties ?? this.properties,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'parentId': parentId,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
        'type': type,
        'blocks': blocks,
        if (data != null) 'data': data,
        if (serverVersion != null) 'serverVersion': serverVersion,
        'properties': properties,
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
        type: json['type'] as String? ?? 'page',
        blocks: (json['blocks'] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .toList(),
        data: json['data'] == null ? null : Map<String, Object?>.from(json['data'] as Map),
        serverVersion: (json['serverVersion'] as num?)?.toInt(),
        properties: json['properties'] is Map
            ? Map<String, Object?>.from(json['properties'] as Map) : const {},
      );

  /// Server REST/MCP record shape: camelCase, ISO timestamps.
  Map<String, Object?> toServerRecord() => {
        'id': id,
        'title': title,
        'body': body,
        'parentId': parentId,
        'properties': properties,
        'type': type,
        'blocks': blocks,
        if (data != null) 'data': data,
        if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
      };

  factory AnamnePage.fromServerRecord(Map<String, Object?> json) => AnamnePage(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        parentId: json['parentId'] as String?,
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now().toUtc(),
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.tryParse(json['deletedAt'] as String),
        type: json['type'] as String? ?? 'page',
        blocks: (json['blocks'] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .toList(),
        data: json['data'] == null ? null : Map<String, Object?>.from(json['data'] as Map),
        serverVersion: (json['version'] as num?)?.toInt(),
        properties: json['properties'] is Map
            ? Map<String, Object?>.from(json['properties'] as Map) : const {},
      );
}
