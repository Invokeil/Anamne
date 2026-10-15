# VPS deployment (single-user alpha)

1. Install Node.js 24+, Caddy and a current Linux distribution. Create an unprivileged `anamne` system user.
2. Check out the repository at `/opt/anamne`, make it readable by that user, and copy `anamne.service` to `/etc/systemd/system/`.
3. Create `/etc/anamne/anamne.env` owned by root with mode `0600`. Set `ANAMNE_API_TOKEN=` to a random 32-byte hex token (`openssl rand -hex 32`). Never commit this file.
4. Make sure `/usr/bin/node` points to Node 24+. If your Node binary is elsewhere, adjust `ExecStart` in the unit.
5. Copy `Caddyfile.example` to the Caddy config, replace its domain and enable TLS. The Node service stays bound to localhost.
6. Run `sudo systemctl daemon-reload`, `sudo systemctl enable --now anamne`, and check `sudo systemctl status anamne`.
7. Back up `/var/lib/anamne/anamne.sqlite` using SQLite's online backup API or stop the service before copying the file. Keep backups and API tokens off the public web.

This service is currently one trusted workspace, one token and no device sync. Public multi-user signup must wait for account isolation, scoped credentials, rate limits and audit logs.
