"""Prevent a repeat of the actual Xcode OSLogType.notice compiler failure.

These source-contract tests run on Windows. macOS Xcode CI remains the
only authority for successful iOS/watchOS SDK compilation.
"""
from pathlib import Path
import re
import plistlib
import unittest

R = Path(__file__).resolve().parents[1]

class OSLogSDKCompatibilityTests(unittest.TestCase):
    def test_error_warning_info_map_to_supported_oslogtype_values(self):
        source = (R / "ios/Sources/DiagnosticCenter.swift").read_text(encoding="utf-8")
        self.assertNotRegex(source, r"\.notice\b")
        self.assertRegex(source, r"severity\s*==\s*\.failure\s*\?\s*\.error")
        self.assertRegex(source, r"severity\s*==\s*\.warning\s*\?\s*\.default\s*:\s*\.info")
        self.assertIn('import OSLog', source)

    def test_no_unsupported_oslog_notice_in_native_sources(self):
        for directory in (R / "ios/Sources", R / "watchOS/Sources"):
            for file in directory.rglob("*.swift"):
                with self.subTest(path=str(file.relative_to(R))):
                    source = file.read_text(encoding="utf-8")
                    self.assertNotRegex(source, r"(?:OSLogType\s*\.\s*notice|level:\s*\.notice\b)")

    def test_marketing_versions_match_ios_and_watch(self):
        ios = plistlib.loads((R / "ios/Resources/Info.plist").read_bytes())
        watch = plistlib.loads((R / "watchOS/Info.plist").read_bytes())
        self.assertEqual(ios["CFBundleShortVersionString"], "0.8.2")
        self.assertEqual(watch["CFBundleShortVersionString"], "0.8.2")
        self.assertEqual(ios["CFBundleVersion"], watch["CFBundleVersion"])

if __name__ == "__main__":
    unittest.main()
