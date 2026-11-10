import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class IndependentGoogleSetupTests(unittest.TestCase):
    def test_google_sheet_setup_is_separate_from_healthkit(self):
        src = (ROOT / "ios/Sources/SyncEngine.swift").read_text(encoding="utf-8")
        setup = src.split("func prepareGoogleSheet() async {", 1)[1].split("private func ensureSheet", 1)[0]
        self.assertIn("ensureSheet(using: sheets)", setup)
        self.assertIn("flushQueue(using: sheets)", setup)
        self.assertNotIn("reader.authorize", setup)
        self.assertNotIn("fullHealthFlowCompleted", setup)

    def test_health_sync_returns_without_entitlement(self):
        src = (ROOT / "ios/Sources/SyncEngine.swift").read_text(encoding="utf-8")
        method = src.split("func sync() async {", 1)[1].split("private func flushQueue", 1)[0]
        self.assertIn("guard fullHealthFlowCompleted else", method)
        self.assertIn("return", method.split("guard fullHealthFlowCompleted else", 1)[1].split("}", 1)[0])

    def test_sheet_create_button_is_not_healthkit_gated(self):
        src = (ROOT / "ios/Sources/OraNaploApp.swift").read_text(encoding="utf-8")
        self.assertIn("await engine.prepareGoogleSheet()", src)
        self.assertIn("Google Sheets létrehozása", src)
        self.assertIn("await engine.sync()", src)
        self.assertNotIn(".disabled(engine.busy || !engine.account.loggedIn || !engine.fullHealthFlowCompleted)", src)

    def test_journal_immediate_upload(self):
        src = (ROOT / "ios/Sources/SyncEngine.swift").read_text(encoding="utf-8")
        journal = src.split("func addJournalEntry(", 1)[1].split("func prepareGoogleSheet() async", 1)[0]
        self.assertIn("await prepareGoogleSheet()", journal)

if __name__ == "__main__":
    unittest.main()
