import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { AnamneStore } from '../src/store.js';

test('actual client targetId operations trash, restore and purge with revisions', () => {
  const s = new AnamneStore(':memory:');
  try {
    const p = s.create({ title: 'Client-shaped request' });
    for (const [index, kind] of ['trash', 'restore', 'trash', 'purge'].entries()) {
      const result = s.syncPush({ ops: [{ opId: `client-tree-${index}`, entity: 'page',
        kind, targetId: p.id, expectedVersion: index + 1 }] }).results[0];
      assert.equal(result.status, 'applied');
    }
    assert.equal(s.get(p.id, { includeDeleted: true }), null);
  } finally { s.close(); }
});

test('missing and stale revisions cannot overwrite existing pages or databases', () => {
  const s = new AnamneStore(':memory:');
  try {
    for (const entity of ['page', 'database']) {
      const p = entity === 'page' ? s.create({ title: 'Current' }) : s.createDatabase({ title: 'Current' });
      for (const [index, revision] of [null, 0, 99].entries()) {
        const result = s.syncPush({ ops: [{ opId: `${entity}-stale-${index}`, entity,
          kind: 'upsert', expectedVersion: revision, record: { id: p.id, title: 'Stale' } }] }).results[0];
        assert.equal(result.status, 'conflict');
      }
      assert.equal((entity === 'page' ? s.get(p.id) : s.getDatabase(p.id)).title, 'Current');
    }
  } finally { s.close(); }
});

test('purge emits every descendant tombstone and prevents stale resurrection', () => {
  const s = new AnamneStore(':memory:');
  try {
    const parent = s.create({ title: 'Parent' });
    const child = s.create({ title: 'Child', parentId: parent.id });
    s.trash(parent.id);
    const cursor = s.syncPull().cursor;
    s.deleteForever(parent.id);
    const deleted = s.syncPull({ cursor }).changes;
    assert.deepEqual(new Set(deleted.map(c => c.id)), new Set([parent.id, child.id]));
    assert.ok(deleted.every(c => c.op === 'delete'));
    for (const [index, id] of [parent.id, child.id].entries()) {
      const result = s.syncPush({ ops: [{ opId: `resurrect-${index}`, entity: 'page',
        kind: 'upsert', record: { id, title: 'Old offline content' } }] }).results[0];
      assert.equal(result.status, 'conflict');
      assert.equal(result.server, null);
      assert.equal(s.get(id, { includeDeleted: true }), null);
    }
  } finally { s.close(); }
});

test('mutation/change feed/acknowledgement roll back together when ack insert fails', () => {
  const s = new AnamneStore(':memory:');
  try {
    const p = s.create({ title: 'Before' });
    const cursor = s.syncPull().cursor;
    const op = { opId: 'fault-atomic-001', entity: 'page', kind: 'upsert', expectedVersion: 1,
      record: { id: p.id, title: 'After' } };
    s.db.exec("CREATE TRIGGER reject_ack BEFORE INSERT ON applied_ops BEGIN SELECT RAISE(ABORT, 'injected ack failure'); END");
    assert.throws(() => s.syncPush({ ops: [op] }), /injected ack failure/);
    assert.equal(s.get(p.id).version, 1);
    assert.equal(s.get(p.id).title, 'Before');
    assert.equal(s.syncPull({ cursor }).changes.length, 0);
    s.db.exec('DROP TRIGGER reject_ack');
    assert.equal(s.syncPush({ ops: [op] }).results[0].status, 'applied');
    assert.equal(s.syncPush({ ops: [op] }).results[0].replay, true);
    assert.equal(s.get(p.id).version, 2);
  } finally { s.close(); }
});

test('an idempotency key cannot be reused with different content', () => {
  const s = new AnamneStore(':memory:');
  try {
    const p = s.create({ title: 'Before' });
    const op = { opId: 'payload-check-001', entity: 'page', kind: 'upsert',
      expectedVersion: 1, record: { id: p.id, title: 'First' } };
    assert.equal(s.syncPush({ ops: [op] }).results[0].status, 'applied');
    assert.equal(s.syncPush({ ops: [{ ...op, record: { id: p.id, title: 'Different' } }] }).results[0].status, 'error');
    assert.equal(s.get(p.id).title, 'First');
  } finally { s.close(); }
});

test('MCP record upsert accepts UI-generated row IDs', () => {
  const s = new AnamneStore(':memory:');
  try {
    const db = s.createDatabase({ records: [{ id: 'r1792040000000000', values: { name: 'Old' } }] });
    const result = s.upsertDatabaseRecord(db.id, { expectedVersion: 1,
      record: { id: 'r1792040000000000', values: { name: 'New' } } });
    assert.equal(result.database.records.length, 1);
    assert.equal(result.database.records[0].values.name, 'New');
  } finally { s.close(); }
});

test('env-token revocation survives restart and env rotation removes old access', () => {
  const directory = mkdtempSync(join(tmpdir(), 'anamne-seed-revoke-'));
  const original = process.env.ANAMNE_API_TOKEN;
  const originalExtra = process.env.ANAMNE_TOKENS;
  const first = 'synthetic-original-token-32-characters';
  const second = 'synthetic-replacement-token-32-characters';
  const path = join(directory, 'notes.sqlite');
  let s;
  try {
    process.env.ANAMNE_TOKENS = '';
    process.env.ANAMNE_API_TOKEN = first;
    s = new AnamneStore(path);
    s.removeToken(s.listTokens()[0].id);
    assert.equal(s.roleFor(first), null);
    s.close();
    s = new AnamneStore(path);
    assert.equal(s.roleFor(first), null);
    s.close();
    process.env.ANAMNE_API_TOKEN = second;
    s = new AnamneStore(path);
    assert.equal(s.roleFor(first), null);
    assert.equal(s.roleFor(second), 'admin');
  } finally {
    s?.close();
    if (original === undefined) delete process.env.ANAMNE_API_TOKEN; else process.env.ANAMNE_API_TOKEN = original;
    if (originalExtra === undefined) delete process.env.ANAMNE_TOKENS; else process.env.ANAMNE_TOKENS = originalExtra;
    rmSync(directory, { recursive: true, force: true });
  }
});

test('rotating an env seed during upgrade removes the legacy named token', () => {
  const s = new AnamneStore(':memory:');
  const original = process.env.ANAMNE_API_TOKEN;
  const extra = process.env.ANAMNE_TOKENS;
  try {
    s.db.exec('DELETE FROM tokens; DELETE FROM env_token_seeds');
    s.addToken({ name: 'primary', role: 'admin', token: 'synthetic-legacy-token-with-32-chars' });
    process.env.ANAMNE_API_TOKEN = 'synthetic-new-token-with-32-characters';
    process.env.ANAMNE_TOKENS = '';
    s.seedTokensFromEnv();
    assert.equal(s.roleFor('synthetic-legacy-token-with-32-chars'), null);
    assert.equal(s.roleFor(process.env.ANAMNE_API_TOKEN), 'admin');
  } finally {
    s.close();
    if (original === undefined) delete process.env.ANAMNE_API_TOKEN; else process.env.ANAMNE_API_TOKEN = original;
    if (extra === undefined) delete process.env.ANAMNE_TOKENS; else process.env.ANAMNE_TOKENS = extra;
  }
});
