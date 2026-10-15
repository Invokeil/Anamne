# Linux desktop

## AppImage

Download the x86_64 AppImage from the project GitHub Release and mark it executable:

```bash
chmod +x Anamne-x86_64.AppImage
./Anamne-x86_64.AppImage
```

If the host has no FUSE support, try extraction mode:

```bash
APPIMAGE_EXTRACT_AND_RUN=1 ./Anamne-x86_64.AppImage
```

The artifact targets Linux x86_64. It was built and smoke-tested on elementary OS 8 (Ubuntu 24.04 base); compatibility with other distributions and older glibc versions is not guaranteed. The AppImage does not bundle every system library.

## Linux bundle

If using the separately distributed Linux bundle, preserve the complete directory structure and run `./anamne` from that directory. Do not copy only the executable; the bundle includes required libraries and Flutter assets.

## Data and sync

Back up/export workspace data before replacing installations or changing storage. Optional sync can be configured in Settings with an HTTPS API URL and a role-appropriate token. Treat tokens as passwords and do not place them in shell history or public logs.

## Troubleshooting

- `Permission denied`: run `chmod +x` on the AppImage.
- FUSE error: use `APPIMAGE_EXTRACT_AND_RUN=1` or install FUSE support appropriate to the distribution.
- Missing shared library: install the distribution's compatible runtime package; do not assume an AppImage includes every host dependency.
- Display/rendering issues: update the graphics stack and test on the intended distribution. A successful build on one Linux release does not establish universal compatibility.
