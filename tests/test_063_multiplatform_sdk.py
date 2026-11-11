"""Regression: a mixed iPhone+Watch Xcode scheme must NEVER be forced to iPhone SDK.
The mock checks the actual command the build helper would pass to xcodebuild.
"""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/ci_xcode_build.sh"

class MultiPlatformSDKTests(unittest.TestCase):
    def test_no_project_wide_sdk_override(self):
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn('-sdk "$SDK"', text)
        self.assertNotIn('SDKROOT=', text)
        self.assertIn('-destination "$DEST"', text)
        self.assertIn('CODE_SIGNING_ALLOWED=NO', text)

    @unittest.skipUnless(shutil.which("bash"), "bash unavailable on this computer")
    def test_actual_xcodebuild_argv_for_all_modes(self):
        expectations = {
            "simulator": ("OraNaplo", "generic/platform=iOS Simulator"),
            "iphone": ("OraNaplo", "generic/platform=iOS"),
            "watch": ("OraNaploWatch", "generic/platform=watchOS Simulator"),
        }
        for mode, (scheme, destination) in expectations.items():
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                tmp = Path(temp)
                fake = tmp / "xcodebuild"
                fake.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$ORANAPLO_TEST_XCODE_ARGS"\n', encoding="utf-8")
                fake.chmod(0o755)
                # The existing build helper polls every 20s. Speed up only the
                # test's PATH-isolated sleep, not the production script.
                fake_sleep = tmp / "sleep"
                fake_sleep.write_text("#!/bin/sh\n/bin/sleep 0.05\n", encoding="utf-8")
                fake_sleep.chmod(0o755)
                output = tmp / "actual_args.txt"
                env = os.environ.copy()
                env["PATH"] = str(tmp) + os.pathsep + env.get("PATH", "")
                env["ORANAPLO_TEST_XCODE_ARGS"] = str(output)
                result = subprocess.run(["bash", str(SCRIPT), mode], cwd=tmp, env=env,
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                args = output.read_text(encoding="utf-8").splitlines()
                self.assertNotIn("-sdk", args)
                self.assertEqual(args[args.index("-scheme") + 1], scheme)
                self.assertEqual(args[args.index("-destination") + 1], destination)
                self.assertIn("CODE_SIGNING_ALLOWED=NO", args)

    def test_workflow_never_claims_global_sdk_selection(self):
        workflow = (ROOT / ".github/workflows/macos-ipa.yml").read_text(encoding="utf-8")
        self.assertNotIn("-sdk iphonesimulator", workflow)
        self.assertNotIn("xcodebuild -sdk iphoneos", workflow)
        self.assertIn("ci_xcode_build.sh simulator", workflow)
        self.assertIn("ci_xcode_build.sh iphone", workflow)
        self.assertIn("ci_xcode_build.sh watch", workflow)

    def test_watch_sources_belong_to_watch_target(self):
        spec=(ROOT/"project.watch.yml").read_text(encoding="utf-8")
        targets=spec.split("targets:\n",1)[1].split("schemes:\n",1)[0]
        phone=targets.split("  OraNaploWatch:\n",1)[0]
        watch=targets.split("  OraNaploWatch:\n",1)[1]
        self.assertIn("path: ios/Sources",phone)
        self.assertNotIn("path: watchOS/Sources",phone)
        self.assertIn("path: watchOS/Sources",watch)
        self.assertIn("platform: watchOS",watch)

if __name__ == "__main__": unittest.main()
