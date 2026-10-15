import assert from 'node:assert/strict';
import test from 'node:test';
import { AnamneStore } from '../src/store.js';

test('sync push creates, updates, replays idempotently and detects conflicts', () => {
  const store = new AnamneStore(':memory:');
  try {
    const opId = 'op-0001-create-page';
    const first = store.syncPush({ ops: [{
      opId, entity: 'page', kind: 'upsert',
      record: { id: '11111111-1111-4111-8111-111111111111', title: 'ডিভাইস নোট', body: 'offline edit' },
    }] });
    assert.equal(first.results[0].status, 'applied');
    assert.equal(first.results[0].version, 1);
    const replay = store.syncPush({ ops: [{
      opId, entity: 'page', kind: 'upsert',
      record: { id: '11111111-1111-4111-8111-111111111111', title: 'ডিভাইস নোট', body: 'offline edit' },
    }] });
    assert.equal(replay.results[0].status, 'applied');
    assert.equal(replay.results[0].replay, true);
    assert.equal(store.get('11111111-1111-4111-8111-111111111111').title, 'ডিভাইস নোট');
    const update = store.syncPush({ ops: [{
      opId: 'op-0002-update-page', entity: 'page', kind: 'upsert', expectedVersion: 1,
      record: { id: '11111111-1111-4111-8111-111111111111', title: 'দ্বিতীয় সংস্করণ', body: 'updated' },
    }] });
    assert.equal(update.results[0].status, 'applied');
    assert.equal(update.results[0].version, 2);
    const conflict = store.syncPush({ ops: [{
      opId: 'op-0003-stale', entity: 'page', kind: 'upsert', expectedVersion: 1,
      record: { id: '11111111-1111-4111-8111-111111111111', title: 'stale', body: 'stale' },
    }] });
    assert.equal(conflict.results[0].status, 'conflict');
    assert.equal(conflict.results[0].serverVersion, 2);
    assert.equal(store.get('11111111-1111-4111-8111-111111111111').title, 'দ্বিতীয় সংস্করণ');
  } finally { store.close(); }
});

test('sync pull returns current state after the cursor, including tombstones', () => {
  const store = new AnamneStore(':memory:');
  try {
    store.create({ id: '22222222-2222-4222-8222-222222222222', title: 'Root' });
    store.create({ id: '33333333-3333-4333-8333-333333333333', title: 'Child',
      parentId: '22222222-2222-4222-8222-222222222222' });
    store.trash('22222222-2222-4222-8222-222222222222');
    const page = store.syncPull({ cursor: 0 });
    assert.equal(page.cursor > 0, true);
    assert.equal(page.changes.length, 2);
    const root = page.changes.find(c => c.id === '22222222-2222-4222-8222-222222222222');
    assert.equal(root.op, 'put');
    assert.ok(root.page.deletedAt, 'trashed page snapshot carries deletedAt');
    store.deleteForever('22222222-2222-4222-8222-222222222222');
    const after = store.syncPull({ cursor: page.cursor });
    const tombstone = after.changes.find(c => c.id === '22222222-2222-4222-8222-222222222222');
    assert.equal(tombstone.op, 'delete');
    // Pulling from 0 again returns the latest state per id (2 pages, one gone).
    const fresh = store.syncPull({ cursor: 0 });
    assert.equal(fresh.changes.length, 2);
  } finally { store.close(); }
});

test('sync handles database upserts and trash/restore/purge ops', () => {
  const store = new AnamneStore(':memory:');
  try {
    const dbId = '44444444-4444-4444-8444-444444444444';
    store.syncPush({ ops: [{
      opId: 'op-db-1', entity: 'database', kind: 'upsert',
      record: { id: dbId, title: 'Tasks', schema: [{ id: 'status', name: 'Status', type: 'select', options: ['todo', 'done'] }] },
    }] });
    const added = store.upsertDatabaseRecord(dbId, { record: { values: { status: 'todo', text: 'buy tea' } } });
    assert.equal(added.database.records.length, 1);
    assert.equal(added.database.records[0].values.text, 'buy tea');
    const updated = store.upsertDatabaseRecord(dbId, {
      record: { id: added.record.id, values: { status: 'done' } },
      expectedVersion: added.database.version,
    });
    assert.equal(updated.database.version, added.database.version + 1);
    assert.equal(updated.database.records[0].values.status, 'done');
    store.syncPush({ ops: [{ opId: 'op-db-2', entity: 'database', kind: 'trash', id: dbId, expectedVersion: 3 }] });
    assert.equal(store.getDatabase(dbId), null);
    assert.ok(store.getDatabase(dbId, { includeDeleted: true }).deletedAt);
    store.syncPush({ ops: [{ opId: 'op-db-2', entity: 'database', kind: 'trash', id: dbId, expectedVersion: 3 }] }); // replay
    assert.equal(store.getDatabase(dbId, { includeDeleted: true }).version,
      store.getDatabase(dbId, { includeDeleted: true }).version);
    store.syncPush({ ops: [{ opId: 'op-db-3', entity: 'database', kind: 'restore', id: dbId, expectedVersion: 4 }] });
    assert.ok(store.getDatabase(dbId));
  } finally { store.close(); }
});

test('sync push of unknown ops reports per-op errors without failing the batch', () => {
  const store = new AnamneStore(':memory:');
  try {
    const bad = store.syncPush({ ops: [
      { opId: 'op-bad-1', entity: 'widget', kind: 'upsert', record: {} },
      { opId: 'op-bad-2', entity: 'page', kind: 'explode', id: '55555555-5555-4555-8555-555555555555' },
      { opId: 'op-good-1', entity: 'page', kind: 'upsert',
        record: { id: '55555555-5555-4555-8555-555555555555', title: 'still applies' } },
    ] });
    assert.equal(bad.results[0].status, 'error');
    assert.equal(bad.results[1].status, 'error');
    assert.equal(bad.results[2].status, 'applied');
  } finally { store.close(); }
});
