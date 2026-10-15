import 'dart:convert';

import 'package:anamne/store/database_doc.dart';
import 'package:anamne/store/page_repository.dart';
import 'package:anamne/sync/api_client.dart';
import 'package:anamne/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  late PageRepository repository;
  setUp(() async {
    repository = PageRepository(await databaseFactoryMemory.openDatabase(
        'sync-${DateTime.now().microsecondsSinceEpoch}.db'));
  });
  tearDown(() async => repository.close());

  test('a rejected operation is attempted once and does not starve pull', () async {
    final local = await repository.create();
    var pushes = 0;
    var pulls = 0;
    final engine = SyncEngine(repository, periodic: false, apiFactory: (url, token) =>
      AnamneApi(baseUrl: url, token: token, client: MockClient((request) async {
        if (request.url.path.endsWith('/push')) {
          pushes++;
          final ops = (jsonDecode(request.body) as Map<String, dynamic>)['ops'] as List;
          return http.Response(jsonEncode({'results': [for (final op in ops)
            {'opId': op['opId'], 'status': 'error', 'message': 'synthetic rejection'}]}), 200);
        }
        pulls++;
        return http.Response(jsonEncode({'cursor': 1, 'more': false, 'changes': [{
          'entity': 'page', 'id': 'remote', 'op': 'put', 'page': {
            'id': 'remote', 'title': 'Remote note', 'body': '', 'version': 1,
            'updatedAt': '2026-10-15T00:00:00.000Z',
          },
        }]}), 200);
      })));
    await engine.configure(serverUrl: 'https://sync.example.test', token: 'synthetic');
    await engine.runOnce().timeout(const Duration(seconds: 2));
    expect(pushes, 1);
    expect(pulls, 1);
    expect((await repository.get('remote'))!.title, 'Remote note');
    expect(await repository.hasPendingOpFor(local.id), isTrue);
    expect(engine.status.value.phase, SyncPhase.error);
    engine.dispose();
  });

  test('acknowledgement rebases an unsent edit before the next request', () async {
    final page = await repository.create();
    await repository.save(page.copyWith(title: 'Second edit'));
    final revisions = <Object?>[];
    var version = 0;
    final engine = SyncEngine(repository, periodic: false, apiFactory: (url, token) =>
      AnamneApi(baseUrl: url, token: token, client: MockClient((request) async {
        if (request.url.path.endsWith('/pull')) {
          return http.Response('{"cursor":0,"more":false,"changes":[]}', 200);
        }
        final ops = (jsonDecode(request.body) as Map<String, dynamic>)['ops'] as List;
        expect(ops, hasLength(1));
        revisions.add(ops.single['expectedVersion']);
        version++;
        return http.Response(jsonEncode({'results': [{
          'opId': ops.single['opId'], 'status': 'applied', 'version': version,
        }]}), 200);
      })));
    await engine.configure(serverUrl: 'https://sync.example.test', token: 'synthetic');
    await engine.runOnce();
    expect(revisions, [null, 1]);
    expect(await repository.outboxCount(), 0);
    expect((await repository.get(page.id))!.serverVersion, 2);
    engine.dispose();
  });

  test('database conflicts preserve local schema/records and queue the copy', () async {
    final db = await repository.createDatabase(title: 'Local tasks');
    await repository.saveDatabase(db.copyWith(
      schema: const [DbProp(id: 'name', name: 'Name', type: 'text')],
      records: const [DbRecord(id: 'r123', values: {'name': 'Keep this'})],
    ));
    await repository.resolveConflict('database', db.id, {
      'id': db.id, 'title': 'Server tasks', 'version': 4, 'schema': [], 'records': [],
    });
    final all = await repository.allDatabases();
    final copy = all.singleWhere((d) => d.id != db.id);
    expect(copy.title, contains('conflict'));
    expect(copy.schema.single.id, 'name');
    expect(copy.records.single.values['name'], 'Keep this');
    expect((await repository.getDatabase(db.id))!.title, 'Server tasks');
    final ops = await repository.outboxOps();
    expect(ops, hasLength(1));
    expect(ops.single['targetId'], copy.id);
    expect(ops.single['expectedVersion'], isNull);
  });

  test('remote purge preserves a pending local edit under a new ID', () async {
    final page = await repository.create();
    await repository.save(page.copyWith(title: 'Unsynced work'));
    await repository.deleteFromServer(page.id);
    expect(await repository.get(page.id), isNull);
    final copy = (await repository.all()).single;
    expect(copy.id, isNot(page.id));
    expect(copy.title, contains('Unsynced work'));
    expect((await repository.outboxOps()).single['targetId'], copy.id);
  });
}
