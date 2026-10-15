import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

const ADMIN = 'admin-token-at-least-24-characters';
const EDITOR = 'editor-token-at-least-24-chars!';
const VIEWER = 'viewer-token-at-least-24-charss';

async function freePort() {
  const server = createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}

test('HTTP roles: viewer read-only, editor writes, admin manages tokens', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'anamne-roles-'));
  const port = await freePort();
  const child = spawn(process.execPath, ['src/http.js'], {
    cwd: join(import.meta.dirname, '..'),
    env: { ...process.env, ANAMNE_DB_PATH: join(directory, 'notes.sqlite'),
      ANAMNE_API_TOKEN: ADMIN,
      ANAMNE_TOKENS: `Editor:editor:${EDITOR};Watcher:viewer:${VIEWER}`,
      ANAMNE_PORT: `${port}` },
  });
  const base = `http://127.0.0.1:${port}/v1`;
  const call = (path, tokenValue, options = {}) => fetch(base + path, {
    ...options,
    headers: { Authorization: `Bearer ${tokenValue}`, 'Content-Type': 'application/json',
      ...options.headers },
  });
  try {
    let ready = false;
    for (let i = 0; i < 60; i++) {
      try {
        const response = await call('/health', ADMIN);
        if (response.ok) { ready = true; break; }
      } catch { /* process starts asynchronously */ }
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    assert.equal(ready, true, 'server should start');
    // Unknown token is rejected.
    assert.equal((await call('/pages', 'intruder-token-at-least-24-chars!!')).status, 401);
    // Viewer reads but cannot write.
    assert.equal((await call('/pages', VIEWER)).status, 200);
    assert.equal((await call('/pages', VIEWER, { method: 'POST', body: '{}' })).status, 403);
    assert.equal((await call('/sync/push', VIEWER, { method: 'POST', body: '{"ops":[]}' })).status, 403);
    // Editor writes pages and syncs but cannot manage tokens.
    const created = await call('/pages', EDITOR, { method: 'POST',
      body: JSON.stringify({ title: 'team note' }) });
    assert.equal(created.status, 201);
    const pushed = await call('/sync/push', EDITOR, { method: 'POST',
      body: JSON.stringify({ ops: [{ opId: 'role-op-1', entity: 'page', kind: 'upsert',
        record: { title: 'from editor' } }] }) });
    assert.equal(pushed.status, 200);
    assert.equal((await pushed.json()).results[0].status, 'applied');
    assert.equal((await call('/tokens', EDITOR)).status, 403);
    assert.equal((await call('/tokens', EDITOR, { method: 'POST', body: '{}' })).status, 403);
    // Admin manages tokens; new editor token can immediately write.
    const minted = await call('/tokens', ADMIN, { method: 'POST',
      body: JSON.stringify({ name: 'Temp', role: 'editor' }) });
    assert.equal(minted.status, 201);
    const mintedBody = await minted.json();
    assert.ok(mintedBody.token.length >= 24);
    const listed = await call('/tokens', ADMIN);
    assert.ok((await listed.json()).tokens.length >= 2);
    const revoked = await call(`/tokens/${mintedBody.id}`, ADMIN, { method: 'DELETE' });
    assert.equal(revoked.status, 200);
    const revokedWrite = await call('/pages', mintedBody.token,
      { method: 'POST', body: '{}' });
    assert.equal(revokedWrite.status, 401);
    // Sync pull works for any role.
    const pull = await call('/sync/pull?cursor=0', VIEWER);
    assert.equal(pull.status, 200);
    const pullBody = await pull.json();
    assert.ok(Array.isArray(pullBody.changes));
    const adminTokens = await (await call('/tokens', ADMIN)).json();
    const primary = adminTokens.tokens.find(item => item.name === 'primary');
    assert.equal((await call(`/tokens/${primary.id}`, ADMIN, { method: 'DELETE' })).status, 200);
    assert.equal((await call('/pages', ADMIN)).status, 401);
  } finally {
    child.kill('SIGTERM');
    await new Promise(resolve => child.once('exit', resolve));
    rmSync(directory, { recursive: true, force: true });
  }
});
