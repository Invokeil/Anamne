import 'dart:convert';

import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

import 'database_factory_io.dart'
    if (dart.library.js_interop) 'database_factory_web.dart' as storage;
import 'page.dart';

class PageRepository {
  PageRepository(this._database);

  final Database _database;
  final StoreRef<String, Map<String, Object?>> _pages =
      stringMapStoreFactory.store('pages');
  static const _uuid = Uuid();

  static Future<PageRepository> open() async =>
      PageRepository(await storage.openAnamneDatabase());

  Future<List<AnamnePage>> all({bool deleted = false}) async {
    final rows = await _pages.find(_database);
    final pages = rows
        .map((row) => AnamnePage.fromJson(row.value))
        .where((page) => page.isDeleted == deleted)
        .toList();
    pages.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return pages;
  }

  Future<AnamnePage> create({String? parentId}) async {
    if (parentId != null && await get(parentId) == null) {
      throw StateError('Parent page does not exist');
    }
    final page = AnamnePage(
      id: _uuid.v4(),
      title: '',
      body: '',
      parentId: parentId,
      updatedAt: DateTime.now().toUtc(),
    );
    await _pages.record(page.id).put(_database, page.toJson());
    return page;
  }

  Future<AnamnePage?> get(String id) async {
    final data = await _pages.record(id).get(_database);
    return data == null ? null : AnamnePage.fromJson(data);
  }

  Future<void> save(AnamnePage page) async {
    await _database.transaction((txn) async {
      final current = await _pages.record(page.id).get(txn);
      if (current == null) return;
      final latest = AnamnePage.fromJson(current);
      await _pages.record(page.id).put(txn, latest.copyWith(
        title: page.title,
        body: page.body,
        updatedAt: DateTime.now().toUtc(),
      ).toJson());
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
        await _pages.record(item.id).put(txn, item.copyWith(restore: true).toJson());
      }
    });
  }

  Future<void> deleteForever(String id) async {
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
    });
  }

  Future<String> exportJson() async {
    final pages = await _pages.find(_database);
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'anamne.pages',
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'pages': pages.map((p) => p.value).toList(),
    });
  }

  Future<void> close() => _database.close();
}
