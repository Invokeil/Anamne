# Anamne 0.2.1 Beta 1 — downloads and CLI guide

Release: [v0.2.1-beta.1](https://github.com/Invokeil/Anamne/releases/tag/v0.2.1-beta.1).
App metadata remains **0.2.1+3**. This is a prerelease for personal evaluation.

## Download selection

| Asset | Use |
|---|---|
| `Anamne-0.2.1-beta.1-android-arm64.apk` | Android arm64 phone/tablet; Android 7/API 24+ |
| `Anamne-0.2.1-beta.1-linux-x86_64.AppImage` | Linux x86_64 desktop |
| `Anamne-0.2.1-beta.1-selfhost-source.tar.gz` / `.zip` | Node.js sync/API/MCP server and deployment source; no Flutter SDK needed |
| `Anamne-0.2.1-beta.1-client-source.zip` | Clean source snapshot supplied with the app binaries, including the five local fixes |
| `Anamne-0.2.1-beta.1-web.zip` | Prebuilt web client; extract and serve over HTTP(S) |
| `INSTALL.md` | This CLI guide, also available directly as a release asset |
| `SHA256SUMS.txt` | SHA-256 checksums for the uploaded assets |

Use the pinned beta tag in commands. GitHub's `/releases/latest` endpoint is for stable releases
and is not the download selector for this beta. Windows/macOS apps are upcoming.

## Linux AppImage

```bash
mkdir -p anamne-beta && cd anamne-beta
curl -fLO https://github.com/Invokeil/Anamne/releases/download/v0.2.1-beta.1/Anamne-0.2.1-beta.1-linux-x86_64.AppImage
curl -fLO https://github.com/Invokeil/Anamne/releases/download/v0.2.1-beta.1/SHA256SUMS.txt
grep '  Anamne-0.2.1-beta.1-linux-x86_64.AppImage$' SHA256SUMS.txt | sha256sum -c -
chmod +x Anamne-0.2.1-beta.1-linux-x86_64.AppImage
./Anamne-0.2.1-beta.1-linux-x86_64.AppImage
```

If FUSE is unavailable, use:

```bash
APPIMAGE_EXTRACT_AND_RUN=1 ./Anamne-0.2.1-beta.1-linux-x86_64.AppImage
```

The local builder reports an elementary OS 8 smoke test. The AppImage payload and dependencies
were inspected separately; compatibility with every Linux distribution is not established.
See [LINUX.md](LINUX.md) for runtime requirements. Build Linux clients on a filesystem supporting
symlinks, such as ext4; the original exFAT checkout could not host Flutter plugin symlinks.

## Android APK

Download on the phone from the release page, or use an already-configured Android platform-tools
installation on the laptop:

```bash
curl -fLO https://github.com/Invokeil/Anamne/releases/download/v0.2.1-beta.1/Anamne-0.2.1-beta.1-android-arm64.apk
adb devices
adb shell getprop ro.product.cpu.abi
adb install -r Anamne-0.2.1-beta.1-android-arm64.apk
```

The complete app payload is arm64. The package name is `tech.invokeil.anamne`; it targets SDK 36.
This release-mode APK uses an **Android Debug development signing key**. Back up/export notes
before changing signing identity or uninstalling. A different signing key can prevent in-place
updates. Real-device install, Bengali IME and lifecycle QA remain open.

## Self-host the sync/API server

Requires **Node.js 24+**, with npm for the optional tests, and `curl`/`tar`. Obtain Node from its
[official downloads](https://nodejs.org/en/download) or an existing trusted version manager.
The server has zero external runtime npm dependencies. No Flutter, Docker or local AI model is
required to run it.

```bash
node --version
curl -fLO https://github.com/Invokeil/Anamne/releases/download/v0.2.1-beta.1/Anamne-0.2.1-beta.1-selfhost-source.tar.gz
tar -xzf Anamne-0.2.1-beta.1-selfhost-source.tar.gz
cd Anamne-selfhost-0.2.1-beta.1
node tool/setup_selfhost.mjs
node --env-file=.env server/src/http.js
```

Setup creates a random admin token in `.env` with mode 0600, uses an absolute SQLite path and
preserves an existing `.env`. Run the server command again after a restart to reuse the same
configuration. From another terminal:

```bash
curl -fsS http://127.0.0.1:8787/health
# Optional, from the package root; npm ships with normal Node.js installations:
(cd server && npm test)
```

Open `.env` locally to obtain the token for Anamne settings. Native clients use the server URL
and token. For a separate web origin, edit `ANAMNE_CORS_ORIGINS` to exact trusted origins, for
example `https://notes.example.com,http://localhost:8080`, then restart the server. A phone's
`localhost` is the phone itself; use a reachable HTTPS server hostname for device sync.

The default listener is localhost. For a VPS, put it behind an HTTPS reverse proxy and use the
provided systemd/Caddy or container examples under `deploy/`. Set the real paths/user in the
examples. No VPS is provisioned by these commands. Keep `.env` and the SQLite data private and
back up the database consistently before upgrades. Roles currently share one workspace.

## MCP

Launch local stdio MCP against the same database/environment:

```bash
node --env-file=.env server/src/mcp.js
```

Example MCP-host configuration; replace both paths with this package's actual absolute paths:

```json
{
  "mcpServers": {
    "anamne": {
      "command": "node",
      "args": [
        "--env-file=/absolute/path/Anamne-selfhost-0.2.1-beta.1/.env",
        "/absolute/path/Anamne-selfhost-0.2.1-beta.1/server/src/mcp.js"
      ]
    }
  }
}
```

For a trusted VPS process, an MCP host can use SSH stdio:

```bash
ssh user@your-server 'cd /opt/anamne && node --env-file=.env server/src/mcp.js'
```

The 14 tools cover the implemented page/database/search/export/sync subset. Stdio inherits
OS/database access; it is not an HTTP-token-protected listener. Remote authenticated HTTP MCP
and measured 99% operation coverage remain roadmap work.

## Web client

```bash
curl -fLO https://github.com/Invokeil/Anamne/releases/download/v0.2.1-beta.1/Anamne-0.2.1-beta.1-web.zip
python3 -m zipfile -e Anamne-0.2.1-beta.1-web.zip anamne-web
python3 -m http.server 8080 --bind 127.0.0.1 --directory anamne-web
```

Open `http://localhost:8080`. Use the full extracted directory; `file://` loading is unsupported.
Browser data is tied to its exact origin. Durable offline web reload is an open roadmap gate.

## Build from source and provenance

For the consolidated repository/tag source:

```bash
git clone --branch v0.2.1-beta.1 --depth 1 https://github.com/Invokeil/Anamne.git
cd Anamne
# Install pinned Flutter 3.47.7, Node 24+, Python 3 and target prerequisites first.
bash tool/build_local.sh web
bash tool/build_local.sh apk
# AppImage also needs appimagetool; see docs/LOCAL_BUILD.md.
```

The APK/AppImage/web assets are the inspected local evaluation builds supplied by the owner,
built from `4a4733d` plus the five local fixes. They were not rebuilt from the release tag.
The custom client-source ZIP preserves that supplied source snapshot; GitHub's automatic
source archives contain the consolidated tag, including later branch/docs changes. The
self-host source package uses the reviewed server/deployment bytes from commit `1624423` and
the release's env-setup helper. See each package's `RELEASE-PROVENANCE.md`.

Independent checks passed: 19 server tests, platform configuration fixture, APK v2 signature,
package/version and arm64 alignment, web metadata/checksum and exact AppImage payload matching.
The local builder reported 22 Flutter tests and clean analysis; those Flutter commands were
not independently rerun. See [the review](reviews/2026-10-15-local-build.md) for remaining QA.

Powered by ©Invokeil Tech · MIT license.
