import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

async function freePort() {
  const server = createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}

test('HTTP requires a token and preserves versions on writes', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'anamne-http-'));
  const port = await freePort();
  const token = 'test-token-at-least-24-characters';
  const child = spawn(process.execPath, ['src/http.js'], {
    cwd: join(import.meta.dirname, '..'),
    env: { ...process.env, ANAMNE_DB_PATH: join(directory, 'notes.sqlite'),
      ANAMNE_API_TOKEN: token, ANAMNE_PORT: `${port}` },
  });
  const base = `http://127.0.0.1:${port}/v1`;
  const request = (path, options = {}) => fetch(base + path, {
    ...options,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json',
      ...options.headers },
  });
  try {
    let ready = false;
    for (let i = 0; i < 60; i++) {
      try {
        const response = await request('/health');
        if (response.ok) { ready = true; break; }
      } catch { /* process starts asynchronously */ }
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    assert.equal(ready, true, 'server should start');
    assert.equal((await fetch(base + '/pages')).status, 401);
    const created = await request('/pages', { method: 'POST',
      body: JSON.stringify({ title: 'নোট', properties: { color: 'blue' } }) });
    assert.equal(created.status, 201);
    const page = await created.json();
    assert.equal((await request(`/pages/${page.id}`)).status, 200);
    const edit = await request(`/pages/${page.id}`, { method: 'PATCH',
      body: JSON.stringify({ expectedVersion: page.version, body: 'hello' }) });
    assert.equal(edit.status, 200);
    assert.equal((await edit.json()).version, 2);
    const stale = await request(`/pages/${page.id}`, { method: 'PATCH',
      body: JSON.stringify({ expectedVersion: page.version, body: 'stale' }) });
    assert.equal(stale.status, 409);
  } finally {
    child.kill('SIGTERM');
    await new Promise(resolve => child.once('exit', resolve));
    rmSync(directory, { recursive: true, force: true });
  }
});
