#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bundle=build/linux/x64/release/bundle
[[ $(uname -m) == x86_64 ]] || { echo 'This packager targets Linux x86_64 only' >&2; exit 1; }
test -x "$bundle/anamne" || { echo 'Run flutter build linux --release first' >&2; exit 1; }
appdir=build/appimage/Anamne.AppDir
rm -rf "$appdir"
mkdir -p "$appdir/usr/bin"
cp -a "$bundle/." "$appdir/usr/bin/"
cp assets/brand/anamne-icon-512.png "$appdir/anamne.png"
cat > "$appdir/anamne.desktop" <<'DESKTOP'
[Desktop Entry]
Name=Anamne
Comment=An open personal workspace
Exec=anamne
Icon=anamne
Type=Application
Categories=Office;Utility;
Terminal=false
DESKTOP
cat > "$appdir/AppRun" <<'APPRUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/usr/bin/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HERE/usr/bin/anamne" "$@"
APPRUN
chmod +x "$appdir/AppRun"
appimagetool=${APPIMAGETOOL:-appimagetool}
command -v "$appimagetool" >/dev/null || { echo 'Set APPIMAGETOOL to your appimagetool executable; see docs/LOCAL_BUILD.md' >&2; exit 1; }
ARCH=x86_64 "$appimagetool" "$appdir" build/appimage/Anamne-x86_64.AppImage
