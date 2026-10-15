/// Structured database documents (Notion-style) stored locally and synced as
/// first-class `database` entities.
class DbProp {
  const DbProp({
    required this.id,
    required this.name,
    required this.type,
    this.options = const [],
  });

  final String id;
  final String name;
  final String type; // text | number | select | multiSelect | checkbox | date
  final List<String> options;

  DbProp copyWith({String? name, String? type, List<String>? options}) => DbProp(
        id: id, name: name ?? this.name, type: type ?? this.type,
        options: options ?? this.options,
      );

  Map<String, Object?> toJson() => {
        'id': id, 'name': name, 'type': type,
        if (options.isNotEmpty) 'options': options,
      };

  factory DbProp.fromJson(Map<String, Object?> json) => DbProp(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        type: json['type'] as String? ?? 'text',
        options: (json['options'] as List<Object?>? ?? const [])
            .whereType<String>()
            .toList(),
      );
}

class DbRecord {
  const DbRecord({required this.id, this.values = const {}});

  final String id;
  final Map<String, Object?> values;

  DbRecord copyWith(Map<String, Object?> values) =>
      DbRecord(id: id, values: {...this.values, ...values});

  Map<String, Object?> toJson() => {'id': id, 'values': values};

  factory DbRecord.fromJson(Map<String, Object?> json) => DbRecord(
        id: json['id'] as String,
        values: json['values'] == null
            ? {}
            : Map<String, Object?>.from(json['values'] as Map),
      );
}

class DbDoc {
  const DbDoc({
    required this.id,
    required this.title,
    this.schema = const [],
    this.records = const [],
    required this.updatedAt,
    this.deletedAt,
    this.serverVersion,
  });

  final String id;
  final String title;
  final List<DbProp> schema;
  final List<DbRecord> records;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int? serverVersion;

  bool get isDeleted => deletedAt != null;
  String get label => title.trim().isEmpty ? 'Untitled database' : title.trim();

  DbDoc copyWith({
    String? title,
    List<DbProp>? schema,
    List<DbRecord>? records,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool restore = false,
    int? serverVersion,
  }) =>
      DbDoc(
        id: id,
        title: title ?? this.title,
        schema: schema ?? this.schema,
        records: records ?? this.records,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: restore ? null : deletedAt ?? this.deletedAt,
        serverVersion: serverVersion ?? this.serverVersion,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'schema': schema.map((p) => p.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deletedAt': deletedAt?.toUtc().toIso8601String(),
        if (serverVersion != null) 'serverVersion': serverVersion,
      };

  factory DbDoc.fromJson(Map<String, Object?> json) => DbDoc(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        schema: (json['schema'] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .map(DbProp.fromJson)
            .toList(),
        records: (json['records'] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .map(DbRecord.fromJson)
            .toList(),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.parse(json['deletedAt'] as String),
        serverVersion: (json['serverVersion'] as num?)?.toInt(),
      );

  Map<String, Object?> toServerRecord() => {
        'id': id,
        'title': title,
        'schema': schema.map((p) => p.toJson()).toList(),
        'records': records.map((r) => r.toJson()).toList(),
        if (deletedAt != null) 'deletedAt': deletedAt!.toUtc().toIso8601String(),
      };

  factory DbDoc.fromServerRecord(Map<String, Object?> json) => DbDoc(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        schema: (json['schema'] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .map(DbProp.fromJson)
            .toList(),
        records: (json['records'] as List<Object?>? ?? const [])
            .whereType<Map<String, Object?>>()
            .map(DbRecord.fromJson)
            .toList(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now().toUtc(),
        deletedAt: json['deletedAt'] == null
            ? null
            : DateTime.tryParse(json['deletedAt'] as String),
        serverVersion: (json['version'] as num?)?.toInt(),
      );
}
