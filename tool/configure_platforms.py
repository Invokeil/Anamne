#!/usr/bin/env python3
"""Apply tracked, repeatable settings to generated platform projects."""
import json
import os
from pathlib import Path
import re
import xml.etree.ElementTree as ET


def configure(root=Path('.')):
    manifest = root / 'web/manifest.json'
    if manifest.exists():
        value = json.loads(manifest.read_text())
        value.update(name='Anamne', short_name='Anamne')
        manifest.write_text(json.dumps(value, indent=2) + '\n')
    index = root / 'web/index.html'
    if index.exists():
        index.write_text(index.read_text().replace('<title>anamne</title>', '<title>Anamne</title>'))

    android = root / 'android/app/src/main/AndroidManifest.xml'
    if android.exists():
        text = android.read_text().replace('android:label="anamne"', 'android:label="Anamne"')
        parsed = ET.fromstring(text)
        key = '{http://schemas.android.com/apk/res/android}name'
        if not any(p.get(key) == 'android.permission.INTERNET' for p in parsed.findall('uses-permission')):
            # Release builds need network access too; debug-only permission is insufficient.
            text = text.replace('</manifest>', '    <uses-permission android:name="android.permission.INTERNET"/>\n</manifest>')
        android.write_text(text)

    gradle = root / 'android/gradle.properties'
    if gradle.exists() and os.environ.get('ANAMNE_LOW_MEMORY') == '1':
        text = gradle.read_text()
        for key, value in {
            'org.gradle.jvmargs': '-Xmx2048m -XX:MaxMetaspaceSize=512m -XX:+HeapDumpOnOutOfMemoryError',
            'org.gradle.workers.max': '2',
            'org.gradle.parallel': 'false',
        }.items():
            pattern = rf'(?m)^{re.escape(key)}=.*$'
            line = f'{key}={value}'
            text = re.sub(pattern, lambda _: line, text) if re.search(pattern, text) else text.rstrip() + '\n' + line + '\n'
        gradle.write_text(text)


if __name__ == '__main__':
    configure()
