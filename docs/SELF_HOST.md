# Self-hosted Anamne API

This guide runs the Node.js + SQLite API locally for evaluation. It is not a hardened production deployment recipe. Do not expose it publicly until you have reviewed TLS termination, firewalling, token management, backups, updates and monitoring.

## Requirements

- Node.js 24 or newer (the server uses Node's built-in SQLite module); npm is included with Node.
- A Linux host for the example service. Bun may be installed, but the repository's local build script currently invokes `node` and `npm test`.

## Run locally

From the repository root:

```bash
cd server
export ANAMNE_API_TOKEN="$(openssl rand -hex 32)"
export ANAMNE_DB_PATH="$PWD/data/anamne.sqlite"
export ANAMNE_CORS_ORIGINS="http://127.0.0.1:8080"
node src/http.js
```

Keep the generated token private. Keep the database on persistent storage and back it up using a consistent SQLite backup procedure. The API listens on its configured local port (8787 by default). Configure the client with the base URL such as `http://127.0.0.1:8787` and the token.

For web development, add the exact origin used by the browser to `ANAMNE_CORS_ORIGINS`. For a phone on the same LAN, bind/reverse-proxy the service on a reachable interface, use the host's LAN address rather than `localhost`, and configure the firewall and HTTPS before sending credentials. Never use a public network without authenticated TLS and appropriate access controls.

## MCP server

The MCP server is a separate local stdio process and accesses its configured SQLite database directly. Start it only in a trusted MCP host with the same absolute database path as the HTTP service if both interfaces must see the same data. A local stdio MCP process has process-level database access; it is not an HTTP role-protected or remote MCP transport.

## Operations

- Rotate/revoke tokens using the supported server configuration and token-store behavior; do not rely on environment-seeded credentials remaining revocable across restarts without checking the current implementation.
- Keep SQLite files and token material out of source control and public artifacts.
- Run tests locally with `(cd server && npm test)`.
- Monitor logs, apply OS/Node security updates, restrict network access, and test database restore procedures before production use.
