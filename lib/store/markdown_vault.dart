import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as path;

import '../editor/block.dart';
import 'database_doc.dart';
import 'page.dart';
import 'page_repository.dart';

/// One-way Markdown projection of the workspace.
///
/// Desktop and Android only: every saved page is written as a `.md` file with
/// YAML-ish frontmatter (`anamne-id`, parent, updated). Files use title-ID names,
/// so external wiki-link resolution is not guaranteed. Databases also get a
/// JSON companion; canvas JSON currently lives inside its Markdown projection.
class MarkdownVault {
  MarkdownVault(this._repository, this.rootPath);

  final PageRepository _repository;
  String rootPath;
  bool enabled = true;
  String? lastError;

  static bool get supported => !kIsWeb;

  String _safeName(String title, String id) {
    final clean = title
        .replaceAll(RegExp(r'[\\/:*?"<>|#\[\]]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final base = clean.isEmpty ? 'Untitled' : clean;
    return '$base-${id.substring(0, 8)}.md';
  }

  String _frontmatter(AnamnePage page) => [
        '---',
        'anamne-id: ${page.id}',
        if (page.parentId != null) 'parent: ${page.parentId}',
        'type: ${page.type}',
        'updated: ${page.updatedAt.toUtc().toIso8601String()}',
        '---',
      ].join('\n');

  Future<void> writePage(AnamnePage page) async {
    if (!enabled || !supported) return;
    try {
      final directory = Directory(rootPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final file = File(path.join(rootPath, _safeName(page.label, page.id)));
      final buffer = StringBuffer(_frontmatter(page))..writeln();
      if (page.type == 'canvas') {
        buffer.writeln('# ${page.label}');
        buffer.writeln();
        buffer.writeln('Canvas payload is stored in the companion JSON file.');
        buffer.writeln();
        buffer.writeln(jsonEncode(page.data ?? {}));
      } else {
        buffer.writeln(blocksToMarkdown(page.blocks.map(Block.fromJson).toList()));
      }
      await file.writeAsString(buffer.toString(), flush: true);
      lastError = null;
    } catch (error) {
      lastError = error.toString();
    }
  }

  Future<void> writeDatabase(DbDoc doc) async {
    if (!enabled || !supported) return;
    try {
      final directory = Directory(rootPath);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final base = _safeName(doc.label, doc.id);
      final file = File(path.join(rootPath, base));
      final buffer = StringBuffer()
        ..writeln(_frontmatterFrom(
            id: doc.id, type: 'database', updated: doc.updatedAt))
        ..writeln()
        ..writeln('# ${doc.label}')
        ..writeln();
        for (final prop in doc.schema) {
          buffer.writeln('- Property: ${prop.name} (${prop.type})');
        }
        buffer.writeln();
        buffer
          ..writeln('| ${doc.schema.map((p) => p.name).join(' | ')}${doc.schema.isEmpty ? '' : ' |'}')
          ..writeln('|${doc.schema.map((_) => ' --- ').join('|')}|');
        for (final record in doc.records) {
          buffer.writeln('| ${doc.schema
              .map((p) => (record.values[p.id] ?? '').toString()
                  .replaceAll('|', '\\|'))
              .join(' | ')} |');
        }
      await file.writeAsString(buffer.toString(), flush: true);
      await File(path.join(rootPath, base.replaceAll('.md', '.json')))
          .writeAsString(const JsonEncoder.withIndent('  ')
              .convert(doc.toServerRecord()), flush: true);
      lastError = null;
    } catch (error) {
      lastError = error.toString();
    }
  }

  String _frontmatterFrom({
    required String id,
    required String type,
    required DateTime updated,
  }) =>
      ['---', 'anamne-id: $id', 'type: $type',
       'updated: ${updated.toUtc().toIso8601String()}', '---'].join('\n');

  /// Mirrors the whole workspace once (used from the sidebar action).
  Future<int> mirrorAll() async {
    var written = 0;
    for (final page in await _repository.all()) {
      await writePage(page);
      written++;
    }
    for (final doc in await _repository.allDatabases()) {
      await writeDatabase(doc);
      written++;
    }
    return written;
  }
}
