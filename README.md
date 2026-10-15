# Anamne

An open, offline-first personal workspace by **Invokeil Tech**. The first milestone contains a Flutter notes interface and a small self-hosted API/MCP service.

## Project brief and implementation plan

| Document | Purpose |
|---|---|
| [prompt.md](prompt.md) | Full Anamne product and implementation brief for continuing coding agents |
| [Plan.md](Plan.md) | Detailed current status, remaining tasks, dependency order and acceptance gates |
| [agent.md](agent.md) | Engineering instructions, data/API/MCP invariants and verification rules |
| [AGENTS.md](AGENTS.md) | Entry point for agents that discover repository instructions by this filename |

These files describe both implemented foundations and future requirements. Source exists for the initial Flutter shell; its platform builds and device behavior still need verification. See `Plan.md` for evidence and remaining work.

## Current status

| Area | Available in this milestone |
|---|---|
| Flutter app | Local page and subpage editing, autosave, search, trash/restore, copy Markdown and portable JSON backup |
| Targets | Android APK, Linux AppImage and web build workflows; Windows/macOS later |
| VPS service | Node.js 24 + SQLite, authenticated versioned REST API |
| MCP | Local stdio server with nine page/search/export tools, sharing the VPS database |
| Sync | **Not implemented yet**. The app's local store and VPS store are separate today. |
| Editor | Plain text/Markdown editing now; block editor and databases are future milestones. |

The long-term scope and acceptance gates are in [ROADMAP.md](docs/ROADMAP.md). The visual rules are in [DESIGN.md](docs/DESIGN.md). Anamne's own icon and loading mark were supplied by the project owner.

## Run the app

Install a [Flutter SDK](https://docs.flutter.dev/install) and the platform prerequisites. Then:

```bash
bash tool/bootstrap.sh
flutter run -d chrome       # or an Android device / Linux desktop
```

`bootstrap.sh` creates standard Flutter Android, Linux and web scaffolds and applies the supplied brand icons. A push to `main` runs the same setup and attempts an APK, web bundle and Linux AppImage. Until CI reports success, these are build targets, not downloadable verified releases.

The first app store is Sembast on device and IndexedDB on web. The roadmap calls for evaluating Drift/SQLite before the larger sync and database phase; this repository does not claim that migration is complete.

## Run the self-hosted service

Requires Node.js 24 or newer. On a VPS, set a strong token and bind behind HTTPS with a reverse proxy:

```bash
cd server
export ANAMNE_API_TOKEN="$(openssl rand -hex 32)"
export ANAMNE_DB_PATH=/var/lib/anamne/anamne.sqlite
node src/http.js
```

The service binds to `127.0.0.1:8787` by default. Keep the token private; copy it to a secret manager, not to the repository. Example request:

```bash
curl -H "Authorization: Bearer $ANAMNE_API_TOKEN" \
  http://127.0.0.1:8787/v1/pages
```

`PATCH /v1/pages/{id}` requires `expectedVersion` from the last GET. A stale update returns 409. API endpoints and schemas are summarized in [API.md](docs/API.md).

## MCP

The MCP server uses newline-delimited JSON-RPC over stdio and the same SQLite database. Configure an MCP host to launch `node /path/to/Anamne/server/src/mcp.js` with `ANAMNE_DB_PATH` set. For a remote VPS use an SSH stdio transport that runs this command on the server. Available tools: `list_pages`, `get_page`, `search_pages`, `create_page`, `update_page`, `trash_page`, `restore_page`, `delete_page_forever`, `export_workspace`.

MCP controls the VPS workspace represented by that database. It does not control the separate offline app copy until synchronization and identity/permission work is complete. Permanent deletion is explicitly named; clients should ask users before invoking it.

## Tests

```bash
cd server && npm test
```

With Flutter installed: `bash tool/bootstrap.sh && flutter analyze && flutter test`.

## Contributing and license

Open issues with a reproducible case, or send a focused pull request. MIT licensed. Product name and artwork attribution: **Powered by ©Invokeil Tech**.
