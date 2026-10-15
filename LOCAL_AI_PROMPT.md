# Local AI assignment — build and verify Anamne

Copy the prompt below to a coding AI running on your own laptop with terminal/file access.
This is a bounded reliability/build assignment. The complete product backlog is in `Plan.md`;
this task does not authorize implementing it all or deploying a server.
A later source/artifact review is recorded in `docs/reviews/2026-10-15-local-build.md`; read it
as well so historical verification gaps are not confused with later local-builder evidence.

---

You are working locally on **Anamne** in **https://github.com/Invokeil/Anamne** for Invokeil Tech.
The owner wants the current fixes verified, any build-blocking defects repaired, and fresh Web,
Linux x86_64 AppImage and Android arm64 APK artifacts built on this laptop. GitHub Actions build
minutes are exhausted: keep `.github/workflows/build.yml` **workflow_dispatch-only**, never
start Actions/Codespaces/cloud builds, and do not use paid build services.

## Read and preserve

1. Read `AGENTS.md`, `agent.md`, `README.md`, `Plan.md`, `docs/FIXES-0.2.1.md`,
   `docs/LOCAL_BUILD.md`, then the affected source/tests. Read `prompt.md` for product context.
2. Inspect the working directory, active branch/commit and local modifications. If absent,
   clone `https://github.com/Invokeil/Anamne.git`. If present, preserve edits before a safe
   fast-forward update. Never use `reset --hard`, force push or delete personal notes.
3. Preserve Anamne's supplied icon/loading assets, MIT license and
   **Powered by ©Invokeil Tech**. Keep Flutter + Sembast and Node.js + SQLite.
4. Current source version is `0.2.1+3`. Do not reuse the supplied old web ZIP or merely edit its
   `version.json`. Build fresh from the checked-out source. Preserve existing package ID and
   signing keys. Do not request secrets in chat or commit tokens, signing material or notes.

## Inspect the laptop and install only relevant prerequisites

- Detect OS/distribution, CPU architecture, memory, disk space and existing tools first. Use
  `/etc/os-release`, `uname -m`, `free -h`, `df -h`, `flutter doctor -v`, tool version commands.
- Follow `docs/LOCAL_BUILD.md`. Use pinned Flutter **3.47.7**, its included Dart, Node.js **24+**,
  Python 3 and the actual target dependencies. Fetch tools from official sources; inspect their
  package/version provenance. Do not blindly upgrade the host, Flutter or locked packages.
- On an 8 GB laptop, build sequentially, keep Flutter test concurrency at one and use the
  low-memory Gradle configuration from the script. Prefer a real phone over an emulator.
- Obtain Android SDK/NDK/CMake/build-tools based on the generated Gradle project and doctor.
  The owner reviews required Android licenses. A phone is optional for compilation.
- Obtain official `appimagetool` for the x86_64 Linux packaging step and record its checksum
  and runtime provenance. AppImage compilation is Linux-only; report incompatible host limits.

## Verify and fix the current source

Start with:

```bash
bash tool/build_local.sh check
```

This runs bootstrap, Node tests, analyzer and Flutter tests. The previous fix environment ran
**19 server tests successfully under Node 24.19.0**, but had **no Flutter/Dart SDK**. Flutter
regression tests were added as source and have not been executed. You must execute them and
repair actual analyzer/runtime/test failures. Do not assume the old GLM build claims verify
this new client.

Focus on real risks in `test/draft_saver_test.dart`, `test/editor_navigation_test.dart`,
`test/sync_regression_test.dart`, repository tests and `server/test/regressions.test.js`:

- Switching editor A→B cannot retain A controllers or save A text under B's ID.
- Pending immutable drafts flush when leaving editor/database/canvas and on lifecycle changes.
  Writes serialize; failures retain retry state while the editor exists. Do not claim abrupt
  OS-kill durability or disposed-editor failed-draft recovery without implementing/testing it.
- Outbox requests carry the correct target ID and revisions. A rejected operation does not
  cause an infinite loop or prevent pulling remote changes. Successive queued writes rebase
  only after a real acknowledgement. Lost-response replay remains idempotent.
- Existing server data cannot be overwritten by a missing/stale revision. Page/canvas and
  database conflicts preserve the latest local content under a new ID. A purge records all
  child deletions and rejects stale resurrection of the original IDs.
- Domain mutation/change-feed/applied-op acknowledgement are atomic, including fault rollback.
- Env-seeded tokens can be revoked permanently and rotated on restart/upgrade. HTTP fallback
  authentication must not bypass the token store. Do not remove access tests to get green output.
- Browser CORS preflights work for exact allowed origins; actual API calls still authenticate.
- MCP create/update preserve block/canvas fields; UI-generated row IDs work through MCP.
  Page custom properties survive client/server round trips.
- Configuring sync starts the timer immediately and pulls refresh the open workspace.

Use synthetic in-memory/temp fixtures, not the owner's real notes. Add/adjust tests for actual
bugs you encounter. If a test exposes a design problem, repair the implementation rather than
weakening the assertion. Format changed Dart files with the pinned SDK, inspect the diff, run
analysis and affected tests again. Record actual commands and results. Keep repository APIs
compatible or document/migrate any deliberate change.

## Produce fresh artifacts

After checks pass:

```bash
bash tool/build_local.sh web
bash tool/build_local.sh linux
bash tool/build_local.sh apk
APPIMAGETOOL=/actual/path/to/appimagetool-x86_64.AppImage APPIMAGE_EXTRACT_AND_RUN=1 bash tool/build_local.sh appimage
```

Replace the example path with the installed tool. Build targets one at a time. Do not copy old
bundles into the output directory. Expected locations:

- Web: `build/web/`; `version.json` must agree with `pubspec.yaml`.
- Linux bundle: `build/linux/x64/release/bundle/` (keep its libraries/assets).
- Android arm64: `build/app/outputs/flutter-apk/app-release.apk`.
- Linux AppImage: `build/appimage/Anamne-x86_64.AppImage`.

Inspect Android signing; a template development-signed release-mode APK is not store-ready.
Do not replace/create a public production signing identity without the owner's instruction.
For broader Linux portability, inspect dynamic libraries/glibc and test the intended distro.
A package that builds on one machine is not verified on all Linux distributions.

## Exercise and report

Serve web using `python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web` and test the
Linux app. With access to a real phone, install only with owner-authorized device access,
preserve existing notes/signing identity, and test Bengali IME, selection, save/switch and
lifecycle. If a display/phone is unavailable, label those scenarios unverified.

Run a local test server with a synthetic SQLite file, exact browser CORS origins and a private
throwaway token. Verify two independent clients' offline edits/conflict copies, delete/retry,
auth/revoke/restart and a real MCP-host create/edit → app sync → API read round trip.
Local stdio MCP has process-level database access; do not claim HTTP role protection or remote
HTTP transport. Do not expose this test server publicly or deploy to the VPS.

Write a local build report under ignored `build/`, with:

1. Exact source commit and any local modifications.
2. OS/architecture and Flutter/Dart, Java/Android SDK, Node and packaging tool versions.
3. Commands, actual test counts, exit codes, repairs and relevant redacted diagnostics.
4. Artifact filenames, sizes and SHA-256 checksums; web version comparison; APK signing type.
5. Manual/device scenarios actually exercised and concrete remaining gaps.

Update source status docs only with evidence. Do not claim exact Notion UI matching, complete
Obsidian compatibility, production readiness, full offline web reload or 99% MCP control.
These are open roadmap gates. Keep changes focused on reliability and build completion.

Return a concise Bangla + English status with the artifact paths and remaining blockers.
Make a local commit for any fixes if appropriate, but do not push additional changes, publish
releases, upload artifacts, dispatch CI or deploy anywhere unless separately instructed by the
owner. Continue independent local work without repeatedly asking for routine reversible steps;
ask only for a concrete missing credential/access/decision that the authorized task requires.

---

