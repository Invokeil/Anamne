import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';
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

function validateProperties(value) {
  if (value == null || typeof value !== 'object' || Array.isArray(value)) {
    throw new StoreError('properties must be a JSON object');
  }
  if (JSON.stringify(value).length > 100000) {
    throw new StoreError('properties are too large');
  }
  return value;
}

function rowToPage(row) {
  if (!row) return null;
  return {
    id: row.id,
    parentId: row.parent_id,
    title: row.title,
    body: row.body,
    properties: JSON.parse(row.properties_json),
    version: row.version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    deletedAt: row.deleted_at,
  };
}

export class AnamneStore {
  constructor(path = process.env.ANAMNE_DB_PATH || './data/anamne.sqlite') {
    if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true });
    this.db = new DatabaseSync(path);
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
    `);
  }

  close() { this.db.close(); }

  get(id, { includeDeleted = false } = {}) {
    expectString(id, 'id', 80);
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
      if (parentId !== null) expectString(parentId, 'parentId', 80);
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

  create({ title = '', body = '', parentId = null, properties = {} } = {}) {
    expectString(title, 'title', 500);
    expectString(body, 'body');
    validateProperties(properties);
    if (parentId !== null && !this.get(parentId)) throw new StoreError('Parent page not found', 404);
    const id = randomUUID();
    const now = new Date().toISOString();
    this.db.prepare(`INSERT INTO pages
      (id,parent_id,title,body,properties_json,version,created_at,updated_at)
      VALUES (?,?,?,?,?,1,?,?)`)
      .run(id, parentId, title, body, JSON.stringify(properties), now, now);
    return this.get(id);
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
    const parentId = input.parentId === undefined ? existing.parentId : input.parentId;
    if (parentId !== null) {
      expectString(parentId, 'parentId', 80);
      if (!this.get(parentId)) throw new StoreError('Parent page not found', 404);
      if (parentId === id || this.descendantIds(id).includes(parentId)) {
        throw new StoreError('A page cannot be placed inside itself or its descendants');
      }
    }
    const now = new Date().toISOString();
    const result = this.db.prepare(`UPDATE pages SET title=?,body=?,properties_json=?,parent_id=?,
      updated_at=?,version=version+1 WHERE id=? AND version=? AND deleted_at IS NULL`)
      .run(title, body, JSON.stringify(properties), parentId, now, id, input.expectedVersion);
    if (result.changes !== 1) throw new StoreError('Version conflict', 409);
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
    const ids = [id, ...this.descendantIds(id)];
    const now = new Date().toISOString();
    const statement = this.db.prepare(`UPDATE pages SET deleted_at=?,updated_at=?,version=version+1 WHERE id=?`);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      for (const key of ids) statement.run(deleted ? now : null, now, key);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
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
    this.db.exec('BEGIN IMMEDIATE');
    try {
      for (const key of ids.reverse()) this.db.prepare('DELETE FROM pages WHERE id=?').run(key);
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    return { deleted: true, id };
  }

  export() {
    const pages = this.db.prepare('SELECT * FROM pages ORDER BY created_at, id').all().map(rowToPage);
    return { format: 'anamne.pages', version: 1, exportedAt: new Date().toISOString(), pages };
  }
}
