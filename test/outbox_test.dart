import 'package:anamne/store/page_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late PageRepository repository;

  setUp(() async {
    final factory = databaseFactoryMemory;
    // A unique in-memory database per test keeps suites isolated.
    repository = PageRepository(
        await factory.openDatabase('test-${DateTime.now().microsecondsSinceEpoch}.db'));
  });

  tearDown(() async {
    await repository.close();
  });

  test('create and save enqueue durable outbox operations', () async {
    final page = await repository.create();
    expect(await repository.outboxCount(), 1);
    final saved = page.copyWith(title: 'বাংলা নোট', blocks: [
      {'id': 'b1', 'type': 'paragraph', 'text': 'অফলাইন এডিট', 'indent': 0},
    ]);
    await repository.save(saved);
    expect(await repository.outboxCount(), 2);
    final ops = await repository.outboxOps();
    final upsert = ops.last;
    expect(upsert['kind'], 'upsert');
    expect(upsert['entity'], 'page');
    final record = upsert['record'] as Map<String, Object?>;
    expect(record['title'], 'বাংলা নোট');
    // The markdown projection is kept for portability and search.
    final stored = await repository.get(page.id);
    expect(stored!.title, 'বাংলা নোট');
    expect(stored.body, contains('অফলাইন এডিট'));
  });

  test('pulled server snapshots never clobber pending local edits', () async {
    final page = await repository.create();
    await repository.save(page.copyWith(title: 'local edit'));
    expect(await repository.outboxCount(), 2);
    await repository.upsertFromServer({
      'id': page.id,
      'title': 'server version',
      'body': 'server body',
      'parentId': null,
      'properties': <String, Object?>{},
      'type': 'page',
      'blocks': <Object?>[],
      'version': 7,
      'updatedAt': DateTime.utc(2026, 10, 15).toIso8601String(),
    });
    final stored = await repository.get(page.id);
    expect(stored!.title, isNot('server version'));
    // Once the outbox is drained, the server state applies.
    final ops = await repository.outboxOps();
    for (final op in ops) {
      await repository.removeOutboxOp(op['opId'] as String);
    }
    await repository.upsertFromServer({
      'id': page.id,
      'title': 'server version',
      'body': 'server body',
      'parentId': null,
      'properties': <String, Object?>{},
      'type': 'page',
      'blocks': <Object?>[],
      'version': 7,
      'updatedAt': DateTime.utc(2026, 10, 15).toIso8601String(),
    });
    final updated = await repository.get(page.id);
    expect(updated!.title, 'server version');
    expect(updated.serverVersion, 7);
  });

  test('trash, restore and permanent delete sync through the outbox', () async {
    final page = await repository.create();
    await repository.trash(page.id);
    expect((await repository.all()).length, 0);
    expect((await repository.all(deleted: true)).length, 1);
    await repository.restore(page.id);
    expect((await repository.all()).length, 1);
    await repository.trash(page.id);
    await repository.deleteForever(page.id);
    expect(await repository.get(page.id), isNull);
    final kinds = (await repository.outboxOps()).map((op) => op['kind']);
    expect(kinds, containsAll(['upsert', 'trash', 'restore', 'purge']));
  });

  test('export keeps the portable anamne.pages contract', () async {
    await repository.create();
    final exported = await repository.exportJson();
    expect(exported, contains('"format": "anamne.pages"'));
    expect(exported, contains('"version": 2'));
  });

  test('imported JSON pages re-enter the sync outbox', () async {
    await repository.importJson('''
{
  "format": "anamne.pages",
  "version": 2,
  "pages": [{
    "id": "imported-0001",
    "title": "Old note",
    "body": "brought over",
    "parentId": null,
    "updatedAt": "2026-10-15T00:00:00.000Z"
  }],
  "databases": []
}
''');
    final pages = await repository.all();
    expect(pages.map((p) => p.title), contains('Old note'));
    expect(await repository.outboxCount(), greaterThan(0));
  });
}
