"""Regression for release networking and repeatable generated-project setup."""
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

from configure_platforms import configure


class PlatformConfigurationTest(unittest.TestCase):
    def test_repeat_preserves_custom_fields_and_adds_one_release_permission(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'web').mkdir()
            (root / 'web/manifest.json').write_text(json.dumps({
                'name': 'anamne', 'short_name': 'anamne', 'custom': 'preserve me'}))
            (root / 'web/index.html').write_text('<title>anamne</title>')
            native = root / 'android/app/src/main'
            native.mkdir(parents=True)
            manifest = native / 'AndroidManifest.xml'
            manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
                                '<application android:label="anamne"/></manifest>')
            gradle = root / 'android/gradle.properties'
            gradle.write_text('org.gradle.jvmargs=-Xmx8G\ncustom.setting=keep\n')
            with patch.dict(os.environ, {'ANAMNE_LOW_MEMORY': '1'}):
                configure(root)
                once = manifest.read_text()
                configure(root)
            self.assertEqual(manifest.read_text(), once)
            parsed = ET.fromstring(once)
            key = '{http://schemas.android.com/apk/res/android}name'
            self.assertEqual([p.get(key) for p in parsed.findall('uses-permission')],
                             ['android.permission.INTERNET'])
            web = json.loads((root / 'web/manifest.json').read_text())
            self.assertEqual(web['custom'], 'preserve me')
            self.assertEqual(web['name'], 'Anamne')
            self.assertIn('custom.setting=keep', gradle.read_text())
            self.assertIn('org.gradle.jvmargs=-Xmx2048m', gradle.read_text())
            self.assertEqual(gradle.read_text().count('org.gradle.workers.max='), 1)


if __name__ == '__main__':
    unittest.main()
