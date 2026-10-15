import readline from 'node:readline';
import { AnamneStore, StoreError } from './store.js';

const store = new AnamneStore();
const object = (properties, required = []) =>
  ({ type: 'object', properties, required, additionalProperties: false });
const string = { type: 'string' };
const id = { type: 'string', description: 'Page UUID' };
const version = { type: 'integer', minimum: 1 };

const tools = {
  list_pages: {
    description: 'List pages, optionally within a parent or in the trash.',
    inputSchema: object({ parentId: { type: ['string', 'null'] }, deleted: { type: 'boolean' },
      limit: { type: 'integer', minimum: 1, maximum: 500 }, offset: { type: 'integer', minimum: 0 } }),
    run: args => ({ pages: store.list(args) }),
  },
  get_page: {
    description: 'Get a page by ID, including a trashed page if requested.',
    inputSchema: object({ id, includeDeleted: { type: 'boolean' } }, ['id']),
    run: ({ id, includeDeleted }) => store.get(id, { includeDeleted }) ||
      (() => { throw new StoreError('Page not found', 404); })(),
  },
  search_pages: {
    description: 'Search page titles and body text.',
    inputSchema: object({ query: string, limit: { type: 'integer', minimum: 1, maximum: 500 } }, ['query']),
    run: ({ query, limit }) => ({ pages: store.search(query, { limit }) }),
  },
  create_page: {
    description: 'Create a page or subpage in this workspace.',
    inputSchema: object({ title: string, body: string,
      parentId: { type: ['string', 'null'] }, properties: { type: 'object' },
      blocks: { type: 'array' }, type: { enum: ['page', 'canvas'] }, data: { type: ['object', 'null'] } }),
    run: args => store.create(args),
  },
  update_page: {
    description: 'Edit title, body, parent or custom properties. Supply the page version to prevent lost updates.',
    inputSchema: object({ id, expectedVersion: version, title: string, body: string,
      parentId: { type: ['string', 'null'] }, properties: { type: 'object' },
      blocks: { type: 'array' }, type: { enum: ['page', 'canvas'] }, data: { type: ['object', 'null'] } },
    ['id', 'expectedVersion']),
    run: ({ id, ...args }) => store.update(id, args),
  },
  trash_page: {
    description: 'Move a page and its descendants to recoverable trash.',
    inputSchema: object({ id }, ['id']),
    run: ({ id }) => store.trash(id),
  },
  restore_page: {
    description: 'Restore a trashed page and its descendants.',
    inputSchema: object({ id }, ['id']),
    run: ({ id }) => store.restore(id),
  },
  delete_page_forever: {
    description: 'Permanently delete a page already in trash and all descendants. Irreversible.',
    inputSchema: object({ id }, ['id']),
    run: ({ id }) => store.deleteForever(id),
  },
  export_workspace: {
    description: 'Export all pages and databases as portable Anamne JSON.',
    inputSchema: object({}),
    run: () => store.export(),
  },
  list_databases: {
    description: 'List structured databases, optionally including trashed ones.',
    inputSchema: object({ deleted: { type: 'boolean' },
      limit: { type: 'integer', minimum: 1, maximum: 500 }, offset: { type: 'integer', minimum: 0 } }),
    run: args => ({ databases: store.listDatabases(args) }),
  },
  get_database: {
    description: 'Get a database with its typed schema and records.',
    inputSchema: object({ id, includeDeleted: { type: 'boolean' } }, ['id']),
    run: ({ id, includeDeleted }) => store.getDatabase(id, { includeDeleted }) ||
      (() => { throw new StoreError('Database not found', 404); })(),
  },
  create_database: {
    description: 'Create a structured database with a typed property schema.',
    inputSchema: object({ title: string, schema: { type: 'array' }, records: { type: 'array' } }),
    run: args => store.createDatabase(args),
  },
  upsert_database_record: {
    description: 'Insert or update one record inside a database. Supply the database version to prevent lost updates.',
    inputSchema: object({ id, expectedVersion: version,
      record: object({ id: { type: ['string', 'null'] }, values: { type: 'object' } }) },
    ['id', 'record']),
    run: ({ id, expectedVersion, record }) =>
      store.upsertDatabaseRecord(id, { record, expectedVersion }),
  },
  sync_status: {
    description: 'Server workspace stats: change-log head cursor and record counts for sync clients.',
    inputSchema: object({}),
    run: () => store.syncStatus(),
  },
};

function result(message) {
  if (message.jsonrpc !== '2.0' || typeof message.method !== 'string') {
    throw new StoreError('Invalid JSON-RPC request');
  }
  switch (message.method) {
    case 'initialize': {
      const proposed = message.params?.protocolVersion;
      const protocolVersion = ['2025-11-25', '2025-06-18'].includes(proposed)
        ? proposed : '2025-11-25';
      return { protocolVersion, capabilities: { tools: {} },
        serverInfo: { name: 'anamne', version: '0.2.1' } };
    }
    case 'ping': return {};
    case 'tools/list': return { tools: Object.entries(tools).map(([name, value]) =>
      ({ name, description: value.description, inputSchema: value.inputSchema })) };
    case 'tools/call': {
      const tool = tools[message.params?.name];
      if (!tool) throw new StoreError('Unknown tool', 404);
      const args = message.params.arguments ?? {};
      if (!args || typeof args !== 'object' || Array.isArray(args)) throw new StoreError('Invalid arguments');
      for (const field of tool.inputSchema.required) {
        if (!Object.hasOwn(args, field)) throw new StoreError(`${field} is required`);
      }
      for (const field of Object.keys(args)) {
        if (!Object.hasOwn(tool.inputSchema.properties, field)) throw new StoreError(`Unknown field: ${field}`);
      }
      const output = tool.run(args);
      return { content: [{ type: 'text', text: JSON.stringify(output) }],
        structuredContent: typeof output === 'object' && output !== null ? output : { value: output } };
    }
    default: throw new StoreError('Method not found', 404);
  }
}

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on('line', line => {
  let request;
  try {
    request = JSON.parse(line);
    if (!Object.hasOwn(request, 'id')) return; // Notification: no response.
    let response;
    try {
      response = { jsonrpc: '2.0', id: request.id, result: result(request) };
    } catch (error) {
      if (request.method === 'tools/call' && error instanceof StoreError) {
        response = { jsonrpc: '2.0', id: request.id, result: {
          content: [{ type: 'text', text: error.message }], isError: true } };
      } else {
        response = { jsonrpc: '2.0', id: request.id,
          error: { code: error.status === 404 ? -32601 : -32602, message: error.message } };
      }
    }
    process.stdout.write(`${JSON.stringify(response)}\n`);
  } catch (error) {
    process.stdout.write(`${JSON.stringify({ jsonrpc: '2.0', id: null,
      error: { code: -32700, message: 'Parse error' } })}\n`);
    console.error(error);
  }
});
input.on('close', () => store.close());
