import 'dart:async';
import 'dart:convert';

import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import '../editor/block.dart';
import 'database_doc.dart';
import 'database_factory_io.dart'
    if (dart.library.js_interop) 'database_factory_web.dart' as storage;
import 'page.dart';

class PageRepository {
  PageRepository(this._database);

  final Database _database;
  final StoreRef<String, Map<String, Object?>> _pages =
      stringMapStoreFactory.store('pages');
  final StoreRef<String, Map<String, Object?>> _databases =
      stringMapStoreFactory.store('databases');
  final StoreRef<String, Map<String, Object?>> _outbox =
      stringMapStoreFactory.store('outbox');
  final StoreRef<String, Map<String, Object?>> _settings =
      stringMapStoreFactory.store('settings');
  static const _uuid = Uuid();

  static Future<PageRepository> open() async =>
      PageRepository(await storage.openAnamneDatabase());

  // ------------------------------------------------------------- settings

  Future<Object?> setting(String key) async {
    final row = await _settings.record(key).get(_database);
    return row?['value'];
  }

  Future<void> setSetting(String key, Object? value) =>
      _settings.record(key).put(_database, {'value': value});

  // ----------------------------------------------------------- outbox ops

  Future<void> _enqueue(Transaction txn, String entity, String kind, String targetId,
      {Map<String, Object?>? record, int? expectedVersion}) async {
    final previous = await _settings.record('outboxSequence').get(txn);
    final sequence = ((previous?['value'] as num?)?.toInt() ?? 0) + 1;
    await _settings.record('outboxSequence').put(txn, {'value': sequence});
    final op = {
      'opId': 'op-${_uuid.v4()}',
      'entity': entity,
      'kind': kind,
      'targetId': targetId,
      'id': targetId,
      'record': record,
      'expectedVersion': expectedVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'attempts': 0,
      'sequence': sequence,
    };
    await _outbox.record(op['opId'] as String).put(txn, op);
  }

  Future<int> outboxCount() async => _outbox.count(_database);

  Future<List<Map<String, Object?>>> outboxOps({int limit = 50}) async {
    final rows = (await _outbox.find(_database)).map((r) => r.value).toList();
    rows.sort((a, b) {
      final sa = (a['sequence'] as num?)?.toInt();
      final sb = (b['sequence'] as num?)?.toInt();
      if (sa == null || sb == null) {
        if (sa == null && sb != null) return -1;
        if (sa != null && sb == null) return 1;
        return (a['createdAt'] as String).compareTo(b['createdAt'] as String);
      }
      return sa.compareTo(sb);
    });
    return rows.take(limit).toList();
  }

  /// Acknowledge a sent snapshot and rebase only its queued successors.
  Future<void> acknowledgeOutbox(String opId, int? version) async {
    await _database.transaction((txn) async {
      final op = await _outbox.record(opId).get(txn);
      if (op == null) return;
      await _outbox.record(opId).delete(txn);
      final id = op['targetId'] as String;
      final entity = op['entity'] as String;
      if (version == null) return;
      if (entity == 'page') {
        final value = await _pages.record(id).get(txn);
        if (value != null) {
          await _pages.record(id).put(
            txn,
            AnamnePage.fromJson(value)
                .copyWith(serverVersion: version)
                .toJson(),
          );
        }
      } else {
        final value = await _databases.record(id).get(txn);
        if (value != null) {
          await _databases.record(id).put(
            txn,
            DbDoc.fromJson(value)
                .copyWith(serverVersion: version)
                .toJson(),
          );
        }
      }
      final remaining = await _outbox.find(txn, finder: Finder(filter: Filter.and([
        Filter.equals('targetId', id), Filter.equals('entity', entity),
      ])));
      for (final row in remaining) {
        await _outbox.record(row.key).put(txn, {...row.value,
          'id': id, 'expectedVersion': version});
      }
    });
  }

  /// Preserve the latest local version before replacing a canonical server ID.
  /// The conflict copy, new outbox entry and obsolete-op removal commit together.
  Future<void> resolveConflict(String entity, String id,
      Map<String, Object?>? server) async {
    await _database.transaction((txn) async {
      final pending = await _outbox.find(txn, finder: Finder(filter: Filter.and([
        Filter.equals('targetId', id), Filter.equals('entity', entity),
      ])));
      if (pending.isNotEmpty) {
        final suffix = ' (conflict ${DateTime.now().toUtc().toIso8601String()})';
        if (entity == 'page') {
          final value = await _pages.record(id).get(txn);
          if (value != null) {
            final local = _migrate(AnamnePage.fromJson(value));
            final copy = AnamnePage(id: _uuid.v4(), title: local.label + suffix,
              body: local.body, updatedAt: DateTime.now().toUtc(), type: local.type,
              blocks: local.blocks, data: local.data, properties: local.properties);
            await _pages.record(copy.id).put(txn, copy.toJson());
            await _enqueue(txn, entity, 'upsert', copy.id, record: copy.toServerRecord());
          }
        } else {
          final value = await _databases.record(id).get(txn);
          if (value != null) {
            final local = DbDoc.fromJson(value);
            final copy = DbDoc(id: _uuid.v4(), title: local.label + suffix,
              schema: local.schema, records: local.records, updatedAt: DateTime.now().toUtc());
            await _databases.record(copy.id).put(txn, copy.toJson());
            await _enqueue(txn, entity, 'upsert', copy.id, record: copy.toServerRecord());
          }
        }
        for (final row in pending) {
          await _outbox.record(row.key).delete(txn);
        }
      }
      if (entity == 'page') {
        if (server == null) { await _pages.record(id).delete(txn); }
        else { await _pages.record(id).put(txn, AnamnePage.fromServerRecord(server).toJson()); }
      } else {
        if (server == null) { await _databases.record(id).delete(txn); }
        else { await _databases.record(id).put(txn, DbDoc.fromServerRecord(server).toJson()); }
      }
    });
  }

  Future<void> removeOutboxOp(String opId) => _outbox.record(opId).delete(_database);

  Future<void> markOutboxAttempt(String opId, String error) async {
    final row = await _outbox.record(opId).get(_database);
    if (row == null) return;
    await _outbox.record(opId).put(_database, {
      ...row,
      'attempts': ((row['attempts'] as num?)?.toInt() ?? 0) + 1,
      'lastError': error,
    });
  }

  Future<bool> hasPendingOpFor(String targetId) async {
    final count = await _outbox.count(_database,
        filter: Filter.equals('targetId', targetId));
    return count > 0;
  }

  // ---------------------------------------------------------------- pages

  /// Applies the v1→v2 migration: plain markdown bodies become blocks.
  AnamnePage _migrate(AnamnePage page) {
    if (page.blocks.isNotEmpty || page.type != 'page') return page;
    if (page.body.trim().isEmpty) return page;
    final blocks = markdownToBlocks(page.body, newId: _uuid.v4)
        .map((b) => b.toJson())
        .toList();
    return page.copyWith(blocks: blocks);
  }

  Future<List<AnamnePage>> all({bool deleted = false}) async {
    final rows = await _pages.find(_database);
    final pages = rows
        .map((row) => _migrate(AnamnePage.fromJson(row.value)))
        .where((page) => page.isDeleted == deleted)
        .toList();
    pages.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return pages;
  }

  Future<AnamnePage?> get(String id) async {
    final data = await _pages.record(id).get(_database);
    return data == null ? null : _migrate(AnamnePage.fromJson(data));
  }

  Future<AnamnePage> create({String? parentId, String type = 'page'}) async {
    if (parentId != null && await get(parentId) == null) {
      throw StateError('Parent page does not exist');
    }
    final page = AnamnePage(
      id: _uuid.v4(),
      title: '',
      body: '',
      parentId: parentId,
      updatedAt: DateTime.now().toUtc(),
      type: type,
      blocks: const [],
    );
    await _database.transaction((txn) async {
      await _pages.record(page.id).put(txn, page.toJson());
      await _enqueue(txn, 'page', 'upsert', page.id, record: page.toServerRecord());
    });
    return page;
  }

  Future<void> save(AnamnePage page) async {
    await _database.transaction((txn) async {
      final current = await _pages.record(page.id).get(txn);
      if (current == null) return;
      final latest = AnamnePage.fromJson(current);
      final projected = page.type == 'canvas'
          ? page
          : page.copyWith(body: blocksToMarkdown(
              page.blocks.map(Block.fromJson).toList()));
      final merged = latest.copyWith(
        title: projected.title,
        body: projected.body,
        updatedAt: DateTime.now().toUtc(),
        blocks: projected.blocks,
        data: projected.data,
        type: projected.type,
      );
      await _pages.record(page.id).put(txn, merged.toJson());
      await _enqueue(txn, 'page', 'upsert', page.id,
          record: merged.toServerRecord(),
          expectedVersion: merged.serverVersion);
    });
  }

  Future<void> trash(String id) async {
    final page = await get(id);
    if (page == null) return;
    // Keep the tree together: restoring a parent restores its descendants.
    final pages = await all();
    final pending = <String>{id};
    var changed = true;
    while (changed) {
      final before = pending.length;
      pending.addAll(pages.where((p) => pending.contains(p.parentId)).map((p) => p.id));
      changed = pending.length != before;
    }
    await _database.transaction((txn) async {
      for (final item in pages.where((p) => pending.contains(p.id))) {
        await _pages.record(item.id).put(
          txn,
          item.copyWith(deletedAt: DateTime.now().toUtc()).toJson(),
        );
      }
      await _enqueue(txn, 'page', 'trash', id, expectedVersion: page.serverVersion);
    });
  }

  Future<void> restore(String id) async {
    final page = await get(id);
    if (page == null) return;
    final pages = await all(deleted: true);
    final pending = <String>{id};
    var changed = true;
    while (changed) {
      final before = pending.length;
      pending.addAll(pages.where((p) => pending.contains(p.parentId)).map((p) => p.id));
      changed = pending.length != before;
    }
    await _database.transaction((txn) async {
      for (final item in pages.where((p) => pending.contains(p.id))) {
        await _pages.record(item.id).put(
          txn,
          item.copyWith(restore: true).toJson(),
        );
      }
      await _enqueue(txn, 'page', 'restore', id, expectedVersion: page.serverVersion);
    });
  }

  Future<void> deleteForever(String id) async {
    final page = await get(id);
    final allRows = await _pages.find(_database);
    final pending = <String>{id};
    var changed = true;
    while (changed) {
      final before = pending.length;
      pending.addAll(allRows.map((r) => AnamnePage.fromJson(r.value))
          .where((p) => pending.contains(p.parentId)).map((p) => p.id));
      changed = pending.length != before;
    }
    await _database.transaction((txn) async {
      for (final key in pending) {
        await _pages.record(key).delete(txn);
      }
      await _enqueue(txn, 'page', 'purge', id, expectedVersion: page?.serverVersion);
    });
  }

  /// Applies a pulled server snapshot without enqueueing an outbox op.
  /// Local edits waiting in the outbox always win over pulled state.
  Future<void> upsertFromServer(Map<String, Object?> record) async {
    final incoming = AnamnePage.fromServerRecord(record);
    await _database.transaction((txn) async {
      final pending = await _outbox.find(txn,
          finder: Finder(filter: Filter.equals('targetId', incoming.id)));
      if (pending.isNotEmpty) return;
      final current = await _pages.record(incoming.id).get(txn);
      final merged = current == null
          ? incoming
          : incoming.copyWith(
              serverVersion: incoming.serverVersion ??
                  AnamnePage.fromJson(current).serverVersion);
      await _pages.record(incoming.id).put(txn, merged.toJson());
    });
  }

  Future<void> deleteFromServer(String id) async {
    await resolveConflict('page', id, null);
  }

  /// Updates local sync metadata (server version) without enqueueing ops.
  Future<void> updatePageServerVersion(String id, int? version) async {
    final current = await _pages.record(id).get(_database);
    if (current == null) return;
    final page = AnamnePage.fromJson(current).copyWith(serverVersion: version);
    await _pages.record(id).put(_database, page.toJson());
  }

  /// Saves a resolved conflict: the local edit is preserved as its own page.
  Future<AnamnePage> createConflictCopy(AnamnePage local) async {
    final copy = AnamnePage(
      id: _uuid.v4(),
      title: '${local.label} (conflict ${DateTime.now().toLocal().toString().substring(0, 16)})',
      body: local.body,
      parentId: null,
      updatedAt: DateTime.now().toUtc(),
      type: local.type,
      blocks: local.blocks,
      data: local.data,
      properties: local.properties,
    );
    await _database.transaction((txn) async {
      await _pages.record(copy.id).put(txn, copy.toJson());
      await _enqueue(txn, 'page', 'upsert', copy.id, record: copy.toServerRecord());
    });
    return copy;
  }

  Future<String> exportJson() async {
    final pages = await _pages.find(_database);
    final databases = await _databases.find(_database);
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'anamne.pages',
      'version': 2,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'pages': pages.map((p) => p.value).toList(),
      'databases': databases.map((d) => d.value).toList(),
    });
  }

  Future<void> importJson(String json) async {
    final data = jsonDecode(json) as Map<String, Object?>;
    final rows = (data['pages'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();
    final databases = (data['databases'] as List<Object?>? ?? const [])
        .whereType<Map<String, Object?>>()
        .toList();
    await _database.transaction((txn) async {
      for (final row in rows) {
        final page = AnamnePage.fromJson(row);
        await _pages.record(page.id).put(txn, page.toJson());
        await _enqueue(txn, 'page', 'upsert', page.id,
            record: page.toServerRecord());
      }
      for (final row in databases) {
        final database = DbDoc.fromJson(row);
        await _databases.record(database.id).put(txn, database.toJson());
        await _enqueue(txn, 'database', 'upsert', database.id,
            record: database.toServerRecord());
      }
    });
  }

  // ------------------------------------------------------------ databases

  Future<List<DbDoc>> allDatabases({bool deleted = false}) async {
    final rows = await _databases.find(_database);
    final docs = rows
        .map((row) => DbDoc.fromJson(row.value))
        .where((d) => d.isDeleted == deleted)
        .toList();
    docs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return docs;
  }

  Future<DbDoc?> getDatabase(String id) async {
    final data = await _databases.record(id).get(_database);
    return data == null ? null : DbDoc.fromJson(data);
  }

  Future<DbDoc> createDatabase({String title = ''}) async {
    final doc = DbDoc(
      id: _uuid.v4(),
      title: title,
      updatedAt: DateTime.now().toUtc(),
    );
    await _database.transaction((txn) async {
      await _databases.record(doc.id).put(txn, doc.toJson());
      await _enqueue(txn, 'database', 'upsert', doc.id, record: doc.toServerRecord());
    });
    return doc;
  }

  Future<void> saveDatabase(DbDoc doc) async {
    await _database.transaction((txn) async {
      final current = await _databases.record(doc.id).get(txn);
      if (current == null) return;
      final latest = DbDoc.fromJson(current);
      final merged = latest.copyWith(
        title: doc.title,
        schema: doc.schema,
        records: doc.records,
        updatedAt: DateTime.now().toUtc(),
      );
      await _databases.record(doc.id).put(txn, merged.toJson());
      await _enqueue(txn, 'database', 'upsert', doc.id,
          record: merged.toServerRecord(),
          expectedVersion: merged.serverVersion);
    });
  }

  Future<void> trashDatabase(String id) async {
    final doc = await getDatabase(id);
    if (doc == null) return;
    await _database.transaction((txn) async {
      await _databases.record(id).put(txn,
          doc.copyWith(deletedAt: DateTime.now().toUtc()).toJson());
      await _enqueue(txn, 'database', 'trash', id, expectedVersion: doc.serverVersion);
    });
  }

  Future<void> restoreDatabase(String id) async {
    final doc = await getDatabase(id);
    if (doc == null) return;
    await _database.transaction((txn) async {
      await _databases.record(id).put(txn, doc.copyWith(restore: true).toJson());
      await _enqueue(txn, 'database', 'restore', id, expectedVersion: doc.serverVersion);
    });
  }

  Future<void> deleteDatabaseForever(String id) async {
    final doc = await getDatabase(id);
    await _database.transaction((txn) async {
      await _databases.record(id).delete(txn);
      await _enqueue(txn, 'database', 'purge', id, expectedVersion: doc?.serverVersion);
    });
  }

  /// Updates local sync metadata (server version) without enqueueing ops.
  Future<void> updateDatabaseServerVersion(String id, int? version) async {
    final current = await _databases.record(id).get(_database);
    if (current == null) return;
    final doc = DbDoc.fromJson(current).copyWith(serverVersion: version);
    await _databases.record(id).put(_database, doc.toJson());
  }

  Future<void> upsertDatabaseFromServer(Map<String, Object?> record) async {
    final incoming = DbDoc.fromServerRecord(record);
    await _database.transaction((txn) async {
      final pending = await _outbox.find(txn,
          finder: Finder(filter: Filter.equals('targetId', incoming.id)));
      if (pending.isNotEmpty) return;
      await _databases.record(incoming.id).put(txn, incoming.toJson());
    });
  }

  Future<void> deleteDatabaseFromServer(String id) =>
      resolveConflict('database', id, null);

  Future<void> close() => _database.close();
}
