# Anamne API v1

Base path: `/v1`. Send `Authorization: Bearer <ANAMNE_API_TOKEN>` to all routes. Default bind: localhost. Responses are JSON; errors have an `error` field. Do not expose the Node port directly to the public internet; terminate HTTPS at a reverse proxy.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Health check (authenticated) |
| GET | `/pages?parentId=&deleted=false&limit=100&offset=0` | Page list |
| POST | `/pages` | Create a page, `title`, `body`, `parentId`, `properties` |
| GET | `/pages/{id}` | Fetch a page, including a trashed one |
| PATCH | `/pages/{id}` | Change fields; requires `expectedVersion` |
| POST | `/pages/{id}/trash` | Move page and descendants to trash |
| POST | `/pages/{id}/restore` | Restore page and descendants |
| DELETE | `/pages/{id}/permanent` | Permanently remove a previously trashed tree |
| GET | `/search?q=...&limit=100` | Search title and body |
| GET | `/export` | Export all pages and metadata as JSON |

Page fields are `id`, `parentId`, `title`, `body`, `properties` (user-defined JSON object), `version`, `createdAt`, `updatedAt`, `deletedAt`. Text is UTF-8, so Bangla is supported. Versions increment on writes, and stale PATCH requests return HTTP 409.

This is the initial contract. Full OpenAPI, token scopes, identity, schema-defined custom actions, pagination consistency, import and device synchronization remain roadmap work. Do not use this API as a public multi-user service yet.
