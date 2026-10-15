# Deploying the Anamne sync server

The server is a zero-dependency Node.js 24 service storing one SQLite file. Two supported paths:

- **Podman (recommended)** — rootless container, works on any VPS with Podman 4+.
- **Bare systemd** — see `anamne.service` at the end of this file.

Local-only use never needs a server: the Flutter app edits offline and syncs when you configure one.

## 1. Build the image with Podman

From the repository root:

```bash
podman build -f deploy/Containerfile -t localhost/anamne-server:0.2.1 .
```

## 2. Run with podman-compose (or `podman compose`)

```bash
export ANAMNE_API_TOKEN="$(openssl rand -hex 32)"
# For a web client hosted on another origin:
export ANAMNE_CORS_ORIGINS="https://notes.example.com,http://localhost:8080"
# Optional team members (roles: admin | editor | viewer):
export ANAMNE_TOKENS="Rahim:editor:editor-token-at-least-24-chars;Boss:admin:another-admin-token-24-chars"
podman-compose -f deploy/compose.yaml up -d
```

This starts the API bound to `127.0.0.1:8787` with a named volume `anamne-data` holding `/data/anamne.sqlite`.

One-command alternative without compose:

```bash
podman run -d --name anamne-server \
  -v anamne-data:/data \
  -e ANAMNE_API_TOKEN="$(openssl rand -hex 32)" \
  -p 127.0.0.1:8787:8787 \
  localhost/anamne-server:0.2.1
```

Verify: `curl http://127.0.0.1:8787/health` → `{"status":"ok"}` (no token needed for this probe).

## 3. HTTPS

Keep the container bound to localhost and terminate TLS with Caddy, Nginx or your existing proxy.
`Caddyfile.example` shows a minimal Caddy site; uncomment the `caddy` service in `compose.yaml`
after adding a real Caddyfile with your domain.

```bash
sudo setcap 'cap_net_bind_service=+ep' $(which podman)   # optional: allow rootless <1024 ports
```

## 4. Systemd with Quadlet (auto-start on boot, rootless)

Save as `~/.config/containers/systemd/anamne.container`:

```ini
[Unit]
Description=Anamne sync server
After=network-online.target

[Container]
Image=localhost/anamne-server:0.2.1
ContainerName=anamne-server
PublishPort=127.0.0.1:8787:8787
Volume=anamne-data:/data
Environment=ANAMNE_API_TOKEN=<paste-a-strong-token>
# Environment=ANAMNE_TOKENS=Rahim:editor:editor-token-at-least-24-chars

[Service]
Restart=always

[Install]
WantedBy=default.target
```

Then: `systemctl --user daemon-reload && systemctl --user start anamne.service`.
Enable lingering so it survives logout: `sudo loginctl enable-linger $USER`.

## 5. Point the app at your server

In Anamne: **Settings → Self-hosted sync**, enter `https://your-domain` and a token with the
`admin` or `editor` role, then **Test** and **Save & sync**. The app keeps editing offline and
pushes/pulls automatically every 15 seconds; the status chip in the top bar shows the truth.

## 6. Backups

- The whole state is one SQLite file inside the volume: stop the service (or use SQLite's online
  backup API) and copy it.
  ```bash
  podman exec anamne-server node -e \
    "console.log(process.env.ANAMNE_DB_PATH)"
  podman volume export anamne-data --output anamne-backup.tar
  ```
- Keep backups and tokens off the public web; the app's **Settings → Copy full workspace JSON**
  is an additional portable escape hatch.

## 7. MCP

Run `node server/src/mcp.js` on the VPS (same `ANAMNE_DB_PATH`) over SSH stdio, with the same
database the REST API uses. See the repository README for the tool list.

## Roles

| Role | Reads | Writes | Manage tokens |
|---|---|---|---|
| admin | ✔ | ✔ | ✔ |
| editor | ✔ | ✔ | ✘ |
| viewer | ✔ | ✘ | ✘ |

The env token (`ANAMNE_API_TOKEN`) seeds an admin. Tokens are stored as SHA-256 hashes;
mint additional ones with `POST /v1/tokens` (admin) and revoke with
`DELETE /v1/tokens/{id}`. Revocation survives restart, including an env-seeded token.
Change the env value to a fresh strong token to regain access after revoking it.
Env seed names (including `primary`) are reserved; use distinct names for manually minted
tokens. A changed named env seed removes its previous token. Removing an extra seed from
the environment does not revoke it: explicitly revoke that token through the API.

## Browser origins and upgrade limits

Set `ANAMNE_CORS_ORIGINS` to exact trusted web origins (scheme, hostname, optional port;
comma-separated, no trailing slash). Native clients do not send browser Origin headers.
Allowed browser preflights return 204 without a token; actual API calls still require one.
Use HTTPS for both deployed web client and API. Changing this value requires a service restart.

This source fix was not run under Podman here. Back up the SQLite database before upgrading;
stop the service before a raw-file/volume export and include WAL state, or use an online SQLite
backup. The earlier 0.2.0 implementation recorded neither all descendant purge events nor durable
revocations. Already-lost deletion/revocation history cannot be reconstructed by this upgrade;
revoke known old credentials again and use a fresh local workspace after a verified backup if
an older device contains orphaned pages. Never delete real notes as an upgrade shortcut.

All token roles currently share one workspace. The local stdio MCP process inherits OS access
to its database; it is not protected by HTTP token roles. No remote HTTP MCP listener is supplied.
