#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

command -v flutter >/dev/null || { echo 'Flutter SDK is required: https://docs.flutter.dev/install' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'Python 3 is required for platform configuration' >&2; exit 1; }
# Never regenerate an existing platform project or replace its custom settings.
platforms=()
for platform in android linux web; do
  if [[ ! -d "$platform" ]]; then platforms+=("$platform"); fi
done
if ((${#platforms[@]})); then
  platform_list=$(IFS=,; echo "${platforms[*]}")
  flutter create --no-pub --project-name anamne --org tech.invokeil --platforms="$platform_list" .
fi
flutter pub get
dart run flutter_launcher_icons

cp assets/brand/anamne-icon-48.png web/favicon.png
cp assets/brand/anamne-icon-192.png web/icons/Icon-192.png
cp assets/brand/anamne-icon-512.png web/icons/Icon-512.png
cp assets/brand/anamne-icon-192.png web/icons/Icon-maskable-192.png
cp assets/brand/anamne-icon-512.png web/icons/Icon-maskable-512.png
python3 tool/configure_platforms.py
echo 'Anamne platform projects are ready.'
