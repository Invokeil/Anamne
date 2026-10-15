#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

target=${1:-web}
case "$target" in
  check|web|linux|apk|appimage|all) ;;
  *) echo 'Usage: bash tool/build_local.sh [check|web|linux|apk|appimage|all]' >&2; exit 2 ;;
esac
for tool in git node npm flutter dart python3; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool (see docs/LOCAL_BUILD.md)" >&2; exit 1; }
done
node -e 'if (Number(process.versions.node.split(".")[0]) < 24) { console.error("Node.js 24+ required"); process.exit(1); }'
version_file=$(mktemp)
trap 'rm -f "$version_file"' EXIT
flutter --version --machine > "$version_file"
python3 - "$version_file" <<'PY'
import json
from pathlib import Path
import sys
expected = Path('.flutter-version').read_text().strip()
actual = json.loads(Path(sys.argv[1]).read_text())['frameworkVersion']
if actual != expected:
    raise SystemExit(f'Use Flutter {expected} for this checkout (found {actual}); see docs/LOCAL_BUILD.md')
PY

# Lower Gradle concurrency for an 8 GB laptop; opt out with ANAMNE_LOW_MEMORY=0.
export ANAMNE_LOW_MEMORY=${ANAMNE_LOW_MEMORY:-1}
if [[ "$target" == linux || "$target" == appimage || "$target" == all ]]; then
  [[ $(uname -s) == Linux ]] || { echo 'Linux/AppImage builds require a Linux host' >&2; exit 1; }
  flutter config --enable-linux-desktop
fi
bash tool/bootstrap.sh
(cd server && npm test)
flutter analyze
flutter test --concurrency=1

build_target() {
  case "$1" in
    check) ;;
    web)
      flutter build web --release
      python3 - <<'PY'
import json
from pathlib import Path
import re
expected = re.search(r'^version:\s*(\S+)', Path('pubspec.yaml').read_text(), re.M).group(1)
version, build = expected.split('+')
actual = json.loads(Path('build/web/version.json').read_text())
if actual.get('version') != version or str(actual.get('build_number')) != build:
    raise SystemExit(f'Stale web build metadata: {actual}; expected {expected}')
print(f'Web artifact version verified: {expected}')
PY
      ;;
    linux) flutter build linux --release ;;
    apk) flutter build apk --release --target-platform android-arm64 ;;
    appimage)
      flutter build linux --release
      bash tool/package_appimage.sh
      ;;
  esac
}

if [[ "$target" == all ]]; then
  for item in web apk appimage; do build_target "$item"; done
else
  build_target "$target"
fi
echo "Local checks/build completed: $target"
