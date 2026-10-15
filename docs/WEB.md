# Web

The evaluated 0.2.1+3 artifacts were supplied by the owner; no GitHub Release assets have
been published at this review. See [the source/build review](reviews/2026-10-15-local-build.md).
The download instructions below apply when an artifact is provided or a release is published.

## Open the hosted build

Use the supplied Web directory/ZIP, a Web artifact attached to a published GitHub Release, or a configured hosting URL when available. For a downloaded web ZIP, extract the complete archive and serve its contents over HTTP(S). Do not open `index.html` as a `file://` URL.

For a local preview with Python 3:

```bash
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Then open <http://127.0.0.1:8080>. If serving an extracted release archive, use that extracted directory instead of `build/web`.

## Data and browser storage

The browser workspace is stored in that browser origin's local storage/IndexedDB. Changing the hostname, scheme, or port creates a different origin and can look like a blank workspace. Export a backup before clearing site data or changing origins. A web build is not a guarantee of complete offline reload support; keep a separate backup.

## Optional self-hosted sync

In Settings, configure the HTTPS API URL and token. Add the exact web origin (scheme, host and port) to the server's allowed CORS origins. For example, `http://127.0.0.1:8080` and `http://localhost:8080` are distinct origins. Production web pages should use HTTPS APIs; browsers can block insecure mixed-content requests.

## Troubleshooting

- Blank or missing assets: serve the full extracted directory, not just `index.html`.
- No workspace: check the exact origin and browser profile, then restore an export if needed.
- Sync/CORS failure: check the API URL, token, allowed origin, TLS certificate and server reachability.

