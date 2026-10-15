# Anamne — execution plan and remaining work

Last reviewed: **2026-10-15**. Implementation baseline: `e2693a543bce715aae84e7783b37354c08b6acae` on GitHub `main`. This is a living plan; update statuses using source and test evidence after each implementation slice.

Read [prompt.md](prompt.md) for the full product requirements and [agent.md](agent.md) for engineering rules. The older [docs/ROADMAP.md](docs/ROADMAP.md) contains background research and broad options; this file resolves the current product name, stack, license and implementation order.

## 1. What we are building

**Anamne** is an open-source personal knowledge workspace: Notion-style pages, blocks and databases; offline editing; linked notes; portable data; self-hosted personal sync; and first-class API/MCP control.

- Product: Anamne.
- Attribution: **Powered by ©Invokeil Tech**.
- Repository: `Invokeil/Anamne`.
- Initial outputs: Android APK, Linux x86_64 AppImage and web build.
- Upcoming outputs: Windows and macOS after their own QA.
- Local use works without a server account. A VPS is used for device sync and integrations.
- Public distribution means people can run their own copies; managed hosting capacity is a separate operational decision.

## 2. Current decisions and historical corrections

| Topic | Current baseline | Remaining decision or gate |
|---|---|---|
| Client | Flutter + Dart, SDK constraint `>=3.8.0 <4.0.0` | Pin an actually tested Flutter release; pass editor and browser gates |
| Android-specific code | No custom Kotlin integration yet | Add only for concrete OS integration requirements |
| Client persistence | Sembast native file and browser IndexedDB | Evaluate Drift/SQLite with a migration preserving current pages |
| Server | Node.js 24 + built-in SQLite | Retain until measured reasons justify a different implementation |
| License | MIT in the current repository | Review chosen dependencies and notices before adoption/release |
| Data authority | Simple local page records now | Versioned structured documents intended; readable Markdown portability |
| Sync | None | Durable queue, identity, cursors, tombstones and conflict recovery |
| MCP | Nine server stdio tools | Remote transport, resources, scopes and application-wide operation parity |
| UI references | Generic initial shell plus design specification | Exact selected Notion screens still need evidence, measurement and comparison |
| Stitch | Design rules prepared | No live Stitch generation or authenticated session verified in this implementation |
| Encryption | No end-to-end encrypted sync | Separate reviewed design and recovery milestone if adopted |

The historical roadmap's Go backend, provisional AGPL choice and unnamed-product text are superseded by the current Node.js implementation, MIT license and Anamne name. Its proposed future directory tree has not been created. Do not rewrite the server or relocate the whole project merely to resemble that old proposal.

## 3. Status vocabulary

- **Source present**: implementation exists; platform behavior may remain unverified.
- **Verified**: a named test/build/manual scenario passed with recorded environment and evidence.
- **Partial**: a working subset or foundation exists; listed requirements remain.
- **Missing**: no implementation is present in the reviewed baseline.
- **Blocked**: a concrete external dependency/access issue prevents the next action; keep unrelated work moving.

A checked item in a source inventory is not proof that a complete product milestone passed. No feature-completion percentage is asserted here.

## 4. Baseline inventory

### Source already committed

- [x] Public `Invokeil/Anamne` repository and MIT license.
- [x] Flutter project manifest and Android/Linux/web bootstrap script.
- [x] Responsive page navigation, drawer/sidebar and plain text editor source.
- [x] Page/subpage creation and title/body editing source.
- [x] Debounced save and Sembast repository implementation.
- [x] Title/body search, recoverable trash and restore source.
- [x] Permanent-delete dialog in the Flutter UI.
- [x] Clipboard Markdown and workspace JSON export.
- [x] Supplied logo derivatives and loading-mark animation adaptation.
- [x] Node.js HTTP API with bearer-token check.
- [x] Server SQLite page storage, custom JSON properties and optimistic PATCH version check.
- [x] Nine MCP stdio tools sharing server storage.
- [x] Four meaningful server tests: HTTP auth/version writes, MCP handshake/page round trip, nested page behavior, literal wildcard search.
- [x] Two Flutter test files (model round trip and initialization-error screen).
- [x] GitHub Actions workflow targeting server tests, web, APK and Linux AppImage.
- [x] systemd/Caddy deployment examples and API/design/roadmap documents.

### Verification record

| Check | Last known result | Limit |
|---|---|---|
| `cd server && npm test` | Four tests passed locally during foundation work | Not a full security, durability, load or protocol compliance audit |
| SVG parse and PNG dimensions | Passed locally | No UI screenshot comparison or OS icon QA |
| Shell syntax and workflow YAML parse | Passed locally | Not proof that platform bootstrap/builds succeed |
| Flutter analysis/tests/build | No recorded pass in the initial workspace | Flutter/Dart SDK absent there; no APK/AppImage/web release verified |
| GitHub CI status query at this review | No statuses returned for baseline commit | Empty response is not proof that Actions passed, failed or never ran |
| Physical Android / Linux / browser QA | Missing | Must record real scenarios and environment |
| VPS live deployment | Missing | Templates exist; no Anamne server deployment verified |

## 5. Remaining feature matrix

| Capability | State | Work required |
|---|---|---|
| Local workspace management | Partial | Multiple workspaces, selection/persistence and isolation |
| Durable page editing | Partial | Save/error/retry states, lifecycle flush and crash/reopen evidence |
| Page organization | Partial | Move/reorder/duplicate/favorites; documented tree deletion/restoration |
| Block editor | Missing | Schema, adapter, formatting, block operations, slash menu, IME QA |
| Attachments | Missing | Local files/images, metadata, safe paths and resumable sync |
| Native backup and restore | Missing | Archive manifest, checksums, import preflight and fresh-install restore |
| Markdown/Notion/CSV import | Missing | Mappers, stable IDs, fidelity report and unsupported-content preservation |
| Links/backlinks/tags | Missing | Stable references, indexing and navigation |
| Daily notes/templates | Missing | User-owned reusable structures and idempotent daily-note creation |
| Databases | Missing | Typed property schema, records, table editing and queries |
| Board/list/gallery/calendar | Missing | Views over the same records, with mobile behavior |
| Relations/formulas/rollups | Missing | Bounded evaluation and a documented supported subset |
| Graph | Missing | Neighborhood query and usable link navigation |
| User/device identity | Missing | Pairing, scoped access, token storage/revoke and workspace ownership |
| Personal sync | Missing | Outbox, cursors, revisions, retry, tombstones and conflict resolution |
| History | Missing | Recoverable revisions, diff and restore policies |
| Public API contract | Partial | Machine-readable OpenAPI, complete schemas, pagination and error policy |
| Remote MCP | Missing | Authenticated transport, discovery, resource contexts and client tests |
| 99% MCP control | Missing | Operation register, feature parity, permission tests and measured coverage |
| Customized API | Partial | Existing JSON properties only; add typed schemas and safe HTTP actions |
| Webhooks/automations | Missing | Declarative triggers, durable jobs, preview/retry/audit |
| Selected Notion UI/UX matching | Missing | Reference ledger, approved measurements, Flutter comparison and behavior QA |
| Themes/density/fonts | Missing | Light/dark, settings, licensed fonts and text/accessibility scaling |
| Android integration | Missing | Share-to-note, file picker and lifecycle/permission handling |
| Desktop ergonomics | Partial | Shortcuts, tabs, command palette, window state and later split view |
| Offline web application | Missing | Reload cache/update strategy, storage diagnostics and recovery |
| Verified packages | Missing | Stable identity/signing, install/upgrade QA, checksums and release notes |
| Public multi-user hosting | Missing | Membership/permission isolation and operational gates; no open signup yet |
| Windows/macOS | Missing | Native scaffolds, integration, packaging and independent QA |

## 6. Dependency order

```mermaid
flowchart TD
  A["M1 Build and save reliability"] --> B["M2 Editor and data model"]
  B --> C["M3 Archive and migration"]
  C --> D["M4 Knowledge links"]
  D --> E["M5 Databases"]
  C --> F["M6 Identity and server contract"]
  F --> G["M7 Personal sync"]
  E --> G
  G --> H["M8 Remote MCP and custom API"]
  H --> I["M10 Release verification"]
  E --> J["M9 UI and platform refinement"]
  J --> I
```

Reference collection and shared API/MCP commands begin with the relevant feature; they are not postponed until M8/M9. The later milestones consolidate coverage and polish. Link/database work can be bounded to a smaller supported subset if it blocks reliable sync and recovery.

## M1 — reproducible client build and truthful local save

**Priority:** P0. **State:** open. **Next implementation assignment.**

### Tasks

- [ ] M1.1 Inspect the active GitHub head, local changes, toolchains and actual Actions job logs/results.
- [ ] M1.2 Pin an available Flutter release and compatible resolved dependency set; document Node version and platform prerequisites.
- [ ] M1.3 Run bootstrap from a clean checkout; ensure it preserves source/tests and is safe to rerun.
- [ ] M1.4 Resolve analysis/test/build failures on an available target. Record blockers for unavailable targets separately.
- [ ] M1.5 Decide which native generated projects/configuration must become versioned before platform integrations; remove relevant ignore rules when adopting them.
- [ ] M1.6 Extract persistence/save state from the large UI file where needed for testability.
- [ ] M1.7 Show saving, durable-saved, error and retry states; do not show saved when a write has not completed.
- [ ] M1.8 Flush or persist drafts safely on page switch, route changes and app lifecycle transitions; surface write exceptions.
- [ ] M1.9 Test concurrent queued saves versus navigation, trash, restore and permanent deletion.
- [ ] M1.10 Define restoration when a child is restored under a deleted parent, and whether separately trashed descendants remain trashed when an ancestor is restored.
- [ ] M1.11 Add persistence/reopen tests, including Bangla and storage failure, using the same repository behavior as the app.
- [ ] M1.12 Start the UI reference-state inventory for navigation/editor/search on Android and desktop.

### Exit gate

A clean checkout produces a usable client on at least one verified target. A page can be edited, acknowledged as saved, reopened after restart and recovered from a simulated failed write. No known reproducible lost-save bug remains in that path. Other platforms are clearly marked unverified until their own builds and QA pass.

## M2 — structured editor and durable domain model

**Depends on:** M1. **State:** missing.

### Tasks

- [ ] M2.1 Write a short architecture decision for structured documents versus direct Markdown authority; retain the owner's Notion-centered priority.
- [ ] M2.2 Define workspace/page/block/property IDs, schema versions, block ordering and unknown-field preservation.
- [ ] M2.3 Evaluate a Flutter editor component with a small Android/Linux/Firefox/Chromium spike; record package version and license decision.
- [ ] M2.4 Implement an editor adapter; keep the portable schema independent of editor package internals.
- [ ] M2.5 Evaluate Drift/SQLite for native/web persistence, migration cost, browser requirements and failure behavior.
- [ ] M2.6 Migrate existing Sembast records with backup/recovery fixtures; preserve IDs and text exactly.
- [ ] M2.7 Add paragraph, heading, lists, tasks, quote, divider and code blocks with initial inline formatting.
- [ ] M2.8 Add slash menu, Markdown shortcuts, undo/redo, block conversion and reorder behavior.
- [ ] M2.9 Add safe image/file and callout blocks; retain originals and validate metadata.
- [ ] M2.10 Test Bangla IME, selection, paste, undo, emoji and mixed-script text on actual input systems.
- [ ] M2.11 Add domain commands, API schemas and MCP read/edit/append/move block operations for the supported block set.

### Exit gate

Supported rich documents round-trip through storage and schema serialization without loss. Existing plain pages migrate. Unsupported blocks survive editing. Android/Bengali and web/editor feasibility evidence is recorded before expanding the editor.

## M3 — recovery, portable archives and import

**Depends on:** M2; restore is required before sync rollout. **State:** missing.

### Tasks

- [ ] M3.1 Version a common native archive schema; reconcile client/server page-field differences first.
- [ ] M3.2 Add file-based export using platform save/share flows and web download, alongside readable Markdown.
- [ ] M3.3 Include manifests, checksums, page/block data, database placeholders and attachment bytes.
- [ ] M3.4 Add restore preflight, version validation, size/path protections and duplicate/conflict choices.
- [ ] M3.5 Restore a complete fixture into a fresh workspace and compare record counts, content, links and asset hashes.
- [ ] M3.6 Import the current `anamne.pages` JSON variants with explicit field mapping and migration diagnostics.
- [ ] M3.7 Add Markdown/frontmatter/wiki-link import and CSV parsing with documented supported subsets.
- [ ] M3.8 Add Notion Markdown/CSV ZIP import, preserving source and producing a fidelity report.
- [ ] M3.9 Add consistent server SQLite backup/restore and a documented upgrade rollback/recovery path.
- [ ] M3.10 Expose import preview, export, verification and restore planning through API/MCP with appropriate scope checks.

### Exit gate

A newly installed copy reconstructs a workspace from an archive. Corrupt, oversized and unsupported input fails recoverably with a report. No complete-backup claim is made before attachments and references are verified.

## M4 — organization and knowledge links

**Depends on:** M2/M3. **State:** mostly missing.

### Tasks

- [ ] M4.1 Finish move, reorder, duplicate, favorites and page-tree keyboard/touch operations.
- [ ] M4.2 Add stable wiki/page/block references, unresolved link states and duplicate-title disambiguation.
- [ ] M4.3 Add backlink/tag indexes maintained with page mutations and migrations.
- [ ] M4.4 Add template creation/application and configurable daily notes.
- [ ] M4.5 Replace whole-workspace linear search where measurements warrant an index; verify multilingual search semantics.
- [ ] M4.6 Add a command palette and basic desktop tabs preserving unsaved edits.
- [ ] M4.7 Add a neighborhood graph after navigation/index correctness is established.
- [ ] M4.8 Add API/MCP commands and resources for these supported operations.

### Exit gate

Rename/move/export/restore preserves references. Search/backlinks reflect edits and trash policy consistently. Templates and daily-note actions are idempotent under retries.

## M5 — databases and consistent views

**Depends on:** M2/M3. **State:** missing.

### Tasks

- [ ] M5.1 Define typed property schemas, record identity, schema migrations and validation errors.
- [ ] M5.2 Implement a table with create/edit/delete, filter/sort, column controls and mobile cell editing.
- [ ] M5.3 Add page-reference properties and relation metadata without duplicating page records.
- [ ] M5.4 Add board and list views over the same data, including offline changes.
- [ ] M5.5 Add gallery/calendar only after the table/board/list contract is stable.
- [ ] M5.6 Define a bounded formula/rollup subset, dependency cycles and error reporting; defer unsupported functions explicitly.
- [ ] M5.7 Add schema/query/row/view operations to REST/MCP; preserve them in archives.

### Exit gate

One record edited in any supported view is consistent in every other view and after reopen/restore. Invalid typed data and evaluation cycles produce bounded, inspectable errors.

## M6 — identity, server contract and shared services

**Depends on:** M3 and the implemented domain scope. **State:** foundational HTTP/store code only.

### Tasks

- [ ] M6.1 Move HTTP/MCP handlers behind shared commands and validation; avoid duplicated business rules.
- [ ] M6.2 Publish OpenAPI and versioned cross-language page/block/property fixtures.
- [ ] M6.3 Introduce workspace ownership, user/device identity and membership boundaries; no public signup until isolation is tested.
- [ ] M6.4 Add scoped credentials, pairing, secure client token storage and revoke/expiry behavior.
- [ ] M6.5 Apply expected revisions/idempotency to all relevant mutations, including tree operations and imports.
- [ ] M6.6 Add durable revision/change history and a consistent cursor/pagination contract.
- [ ] M6.7 Add audit metadata, rate limits, request bounds and useful redacted error diagnostics.
- [ ] M6.8 Implement safe attachment metadata, hashing, resumable upload/download and access checks.
- [ ] M6.9 Review tree mutation atomicity, independently trashed descendants and multi-process SQLite behavior.
- [ ] M6.10 Add access-denial, conflict, rollback and malformed-input scenarios for both HTTP and MCP entry points.

### Exit gate

Two workspaces cannot read/write each other's data. Revoked credentials fail. The same permitted operation has equivalent results and errors through API and MCP. Revision history and backups are recoverable.

## M7 — connect app, server and MCP with personal sync

**Depends on:** M2/M3/M6 and chosen knowledge/database subset. **State:** missing.

### Tasks

- [ ] M7.1 Persist a local outbox atomically with edits; allocate stable operation IDs.
- [ ] M7.2 Define push/pull requests, cursors, base revisions, acknowledgements and compatibility policy.
- [ ] M7.3 Add bounded batching, retries/backoff, reconnect, offline/auth errors and cancellation.
- [ ] M7.4 Preserve both sides of conflicts; implement revision diff and an explicit resolution UI.
- [ ] M7.5 Add tombstone retention, stale-device handling and delete/restore reconciliation.
- [ ] M7.6 Coordinate resumable asset sync and metadata availability without blocking text editing.
- [ ] M7.7 Show device/sync state, pending changes, retry and conflict actions truthfully.
- [ ] M7.8 Test phone and desktop offline edits, duplicate/reordered requests, server restart and upgrade with pending outbox entries.
- [ ] M7.9 Verify an MCP-created/edited page appears in the app after sync, and app edits appear through API/MCP.
- [ ] M7.10 Document first-time pairing, lost-device revocation, backup restore and resync behavior.

### Exit gate

The app and MCP operate the same logical workspace. Same-page offline edits on two devices are recoverable. Old devices cannot silently resurrect permanent deletions. No unacknowledged data disappears during reconnect or upgrade.

## M8 — complete MCP coverage, customized API and automation

**Depends on:** M6/M7; parity work also accompanies M2–M7. **State:** nine initial stdio tools only.

### Tasks

- [ ] M8.1 Adopt or verify a maintained MCP implementation and negotiated protocol versions; test malformed messages and lifecycle behavior.
- [ ] M8.2 Add authenticated Streamable HTTP for remote clients, with session/origin/authorization handling appropriate to the chosen spec.
- [ ] M8.3 Add typed tool input/output schemas and structured domain errors for every supported operation.
- [ ] M8.4 Add page/schema/search/sync/history resources and useful optional workflow prompts.
- [ ] M8.5 Create an operation register mapping UI → shared command → REST → MCP → scope → evidence.
- [ ] M8.6 Include workspace, block, database, file, import/export, history, settings and admin operations as those features ship.
- [ ] M8.7 Add scoped preview/apply behavior for destructive/bulk actions and approved external actions.
- [ ] M8.8 Extend custom properties into typed user-defined schemas with migrations and API exposure.
- [ ] M8.9 Add declarative custom HTTP actions with schema validation, destination controls, secrets and dry-run previews.
- [ ] M8.10 Add durable webhook/automation jobs, deduplication, retry/audit history and revoke/disable controls.
- [ ] M8.11 Test SSRF/redirect/oversize/error cases for external HTTP actions.
- [ ] M8.12 Compute MCP coverage using tested eligible operations; target ≥99% and require all critical operations.

### Coverage rule

`coverage = 100 × tested MCP operations / eligible implemented domain operations`.

Count an operation only after its success, validation, permission and relevant failure behavior is exercised. Record OS-bound exclusions separately. Do not equate nine tools or an endpoint count with 99% application control. The current coverage is **not measured**.

### Exit gate

A real MCP client can complete the supported normal workspace journeys with documented scopes. Coverage evidence supports the claim, and remote/API actions preserve the same authorization and durability guarantees as the UI.

## M9 — measured UI/UX matching and platform refinement

**Depends on:** reference collection starts at M1; full flows depend on their features. **State:** specification and initial shell only.

### Tasks

- [ ] M9.1 Build a reference ledger with approved Notion screens, platform/app version, viewport, theme, source/date and observed interactions.
- [ ] M9.2 Include empty, loading, editing, keyboard, selection, menu, offline, error and conflict states.
- [ ] M9.3 Use Stitch when helpful for a specified screen/flow; retain its actual output and conversion notes. Handle sign-in only when required.
- [ ] M9.4 Implement measured Flutter typography, spacing, navigation, control positions and transitions with Anamne assets.
- [ ] M9.5 Compare matching-size screenshots and interaction recordings; track discrepancies rather than declaring an unsupported exact match.
- [ ] M9.6 Add light/dark, density, text sizing, licensed Bengali fonts and persistent settings.
- [ ] M9.7 Add TalkBack/screen-reader semantics, focus order, keyboard-only operation, text scaling and reduced motion.
- [ ] M9.8 Add Android share-to-note, file access, background/lifecycle constraints and predictable Android back behavior.
- [ ] M9.9 Finish Linux Wayland/X11, shortcut/window and desktop integration behavior; add split view only after the editor is stable.
- [ ] M9.10 Add web storage diagnostics, offline reload/app-shell caching and update behavior that preserves pending edits.

### Exit gate

Named reference states have comparison evidence and accepted discrepancies. Bangla input and accessibility gates pass. No universal or unmeasured pixel/UX-equivalence claim is made.

## M10 — self-hosting, performance and public beta delivery

**Depends on:** agreed M1–M9 release scope. **State:** templates/workflow only.

### Tasks

- [ ] M10.1 Validate minimal single-user VPS install/upgrade/uninstall procedures on an actual supported host.
- [ ] M10.2 Benchmark server memory, peak operations, SQLite contention, backup/export/restore, disk growth and bounded concurrent clients.
- [ ] M10.3 Benchmark 1,000/10,000-note fixtures and a 2,000-block document with hardware/build details.
- [ ] M10.4 Fix measured typing/scrolling/search regressions; do not introduce compulsory services to mask them.
- [ ] M10.5 Pin build inputs, track native configuration deliberately, cache CI safely and avoid unnecessary documentation-only build cost.
- [ ] M10.6 Produce signed Android APK with stable identity/key handling; test install, upgrade and offline reopen on the target phone.
- [ ] M10.7 Produce AppImage with a supported runtime baseline; test dependency resolution and installation flow on representative Linux systems.
- [ ] M10.8 Publish web build only after HTTPS/offline/storage/update behavior is documented and verified.
- [ ] M10.9 Add release checksums, changelog, third-party notices, contributor guide, issue templates and a security reporting policy with a real contact.
- [ ] M10.10 Add privacy/diagnostic guidance; analytics/crash reporting must be optional and redact note content/secrets.
- [ ] M10.11 Verify fresh workspace restore and old-version upgrade on every claimed supported platform.
- [ ] M10.12 Publish a tagged beta with supported/unsupported features and known issues.

### Exit gate

Artifacts exist and have install/upgrade evidence. Core data-loss, permission, recovery and IME gates pass. VPS suitability is described from measurements. No release is called production-ready merely because CI is green.

## M11 — expansion after a dependable beta

Separate scoped milestones; these are not implicit requirements to complete before the first useful personal build.

- [ ] Windows build/integration/installer and platform QA.
- [ ] macOS build/integration/package and platform QA.
- [ ] Bidirectional Markdown folder bridge with conflict-safe external edits.
- [ ] Broader formulas/rollups, timeline and more advanced database queries.
- [ ] Larger graph, canvas/whiteboard and rich embeds.
- [ ] Capability-limited plugin SDK and reviewed extension lifecycle.
- [ ] Optional BYOK AI with custom/OpenAI-compatible providers and explicit content-sharing controls.
- [ ] Optional E2EE with complete key management, recovery and model-specific feature trade-offs.
- [ ] Team collaboration, sharing, comments, publishing and granular memberships.
- [ ] Optional managed hosting after capacity, billing/operations and user isolation are explicitly planned.

## 7. Release scenario register

All rows are open unless dated evidence is attached. Add test names, actual commands, platform and artifact/commit references as work progresses.

| ID | Scenario | Required outcome |
|---|---|---|
| R01 | Offline edit → acknowledged save → force close → reopen | Exact saved content recovered |
| R02 | Storage write failure/quota/disk full | Visible failure, recoverable draft, no false saved state |
| R03 | Bangla IME + formatting/selection/undo | Composition and content preserved |
| R04 | Rename/move/nested trash/restore | No cycles, lost links or undocumented descendant changes |
| R05 | Native archive → fresh install restore | Data/asset/link counts and checksums match |
| R06 | Import unsupported/corrupt/oversized input | Bounded failure and useful fidelity report |
| R07 | Two devices edit same page offline | Both revisions retained and reviewable |
| R08 | Duplicate/reordered push and server restart | Idempotent operations and durable cursor |
| R09 | Delete/restore vs stale-device reconnect | No silent resurrection or data loss |
| R10 | Revoked token or another workspace ID | Access denied without data disclosure |
| R11 | UI/API/MCP equivalent mutation | Same domain validation, permissions and revision result |
| R12 | Upgrade with pending local edits | Outbox, schema and recovery remain consistent |
| R13 | Browser offline reload/multi-tab/update | Content remains available, changes do not vanish |
| R14 | Android/Linux package install and upgrade | Stable identity, retained data, usable editor |
| R15 | Custom HTTP action hostile destination/error | Destination/secret controls hold; retries do not duplicate side effects |

## 8. Risks to resolve first

| Risk | Evidence or reason | Next resolution |
|---|---|---|
| Unverified client builds | SDK absent during foundation creation | M1 clean checkout and actual build logs |
| Save failure visibility/lifecycle loss | Debounced callbacks exist; no complete save-state UI | M1 persistence/lifecycle scenarios |
| Divergent client/server schema | Current client omits server version/properties/creation metadata | M2/M3 canonical schema and fixtures |
| Inconsistent tree semantics | Current store methods cascade broadly | M1/M6 explicit policy and regression scenarios |
| Superficial MCP validation | Manual stdio server handles only an initial protocol/tool subset | M6/M8 schema/protocol/permission review |
| Large workspace memory | Native Sembast and current lists load whole records | M2 storage choice and M10 fixtures |
| Backend rewrite churn | Old roadmap proposes Go; source is Node.js | Retain Node and measure first |
| Build-resource limits | Flutter/Gradle and multi-target CI are heavy | Use appropriate runner, caching and scoped build gates |
| UI mismatch | Reference screens have not been measured | M1/M9 reference ledger and screen comparisons |

## 9. Working cadence and evidence

Do not treat old rough week estimates as a deadline. Deliver one complete behavior at a time, with storage and API/MCP implications considered. Suggested first slices: clean client build → safe save/reopen → rich document serialization → archive restore → link navigation → table edit → paired-device sync → remote MCP parity.

For each completed task record:

```text
Task ID:
Commit:
Behavior delivered:
Schema / migration impact:
Commands and actual results:
Device / OS / build mode:
Screenshot or trace if relevant:
Known limitation:
Next task:
```

Relevant existing commands:

```bash
# Server checks (Node.js 24+)
cd server
npm test
```

```bash
# Client checks, only where Flutter and platform prerequisites are installed
bash tool/bootstrap.sh
flutter analyze
flutter test
flutter build web --release
flutter build apk --release
flutter build linux --release
bash tool/package_appimage.sh
```

These are commands to run with the needed environment, not a claim that all have passed. Keep APK signing material, API tokens and real user notes out of fixtures and commits.

## 10. Definition of done

An implementation item is done when its accepted behavior works, necessary failure cases are exercised, migrations/recovery are safe, supported platforms have evidence, and UI/API/MCP coverage or deliberate gaps are documented. Update this file and the README together when product status changes.
