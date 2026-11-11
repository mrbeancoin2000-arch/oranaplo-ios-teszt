"""Regression for Xcode embedded-binary validation of the modern watch app.
Xcode 14+ single-target apps use WKApplication; the legacy WKWatchKitApp
marker causes 'WatchKit App doesn't contain any WatchKit Extensions'.
"""
import plistlib
import tempfile
import unittest
from pathlib import Path
from tools.check_build_inputs import validate

ROOT=Path(__file__).resolve().parents[1]

class WatchSingleTargetTests(unittest.TestCase):
    def test_watch_is_single_target(self):
        info=plistlib.loads((ROOT/'watchOS/Info.plist').read_bytes())
        self.assertIs(info.get('WKApplication'), True)
        self.assertIsNot(info.get('WKWatchKitApp'),True)
        self.assertEqual(info.get('WKCompanionAppBundleIdentifier'),'hu.oranaplo.ios')
        spec=(ROOT/'project.watch.yml').read_text(encoding='utf8')
        self.assertIn('  OraNaploWatch:\n    type: application\n    platform: watchOS', spec)
        self.assertIn('      - target: OraNaploWatch\n        embed: true',spec)
        self.assertNotIn('watchkit2-extension',spec)

    def test_legacy_watch_plist_fails_prebuild_validation(self):
        # Validate a minimal in-place temp copy of the already configured project,
        # without changing files in the original source tree.
        with tempfile.TemporaryDirectory() as d:
            target=Path(d)
            for name in ['ios/Resources/Info.plist','ios/Resources/OraNaplo.entitlements',
                         'project.yml','project.watch.yml','ios/Sources/AppConfig.swift',
                         'watchOS/Info.plist']:
                dest=target/name
                dest.parent.mkdir(parents=True,exist_ok=True)
                dest.write_bytes((ROOT/name).read_bytes())
            p=target/'watchOS/Info.plist'
            s=p.read_text('utf8').replace('<key>WKApplication</key><true/>',
                                           '<key>WKWatchKitApp</key><true/>')
            p.write_text(s,encoding='utf8')
            problems=validate(target)
            self.assertTrue(any('WKApplication' in x for x in problems),problems)
            self.assertTrue(any('WKWatchKitApp' in x for x in problems),problems)

if __name__=='__main__':
    unittest.main()
