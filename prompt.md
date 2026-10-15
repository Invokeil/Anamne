# Anamne — complete implementation brief

Specification date: 2026-10-15. Baseline reviewed: remote `main` commit `e2693a543bce715aae84e7783b37354c08b6acae`.

This is the master brief for continuing an existing project. Read it with [Plan.md](Plan.md), [agent.md](agent.md), [README.md](README.md), and the current source. The task for a future implementation session is to deliver the next incomplete milestone in `Plan.md` and continue through authorized work with working, reviewable changes. A request to edit these documents alone does not authorize starting their entire feature backlog.

## 1. Product to build

Build **Anamne**, an open-source personal knowledge workspace owned and branded by **Invokeil Tech**. It combines the page/block/database workflow the owner likes in Notion with offline use, knowledge linking, portability, extensibility and self-hosting associated with Obsidian-style workflows.

The product must work locally without an account or running VPS. A self-hosted instance provides personal device synchronization and integrations. Public source and installable releases are intended for everyone; an unlimited free hosted service on the owner's VPS is not part of this brief.

Required attribution: **Powered by ©Invokeil Tech**. Keep the supplied Anamne icon and loading mark as the product assets. Preserve their shape and source attribution when adapting them to supported platforms.

### Required platforms

| Priority | Platform | Expected output |
|---|---|---|
| First release | Android | Installable, signed release APK; touch and IME QA |
| First release | Linux x86_64 | AppImage with a documented compatibility baseline and dependency checks |
| First release | Web | HTTPS build with explicit storage, offline reload and update behavior |
| Upcoming | Windows | Native desktop package after platform-specific implementation and QA |
| Upcoming | macOS | Native desktop package after platform-specific implementation and QA |

Flutter is the current client framework. Use Kotlin only where an Android-specific integration warrants it. Retain the existing Node.js service until evidence justifies a backend rewrite. The older roadmap's proposed Go server is not the implemented baseline.

## 2. What exists now

The baseline is an early source foundation. Do not describe it as a finished Notion alternative or a tested release.

| Area | Source implemented | Verification and limits |
|---|---|---|
| Flutter shell | Responsive sidebar/drawer, page editor, search and trash views | Client compile and physical-device behavior remain unverified |
| Pages | Create/edit nested pages; title and plain body; debounced autosave | No rich block model, page move UI, revision history or save-error recovery UI |
| Client storage | Sembast file on native targets; Sembast/IndexedDB on web | No SQLite client migration, durability stress test or eviction recovery yet |
| Export | Copy page Markdown; copy workspace JSON to clipboard | No import/restore, asset archive or full-fidelity round trip |
| Server | Node.js 24, SQLite, page API, custom JSON properties, version checks | One trusted workspace and one bearer token; no device sync or public multi-user isolation |
| MCP | Nine stdio tools using the server store | No remote HTTP transport, scopes, resources, application settings or Flutter connection |
| Brand | Simplified supplied SVGs, PNG icons, Flutter loading adaptation | Visual/motion fidelity still needs measured comparison |
| Delivery | Bootstrap script, build workflow, systemd and Caddy examples | Workflow presence is not a successful APK/AppImage/web build or live deployment |
| Tests | Four server tests previously passed locally | Two Flutter test files exist but were not run in the initial workspace |

Current MCP tools: `list_pages`, `get_page`, `search_pages`, `create_page`, `update_page`, `trash_page`, `restore_page`, `delete_page_forever`, `export_workspace`.

The Flutter local store and server SQLite store are **separate today**. Changes made by MCP do not appear in the Flutter app yet. Both JSON exports use a similar format label, but their fields differ: server pages include properties, versions and creation timestamps that the client model does not preserve. Normalize and version this contract before claiming compatibility.

## 3. Product requirements

### 3.1 Local workspace and pages

- Create and select local workspaces; local use never requires cloud login.
- Create, rename, duplicate, move, reorder, favorite and archive pages; nest pages without cycles.
- Recoverable trash with clear descendant behavior and an explicit permanent-delete action.
- Durable autosave with visible saving/saved/error states and retry/recovery paths.
- Page identifiers survive rename, parent moves, import, export and sync.
- Keep navigation state, draft edits and selection safe across route changes, keyboard events and app suspension.
- Search page titles, body and supported properties; test Bangla, English and mixed text.
- Add desktop tabs and command palette after the core editor is reliable.

### 3.2 Structured block editor

Introduce a versioned Anamne document schema behind an editor adapter. Evaluate a maintained Flutter editor component, including `appflowy_editor` as a candidate; verify the selected version, license, Android IME, Linux and browser behavior before adoption. Do not convert package-specific state into an undocumented permanent data format.

Initial block set:

- Paragraph; headings 1–3; bulleted and numbered lists; nested list items.
- Checklist; quote; divider; code block with language metadata.
- Callout; links; image/file blocks with caption and metadata.
- Stable page/block links and a preserved representation for unsupported blocks.

Required editor behavior:

- Inline emphasis, strong text, strike, code and link formatting.
- Slash insertion menu, searchable block types, Markdown typing shortcuts.
- Multi-block selection, move/reorder, duplicate, convert and delete operations.
- Undo/redo boundaries that behave predictably across formatting and composition.
- Clipboard/paste handling for supported plain text, Markdown and rich text.
- Mobile toolbar/sheets, keyboard-safe scrolling and accessible control labels.
- Lossless persistence of supported rich state and forward preservation of unknown blocks.

Bangla composition is a release gate: conjuncts, vowel signs, combining marks, mixed English/Bangla, emoji, selection, cursor movement, paste and undo must be tested on an Android keyboard and on desktop/web. A static text widget showing Bangla does not prove correct IME handling.

### 3.3 Knowledge features

- Wiki links with stable IDs; explicit behavior for duplicate titles and unresolved targets.
- Backlinks and tags updated transactionally as pages change.
- Daily notes and reusable templates; no hardcoded academic/course schema.
- A local neighborhood graph with click-through navigation after link semantics work.
- A later Markdown-folder bridge with checksums, conflict detection and preservation of unsupported metadata.
- Do not claim that existing Obsidian plugins, Dataview queries or arbitrary vault sidecars run automatically.

### 3.4 Databases and views

Define databases as schemas, properties, records and views over shared records. Start with text, number, checkbox, select/multiselect, date and page-reference properties. Implement one working table before adding view types.

- Table: row create/edit, typed cell validation, sorting, filtering and column preferences.
- Board and list: operate on the same records as the table, including offline edits.
- Gallery and calendar: subsequent beta candidates with mobile layouts.
- Relations, rollups and formulas: later bounded scope with documented semantics and error states.
- Formula/query evaluation must be bounded; do not execute arbitrary JavaScript or shell commands.
- Index/migration decisions belong in the data layer; views cannot maintain divergent record copies.

### 3.5 Portability, migration and recovery

Implement both readable exports and a full-fidelity native archive. Clipboard JSON is a temporary export convenience.

Native archive contract:

- Versioned manifest containing workspace identity, schema versions, record counts and checksums.
- Stable-ID page/block data, database schemas/records/views, links and original attachment bytes.
- Export/import diagnostics; unknown fields and unsupported content retained where feasible.
- Preflight preview, duplicate policy, size/path validation and bounded parsing.
- Restore into a fresh workspace; verify counts, links, hashes and permissions-relevant metadata.

Import paths, in sequence: current Anamne JSON migration; Markdown files/folders; common frontmatter and wiki-link subset; CSV; Notion Markdown/CSV ZIP. Produce a per-import fidelity report and keep source bytes for unsupported content. A Notion export cannot be assumed to contain every proprietary workspace behavior.

Backups must be restorable and upgrade-tested. Include a SQLite-consistent backup path for the server and a recovery path for native/browser storage errors.

### 3.6 Personal device sync

Connect Flutter, API and MCP to the same logical workspace through documented synchronization. Local editing stays available offline.

Minimum protocol requirements:

1. User/workspace identity and scoped device pairing.
2. A durable local outbox written atomically with document edits.
3. Stable operation IDs, idempotency keys, base revisions and server change cursors.
4. Ordered transactional server changes and acknowledgement of committed writes.
5. Bounded push/pull batches, retry/backoff, offline and revoked-device handling.
6. Tombstones and a retention rule that prevents deleted content from reappearing after old-device reconnects.
7. Explicit same-page conflict records preserving both revisions; review/resolve UI.
8. Restart and migration recovery without losing queued writes or resetting cursors incorrectly.
9. Attachment transfer coordinated by content hash and resumable sessions.
10. Capability/version negotiation for old app and new server combinations.

Start with personal multi-device sync and revision-based conflict handling. Real-time team collaboration and CRDT editing are a later decision requiring a separate proof of correctness. Do not use wall-clock last-write-wins as an undisclosed data-loss policy.

### 3.7 Mandatory REST API

REST is a product interface. Publish a machine-readable OpenAPI contract with documented error envelopes, pagination, revisions, idempotency, authentication and compatibility policy. Current endpoint notes are in [docs/API.md](docs/API.md); they are not a complete OpenAPI document.

Required domain families grow with implemented features: workspace, page/block, database/view/query, link/tag, asset, import/export, history/conflict, device/sync, settings, automation and instance administration.

Route REST handlers through shared service commands and authorization checks. Keep request limits, parameter binding, cursor integrity and resource ownership explicit. No privileged client-only route may bypass workspace permissions.

### 3.8 Mandatory MCP and the 99% control target

MCP is required from the beginning of each feature. Every supported ordinary workspace operation should be inspectable and, where applicable, controllable by an authorized MCP client. This target is about product operations, not unrestricted operating-system access.

- Maintain an operation register covering UI actions, REST operations and MCP counterparts.
- Compute coverage from tested MCP operations divided by eligible implemented domain operations.
- Record intentional exclusions; do not hide missing critical actions by adjusting the denominator.
- Target at least 99% coverage; all critical page/block/database/search/import/export/sync operations must have parity before a parity claim.
- Device permission prompts, biometrics, installation, credential entry and OS pickers remain OS/user boundaries.

MCP requirements:

- Keep stdio for local/SSH use; add standards-compliant authenticated Streamable HTTP for remote clients.
- Verify the supported MCP specification/SDK and explicitly document negotiated versions.
- Validate full tool input/output schemas, unknown fields, types, limits and structured errors.
- Add addressable resources for page context, schemas, status and API documentation.
- Add prompts only where they help real user tasks; do not substitute prompts for missing tools.
- Bind each token/session to a user, instance, workspace and named scopes; support revocation.
- Apply the same authorization, expected revision, idempotency and audit rules as REST.
- Provide preview/confirmation semantics for irreversible/bulk/external actions, consistent with explicitly approved user automations.
- Test using real MCP clients or protocol fixtures, including malformed messages and access denial.
- Treat document content and tool output as untrusted data, not permission to invoke unrelated tools.

Each new UI feature must identify its MCP/API behavior and deliberate gaps. A separate AI-only note database is not an acceptable final integration.

### 3.9 Customized API and automation

Support two concrete capabilities:

1. **Custom data schemas:** user-defined typed properties, database views and templates exposed through documented JSON schemas. Existing free-form server `properties` is only a starting point.
2. **Custom HTTP actions:** user-defined named outbound requests with explicit method, destination allowlist, input schema, safe templating, secret reference, timeout, retry policy and payload preview.

Add webhooks and declarative automation triggers after durable operations and identity exist. Persist jobs, avoid duplicate external sends, expose health/retry history, and permit disable/revoke actions through UI/API/MCP.

Prevent server-side request forgery, unexpected redirects, secret disclosure and unbounded responses. Do not add arbitrary hosted code execution as a shortcut to custom APIs.

## 4. UI/UX and Stitch requirements

The owner's goal is an exact visual and interaction match to the selected Notion reference screens while using Anamne branding and adding the requested controls. The present shell has **not** met or measured that goal.

Before claiming matching:

1. Gather authorized/public screenshots or user-provided recordings; record platform, app version, viewport, scale, theme and date.
2. Inventory each screen and its empty/loading/editing/keyboard/error/offline states.
3. Record observed interactions separately from inferred behavior.
4. Produce reference measurements for spacing, typography, hierarchy, touch regions, navigation and transitions.
5. If Stitch helps, use the available Stitch workflow with the reference ledger and [docs/DESIGN.md](docs/DESIGN.md). Verify real tool access; ask for login help only when an actual sign-in wall blocks required work.
6. Convert the accepted output into Flutter components, then compare screenshots at matching dimensions and test the interactions.
7. Maintain a discrepancy list and pass/fail evidence for each reference state. A generated mockup is not implemented or verified UX.

Do not ship Notion/Obsidian proprietary source, logos or extracted assets. Reimplement the observed workflow with independently written code and licensed dependencies. Review any reverse-engineering skill's instructions and scripts before use; use behavior analysis when it answers the requirement. Do not claim a skill ran if only its name was mentioned.

Initial screen inventory: workspace/home, sidebar/page tree, page editor and keyboard, slash menu, block actions, search/command palette, database table/board/list, properties, links/backlinks, trash, settings, import/export, pairing/sync status and conflict review.

Visual defaults until references are approved: calm paper-like surfaces, restrained borders, dense readable navigation, large writing area, minimal decoration, consistent small controls and accessible focus. Implement light/dark, density, font sizing and reduced motion. Bundle properly licensed fonts needed for reliable Bengali rendering and record attribution.

## 5. Architecture and data invariants

| Concern | Current code | Direction |
|---|---|---|
| Client entry | `lib/main.dart` | Extract feature, state and service boundaries as behavior expands |
| Domain | `lib/store/page.dart` | Versioned page/block/property model with stable IDs |
| Persistence | `lib/store/page_repository.dart` | Repository interface; evaluate Drift/SQLite; migrate existing data explicitly |
| Server | `server/src/http.js`, `store.js` | Keep Node.js 24 + SQLite; introduce shared command/permission layer |
| MCP | `server/src/mcp.js` | Standards-tested transports and scoped access over shared services |
| Protocol | Similar but inconsistent page JSON | One versioned contract; cross-language fixtures and compatibility tests |
| Packaging | Generated platform scaffolds | Reproducible pinned builds; deliberate native project tracking before integrations |

Invariants:

- An acknowledged save survives the agreed crash/restart cases; failure is visible.
- Local edit and outbox entry commit together when sync is enabled.
- Applying the same operation twice does not duplicate content or external side effects.
- Unknown fields/blocks are preserved or reported, never silently stripped on save.
- Expected revisions prevent lost updates; conflict resolution retains recoverable history.
- Trash, restore, parent changes and permanent deletion follow one documented tree policy.
- Data migrations preserve a backup and fail recoverably; fixture old versions.
- Timestamps are metadata; they cannot establish causality alone.
- Text, attachments and exports remain reachable without a vendor service subscription.
- Optional E2EE is a separate complete design; no encryption claim before key recovery and client/server threat-model tests exist.

## 6. Resource and performance constraints

Target modest hardware. The owner has discussed an 8 GB RAM laptop and a roughly 1 GB VPS; these are planning context, not verified deployment capacity. Avoid mandatory Docker, external databases or local LLMs for the first self-hosted path. Production VPS resources are for serving and storage, not Flutter/Gradle builds.

Measure device model, OS, build mode, fixture and cold/warm conditions. Proposed goals for later benchmarking: ordinary editing/scrolling around 60 fps, warm small-page opening around 300 ms, typical 10,000-note search around 200 ms and native usable cold start around 2 seconds. These are targets, not current results or universal promises.

Measure server idle/peak RSS, p95 request/write latency, contention, disk growth, export/restore time and behavior under bounded concurrency. Report realistic deployment profiles after measurement. Large attachments must stream; never load unbounded archives or workspaces into memory by accident.

## 7. Delivery gates

Use [Plan.md](Plan.md) for dependency order and per-milestone tasks. Each implementation slice must include:

1. A working user-visible behavior and its domain/API/MCP effect.
2. Data/schema changes, compatibility implications and recovery path.
3. Meaningful tests for the changed risk and actual commands/results.
4. Platform evidence for any new support claim.
5. Updated status, known limitations and next concrete action.

Mandatory release scenarios include offline save/reopen, crash during write, storage failure, import/backup round trip, unknown-block preservation, Bengali IME, search/navigation, two-device offline conflict, duplicate/reordered sync, delete versus stale device, revoked access, upgrade with queued edits and restored server backup.

For packaging, document supported Linux baseline and Wayland/X11 behavior. Keep Android application identity and release signing stable; do not commit signing keys. Pin toolchains/dependencies and verify checksums/artifacts before publishing a release.

## 8. First continuation assignment

Start at **M1 — reproducible client build and truthful local save** in [Plan.md](Plan.md):

- Inspect current branches, source, toolchain and Actions evidence.
- Get the current client analyzed, tested and built on at least one available target; fix concrete build errors.
- Document inability to run a target instead of inventing a pass.
- Add reliable saving/error/retry behavior and lifecycle-safe flush semantics.
- Establish persistence/reopen tests and confirm that editing, navigation, trash and restoration do not silently lose content.
- Record evidence and leave the repository ready for the editor/data-schema milestone.

Continue independently on authorized reversible work. Ask only for missing access, material unresolved requirements or actions that truly require a new decision. Report changes and blockers plainly, in Bangla mixed with English for this owner.
