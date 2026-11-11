import pathlib,plistlib,re,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
SRC=ROOT/'ios/Sources'
class RunningBusinessTests(unittest.TestCase):
    def text(self,name):return (SRC/name).read_text(encoding='utf-8')
    def test_real_watch_workout_session(self):
        watch=(ROOT/'watchOS/Sources/WatchWorkout.swift').read_text(encoding='utf-8')
        for token in ['HKWorkoutSession','HKLiveWorkoutBuilder','HKLiveWorkoutDataSource','requestAuthorization','heartRate','pause()','resume()','finishWorkout()','sendMessage']:
            self.assertIn(token,watch)
    def test_watch_variant_separate_from_untested_iphone(self):
        self.assertIn('OraNaploWatch:',(ROOT/'project.watch.yml').read_text(encoding='utf-8'))
        self.assertNotIn('OraNaploWatch:',(ROOT/'project.yml').read_text(encoding='utf-8'))
        self.assertTrue((ROOT/'watchOS/Info.plist').exists())
    def test_watch_ios_link(self):
        bridge=self.text('WatchBridge.swift')
        for value in ['WCSession','didReceiveMessage','watchBPM','requestPermissionAndStart','sessionDidDeactivate']:
            self.assertIn(value,bridge)
    def test_bg_gps_energy_and_permission(self):
        t=self.text('RunTracker.swift')
        for value in ['allowsBackgroundLocationUpdates = true','kCLLocationAccuracyNearestTenMeters','distanceFilter = 8','locationManagerDidPauseLocationUpdates','activeStart']:
            self.assertIn(value,t)
        info=plistlib.loads((ROOT/'ios/Resources/Info.plist').read_bytes())
        self.assertIn('location',info['UIBackgroundModes'])
    def test_dashboard_generates_charts_and_is_private(self):
        sheets=self.text('GoogleSheets.swift')
        for value in ['styleDashboard','addChart','Dashboard','Celok','Rekordok','USER_ENTERED','updateRunAchievements']:
            self.assertIn(value,sheets)
        self.assertNotIn('maps.googleapis.com',sheets)
    def test_running_goals_and_pr_core(self):
        t=self.text('RunInsightsCore.swift')
        for value in ['1_000, 5_000, 10_000, 21_097','breakBefore','newlyBroken','weeklyStreak']:
            self.assertIn(value,t)
    def test_share_requires_tap_and_is_local(self):
        card=self.text('RunShareCard.swift')
        self.assertIn('MKMapSnapshotter',card)
        self.assertIn('UIGraphicsImageRenderer',card)
        self.assertNotIn('URLSession',card)
        self.assertIn('ShareLink(item:shareCardURL)',self.text('RunTrackerView.swift'))
    def test_3_languages_have_business_keys(self):
        t=self.text('L10n.swift')
        for lang in ['hu','en','de']:
            match=re.search(r'^\s*"'+lang+r'": \[(.*?)(?=^\s*"(?:hu|en|de)": \[|^\s*\]\s*$)',t,re.S|re.M)
            self.assertIsNotNone(match)
            for key in ['run.goals.title','run.pr.title','run.watch.title','run.share.card.create']:
                self.assertIn('"'+key+'"',match.group(1))
    def test_ci_diagnostics_expose_swift_errors(self):
        t=(ROOT/'tools/ci_xcode_build.sh').read_text(encoding='utf-8')
        self.assertIn('grep -nE',t)
        self.assertIn('seconds elapsed',t)
        self.assertIn('xcodebuild -quiet',t)
        self.assertIn('xcodebuild-simulator.log',(ROOT/'.github/workflows/macos-ipa.yml').read_text(encoding='utf-8'))

class DurablePRandFormulaTests(unittest.TestCase):
    def test_google_achievements_use_entire_local_archive(self):
        sheets=(SRC/'GoogleSheets.swift').read_text(encoding='utf-8')
        engine=(SRC/'SyncEngine.swift').read_text(encoding='utf-8')
        self.assertIn('records: [RunPersonalRecord], goals: RunGoalSummary',sheets)
        self.assertIn('records:RunTracker.shared.personalRecords',engine)
        self.assertIn('goals:RunTracker.shared.weeklySummary',engine)
        self.assertIn('ARRAYFORMULA(VALUE(FILTER',sheets)
    def test_route_free_summary_is_not_rotated_with_map_cache(self):
        tracker=(SRC/'RunTracker.swift').read_text(encoding='utf-8')
        self.assertIn('record-archive.json',tracker)
        self.assertIn('run-summary.json',tracker)
        self.assertIn('Array(history.prefix(25))',tracker)
        self.assertIn('RunInsights.historicalGoals',tracker)

