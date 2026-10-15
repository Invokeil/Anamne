import http from 'node:http';
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
  if (!header?.startsWith('Bearer ')) return null;
  return store.roleFor(header.slice(7));
}

const corsOrigins = new Set((process.env.ANAMNE_CORS_ORIGINS || '')
  .split(',').map(value => value.trim()).filter(Boolean));

function cors(req, res) {
  const origin = req.headers.origin;
  if (!origin) return true; // Native clients do not need browser CORS.
  let sameHost = false;
  try {
    const parsed = new URL(origin);
    sameHost = ['http:', 'https:'].includes(parsed.protocol) && parsed.host === req.headers.host;
  } catch { return false; }
  if (!sameHost && !corsOrigins.has(origin)) return false;
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PATCH, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Max-Age', '600');
  return true;
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

const PAGE_PATH = /^\/v1\/pages\/([a-f0-9-]{16,80})(?:\/(trash|restore|permanent))?$/;
const DB_PATH = /^\/v1\/databases\/([a-f0-9-]{16,80})(?:\/(trash|restore|permanent))?$/;
const TOKEN_PATH = /^\/v1\/tokens\/([a-f0-9]{64})$/;

const server = http.createServer(async (req, res) => {
  try {
    if (!cors(req, res)) return respond(res, 403, { error: 'Origin is not allowed' });
    // Preflight is unauthenticated; the actual request still needs a token.
    if (req.method === 'OPTIONS') {
      res.writeHead(204);
      return res.end();
    }
    // Unauthenticated liveness probe for load balancers and container healthchecks.
    if (req.method === 'GET' && req.url === '/health') {
      return respond(res, 200, { status: 'ok' });
    }
    const role = authorize(req.headers.authorization);
    if (!role) return respond(res, 401, { error: 'Unauthorized' });
    if (req.method !== 'GET' && role === 'viewer') {
      return respond(res, 403, { error: 'Forbidden: viewer role cannot write' });
    }
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
    else if (req.method === 'GET' && path === '/v1/sync/pull') result = store.syncPull({
      cursor: Number(url.searchParams.get('cursor') || 0),
      limit: Number(url.searchParams.get('limit') || 200),
    });
    else if (req.method === 'POST' && path === '/v1/sync/push') result = store.syncPush(await jsonBody(req));
    else if (req.method === 'GET' && path === '/v1/sync/status') result = store.syncStatus();
    else if (req.method === 'GET' && path === '/v1/databases') result = {
      databases: store.listDatabases({
        deleted: url.searchParams.get('deleted') === 'true',
        limit: Number(url.searchParams.get('limit') || 100),
        offset: Number(url.searchParams.get('offset') || 0),
      }),
    };
    else if (req.method === 'POST' && path === '/v1/databases') {
      result = store.createDatabase(await jsonBody(req));
      status = 201;
    } else if (path === '/v1/tokens' || TOKEN_PATH.test(path)) {
      if (role !== 'admin') return respond(res, 403, { error: 'Forbidden: admin role required' });
      if (req.method === 'GET' && path === '/v1/tokens') result = { tokens: store.listTokens() };
      else if (req.method === 'POST' && path === '/v1/tokens') {
        result = store.addToken(await jsonBody(req));
        status = 201;
      } else if (req.method === 'DELETE' && TOKEN_PATH.test(path)) {
        result = store.removeToken(TOKEN_PATH.exec(path)[1]);
      } else return respond(res, 405, { error: 'Method not allowed' });
    } else {
      const pageMatch = PAGE_PATH.exec(path);
      const dbMatch = DB_PATH.exec(path);
      if (pageMatch) {
        const [, id, action] = pageMatch;
        if (req.method === 'GET' && !action) result = store.get(id, { includeDeleted: true });
        else if (req.method === 'PATCH' && !action) result = store.update(id, await jsonBody(req));
        else if (req.method === 'POST' && action === 'trash') result = store.trash(id);
        else if (req.method === 'POST' && action === 'restore') result = store.restore(id);
        else if (req.method === 'DELETE' && action === 'permanent') result = store.deleteForever(id);
        else return respond(res, 405, { error: 'Method not allowed' });
        if (result === null) return respond(res, 404, { error: 'Page not found' });
      } else if (dbMatch) {
        const [, id, action] = dbMatch;
        if (req.method === 'GET' && !action) result = store.getDatabase(id, { includeDeleted: true });
        else if (req.method === 'PATCH' && !action) result = store.updateDatabase(id, await jsonBody(req));
        else if (req.method === 'POST' && action === 'trash') result = store.trashDatabase(id);
        else if (req.method === 'POST' && action === 'restore') result = store.restoreDatabase(id);
        else if (req.method === 'DELETE' && action === 'permanent') result = store.deleteDatabaseForever(id);
        else return respond(res, 405, { error: 'Method not allowed' });
        if (result === null) return respond(res, 404, { error: 'Database not found' });
      } else {
        return respond(res, 404, { error: 'Not found' });
      }
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
