# Anamne

An open personal workspace by **Invokeil Tech**: Notion-style pages and databases,
linked notes, local editing, self-hosted sync and first-class API/MCP.

**Source version: 0.2.1+3.** This updates the supplied GLM 0.2.0 source with reliability
fixes. The owner supplied local Web/APK/AppImage builds and a report of 22 passing Flutter tests.
Independent checks confirm 19 server tests, APK signature/metadata and AppImage payload integrity.
Read [the build review](docs/reviews/2026-10-15-local-build.md) for evidence and remaining device QA.
No GitHub release assets are published by this source consolidation.

## Build locally

GitHub Actions is **manual-only** to preserve the owner's exhausted build allowance.
A push or pull request does not run this repository's build workflow. Do not dispatch it
for the local-build task.

```bash
git clone https://github.com/Invokeil/Anamne.git
cd Anamne
# Prerequisites: Flutter 3.47.7, Node.js 24+, Python 3 and target tools.
bash tool/build_local.sh web
# Other targets, one at a time:
bash tool/build_local.sh linux
bash tool/build_local.sh apk
# Requires appimagetool; see the guide:
APPIMAGETOOL=/absolute/path/to/appimagetool-x86_64.AppImage APPIMAGE_EXTRACT_AND_RUN=1 bash tool/build_local.sh appimage
```

The script bootstraps missing Flutter platform projects, applies Anamne branding and Android
release network permission, runs server tests, `flutter analyze` and single-process Flutter
tests, then builds the requested target. It stops on failure. Web metadata must match
`pubspec.yaml`. It uses lower Gradle concurrency by default for an 8 GB laptop.

For installation, distro-specific prerequisites, Android tooling, output locations and
troubleshooting use **[docs/LOCAL_BUILD.md](docs/LOCAL_BUILD.md)**. Give your local coding AI
**[LOCAL_AI_PROMPT.md](LOCAL_AI_PROMPT.md)** for the complete build/verification assignment.

## Current source

| Area | Present | Remaining limits |
|---|---|---|
| Editor | Blocks, slash menu, headings/lists/tasks, code/callouts, reorder, database embeds | Inline rich text, complete undo/redo, attachment blocks and physical Bengali IME QA |
| Notes | Nested pages, search, trash/restore, JSON/Markdown export | Multiple isolated workspaces, complete archive restore and import fidelity |
| Knowledge | Wiki links, backlinks/outgoing links, bounded graph | Stable-ID link resolution, tags/templates and external-vault link fidelity |
| Databases | Typed schema, table/board, row editing, sort/filter | Relations, formulas/rollups, calendar/gallery; advanced schema validation |
| Canvas | Sticky notes, connectors, pan/zoom stored in page data | Device UX and save/lifecycle verification |
| Sync | Durable ordered outbox, revision conflicts, page/database conflict copies, cursor pull, purge tombstones | Multi-device client QA, history and recovery UI; fixed 15-second retry |
| Identity | Hashed admin/editor/viewer tokens, revoke and env rotation | One shared workspace; local tokens are not yet stored in an OS credential vault |
| API/MCP | REST page/database/sync/token API; 14 stdio MCP tools | Authenticated remote MCP, measured 99% parity and declarative custom APIs |
| Files | Native Markdown projection and database JSON companion | Mirror is one-way; complete backup/Obsidian compatibility is not established |
| Targets | Web, Android arm64 APK, Linux x86_64 bundle/AppImage scripts | Local evaluation builds inspected; device/install QA pending; Windows/macOS upcoming |

The UI is inspired by Notion. Exact reference-screen/interaction matching has not been
measured. Offline note storage works without a server; offline **web reload** needs a future
app-shell/update strategy. Do not reuse the supplied old web ZIP: its metadata did not match
its source. Build fresh from this checkout.

## Run locally

```bash
bash tool/bootstrap.sh
flutter run -d linux
# Browser alternative: flutter run -d chrome
```

Sembast stores native data; IndexedDB stores browser data. Local mutations enqueue sync
operations in the same durable transaction. Drafts flush on navigation/lifecycle transitions;
write errors have retry state. This does not guarantee persistence after an abrupt OS kill
before the debounce or recover a failed write after its editor has been destroyed.

## Self-hosted server and web connection

Node.js 24+ is required; the server has no third-party runtime npm dependencies.

```bash
cd server
export ANAMNE_API_TOKEN="$(openssl rand -hex 32)"
export ANAMNE_DB_PATH=./data/anamne.sqlite
# Exact browser origins; needed when the web app is on another host/port:
export ANAMNE_CORS_ORIGINS="http://localhost:8080,https://notes.example.com"
node src/http.js
```

The default bind is `127.0.0.1:8787`. Use HTTPS behind a reverse proxy for a deployed service.
In Anamne settings enter the server URL and token, test, then save. Sync starts every 15 seconds
without requiring an app restart. All HTTP roles currently share one workspace.

See [deploy/README.md](deploy/README.md) for Podman/compose, systemd, TLS and backup guidance.
No VPS deployment is performed by cloning/building this project. Back up the SQLite database
before upgrading; older missing deletion/revocation history cannot be reconstructed.

## API and MCP

[docs/API.md](docs/API.md) describes `/v1` endpoints. Updates use `expectedVersion`; sync
creation without a revision cannot overwrite an existing ID. Identical opId retries replay
the original acknowledgement; a different payload under the same key is rejected.

Launch an MCP host's stdio process as `node /absolute/path/to/Anamne/server/src/mcp.js`, with
`ANAMNE_DB_PATH` pointing at the same SQLite database. SSH stdio can launch it on a VPS.
The process inherits OS access to that database; HTTP role tokens are not its auth layer.

Tools: `list_pages`, `get_page`, `search_pages`, `create_page`, `update_page`, `trash_page`,
`restore_page`, `delete_page_forever`, `export_workspace`, `list_databases`, `get_database`,
`create_database`, `upsert_database_record`, `sync_status`. Create/update support block/canvas
fields. This is not yet a remote HTTP MCP server or a verified 99% app-control implementation.

## Verification and plans

Node.js 24.19.0: **19 server tests passed** for this fix, including transaction rollback,
revision safety, descendant purge, token revoke/rotation/restart, CORS and MCP behavior.
The supplied local report records **22 Flutter tests passed**, clean analysis and target builds
on Flutter 3.47.7. Those Flutter commands were not rerun by this reviewer (SDK unavailable);
APK/AppImage/web checks are recorded separately in the [build review](docs/reviews/2026-10-15-local-build.md).
Run `bash tool/build_local.sh check` on the exact checkout before distributing new builds.

| Document | Purpose |
|---|---|
| [docs/reviews/2026-10-15-local-build.md](docs/reviews/2026-10-15-local-build.md) | Uploaded source/build review, checksums and verification limits |
| [docs/FIXES-0.2.1.md](docs/FIXES-0.2.1.md) | Specific fixes, evidence and remaining limitations |
| [docs/LOCAL_BUILD.md](docs/LOCAL_BUILD.md) | Laptop setup, commands, artifacts and QA |
| [LOCAL_AI_PROMPT.md](LOCAL_AI_PROMPT.md) | Ready-to-use local AI assignment |
| [prompt.md](prompt.md) | Complete product requirements |
| [Plan.md](Plan.md) | Source status, remaining milestones and acceptance gates |
| [AGENTS.md](AGENTS.md) / [agent.md](agent.md) | Engineering rules |
| [docs/DESIGN.md](docs/DESIGN.md) | Design direction; measured reference matching remains open |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Historical research |

MIT licensed. Preserve the supplied brand assets and **Powered by ©Invokeil Tech**.

