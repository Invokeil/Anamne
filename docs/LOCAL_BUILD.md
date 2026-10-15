# Build Anamne on a local laptop

This guide targets Linux laptops (including elementaryOS/Ubuntu and Fedora). Build locally;
GitHub Actions is manual-only and must stay that way for this task. Windows/macOS application
support remains upcoming. Use a Linux host for the Linux bundle/AppImage.

## 1. Inspect, then clone

```bash
cat /etc/os-release
uname -m
free -h
df -h .
git --version
node --version
python3 --version
flutter --version
flutter doctor -v
```

A missing command is a prerequisite to install, not a reason to delete caches or the project.
Allow room for Flutter, Android SDK/NDK, Gradle caches and outputs. On 8 GB RAM, close other
heavy applications, use a physical phone and build one target at a time.

```bash
git clone https://github.com/Invokeil/Anamne.git
cd Anamne
git status --short
git rev-parse HEAD
```

For an existing checkout, inspect `git status` first; preserve edits, then `git pull --ff-only`
when clean. Do not use `reset --hard`, force pushes or remove user data.

## 2. Install the tools appropriate for this host

Use **Flutter 3.47.7** from the [official SDK archive](https://docs.flutter.dev/install/archive).
The archive lists this release; it is the pinned input, not a claim that these fixes already
passed a build. Install into a user-owned directory and put its `bin` on PATH. Flutter includes
Dart. Do not silently upgrade the pinned version or the locked dependencies to make a failure
vanish. Follow [Flutter installation](https://docs.flutter.dev/install/manual) for PATH/setup.

Install Node.js **24 or newer** from [Node.js](https://nodejs.org/en/download) or an existing
trusted version manager. An old distribution `nodejs` package may be insufficient for
`node:sqlite`. `npm test` needs no npm install here: the server has zero external dependencies.

For Ubuntu/elementaryOS/Debian-family Linux desktop prerequisites:

```bash
sudo apt-get update
sudo apt-get install -y git curl unzip xz-utils zip python3 clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev liblzma-dev libglu1-mesa
```

Check availability against your actual distribution/version. Fedora-family equivalents
(package naming can vary by release):

```bash
sudo dnf install git curl unzip xz zip python3 clang cmake ninja-build pkgconf-pkg-config gtk3-devel libstdc++-devel xz-devel mesa-libGLU
```

Do not run both package-manager commands. These are development dependencies, not a full
system upgrade. See the [official Linux Flutter setup](https://docs.flutter.dev/platform-integration/linux/setup)
and resolve `flutter doctor -v` for the chosen target. Browser development also needs Chrome
or a supported browser; building web alone does not need a browser process.

## 3. Run checks and build web first

```bash
bash tool/build_local.sh check
bash tool/build_local.sh web
```

Each command bootstraps missing platform directories, gets Flutter dependencies, applies
brand/configuration and runs Node tests, analyzer and `flutter test --concurrency=1`. A build
command runs those checks before compiling its target. Generated platform projects are ignored;
tracked `tool/configure_platforms.py` reapplies important release-network/brand settings.
Existing platform directories are preserved. If a platform directory is incomplete, repair it
with a backed-up diff rather than deleting it blindly.

Outputs: `build/web/`, with `version.json` checked against **0.2.1+3** in `pubspec.yaml`.
Serve over HTTP for testing, not a `file://` URL:

```bash
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Open `http://localhost:8080` in a browser. For a local API on port 8787, configure
`ANAMNE_CORS_ORIGINS=http://localhost:8080`; if you open `http://127.0.0.1:8080`, that is a
separate origin and must be listed too. An HTTPS web app needs an HTTPS API.

Browser notes live in that browser origin's IndexedDB. Changing port/hostname can appear to
create an empty workspace; export a backup first. The app's durable local note store is not
a complete offline web reload cache. Do not patch old build metadata and call it rebuilt.

## 4. Linux desktop and AppImage

```bash
bash tool/build_local.sh linux
./build/linux/x64/release/bundle/anamne
```

Ship the complete bundle directory, not only its executable. For the x86_64 AppImage, obtain
`appimagetool-x86_64.AppImage` from the [official AppImage releases](https://github.com/AppImage/appimagetool/releases).
Record the chosen release, its checksum and any upstream verification. Give its actual path:

```bash
chmod +x /absolute/path/to/appimagetool-x86_64.AppImage
APPIMAGETOOL=/absolute/path/to/appimagetool-x86_64.AppImage APPIMAGE_EXTRACT_AND_RUN=1 bash tool/build_local.sh appimage
chmod +x build/appimage/Anamne-x86_64.AppImage
./build/appimage/Anamne-x86_64.AppImage
```

`APPIMAGE_EXTRACT_AND_RUN=1` allows the packaging tool to run on systems without FUSE setup.
The resulting app may also be run with `APPIMAGE_EXTRACT_AND_RUN=1` when needed. The official
tool may download an AppImage runtime; record it or supply a verified local one through
`APPIMAGETOOL_RUNTIME_FILE`. The current packaging script supports Linux x86_64 only and does
not bundle every system dependency; test on the intended distribution before release.

Output: `build/appimage/Anamne-x86_64.AppImage`. Build on an appropriately old compatible Linux
base when wider glibc compatibility is required; a Fedora-built package is not automatically
compatible with every older Ubuntu/elementaryOS install.

## 5. Android APK on the laptop

Follow the [official Android Flutter setup](https://docs.flutter.dev/platform-integration/android/setup).
Install a compatible JDK and Android SDK command-line tools/platform-tools, the platform and
build-tools required by the generated pinned Flutter project, plus its NDK/CMake requirements.
Android Studio's SDK Manager is one option; [sdkmanager](https://developer.android.com/tools/sdkmanager)
is the CLI option. Inspect the generated Gradle project and `flutter doctor -v`; do not guess
SDK/NDK versions or install an emulator on a memory-limited laptop merely to build an APK.

```bash
flutter doctor --android-licenses
flutter doctor -v
bash tool/build_local.sh apk
```

Review Android licenses interactively. If Flutter cannot locate the SDK, use the real directory:
`flutter config --android-sdk /absolute/path/to/Android/Sdk`. If needed, select a compatible
installed JDK with `flutter config --jdk-dir /absolute/path/to/jdk` and rerun doctor.

The default local APK targets **Android arm64** and keeps Gradle workers at two with a 2 GB
heap (`ANAMNE_LOW_MEMORY=0` leaves existing Gradle settings alone). Output:
`build/app/outputs/flutter-apk/app-release.apk`.

For a phone with another ABI, verify its ABI first and use Flutter's corresponding
`--target-platform` option. For separate APKs for the supported ABIs:

```bash
flutter build apk --release --split-per-abi
```

The generated Flutter template can sign a release-mode APK with a development key. Inspect
its actual Gradle signing config; this is **not** a production store-signing setup. Preserve
existing application ID and signing keys. Never commit keys or their passwords. Installing
over an APK signed by a different key fails; export notes before any uninstall/identity change.

Connect and authorize a real device over USB, then:

```bash
adb devices
adb shell getprop ro.product.cpu.abi
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Use a trusted HTTPS API for device sync. `localhost` on the phone is the phone itself. The
release manifest includes INTERNET permission; it does not enable insecure cleartext traffic
for production. No phone connection is required merely to compile the APK.

## 6. Server and MCP verification

```bash
(cd server && npm test)
```

The fix environment recorded 19 passes under Node 24.19.0; rerun and record the laptop's actual
result. To test locally with synthetic notes, start the server in another terminal:

```bash
cd server
export ANAMNE_API_TOKEN="$(openssl rand -hex 32)"
export ANAMNE_DB_PATH=./data/local-qa.sqlite
export ANAMNE_CORS_ORIGINS="http://localhost:8080,http://127.0.0.1:8080"
node src/http.js
```

Keep the token private. Configure the app against `http://localhost:8787` for same-laptop web
QA. Launch `node server/src/mcp.js` using that **same absolute database path** in an MCP host
for app/MCP round-trip tests. Local stdio has process/database privileges; there is no remote
HTTP MCP listener in this version. Do not test destructive cases on a real personal workspace.

## 7. Acceptance and handoff

Test using synthetic content:

- Edit A and immediately open B: B shows B's text; A is saved under A's ID. Reopen both.
- Change a database cell/title and a canvas node; leave before the debounce. Reopen and confirm.
- Exercise an injected local save failure: unsaved/error state remains and retry succeeds.
- Type Bengali/English/emoji with actual IME, change selection, press Enter/Backspace and switch pages.
- Make two offline edits to the same page/database, reconnect and confirm both versions remain
  recoverable. Test API/MCP edits appearing in the app after pull without reopening the app.
- Retry a request after a lost response; verify no duplicate mutation. Reject stale revisions.
- Trash/restore/purge a parent with children; sync a second stale client and confirm no silent
  resurrection of canonical IDs. Any conflict copy has a new ID.
- Revoke/rotate a token, restart the test server, and confirm the old value stays denied.
- Serve web from an allowed origin; inspect preflight/auth failures from a disallowed origin.

Record command exit codes, commit, OS/architecture, SDK/Java/Node versions, QA gaps and artifact
hashes. Example checksums after successful relevant builds:

```bash
git rev-parse HEAD
flutter --version
node --version
sha256sum build/web/main.dart.js build/app/outputs/flutter-apk/app-release.apk build/appimage/Anamne-x86_64.AppImage
```

Only list files actually produced. On failures, retain relevant redacted logs and fix the cause;
do not suppress analyzer errors, delete regression tests or report an unrun test as passed.
