"""CI regression test for Swift AppLanguage/ String comparison mistakes.

These comparisons can slip through syntax-only parsing but fail real Xcode builds.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]

class SwiftLanguageComparisonTests(unittest.TestCase):
    def test_app_language_is_raw_value_enum(self):
        source = (ROOT / "ios/Sources/L10n.swift").read_text(encoding="utf-8")
        self.assertIn("enum AppLanguage: String", source)
        for case in ("hu", "en", "de"):
            self.assertRegex(source, r"\bcase\s+hu,\s*en,\s*de\b")

    def test_app_language_compared_to_cases_not_strings(self):
        for relative in ("ios/Sources/RunTrackerView.swift", "ios/Sources/NewDashboardViews.swift"):
            with self.subTest(source=relative):
                code = (ROOT / relative).read_text(encoding="utf-8")
                self.assertNotRegex(code, r"\blanguage\s*==\s*[\"'](?:hu|en|de)[\"']")
                self.assertIn("language == .", code)

    def test_language_settings_remain_strings_for_storage(self):
        for relative in ("ios/Sources/RunTrackerView.swift", "ios/Sources/NewDashboardViews.swift"):
            with self.subTest(source=relative):
                code = (ROOT / relative).read_text(encoding="utf-8")
                self.assertIn('AppStorage("oranaplo.app.language")', code)
                self.assertIn('AppLanguage(rawValue:languageCode)', code.replace(' ',''))

if __name__ == "__main__":
    unittest.main()
