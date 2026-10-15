# Anamne API v1 (0.2.1)

Base path: `/v1`. Send `Authorization: Bearer <token>` to all routes except `GET /health`
(liveness probe, no auth). Default bind: localhost. Responses are JSON; errors have an `error`
field. Do not expose the Node port directly to the public internet; terminate HTTPS at a reverse
proxy.

Tokens carry roles: `admin`, `editor`, `viewer`. Viewers are read-only; only admins manage
tokens. The env token (`ANAMNE_API_TOKEN`) is an admin; extra users come from `ANAMNE_TOKENS`
(`Name:role:token;…`) or `POST /v1/tokens`. Tokens are stored hashed.

## Pages

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` (no `/v1`) | Liveness probe |
| GET | `/v1/health` | Authenticated health check |
| GET | `/pages?parentId=&deleted=false&limit=100&offset=0` | Page list |
| POST | `/pages` | Create a page (`id` optional for sync clients) |
| GET | `/pages/{id}` | Fetch a page, including a trashed one |
| PATCH | `/pages/{id}` | Change fields; requires `expectedVersion` |
| POST | `/pages/{id}/trash` | Move page and descendants to trash |
| POST | `/pages/{id}/restore` | Restore page and descendants |
| DELETE | `/pages/{id}/permanent` | Permanently remove a previously trashed tree |
| GET | `/search?q=...&limit=100` | Search title and body |
| GET | `/export` | Export pages + databases as portable JSON (format v2) |

Page fields: `id`, `parentId`, `title`, `body` (markdown projection), `type` (`page` | `canvas`),
`blocks` (portable block JSON), `data` (canvas payload), `properties`, `version`, `createdAt`,
`updatedAt`, `deletedAt`. Stale writes return HTTP 409.

## Databases

| Method | Path | Purpose |
|---|---|---|
| GET | `/databases?deleted=false&limit=100&offset=0` | List databases |
| POST | `/databases` | Create (`title`, `schema`, `records`) |
| GET | `/databases/{id}` | Fetch one |
| PATCH | `/databases/{id}` | Change `title`/`schema`/`records`; requires `expectedVersion` |
| POST | `/databases/{id}/trash` / `restore` | Trash/restore |
| DELETE | `/databases/{id}/permanent` | Permanent delete after trash |

Schema properties: `{id, name, type}` with `type` one of `text`, `number`, `select`,
`multiSelect`, `checkbox`, `date` (`options` for the select kinds). Records are
`{id, values}` objects; up to 5000 per database.

## Sync (offline-first clients)

| Method | Path | Purpose |
|---|---|---|
| POST | `/sync/push` | Apply a batch of ≤ 100 outbox ops, idempotent by `opId` |
| GET | `/sync/pull?cursor=0&limit=200` | Changes after the cursor (upserts + tombstones) |
| GET | `/sync/status` | Change-log head cursor and record counts |

Push op: `{opId, entity: "page"|"database", kind: "upsert"|"trash"|"restore"|"purge", id?,
record?, expectedVersion?}`. Legacy `targetId` is accepted as an alias for `id`.
Omit `expectedVersion` only when creating a new entity; all existing-entity changes require
an exact positive revision. Results per op: `applied` (with new `version`), `conflict`
(with `server` snapshot, or `null` for a missing/purged ID), or `error` (per-op reason).
Replaying the same operation returns its original status plus `replay: true`; changing the
semantic payload under the same opId returns an error. Domain change, change feed and applied
acknowledgement commit atomically. Purged IDs cannot be recreated; use a new ID for a recovery copy.
The server owns canonical timestamps; the client resolves conflicts by keeping the server
snapshot and preserving the local edit as a conflict copy.

The client sends at most one operation per entity ID in a batch and rebases queued successors
after acknowledgement. A pass is bounded to four batches; rejected operations wait for a later
15-second pass, and do not prevent the pull phase. This is fixed-interval retry, not exponential
backoff. Conflict copies cover pages, canvases and database schema/records. Each purged page
descendant has a delete event and retained tombstone.

Pull response: `{cursor, more, changes}` where each change is `{entity, id, op: "put"|"delete"}`
plus `page`/`database` snapshots for `put`. Clients persist the returned cursor.

## Tokens (admin only)

| Method | Path | Purpose |
|---|---|---|
| GET | `/tokens` | List tokens (hashed, with hints) |
| POST | `/tokens` | Mint `{name, role, token?}`; auto-generated when omitted |
| DELETE | `/tokens/{sha256}` | Revoke |

## MCP

The stdio MCP server (14 tools) shares this database: page tools, `list_databases`,
`get_database`, `create_database`, `upsert_database_record` and `sync_status`. Launch
`node server/src/mcp.js` with `ANAMNE_DB_PATH` set (SSH stdio for remote hosts).

`create_page` / `update_page` accept `blocks`, `type` and `data` as well as text/properties.
Database record IDs accept the same 1–40 character alphanumeric/underscore/hyphen form used
by the app (`r` plus timestamp), including UUID strings. The stdio process has OS/database
access; HTTP token roles are not a stdio authentication layer. MCP coverage is unmeasured.

## Browser access

Configure `ANAMNE_CORS_ORIGINS` with exact trusted origins, comma-separated. Same-host browser
requests are allowed; requests without Origin (native clients) use normal bearer authentication.
Preflight OPTIONS is unauthenticated; every actual `/v1` request still requires its token.
There is no wildcard origin default. Revoked env tokens stay revoked after restart; rotate to a
new value for a replacement. All roles currently operate a single shared workspace.

This contract is versioned with the repository. E2EE, rate limits and public multi-user signup
remain roadmap work; do not expose this API as an open public service yet.
