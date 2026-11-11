"""Regression tests for the one-button Windows pipeline and generated running permissions."""
import contextlib
import importlib.util
import io
import json
import plistlib
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class OneButtonReleaseTests(unittest.TestCase):
    def test_setup_configuration_preserves_background_location_after_two_runs(self):
        spec=importlib.util.spec_from_file_location('oranaplo_configure_test',ROOT/'tools/configure.py')
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as d:
            dest=Path(d)
            (dest/'ios/Sources').mkdir(parents=True)
            (dest/'ios/Resources').mkdir(parents=True)
            shutil.copy2(ROOT/'ios/Resources/Info.plist',dest/'ios/Resources/Info.plist')
            public = plistlib.loads((ROOT/'ios/Resources/Info.plist').read_bytes())
            # Public Client ID only; no developer secrets are needed for a unit test.
            (dest/'google_oauth.json').write_text(json.dumps({
                'ios_client_id': public['GIDClientID'],
                'ios_bundle_id': 'hu.oranaplo.ios',
            }),encoding='utf-8')
            module.ROOT=dest
            module.CONFIG=dest/'google_oauth.json'
            src=plistlib.loads((dest/'ios/Resources/Info.plist').read_bytes())
            src['UIBackgroundModes']=['fetch','location','location','audio']
            (dest/'ios/Resources/Info.plist').write_bytes(plistlib.dumps(src))
            with contextlib.redirect_stdout(io.StringIO()):
                for _ in range(2):
                    self.assertEqual(module.main(),0)
            found=plistlib.loads((dest/'ios/Resources/Info.plist').read_bytes())
            self.assertEqual(found['UIBackgroundModes'],['fetch','location','audio'])
            self.assertEqual(found['NSLocationWhenInUseUsageDescription'],src['NSLocationWhenInUseUsageDescription'])
            self.assertEqual(found['NSMotionUsageDescription'],src['NSMotionUsageDescription'])

    def test_configuration_fixes_legacy_fetch_only_plist(self):
        spec=importlib.util.spec_from_file_location('legacy_configure_test',ROOT/'tools/configure.py')
        module=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as d:
            dest=Path(d)
            (dest/'ios/Sources').mkdir(parents=True)
            (dest/'ios/Resources').mkdir(parents=True)
            shutil.copy2(ROOT/'ios/Resources/Info.plist',dest/'ios/Resources/Info.plist')
            public = plistlib.loads((ROOT/'ios/Resources/Info.plist').read_bytes())
            # Public Client ID only; no developer secrets are needed for a unit test.
            (dest/'google_oauth.json').write_text(json.dumps({
                'ios_client_id': public['GIDClientID'],
                'ios_bundle_id': 'hu.oranaplo.ios',
            }),encoding='utf-8')
            module.ROOT=dest
            module.CONFIG=dest/'google_oauth.json'
            p=dest/'ios/Resources/Info.plist'
            info=plistlib.loads(p.read_bytes())
            info['UIBackgroundModes']=['fetch']
            p.write_bytes(plistlib.dumps(info))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(module.main(),0)
            current=plistlib.loads(p.read_bytes())
            self.assertEqual(current['UIBackgroundModes'],['fetch','location'])

    def test_one_button_calls_every_stage_in_order(self):
        bat=(ROOT/'00_MINDENT_INDIT.bat').read_text(encoding='utf8')
        steps=['01_WINDOWS_ELOKESZITES.bat','05_FIZETES_ELOTTI_TESZTEK.bat',
               '02_FELHOS_IPA_EPITES.bat','03_SIDELOADLY_MEGNYITAS.bat']
        positions=[bat.index(x) for x in steps]
        self.assertEqual(positions,sorted(positions))
        self.assertIn('if errorlevel 1 goto :failed',bat)
        self.assertIn('ORANAPLO_FROM_ALL=1',bat)
        self.assertIn('MINDENT_INDIT_',bat)
        for path in steps:
            self.assertTrue((ROOT/path).is_file())
            self.assertIn('if not defined ORANAPLO_FROM_ALL pause',(ROOT/path).read_text(encoding='utf8'))

    def test_cloud_upload_allowlist_has_real_test_dependencies(self):
        cloud=(ROOT/'tools/cloud_build.ps1').read_text(encoding='utf8')
        for marker in ["'.swift','.js','.mjs','.xml','.json','.storekit'", 
                       "Add-ByExtension 'website'", "Add-ByExtension 'scripts'",
                       r"Add-ByExtension 'ios\Resources' @('.strings'", 
                       "'release_manifest.json'"]:
            self.assertIn(marker,cloud)

    def test_cloud_does_not_reuse_previous_github_run(self):
        cloud=(ROOT/'tools/cloud_build.ps1').read_text(encoding='utf8')
        self.assertIn('rev-parse HEAD',cloud)
        self.assertIn('headSha,event,displayTitle',cloud)
        self.assertIn('tools/select_github_run.py --token $requestID --sha $expectedSHA',cloud)
        self.assertIn("$details.headSha -ne $expectedSHA",cloud)
        self.assertIn("$details.event -ne 'workflow_dispatch'",cloud)
        self.assertNotIn('@($json | ConvertFrom-Json)',cloud.split('# Each dispatch carries')[0])

    def test_one_mac_run_compiles_simulator_and_iphoneos(self):
        ci=(ROOT/'.github/workflows/macos-ipa.yml').read_text(encoding='utf8')
        for marker in ['tools/prepayment_audit.py','ci_xcode_build.sh simulator','ci_xcode_build.sh iphone',
                       'xcodebuild-simulator.log','ipa-verification.txt','prepayment-run.log']:
            self.assertIn(marker,ci)

    def test_ipa_verification_guards_background_mode(self):
        code=(ROOT/'tools/verify_ipa.py').read_text(encoding='utf8')
        self.assertIn('"fetch", "location"',code)
        self.assertIn('NSMotionUsageDescription',code)
        self.assertIn('NSLocationWhenInUseUsageDescription',code)

if __name__=='__main__': unittest.main()
