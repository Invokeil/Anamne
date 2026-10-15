import http from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { AnamneStore, StoreError } from './store.js';

const token = process.env.ANAMNE_API_TOKEN;
if (!token || token.length < 24) {
  console.error('Set ANAMNE_API_TOKEN to a random value of at least 24 characters.');
  process.exit(1);
}

const store = new AnamneStore();
const host = process.env.ANAMNE_HOST || '127.0.0.1';
const port = Number(process.env.ANAMNE_PORT || 8787);

function authorize(header) {
  if (!header?.startsWith('Bearer ')) return false;
  const supplied = Buffer.from(header.slice(7));
  const expected = Buffer.from(token);
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}

function respond(res, status, body) {
  const serialized = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  res.end(serialized);
}

async function jsonBody(req) {
  if (!req.headers['content-type']?.startsWith('application/json')) {
    throw new StoreError('Content-Type must be application/json', 415);
  }
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 1_000_000) throw new StoreError('Request too large', 413);
    chunks.push(chunk);
  }
  try {
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error();
    return body;
  } catch {
    throw new StoreError('Expected JSON object');
  }
}

const server = http.createServer(async (req, res) => {
  try {
    if (!authorize(req.headers.authorization)) return respond(res, 401, { error: 'Unauthorized' });
    const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
    const path = url.pathname;
    let result;
    let status = 200;
    if (req.method === 'GET' && path === '/v1/health') result = { status: 'ok' };
    else if (req.method === 'GET' && path === '/v1/pages') result = {
      pages: store.list({ parentId: url.searchParams.has('parentId')
        ? url.searchParams.get('parentId') || null : undefined,
      deleted: url.searchParams.get('deleted') === 'true',
      limit: Number(url.searchParams.get('limit') || 100),
      offset: Number(url.searchParams.get('offset') || 0) }),
    };
    else if (req.method === 'POST' && path === '/v1/pages') {
      result = store.create(await jsonBody(req));
      status = 201;
    } else if (req.method === 'GET' && path === '/v1/search') result = {
      pages: store.search(url.searchParams.get('q') || '',
        { limit: Number(url.searchParams.get('limit') || 100) }),
    };
    else if (req.method === 'GET' && path === '/v1/export') result = store.export();
    else {
      const match = /^\/v1\/pages\/([a-f0-9-]{36})(?:\/(trash|restore|permanent))?$/.exec(path);
      if (!match) return respond(res, 404, { error: 'Not found' });
      const [, id, action] = match;
      if (req.method === 'GET' && !action) result = store.get(id, { includeDeleted: true });
      else if (req.method === 'PATCH' && !action) result = store.update(id, await jsonBody(req));
      else if (req.method === 'POST' && action === 'trash') result = store.trash(id);
      else if (req.method === 'POST' && action === 'restore') result = store.restore(id);
      else if (req.method === 'DELETE' && action === 'permanent') result = store.deleteForever(id);
      else return respond(res, 405, { error: 'Method not allowed' });
      if (result === null) return respond(res, 404, { error: 'Page not found' });
    }
    respond(res, status, result);
  } catch (error) {
    if (error instanceof StoreError) return respond(res, error.status, { error: error.message });
    console.error(error);
    respond(res, 500, { error: 'Internal error' });
  }
});

server.listen(port, host, () => console.error(`Anamne API listening on ${host}:${port}`));

function shutdown() { server.close(() => { store.close(); process.exit(0); }); }
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
