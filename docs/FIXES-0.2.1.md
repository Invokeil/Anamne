# Anamne 0.2.1 reliability fix record

Date: 2026-10-15. Inputs: owner's uploaded GLM 0.2.0 source plus its separately supplied web
artifact. Source is now **0.2.1+3**; server/MCP report **0.2.1**. The old web archive was not
repackaged: fresh artifacts must be produced from this source with the local toolchain.

## Changes

| Defect | Source correction | Evidence / limit |
|---|---|---|
| A→B navigation retained A editor state | Page/database/canvas keyed by entity ID; editor resets on changed documents and clean remote updates | Flutter navigation regression added; not executed here |
| Leaving during debounce lost saves | Immutable draft snapshots; serialized saves; navigation/lifecycle flush; visible failure/retry state | Draft/navigation tests added; not executed here |
| Client sent targetId while trash/restore/purge server expected id | Client sends both; server accepts legacy targetId | Server client-shaped request test passes |
| Rejected outbox item caused endless immediate retry and blocked pull | Bounded four-batch pass; one item per entity per batch; rejected target blocked for this pass; pull proceeds | Flutter mocked-HTTP regression added; not executed here |
| Queued edits reused obsolete base revisions | Durable sequence ordering and transactional ack/rebase of unsent successors | Flutter ack-order regression added; not executed here |
| Missing/stale revisions silently overwrote server data | Existing entities require exact expectedVersion; missing revision is create-only | Page/database revision tests pass |
| Database conflict discarded local state | Atomic page/database conflict copy, outbox replacement and server snapshot application | Flutter database-schema/record preservation test added; not executed here |
| Parent purge omitted child deletions; stale devices could recreate IDs | Change events and retained purge tombstones for every descendant; same-ID create blocked | Server stale-child/purge test passes |
| Applied-op record could fail after mutation commit | Nested domain savepoints inside outer mutation/change/ack transaction; canonical payload hash for op replay | Injected ack failure rollback + replay/payload tests pass |
| Revoked primary env token still authorized / reappeared | HTTP consults only token store; durable revoked hash; named env rotation removes old value, including legacy upgrade | HTTP denied-after-revoke and store restart/rotation tests pass |
| Cross-origin web requests failed preflight | Explicit origin allowlist; unauthenticated OPTIONS; actual requests retain bearer auth | HTTP allowed/disallowed origin and preflight tests pass |
| MCP rejected UI-generated row IDs | Shared slug validation for row upsert | Server row-ID test passes |
| MCP schema omitted block/canvas fields; client discarded properties | Tool schemas include blocks/type/data; page model round-trips properties | MCP protocol test passes; Flutter model test source updated |
| New sync settings did not start periodic sync; pulls left stale UI | Configure starts timer; workspace observes pull completion; API client/timer disposal | Flutter source; real periodic/UI/device QA still required |
| Source and supplied bundle version disagreed | Source version bump; local web build verifies generated version.json | Build script source; fresh Flutter build still required |
| Unwanted CI minutes on push | Workflow triggers changed to workflow_dispatch only | YAML inspected; no workflow dispatched for this task |
| Android release lacked guaranteed network permission | Tracked platform configuration adds main-manifest INTERNET permission idempotently | Python fixture test; APK not compiled here |

## Verification recorded here

- Node.js **24.19.0**: `cd server && npm test` — **19 tests passed**, zero failures.
- Shell syntax and Python platform-configuration fixture checks run locally. These do not
  establish a successful Flutter bootstrap or artifact build.
- Flutter/Dart analysis, all Flutter tests and all target builds: **not run**, SDK absent.
- Podman runtime, phone install, Linux desktop GUI, browser interaction/IME, two-device sync and
  a live MCP-host-to-app journey: **not run**.

The historical GLM report of passing Flutter tests/web build does not verify these changed
files. The supplied old web archive's version metadata was 0.1.0+1 despite its 0.2.0+2 source.
Do not distribute it under this fix's version label.

## Remaining gaps

- Draft flush starts a durable write but cannot guarantee completion if the OS kills the process
  first. A failed write after editor disposal has no persistent recovery registry yet.
- Client regression source requires compilation/execution with pinned Flutter. Network races,
  in-flight edits and database/canvas navigation need manual multi-device tests.
- Retry is fixed interval, not exponential backoff; the outbox has no rejected-item management UI.
- Sync currently binds one local workspace to one server URL. Back up and use a separate local
  store to change servers. There is no complete workspace switch/reset/import recovery UI.
- Previously missing 0.2.0 purge/revocation history cannot be recovered after the fact. Back up
  first; explicitly revoke known old tokens again and inspect older-device orphaned content.
- One shared server workspace; no membership isolation or public signup. Client tokens remain in
  local Sembast settings instead of OS secure storage. HTTP token roles do not protect stdio MCP.
- MCP is local/SSH stdio with 14 tools; remote authenticated HTTP and measured 99% coverage remain
  open. Custom HTTP actions/webhooks, resources and full UI/admin parity remain incomplete.
- Notion exact UI/UX matching, rich inline formatting, robust unknown-block round trips, full
  archive/attachment restore, signing/upgrade QA and offline web-shell caching remain open.
- Markdown vault is a one-way projection; title-ID filenames and stale rename/trash mirrors do
  not establish complete Obsidian interoperability. Do not treat it as a verified full backup.
- Container templates are source only; the data directory ownership was corrected but no image
  was built/run here. Back up before real deployment and verify runtime permissions/restore.

Use [LOCAL_BUILD.md](LOCAL_BUILD.md) and [../LOCAL_AI_PROMPT.md](../LOCAL_AI_PROMPT.md) to finish
local verification and produce fresh artifacts without consuming GitHub Actions minutes.
