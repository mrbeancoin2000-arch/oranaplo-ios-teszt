import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "ios" / "Sources"

class BusinessAndReliabilityTests(unittest.TestCase):
    def test_storekit_uses_verified_entitlements_not_local_toggle(self):
        src = (SRC / "SubscriptionManager.swift").read_text(encoding="utf-8")
        for token in ("import StoreKit", "Transaction.currentEntitlements", "case .verified", "transaction.revocationDate == nil", "product.purchase(options: options)", "AppStore.sync()"): 
            self.assertIn(token, src)
        self.assertNotIn("UserDefaults.standard.bool(forKey: \"isPremium\")", src)

    def test_free_tier_uploads_heart_rate_only(self):
        src = (SRC / "SyncEngine.swift").read_text(encoding="utf-8")
        catalog = (SRC / "Models.swift").read_text(encoding="utf-8")
        queue = (SRC / "LocalQueue.swift").read_text(encoding="utf-8")
        self.assertIn('freeSampleIdentifier = "HKQuantityTypeIdentifierHeartRate"', catalog)
        self.assertIn('metric.id == Catalog.freeSampleIdentifier', src)
        self.assertIn('restrictToFreeTier()', src)
        self.assertIn('row.sheet == "Pulzus"', queue)
        self.assertIn('nextBatch(limit: 150, allowPremium: SubscriptionManager.shared.proActive)', src)
        self.assertNotIn('pending.removeAll { row in', queue)
        self.assertIn('fullData && enabledGroups.contains("edzes")', src)

    def test_import_anchor_scoped_by_account_and_range(self):
        src = (SRC / "SyncEngine.swift").read_text(encoding="utf-8")
        self.assertIn('let identity = account.email.lowercased()', src)
        self.assertIn(r'anchor.v3.\(identity).\(selectedDays).\(metric.id)', src)

    def test_latest_workout_notices_and_100m(self):
        overview = (SRC / "HealthOverview.swift").read_text(encoding="utf-8")
        workout = (SRC / "WorkoutExport.swift").read_text(encoding="utf-8")
        for value in ("latestWorkout()", "HighHeartRateEvent", "LowHeartRateEvent", "IrregularHeartRhythmEvent", "stepCount", "split100m"):
            self.assertIn(value, overview)
        self.assertIn('SplitMath.calculate', workout)
        self.assertIn('segmentDistance = 0', (SRC / 'SplitMath.swift').read_text(encoding='utf-8'))

    def test_complete_translations_no_missing_keys(self):
        loc = (SRC / "L10n.swift").read_text(encoding="utf-8")
        view = (SRC / "OraNaploApp.swift").read_text(encoding="utf-8")
        import ast
        # Separate language dictionary blocks and check exactly equal key sets.
        blocks = {}
        for language in ('hu','en','de'):
            m = re.search(r'"'+language+r'": \[([\s\S]*?)\n        \],', loc)
            self.assertIsNotNone(m, language)
            blocks[language] = set(re.findall(r'^\s+"([\w.]+)":',m.group(1),re.M))
        self.assertEqual(blocks['hu'],blocks['en'])
        self.assertEqual(blocks['hu'],blocks['de'])
        keys=set(re.findall(r'\bt\("([\w.]+)"\)',view))
        self.assertTrue(keys.issubset(blocks['hu']), keys-blocks['hu'])
        for label in ('tab.home','tab.metrics','tab.journal','tab.settings','tier.buy','tier.restore','onboard.health','onboard.google','onboard.sheets'):
            self.assertIn(label,blocks['de'])

    def test_localized_health_privacy_prompts(self):
        for lang in ('hu','en','de'):
            f=ROOT/'ios'/'Resources'/f'{lang}.lproj'/'InfoPlist.strings'
            self.assertTrue(f.exists())
            self.assertIn('NSHealthShareUsageDescription',f.read_text(encoding="utf-8"))

if __name__ == '__main__': unittest.main()
