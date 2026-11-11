"""Offline IPA consistency tests, independent of customer OAuth settings."""
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = '1234567890-unittest.apps.googleusercontent.com' # Valid *shape*, synthetic test only
REVERSED = '.'.join(reversed(CLIENT.split('.')))


def fixture():
    return {
        'CFBundleIdentifier': 'hu.oranaplo.ios',
        'GIDClientID': CLIENT,
        'CFBundleURLTypes': [{'CFBundleURLSchemes': [REVERSED]}],
        'NSHealthShareUsageDescription': 'Teszt read permission',
        'NSHealthUpdateUsageDescription': 'Teszt update permission',
        'NSLocationWhenInUseUsageDescription': 'Testing location permission',
        'NSMotionUsageDescription': 'Testing pedometer permission',
        'UIBackgroundModes': ['fetch', 'location'],
    }


def run_verifier(info, directory):
    ipa = Path(directory) / 'test.ipa'
    with zipfile.ZipFile(ipa, 'w') as out:
        out.writestr('Payload/OraNaplo.app/Info.plist', plistlib.dumps(info))
    return subprocess.run([sys.executable, str(ROOT/'tools/verify_ipa.py'), str(ipa)], capture_output=True, text=True)


class IPAInfoTests(unittest.TestCase):
    def test_verifier_accepts_valid_synthetic_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = run_verifier(fixture(), tmp)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_verifier_rejects_missing_background_location(self):
        with tempfile.TemporaryDirectory() as tmp:
            broken = fixture()
            broken['UIBackgroundModes'] = ['fetch']
            result = run_verifier(broken, tmp)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('background mode: location', result.stdout)

    def test_verifier_reports_missing_google_callback(self):
        with tempfile.TemporaryDirectory() as tmp:
            broken = fixture()
            broken['CFBundleURLTypes'] = []
            result = run_verifier(broken, tmp)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('CFBundleURLSchemes', result.stdout)

    def test_verifier_rejects_missing_client_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            broken = fixture()
            broken['GIDClientID'] = ''
            result = run_verifier(broken, tmp)
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertIn('GIDClientID', result.stdout)

    def test_missing_oauth_fields_are_restored_in_unsigned_app(self):
        source = plistlib.loads((ROOT/'ios/Resources/Info.plist').read_bytes())
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp) / 'Info.plist'
            broken = dict(source)
            broken.pop('GIDClientID', None)
            broken.pop('CFBundleURLTypes', None)
            broken['CFBundleIdentifier'] = 'hu.oranaplo.ios'
            target.write_bytes(plistlib.dumps(broken))
            result = subprocess.run([sys.executable, str(ROOT/'tools/fix_built_plist.py'), str(target)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            repaired = plistlib.loads(target.read_bytes())
            self.assertEqual(repaired['GIDClientID'], source['GIDClientID'])
            self.assertEqual(repaired['CFBundleURLTypes'], source['CFBundleURLTypes'])
            self.assertEqual(repaired['CFBundleIdentifier'], 'hu.oranaplo.ios')

    def test_project_configuration_matches_google_json(self):
        import json
        data = json.loads((ROOT/'google_oauth.json').read_text(encoding='utf-8'))
        plist = plistlib.loads((ROOT/'ios/Resources/Info.plist').read_bytes())
        client = data['ios_client_id']
        self.assertEqual(plist['GIDClientID'], client)
        schemes = [s for t in plist['CFBundleURLTypes'] for s in t['CFBundleURLSchemes']]
        self.assertIn('.'.join(reversed(client.split('.'))), schemes)
        swift = (ROOT/'ios/Sources/AppConfig.swift').read_text(encoding='utf-8')
        self.assertIn(client, swift)
        self.assertIn(data['ios_bundle_id'], swift)

    def test_xcodegen_does_not_overwrite_plist_and_entitlements(self):
        # Previous failure: XcodeGen target `info.path` regenerated Info.plist
        # without the custom Google and HealthKit keys. The same happens to
        # entitlements when using `entitlements.path` without `properties`.
        spec = (ROOT/'project.yml').read_text(encoding='utf-8')
        self.assertIn('INFOPLIST_FILE: ios/Resources/Info.plist', spec)
        self.assertIn('CODE_SIGN_ENTITLEMENTS: ios/Resources/OraNaplo.entitlements', spec)
        import re
        self.assertNotRegex(spec, r'(?m)^\s+info:\s*$')
        self.assertNotRegex(spec, r'(?m)^\s+entitlements:\s*$')

    def test_preflight_healthkit_google_config(self):
        from importlib.util import spec_from_file_location, module_from_spec
        sp = spec_from_file_location('check_build_inputs', ROOT/'tools/check_build_inputs.py')
        m = module_from_spec(sp)
        sp.loader.exec_module(m)
        self.assertEqual(m.validate(ROOT), [])
        import plistlib
        ent = plistlib.loads((ROOT/'ios/Resources/OraNaplo.entitlements').read_bytes())
        self.assertIs(ent.get('com.apple.developer.healthkit'), True)


if __name__ == '__main__': unittest.main()
