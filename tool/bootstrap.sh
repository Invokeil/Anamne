#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

command -v flutter >/dev/null || { echo 'Flutter SDK is required: https://docs.flutter.dev/install' >&2; exit 1; }
flutter create --project-name anamne --org tech.invokeil --platforms=android,linux,web .
flutter pub get
dart run flutter_launcher_icons

cp assets/brand/anamne-icon-48.png web/favicon.png
cp assets/brand/anamne-icon-192.png web/icons/Icon-192.png
cp assets/brand/anamne-icon-512.png web/icons/Icon-512.png
cp assets/brand/anamne-icon-192.png web/icons/Icon-maskable-192.png
cp assets/brand/anamne-icon-512.png web/icons/Icon-maskable-512.png
python3 - <<'PY'
from pathlib import Path
manifest = Path('web/manifest.json')
if manifest.exists():
    manifest.write_text(manifest.read_text().replace('"name": "anamne"', '"name": "Anamne"').replace('"short_name": "anamne"', '"short_name": "Anamne"'))
index = Path('web/index.html')
if index.exists():
    index.write_text(index.read_text().replace('<title>anamne</title>', '<title>Anamne</title>'))
android = Path('android/app/src/main/AndroidManifest.xml')
if android.exists():
    android.write_text(android.read_text().replace('android:label="anamne"', 'android:label="Anamne"'))
PY
echo 'Anamne platform projects are ready.'
