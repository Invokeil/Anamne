import { DatabaseSync } from 'node:sqlite';
import { createHash, randomUUID } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export class StoreError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

function expectString(value, field, max = 200000) {
  if (typeof value !== 'string' || value.length > max) {
    throw new StoreError(`${field} must be a string of at most ${max} characters`);
  }
  return value;
}

function expectId(value, field = 'id') {
  expectString(value, field, 80);
  if (!/^[a-f0-9-]{16,80}$/i.test(value)) {
    throw new StoreError(`${field} must be a UUID-like identifier`);
  }
  return value;
}

function expectSlug(value, field, max = 40) {
  expectString(value, field, max);
  if (!/^[A-Za-z0-9_-]{1,40}$/.test(value)) {
    throw new StoreError(`${field} must be 1–40 characters of A–Z, a–z, 0–9, _ or -`);
  }
  return value;
}

function validateProperties(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new StoreError('properties must be a JSON object');
  }
  if (JSON.stringify(value).length > 100000) {
    throw new StoreError('properties are too large');
  }
  return value;
}

const PAGE_TYPES = ['page', 'canvas'];
const PROP_TYPES = ['text', 'number', 'select', 'multiSelect', 'checkbox', 'date'];

function validateBlocks(value) {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value)) throw new StoreError('blocks must be an array');
  const serialized = JSON.stringify(value);
  if (serialized.length > 500000) throw new StoreError('blocks are too large');
  return value;
}

function validateData(value) {
  if (value === undefined) return null;
  if (value === null) return null;
  if (typeof value !== 'object' || Array.isArray(value)) {
    throw new StoreError('data must be a JSON object');
  }
  if (JSON.stringify(value).length > 500000) throw new StoreError('data is too large');
  return value;
}

function validateSchema(value) {
  if (!Array.isArray(value)) throw new StoreError('schema must be an array of properties');
  if (value.length > 64) throw new StoreError('schema supports at most 64 properties');
  const seen = new Set();
  for (const prop of value) {
    if (!prop || typeof prop !== 'object' || Array.isArray(prop)) {
      throw new StoreError('each schema entry must be an object');
    }
    expectSlug(prop.id, 'schema property id');
    if (seen.has(prop.id)) throw new StoreError(`duplicate schema property ${prop.id}`);
    seen.add(prop.id);
    expectString(prop.name, 'schema property name', 120);
    if (!PROP_TYPES.includes(prop.type)) {
      throw new StoreError(`schema property type must be one of ${PROP_TYPES.join(', ')}`);
    }
    if (prop.type === 'select' || prop.type === 'multiSelect') {
      if (prop.options !== undefined) {
        if (!Array.isArray(prop.options) || prop.options.length > 64) {
          throw new StoreError('select options must be an array of at most 64 strings');
        }
        for (const option of prop.options) expectString(option, 'select option', 120);
      }
    }
  }
  return value;
}

function validateRecords(value) {
  if (!Array.isArray(value)) throw new StoreError('records must be an array');
  if (value.length > 5000) throw new StoreError('databases support at most 5000 records');
  for (const record of value) {
    if (!record || typeof record !== 'object' || Array.isArray(record)) {
      throw new StoreError('each record must be an object');
    }
    expectSlug(record.id, 'record id');
    if (record.values == null || typeof record.values !== 'object' || Array.isArray(record.values)) {
      throw new StoreError('record values must be a JSON object');
    }
  }
  if (JSON.stringify(value).length > 2000000) throw new StoreError('records are too large');
  return value;
}

function rowToPage(row) {
  if (!row) return null;
  return {
    id: row.id,
    parentId: row.parent_id,
    title: row.title,
    body: row.body,
    type: row.type || 'page',
    blocks: JSON.parse(row.blocks_json || '[]'),
    data: row.data_json ? JSON.parse(row.data_json) : null,
    properties: JSON.parse(row.properties_json),
    version: row.version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  };
}

function rowToDatabase(row) {
  if (!row) return null;
  return {
    id: row.id,
    title: row.title,
    schema: JSON.parse(row.schema_json),
    records: JSON.parse(row.records_json),
    version: row.version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  };
}

function hashToken(token) {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}

function canonicalJson(value) {
  if (Array.isArray(value)) return value.map(canonicalJson);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonicalJson(value[key])]));
  }
  return value;
}

export class AnamneStore {
  constructor(path = process.env.ANAMNE_DB_PATH || './data/anamne.sqlite') {
    if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
    this._txDepth = 0;
    this.db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS pages (
        id TEXT PRIMARY KEY,
        parent_id TEXT REFERENCES pages(id) ON DELETE SET NULL,
        title TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        properties_json TEXT NOT NULL DEFAULT '{}',
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      );
      CREATE INDEX IF NOT EXISTS pages_parent ON pages(parent_id);
      CREATE INDEX IF NOT EXISTS pages_updated ON pages(updated_at DESC);
      CREATE TABLE IF NOT EXISTS changes (
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        entity TEXT NOT NULL,
        id TEXT NOT NULL,
        op TEXT NOT NULL,
        ts TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS changes_id ON changes(entity, id);
      CREATE TABLE IF NOT EXISTS applied_ops (
        op_id TEXT PRIMARY KEY,
        applied_at TEXT NOT NULL,
        result_json TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS databases (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        schema_json TEXT NOT NULL DEFAULT '[]',
        records_json TEXT NOT NULL DEFAULT '[]',
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      );
      CREATE TABLE IF NOT EXISTS tokens (
        token_hash TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        role TEXT NOT NULL CHECK (role IN ('admin','editor','viewer')),
        hint TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS revoked_tokens (
        token_hash TEXT PRIMARY KEY, revoked_at TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS env_token_seeds (
        name TEXT PRIMARY KEY, token_hash TEXT NOT NULL
      );
      CREATE TABLE IF NOT EXISTS purged_entities (
        entity TEXT NOT NULL, id TEXT NOT NULL, version INTEGER NOT NULL,
        purged_at TEXT NOT NULL, PRIMARY KEY(entity, id)
      );
    `);
    // Migrate pre-0.2 databases: pages gain the structured columns.
    const columns = this.db.prepare('PRAGMA table_info(pages)').all().map(c => c.name);
    if (!columns.includes('type')) {
      this.db.exec("ALTER TABLE pages ADD COLUMN type TEXT NOT NULL DEFAULT 'page'");
    }
    if (!columns.includes('blocks_json')) {
      this.db.exec("ALTER TABLE pages ADD COLUMN blocks_json TEXT NOT NULL DEFAULT '[]'");
    }
    if (!columns.includes('data_json')) {
      this.db.exec('ALTER TABLE pages ADD COLUMN data_json TEXT');
    }
    const opColumns = this.db.prepare('PRAGMA table_info(applied_ops)').all().map(c => c.name);
    if (!opColumns.includes('payload_hash')) this.db.exec('ALTER TABLE applied_ops ADD COLUMN payload_hash TEXT');
    // Existing 0.1 records must also appear in a new device's initial pull.
    for (const [entity, table] of [['page', 'pages'], ['database', 'databases']]) {
      this.db.prepare(`INSERT INTO changes(entity,id,op,ts)
        SELECT ?,p.id,'put',p.updated_at FROM ${table} p
        WHERE NOT EXISTS (SELECT 1 FROM changes c WHERE c.entity=? AND c.id=p.id)`)
        .run(entity, entity);
    }
    this.seedTokensFromEnv();
  }

  close() { this.db.close(); }

  // ---------------------------------------------------------------- tokens

  seedTokensFromEnv() {
    const seeds = [];
    if (process.env.ANAMNE_API_TOKEN) {
      seeds.push({ name: 'primary', role: 'admin', token: process.env.ANAMNE_API_TOKEN });
    }
    const extra = process.env.ANAMNE_TOKENS; // "Alice:admin:token1;Bob:editor:token2"
    if (extra) {
      for (const part of extra.split(';')) {
        const match = /^([^:]+):(admin|editor|viewer):(.+)$/.exec(part.trim());
        if (match) seeds.push({ name: match[1], role: match[2], token: match[3] });
      }
    }
    const now = new Date().toISOString();
    for (const seed of seeds) {
      const tokenHash = hashToken(seed.token);
      const previous = this.db.prepare('SELECT token_hash FROM env_token_seeds WHERE name=?').get(seed.name);
      // 0.2.0 did not track env seeds separately. Adopt its named seed once,
      // removing an old value when the owner rotates it during this upgrade.
      if (!previous) {
        this.db.prepare('DELETE FROM tokens WHERE name=? AND token_hash<>?').run(seed.name, tokenHash);
      }
      if (previous && previous.token_hash !== tokenHash) {
        this.db.prepare('DELETE FROM tokens WHERE token_hash=?').run(previous.token_hash);
      }
      this.db.prepare('INSERT INTO env_token_seeds(name,token_hash) VALUES (?,?) ON CONFLICT(name) DO UPDATE SET token_hash=excluded.token_hash')
        .run(seed.name, tokenHash);
      if (this.db.prepare('SELECT 1 FROM revoked_tokens WHERE token_hash=?').get(tokenHash)) continue;
      this.db.prepare(`INSERT INTO tokens (token_hash, name, role, hint, created_at)
        VALUES (?,?,?,?,?)
        ON CONFLICT(token_hash) DO UPDATE SET name = excluded.name, role = excluded.role`)
        .run(tokenHash, seed.name, seed.role,
          `…${seed.token.slice(-4)}`, now);
    }
  }

  roleFor(token) {
    if (typeof token !== 'string' || token.length === 0 || token.length > 200) return null;
    const row = this.db.prepare('SELECT role FROM tokens WHERE token_hash = ?')
      .get(hashToken(token));
    return row ? row.role : null;
  }

  listTokens() {
    return this.db.prepare(
      'SELECT token_hash AS id, name, role, hint, created_at AS createdAt FROM tokens ORDER BY created_at, name')
      .all();
  }

  addToken({ name, role, token } = {}) {
    expectString(name, 'name', 80);
    if (!['admin', 'editor', 'viewer'].includes(role)) {
      throw new StoreError('role must be admin, editor or viewer');
    }
    let value = token;
    if (value === undefined) value = randomUUID().replaceAll('-', '') + randomUUID().replaceAll('-', '');
    expectString(value, 'token', 200);
    if (value.length < 24) throw new StoreError('token must be at least 24 characters');
    if (this.db.prepare('SELECT 1 FROM revoked_tokens WHERE token_hash=?').get(hashToken(value))) {
      throw new StoreError('This token was revoked; generate a new token', 409);
    }
    const now = new Date().toISOString();
    this.db.prepare(`INSERT INTO tokens (token_hash, name, role, hint, created_at) VALUES (?,?,?,?,?)`)
      .run(hashToken(value), name, role, `…${value.slice(-4)}`, now);
    return { id: hashToken(value), name, role, hint: `…${value.slice(-4)}`, token: value, createdAt: now };
  }

  removeToken(id) {
    expectString(id, 'token id', 128);
    this._begin();
    try {
      const result = this.db.prepare('DELETE FROM tokens WHERE token_hash = ?').run(id);
      if (result.changes !== 1) throw new StoreError('Token not found', 404);
      this.db.prepare('INSERT OR REPLACE INTO revoked_tokens(token_hash,revoked_at) VALUES (?,?)')
        .run(id, new Date().toISOString());
      this._commit();
    } catch (error) { this._rollback(); throw error; }
    return { deleted: true, id };
  }

  // ------------------------------------------------------------- change log

  _logChange(txn, entity, id, op) {
    txn.prepare('INSERT INTO changes (entity, id, op, ts) VALUES (?,?,?,?)')
      .run(entity, id, op, new Date().toISOString());
  }

  _begin() {
    this.db.exec(this._txDepth === 0 ? 'BEGIN IMMEDIATE' : `SAVEPOINT anamne_${this._txDepth}`);
    this._txDepth++;
  }
  _commit() {
    const depth = this._txDepth - 1;
    this.db.exec(depth === 0 ? 'COMMIT' : `RELEASE SAVEPOINT anamne_${depth}`);
    this._txDepth = depth;
  }
  _rollback() {
    const depth = this._txDepth - 1;
    if (depth < 0) return;
    this.db.exec(depth === 0 ? 'ROLLBACK' : `ROLLBACK TO SAVEPOINT anamne_${depth}`);
    if (depth > 0) this.db.exec(`RELEASE SAVEPOINT anamne_${depth}`);
    this._txDepth = depth;
  }

  _purged(entity, id) {
    return this.db.prepare('SELECT version FROM purged_entities WHERE entity=? AND id=?').get(entity, id);
  }

  _rememberPurge(entity, id, version) {
    this.db.prepare('INSERT OR REPLACE INTO purged_entities(entity,id,version,purged_at) VALUES (?,?,?,?)')
      .run(entity, id, version, new Date().toISOString());
    this._logChange(this.db, entity, id, 'delete');
  }

  // ------------------------------------------------------------------ pages

  get(id, { includeDeleted = false } = {}) {
    expectId(id);
    const row = this.db.prepare('SELECT * FROM pages WHERE id = ?').get(id);
    if (!row || (row.deleted_at && !includeDeleted)) return null;
    return rowToPage(row);
  }

  list({ parentId, deleted = false, limit = 100, offset = 0 } = {}) {
    if (!Number.isInteger(limit) || limit < 1 || limit > 500) throw new StoreError('limit must be 1–500');
    if (!Number.isInteger(offset) || offset < 0) throw new StoreError('offset must be nonnegative');
    let sql = 'SELECT * FROM pages WHERE deleted_at IS ' + (deleted ? 'NOT NULL' : 'NULL');
    const args = [];
    if (parentId !== undefined) {
      if (parentId !== null) expectId(parentId, 'parentId');
      sql += parentId === null ? ' AND parent_id IS NULL' : ' AND parent_id = ?';
      if (parentId !== null) args.push(parentId);
    }
    sql += ' ORDER BY updated_at DESC, id LIMIT ? OFFSET ?';
    return this.db.prepare(sql).all(...args, limit, offset).map(rowToPage);
  }

  search(query, { limit = 100 } = {}) {
    expectString(query, 'query', 500);
    if (!Number.isInteger(limit) || limit < 1 || limit > 500) throw new StoreError('limit must be 1–500');
    // Bound input is treated literally; escape LIKE wildcards.
    const pattern = `%${query.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%`;
    return this.db.prepare(`SELECT * FROM pages WHERE deleted_at IS NULL
      AND (title LIKE ? ESCAPE '\\' OR body LIKE ? ESCAPE '\\')
      ORDER BY updated_at DESC, id LIMIT ?`).all(pattern, pattern, limit).map(rowToPage);
  }

  create({ title = '', body = '', parentId = null, properties = {}, id, type = 'page', blocks = [], data = null } = {}) {
    expectString(title, 'title', 500);
    expectString(body, 'body');
    validateProperties(properties);
    validateBlocks(blocks);
    validateData(data);
    if (!PAGE_TYPES.includes(type)) throw new StoreError(`type must be one of ${PAGE_TYPES.join(', ')}`);
    if (parentId !== null && !this.get(parentId)) throw new StoreError('Parent page not found', 404);
    const key = id === undefined ? randomUUID() : expectId(id);
    if (this._purged('page', key)) throw new StoreError('Page was permanently deleted; create a new ID', 409);
    const now = new Date().toISOString();
    if (this.db.prepare('SELECT 1 FROM pages WHERE id = ?').get(key)) {
      throw new StoreError('Page already exists', 409);
    }
    this._begin();
    try {
      this.db.prepare(`INSERT INTO pages
        (id,parent_id,title,body,properties_json,version,created_at,updated_at,deleted_at,type,blocks_json,data_json)
        VALUES (?,?,?,?,?,1,?,?,NULL,?,?,?)`)
        .run(key, parentId, title, body, JSON.stringify(properties), now, now, type,
          JSON.stringify(blocks), data === null ? null : JSON.stringify(data));
      this._logChange(this.db, 'page', key, 'put');
      this._commit();
    } catch (error) {
      this._rollback();
      throw error;
    }
    return this.get(key);
  }

  update(id, input = {}) {
    const existing = this.get(id);
    if (!existing) throw new StoreError('Page not found', 404);
    if (!Number.isInteger(input.expectedVersion)) throw new StoreError('expectedVersion is required');
    if (existing.version !== input.expectedVersion) throw new StoreError('Version conflict', 409);
    const title = input.title === undefined ? existing.title : expectString(input.title, 'title', 500);
    const body = input.body === undefined ? existing.body : expectString(input.body, 'body');
    const properties = input.properties === undefined
      ? existing.properties : validateProperties(input.properties);
    const blocks = input.blocks === undefined ? existing.blocks : validateBlocks(input.blocks);
    const data = input.data === undefined ? existing.data : validateData(input.data);
    const type = input.type === undefined ? existing.type : input.type;
    if (!PAGE_TYPES.includes(type)) throw new StoreError(`type must be one of ${PAGE_TYPES.join(', ')}`);
    const parentId = input.parentId === undefined ? existing.parentId : input.parentId;
    if (parentId !== null) {
      expectId(parentId, 'parentId');
      if (!this.get(parentId)) throw new StoreError('Parent page not found', 404);
      if (parentId === id || this.descendantIds(id).includes(parentId)) {
        throw new StoreError('A page cannot be placed inside itself or its descendants');
      }
    }
    const now = new Date().toISOString();
    this._begin();
    try {
      const result = this.db.prepare(`UPDATE pages SET title=?,body=?,properties_json=?,parent_id=?,
        updated_at=?,version=version+1,type=?,blocks_json=?,data_json=? WHERE id=? AND version=? AND deleted_at IS NULL`)
        .run(title, body, JSON.stringify(properties), parentId, now, type,
          JSON.stringify(blocks), data === null ? null : JSON.stringify(data),
          id, input.expectedVersion);
      if (result.changes !== 1) throw new StoreError('Version conflict', 409);
      this._logChange(this.db, 'page', id, 'put');
      this._commit();
    } catch (error) {
      this._rollback();
      throw error;
    }
    return this.get(id);
  }

  descendantIds(id) {
    return this.db.prepare(`WITH RECURSIVE descendants(id) AS (
      SELECT id FROM pages WHERE parent_id = ?
      UNION SELECT p.id FROM pages p JOIN descendants d ON p.parent_id=d.id
    ) SELECT id FROM descendants`).all(id).map(row => row.id);
  }

  _changeTree(id, deleted) {
    const page = this.get(id, { includeDeleted: true });
    if (!page) throw new StoreError('Page not found', 404);
    if (deleted && page.deletedAt) return page; // already trashed: idempotent
    if (!deleted && !page.deletedAt) return page; // already live: idempotent
    const ids = [id, ...this.descendantIds(id)];
    const now = new Date().toISOString();
    const statement = this.db.prepare(
      'UPDATE pages SET deleted_at=?,updated_at=?,version=version+1 WHERE id=?');
    this._begin();
    try {
      for (const key of ids) {
        statement.run(deleted ? now : null, now, key);
        this._logChange(this.db, 'page', key, 'put');
      }
      this._commit();
    } catch (error) {
      this._rollback();
      throw error;
    }
    return this.get(id, { includeDeleted: true });
  }

  trash(id) { return this._changeTree(id, true); }
  restore(id) { return this._changeTree(id, false); }

  deleteForever(id) {
    const page = this.get(id, { includeDeleted: true });
    if (!page) throw new StoreError('Page not found', 404);
    if (!page.deletedAt) throw new StoreError('Move page to trash first', 409);
    const ids = [id, ...this.descendantIds(id)];
    this._begin();
    try {
      for (const key of ids.reverse()) {
        const row = this.db.prepare('SELECT version FROM pages WHERE id=?').get(key);
        this._rememberPurge('page', key, (row?.version ?? 0) + 1);
        this.db.prepare('DELETE FROM pages WHERE id=?').run(key);
      }
      this._commit();
    } catch (error) {
      this._rollback();
      throw error;
    }
    return { deleted: true, id };
  }

  export() {
    const pages = this.db.prepare('SELECT * FROM pages ORDER BY created_at, id').all().map(rowToPage);
    const databases = this.db.prepare('SELECT * FROM databases ORDER BY created_at, id').all().map(rowToDatabase);
    return {
      format: 'anamne.pages', version: 2,
      exportedAt: new Date().toISOString(), pages, databases,
    };
  }

  // -------------------------------------------------------------- databases

  getDatabase(id, { includeDeleted = false } = {}) {
    expectId(id);
    const row = this.db.prepare('SELECT * FROM databases WHERE id = ?').get(id);
    if (!row || (row.deleted_at && !includeDeleted)) return null;
    return rowToDatabase(row);
  }

  listDatabases({ deleted = false, limit = 100, offset = 0 } = {}) {
    if (!Number.isInteger(limit) || limit < 1 || limit > 500) throw new StoreError('limit must be 1–500');
    if (!Number.isInteger(offset) || offset < 0) throw new StoreError('offset must be nonnegative');
    return this.db.prepare(`SELECT * FROM databases WHERE deleted_at IS
      ${deleted ? 'NOT NULL' : 'NULL'} ORDER BY updated_at DESC, id LIMIT ? OFFSET ?`)
      .all(limit, offset).map(rowToDatabase);
  }

  createDatabase({ title = '', schema = [], records = [], id } = {}) {
    expectString(title, 'title', 500);
    validateSchema(schema);
    validateRecords(records);
    const key = id === undefined ? randomUUID() : expectId(id);
    if (this._purged('database', key)) throw new StoreError('Database was permanently deleted; create a new ID', 409);
    if (this.db.prepare('SELECT 1 FROM databases WHERE id = ?').get(key)) {
      throw new StoreError('Database already exists', 409);
    }
    const now = new Date().toISOString();
    this._begin();
    try {
      this.db.prepare(`INSERT INTO databases
        (id,title,schema_json,records_json,version,created_at,updated_at,deleted_at)
        VALUES (?,?,?,?,1,?,?,NULL)`)
        .run(key, title, JSON.stringify(schema), JSON.stringify(records), now, now);
      this._logChange(this.db, 'database', key, 'put');
      this._commit();
    } catch (error) {
      this._rollback();
      throw error;
    }
    return this.getDatabase(key);
  }

  updateDatabase(id, input = {}) {
    const existing = this.getDatabase(id);
    if (!existing) throw new StoreError('Database not found', 404);
    if (!Number.isInteger(input.expectedVersion)) throw new StoreError('expectedVersion is required');
    if (existing.version !== input.expectedVersion) throw new StoreError('Version conflict', 409);
    const title = input.title === undefined ? existing.title : expectString(input.title, 'title', 500);
    const schema = input.schema === undefined ? existing.schema : validateSchema(input.schema);
    const records = input.records === undefined ? existing.records : validateRecords(input.records);
    const now = new Date().toISOString();
    this._begin();
    try {
      const result = this.db.prepare(`UPDATE databases SET title=?,schema_json=?,records_json=?,
        updated_at=?,version=version+1 WHERE id=? AND version=? AND deleted_at IS NULL`)
        .run(title, JSON.stringify(schema), JSON.stringify(records), now, id, input.expectedVersion);
      if (result.changes !== 1) throw new StoreError('Version conflict', 409);
      this._logChange(this.db, 'database', id, 'put');
      this._commit();
    } catch (error) {
      this._rollback();
      throw error;
    }
    return this.getDatabase(id);
  }

  _changeDatabase(id, deleted) {
    const database = this.getDatabase(id, { includeDeleted: true });
    if (!database) throw new StoreError('Database not found', 404);
    if (Boolean(database.deletedAt) === deleted) return database; // idempotent
    const now = new Date().toISOString();
    this._begin();
    try {
      this.db.prepare('UPDATE databases SET deleted_at=?,updated_at=?,version=version+1 WHERE id=?')
        .run(deleted ? now : null, now, id);
      this._logChange(this.db, 'database', id, 'put');
      this._commit();
    } catch (error) {
      this._rollback();
      throw error;
    }
    return this.getDatabase(id, { includeDeleted: true });
  }

  trashDatabase(id) { return this._changeDatabase(id, true); }
  restoreDatabase(id) { return this._changeDatabase(id, false); }

  deleteDatabaseForever(id) {
    const database = this.getDatabase(id, { includeDeleted: true });
    if (!database) throw new StoreError('Database not found', 404);
    if (!database.deletedAt) throw new StoreError('Move database to trash first', 409);
    this._begin();
    try {
      this._rememberPurge('database', id, database.version + 1);
      this.db.prepare('DELETE FROM databases WHERE id=?').run(id);
      this._commit();
    } catch (error) {
      this._rollback();
      throw error;
    }
    return { deleted: true, id };
  }

  upsertDatabaseRecord(id, { record, expectedVersion } = {}) {
    if (!record || typeof record !== 'object' || Array.isArray(record)) {
      throw new StoreError('record must be an object');
    }
    const database = this.getDatabase(id);
    if (!database) throw new StoreError('Database not found', 404);
    const recordId = record.id == null ? randomUUID() : expectSlug(record.id, 'record id');
    const merged = { id: recordId, values: record.values ?? {} };
    const existing = database.records.find(item => item.id === recordId);
    const records = existing
      ? database.records.map(item => item.id === recordId ? merged : item)
      : [...database.records, merged];
    return {
      database: this.updateDatabase(id, {
        expectedVersion: expectedVersion ?? database.version, records,
      }),
      record: merged,
    };
  }

  // ------------------------------------------------------------------- sync

  syncPush({ ops } = {}) {
    if (!Array.isArray(ops)) throw new StoreError('ops must be an array');
    if (ops.length > 100) throw new StoreError('at most 100 operations per push');
    const results = [];
    for (const op of ops) {
      results.push(this._applySyncOp(op));
    }
    return { results, serverTime: new Date().toISOString() };
  }

  _applySyncOp(op) {
    const opId = typeof op?.opId === 'string' ? op.opId : '';
    try {
      if (!op || typeof op !== 'object' || Array.isArray(op)) {
        throw new StoreError('each operation must be an object');
      }
      const id = expectString(op.opId, 'opId', 80);
      if (!/^[A-Za-z0-9_.:-]{6,80}$/.test(id)) throw new StoreError('Invalid opId');
      const { entity, kind } = op;
      if (!['page', 'database'].includes(entity)) throw new StoreError('Invalid sync entity');
      if (!['upsert', 'trash', 'restore', 'purge'].includes(kind)) throw new StoreError('Invalid sync kind');
      // Accept old clients' targetId as an alias; new clients send id as well.
      const normalized = { ...op, id: op.id ?? op.targetId };
      const payloadHash = createHash('sha256').update(JSON.stringify(canonicalJson({
        entity, kind, id: normalized.id ?? null,
        record: op.record ?? null, expectedVersion: op.expectedVersion ?? null,
      }))).digest('hex');
      this._begin();
      try {
        const replay = this.db.prepare('SELECT result_json,payload_hash FROM applied_ops WHERE op_id=?').get(id);
        if (replay) {
          if (replay.payload_hash && replay.payload_hash !== payloadHash) {
            throw new StoreError('opId was already used with a different payload', 409);
          }
          this._commit();
          return { opId: id, entity, kind, ...JSON.parse(replay.result_json), replay: true };
        }
        const result = this._applyEntityOp(normalized);
        // Domain mutation, change feed and acknowledgement commit together.
        this.db.prepare('INSERT INTO applied_ops(op_id,applied_at,result_json,payload_hash) VALUES (?,?,?,?)')
          .run(id, new Date().toISOString(), JSON.stringify(result), payloadHash);
        this._commit();
        return { opId: id, entity, kind, ...result };
      } catch (error) { this._rollback(); throw error; }
    } catch (error) {
      if (error instanceof StoreError) return { opId, status: 'error', code: error.status, message: error.message };
      throw error;
    }
  }

  _applyEntityOp(op) {
    const page = op.entity === 'page';
    const read = id => page ? this.get(id, { includeDeleted: true }) : this.getDatabase(id, { includeDeleted: true });
    const id = op.kind === 'upsert'
      ? (op.record?.id == null ? randomUUID() : expectId(op.record.id, 'record id'))
      : expectId(op.id);
    const existing = read(id);
    const purged = this._purged(op.entity, id);
    const conflict = reason => ({ status: 'conflict', id, reason,
      server: existing, serverVersion: existing?.version ?? purged?.version ?? null });
    if (!existing) {
      if (purged) return op.kind === 'purge'
        ? { status: 'applied', id, noop: true, version: purged.version }
        : conflict('permanently_deleted');
      if (op.kind !== 'upsert') return conflict('missing');
      if (op.expectedVersion != null && op.expectedVersion !== 0) return conflict('missing');
      if (!op.record || typeof op.record !== 'object' || Array.isArray(op.record)) {
        throw new StoreError('record must be an object');
      }
      if (page) this.create({ ...op.record, id });
      else this.createDatabase({ ...op.record, id });
      if (op.record.deletedAt) {
        if (page) this.trash(id); else this.trashDatabase(id);
      }
    } else {
      // A missing revision is create-only, never permission to overwrite.
      if (!Number.isInteger(op.expectedVersion) || op.expectedVersion !== existing.version) {
        return conflict('revision_mismatch');
      }
      switch (op.kind) {
        case 'upsert':
          if (existing.deletedAt) return conflict('trashed');
          if (!op.record || typeof op.record !== 'object' || Array.isArray(op.record)) {
            throw new StoreError('record must be an object');
          }
          if (page) this.update(id, { ...op.record, expectedVersion: op.expectedVersion });
          else this.updateDatabase(id, { ...op.record, expectedVersion: op.expectedVersion });
          if (op.record.deletedAt) {
            if (page) this.trash(id); else this.trashDatabase(id);
          }
          break;
        case 'trash': if (page) this.trash(id); else this.trashDatabase(id); break;
        case 'restore': if (page) this.restore(id); else this.restoreDatabase(id); break;
        case 'purge':
          if (page) this.deleteForever(id); else this.deleteDatabaseForever(id);
          return { status: 'applied', id, version: existing.version + 1 };
      }
    }
    const record = read(id);
    return { status: 'applied', id, version: record.version, record };
  }

  syncPull({ cursor = 0, limit = 200 } = {}) {
    if (!Number.isInteger(cursor) || cursor < 0) throw new StoreError('cursor must be a nonnegative integer');
    if (!Number.isInteger(limit) || limit < 1 || limit > 500) throw new StoreError('limit must be 1–500');
    const rows = this.db.prepare(
      'SELECT * FROM changes WHERE seq > ? ORDER BY seq ASC LIMIT ?').all(cursor, limit);
    const latest = new Map();
    for (const row of rows) latest.set(`${row.entity}:${row.id}`, row);
    const changes = [];
    for (const row of latest.values()) {
      if (row.entity === 'page') {
        const page = this.get(row.id, { includeDeleted: true });
        changes.push(page
          ? { entity: 'page', id: row.id, op: 'put', page }
          : { entity: 'page', id: row.id, op: 'delete' });
      } else {
        const database = this.getDatabase(row.id, { includeDeleted: true });
        changes.push(database
          ? { entity: 'database', id: row.id, op: 'put', database }
          : { entity: 'database', id: row.id, op: 'delete' });
      }
    }
    const nextCursor = rows.length === limit
      ? rows[rows.length - 1].seq
      : (this.db.prepare('SELECT MAX(seq) AS head FROM changes').get().head ?? cursor);
    return { cursor: nextCursor, more: rows.length === limit, changes };
  }

  syncStatus() {
    const head = this.db.prepare('SELECT MAX(seq) AS head FROM changes').get().head ?? 0;
    const pages = this.db.prepare('SELECT COUNT(*) AS n FROM pages WHERE deleted_at IS NULL').get().n;
    const databases = this.db.prepare('SELECT COUNT(*) AS n FROM databases WHERE deleted_at IS NULL').get().n;
    return { head, pages, databases };
  }
}
