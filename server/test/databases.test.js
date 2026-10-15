import assert from 'node:assert/strict';
import test from 'node:test';
import { AnamneStore } from '../src/store.js';

const SCHEMA = [
  { id: 'name', name: 'Name', type: 'text' },
  { id: 'status', name: 'Status', type: 'select', options: ['todo', 'doing', 'done'] },
  { id: 'points', name: 'Points', type: 'number' },
  { id: 'done', name: 'Done', type: 'checkbox' },
  { id: 'due', name: 'Due', type: 'date' },
];

test('databases: CRUD with typed schema and optimistic version checks', () => {
  const store = new AnamneStore(':memory:');
  try {
    const database = store.createDatabase({ title: 'Sprint board', schema: SCHEMA });
    assert.equal(database.version, 1);
    assert.deepEqual(database.schema.map(p => p.type),
      ['text', 'select', 'number', 'checkbox', 'date']);
    const updated = store.updateDatabase(database.id, {
      expectedVersion: 1,
      records: [{ id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', values: { name: 'Ship sync', status: 'doing', points: 5 } }],
    });
    assert.equal(updated.version, 2);
    assert.equal(updated.records[0].values.name, 'Ship sync');
    assert.throws(() => store.updateDatabase(database.id,
      { expectedVersion: 1, title: 'lost' }), /Version conflict/);
    const list = store.listDatabases();
    assert.equal(list.length, 1);
    store.trashDatabase(database.id);
    assert.equal(store.listDatabases().length, 0);
    store.restoreDatabase(database.id);
    assert.equal(store.listDatabases().length, 1);
    store.trashDatabase(database.id);
    store.deleteDatabaseForever(database.id);
    assert.equal(store.getDatabase(database.id, { includeDeleted: true }), null);
  } finally { store.close(); }
});

test('databases: rejects invalid schemas and oversized payloads', () => {
  const store = new AnamneStore(':memory:');
  try {
    assert.throws(() => store.createDatabase({ title: 'bad', schema: [{ id: 'x', name: 'X', type: 'magic' }] }),
      /type must be one of/);
    assert.throws(() => store.createDatabase({ title: 'dup', schema: [
      { id: 'a', name: 'A', type: 'text' }, { id: 'a', name: 'A2', type: 'text' },
    ] }), /duplicate/);
    assert.throws(() => store.createDatabase({ title: 'many', records: new Array(5001).fill(0)
      .map((_, i) => ({ id: `record-${i}`, values: {} })) }), /at most 5000/);
    const upserted = store.createDatabase({ title: 'ok' });
    const result = store.upsertDatabaseRecord(upserted.id, { record: { values: { any: 'shape' } } });
    assert.equal(result.database.records.length, 1);
    assert.ok(result.record.id, 'upsert generates a record id');
  } finally { store.close(); }
});
