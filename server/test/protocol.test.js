import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createInterface } from 'node:readline';
import test from 'node:test';

test('MCP stdio handshake, tool discovery and page round trip', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'anamne-mcp-'));
  const child = spawn(process.execPath, ['src/mcp.js'], {
    cwd: join(import.meta.dirname, '..'),
    env: { ...process.env, ANAMNE_DB_PATH: join(directory, 'notes.sqlite') },
  });
  const lines = createInterface({ input: child.stdout });
  const iterator = lines[Symbol.asyncIterator]();
  const call = async (id, method, params = {}) => {
    child.stdin.write(JSON.stringify({ jsonrpc: '2.0', id, method, params }) + '\n');
    const line = await iterator.next();
    assert.equal(line.done, false);
    return JSON.parse(line.value);
  };
  try {
    const init = await call(1, 'initialize', { protocolVersion: '2025-11-25' });
    assert.equal(init.result.serverInfo.name, 'anamne');
    assert.equal((await call(2, 'tools/list')).result.tools.length, 9);
    const created = await call(3, 'tools/call',
      { name: 'create_page', arguments: { title: 'MCP page' } });
    const page = created.result.structuredContent;
    assert.equal(page.title, 'MCP page');
    const fetched = await call(4, 'tools/call',
      { name: 'get_page', arguments: { id: page.id } });
    assert.equal(fetched.result.structuredContent.id, page.id);
  } finally {
    child.stdin.end();
    child.kill();
    lines.close();
    rmSync(directory, { recursive: true, force: true });
  }
});
