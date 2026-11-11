import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class PremiumInterfaceTests(unittest.TestCase):
    def test_focused_native_tabs(self):
        code = (ROOT / 'ios/Sources/OraNaploApp.swift').read_text(encoding='utf-8')
        for label in ('tab.home', 'tab.metrics', 'tab.journal', 'tab.settings'):
            self.assertIn(label, code)
        self.assertIn('TabView(selection:', code)
        self.assertIn('MetalSurface', code)

    def test_sheet_open_is_a_real_action(self):
        code = (ROOT / 'ios/Sources/OraNaploApp.swift').read_text(encoding='utf-8')
        self.assertIn('if let url = engine.sheetURL', code)
        self.assertIn('Button { openURL(url) }', code)
        self.assertIn('t("sheet.open")', code)
        self.assertIn('await engine.prepareGoogleSheet()', code)

    def test_sheet_link_matches_active_account(self):
        src = (ROOT / 'ios/Sources/SyncEngine.swift').read_text(encoding='utf-8')
        self.assertIn('enum SpreadsheetRegistry', src)
        self.assertIn('SpreadsheetRegistry.sheetID(for: account.email) == sheetID', src)
        self.assertIn('SpreadsheetRegistry.setSheetID(id, for: account.email)', src)
        self.assertIn('sheetID = ""', src)

    def test_offline_queue_is_separate_for_each_account(self):
        src = (ROOT / 'ios/Sources/LocalQueue.swift').read_text(encoding='utf-8')
        self.assertIn('func selectAccount(_ email:', src)
        self.assertIn('SHA256.hash', src)
        self.assertIn('account-\\(accountIdentifier)', src)
        self.assertIn('pendingFile', src)

    def test_recovery_requires_authorized_google_account(self):
        src = (ROOT / 'ios/Sources/SyncEngine.swift').read_text(encoding='utf-8')
        google = (ROOT / 'ios/Sources/GoogleSheets.swift').read_text(encoding='utf-8')
        self.assertIn('recoverCurrentSheetIfNeeded()', src)
        self.assertIn('account.loggedIn, sheetID.isEmpty', src)
        self.assertIn('findExistingSpreadsheet()', google)
        self.assertIn('https://www.googleapis.com/drive/v3/files', google)


if __name__ == '__main__':
    unittest.main()
