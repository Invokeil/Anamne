# Anamne local source and build review — 2026-10-15

The supplied source changes are suitable for consolidation into `main`. The missing editor
hover fix is present in both the supplied source and `build-fixes-local`. Keep the newer
`main` changes and the platform guides while incorporating that fix. This review supports a
source update and local evaluation; it does not certify a production release or every roadmap
feature. No GitHub Actions workflow was dispatched and no binary release was published.

## Inputs and source provenance

The owner supplied `Anamne.zip` through a download link after the chat attachment failed.

| Input | Value |
|---|---|
| Archive size | 233,738,746 bytes |
| Archive SHA-256 | `3dffa702a96db47fc38ac5c0a419768b2c881f3c71a3fbbbf30f350cdc184a48` |
| Archive entries / expanded size | 3,681 / 669,761,416 bytes |
| Source's recorded starting commit | `4a4733d5d6a3fbf867cffa4b94c307225a61b076` |
| Recorded source branch | `main`, with uncommitted local changes |
| Reviewed GitHub main | `e5a51c59512675f922298f470daaba396ca20aae` |
| Reviewed local-fixes branch | `7b3288e45d178ed4b77e072e9d3a6ddb96c69b8a` |
| App / server version | `0.2.1+3` / `0.2.1` |

The source archive contained no absolute/traversal paths or ZIP symlink entries. It included
generated Android/Linux/web projects, compiler caches and duplicate build outputs. Those
generated files are inspection inputs, not source files to commit. Source pattern checks found
no matching private keys or common API-token patterns; this is a bounded scan, not a complete
secret-detection or security certification. No private signing key was included in the source.

The local build report records Flutter 3.47.7 / Dart 3.13.5, Node 24.10.0, Python 3.12.3,
OpenJDK 21 and elementary OS 8. Android SDK/NDK versions were selected from the generated
project. The Linux target was built from a filesystem supporting symlinks after an exFAT
checkout could not create its plugin symlinks. Preserve that distinction when reproducing it.

## Source review and consolidation

Relative to starting commit `4a4733d`, five tracked files changed:

- `lib/editor/block_editor.dart`: `FittedBox(fit: BoxFit.scaleDown)` contains the drag handle
  and menu in the existing 40 px gutter; remaining edits are formatting.
- `lib/store/page_repository.dart`, `lib/sync/sync_engine.dart`, `lib/ui/settings_dialog.dart`:
  analyzer-required braces and formatting.
- `test/editor_navigation_test.dart`: waits 400 ms after a canvas double tap so gesture timers
  finish before the test tree is disposed.

The current GitHub `main` already contained the braces/timer fixes and four platform guides,
but its editor file did not contain the hover fix despite its commit message mentioning it.
The two remote branch trees differed only in that editor file. Consolidate using the reviewed
branch's minimal editor change; the supplied formatted editor has the same hover behavior.

Retain `main`'s existing `SyncStatus.copyWith` message fallback rather than replacing it with
the older uploaded variant. Keep the four guides absent from the older uploaded checkout.
Server/API/MCP source, dependency lockfile, brand assets and the manual-only workflow are
unchanged by this consolidation. The stdio MCP contract remains 14 tools; 99% coverage and an
authenticated remote HTTP MCP transport are still unimplemented/unmeasured roadmap gates.

## Independently checked

| Check | Result |
|---|---|
| Uploaded server: `npm test` | **19 passed, 0 failed**, Node.js 24.19.0 |
| Shell syntax | Bootstrap, local build and AppImage packager pass `bash -n` |
| Platform configuration fixture | **1 passed**; repeated setup preserves custom fields and one release INTERNET permission |
| APK ZIP integrity | All ZIP CRCs pass |
| APK signature | `apksigner verify --verbose --print-certs` passes; APK Signature Scheme v2 |
| APK identity | `tech.invokeil.anamne`, label Anamne, versionName 0.2.1, versionCode 3 |
| Android levels / permission | minSdk 24, target/compile SDK 36, INTERNET present; no debuggable application flag observed |
| Android arm64 native packaging | Three arm64 libraries stored uncompressed at 16 KB aligned ZIP offsets; ELF LOAD alignments at least 16 KB |
| APK/build output consistency | Supplied APK equals both archived final APK outputs; packaged `libapp.so` equals the archived stripped native output |
| Android compiler-source evidence | Embedded kernel sources contain exact copies of 19 uploaded Dart source files, including the corrected editor and draft saver; the web-only factory is absent as expected |
| Web | Supplied main.dart.js checksum matches report; version.json is 0.2.1 / build 3 |
| AppImage | Valid SquashFS 4 filesystem; all 16 Linux-bundle payload files match byte-for-byte |
| Linux branding/launcher | Anamne icon matches source; desktop entry and AppRun launch the bundled executable |
| Linux dependency inspection | x86_64 ELF files; executable dependencies resolve in the review container |

Android signing certificate: `C=US, O=Android, CN=Android Debug`; SHA-256 fingerprint:
`3bf3eac6bd2ee28a28c546e4fe4ad34bf00713a49ecc81628c58f38a83bf7246`.
The APK is a **development-signed release-mode evaluation build**, not a production signing
identity. The complete Flutter engine/AOT payload is arm64. Other ABI directories contain only
`libdartjni.so`; do not label this a complete x86_64 or 32-bit ARM app.

The highest GLIBC symbol version observed in the bundled executable/native JNI library is
2.34; the Flutter engine uses symbols through 2.18. These observations do not establish support
for every Linux distribution or account for every host GTK/C++ dependency.

## Checksums

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `Anamne-0.2.1+3-android-arm64-release.apk` | 19,688,021 | `d110c418badbc2f9fa735431f0b7dc246607aceebc79715d083c0b70037b22c8` |
| `Anamne-x86_64.AppImage` | 10,521,080 | `b64a650d64f0c1e8950390d20426eab569c8ca9dcd2a58101d981ca2853b98af` |
| `web/main.dart.js` | 3,306,496 | `a0c66e6d812e378220ef6face32fc0fcfab2f850ae68a5f737a71333be41d198` |
| `linux-bundle/anamne` | 23,840 | `877c0e0070e15b8f1caa583b76ddc9652fa1e2333caea666f8b615f2bf9a6084` |

These hashes identify the supplied artifacts. They are not hashes of a fresh build of the
consolidation commit. Compiler-cache fingerprints alone are not authoritative: some cached
entries differ from current bytes while the embedded Android kernel sources match them.
Neither cache inspection nor signature validity proves an independently reproducible build.

## Builder-reported evidence and remaining QA

The supplied local report states: analyzer clean, **22 Flutter tests passed**, Web/APK/Linux
and AppImage builds succeeded; web HTTP preview returned 200; the Linux window opened in a
six-second smoke test. These are the local builder's results, not independently rerun Flutter
commands. Flutter/Dart SDK is absent from the review environment.

A separate headless Linux startup attempt could not create the review container's X11
listening sockets; GTK consequently could not open its display. This is not a completed GUI
test and is not evidence of an Anamne-specific startup defect. No Android phone was attached.

Still required before a public release claim:

- Real Android install/upgrade, Bengali IME, selection, save/switch, background/resume and back
  behavior; static target-SDK/alignment checks do not prove those scenarios.
- Manual two-client offline conflict/delete/retry tests and an MCP-host → app → API round trip.
- Clean-checkout Flutter analysis/tests/build on the exact consolidated commit; record commit,
  toolchain and artifact hashes together, using a symlink-capable filesystem for Linux.
- Production Android signing and target Linux install/upgrade compatibility checks.
- Existing roadmap gates: durable recovery of failed disposed drafts, secure token storage,
  workspace isolation, full backup/import fidelity, offline web-shell/update strategy and MCP
  parity. Exact Notion UI/UX matching is not established by this review.

Use [the local build guide](../LOCAL_BUILD.md) and
[the local AI assignment](../../LOCAL_AI_PROMPT.md). Keep Actions `workflow_dispatch` only;
building or reviewing locally does not require spending GitHub build minutes.

Tool references: [Android apksigner](https://developer.android.com/tools/apksigner),
[Android 16 KB checks](https://developer.android.com/guide/practices/page-sizes),
[Flutter SDK archive](https://docs.flutter.dev/install/archive).
