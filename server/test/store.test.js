import assert from 'node:assert/strict';
import test from 'node:test';
import { AnamneStore } from '../src/store.js';

test('nested pages, search, version conflicts, trash and restore', () => {
  const store = new AnamneStore(':memory:');
  try {
    const root = store.create({ title: 'বাংলা নোট', body: 'প্রথম খসড়া' });
    const child = store.create({ parentId: root.id, title: 'Child', body: 'hello' });
    assert.equal(store.search('বাংলা')[0].id, root.id);
    assert.equal(store.list({ parentId: root.id })[0].id, child.id);
    const changed = store.update(root.id, { expectedVersion: root.version,
      body: 'updated', properties: { category: 'notes' } });
    assert.equal(changed.version, 2);
    assert.deepEqual(changed.properties, { category: 'notes' });
    assert.throws(() => store.update(root.id, { expectedVersion: 1, title: 'lost' }),
      /Version conflict/);
    assert.throws(() => store.update(root.id,
      { expectedVersion: 2, parentId: child.id }), /descendants/);
    store.trash(root.id);
    assert.equal(store.get(child.id), null);
    store.restore(root.id);
    assert.equal(store.get(child.id)?.title, 'Child');
    assert.equal(store.export().pages.length, 2);
    store.trash(root.id);
    store.deleteForever(root.id);
    assert.equal(store.export().pages.length, 0);
  } finally { store.close(); }
});

test('search treats SQL wildcards as literals', () => {
  const store = new AnamneStore(':memory:');
  try {
    store.create({ title: '100% notes' });
    store.create({ title: 'another entry' });
    assert.equal(store.search('%').length, 1);
    assert.equal(store.search('_').length, 0);
  } finally { store.close(); }
});
