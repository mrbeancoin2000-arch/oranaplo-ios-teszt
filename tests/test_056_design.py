import unittest,re,plistlib,json
from pathlib import Path
P=Path(__file__).resolve().parents[1]
def source(name):return (P/'ios/Sources'/name).read_text(encoding='utf-8')
class NewDesignChecks(unittest.TestCase):
    def test_five_tabs(self):
        text=source('OraNaploApp.swift')
        area=text.split('TabView(selection: $selectedTab) {',1)[1].split('}.tint(',1)[0]
        # Some formatters put a newline before .tint; compare tag sequence in first 650 chars
        titles=['TodayDashboardView()','AnalysisDashboardView()','RunTrackerView()','LeaderboardDashboardView()','profileHub.tabItem']
        positions=[area.find(title) for title in titles]
        self.assertTrue(all(p>=0 for p in positions),positions)
        self.assertEqual(positions,sorted(positions))
    def test_daily_is_real_healthkit(self):
        s=source('DailyHealthDashboard.swift')
        for value in ['.stepCount','.activeEnergyBurned','.distanceWalkingRunning','.appleExerciseTime','.sleepAnalysis','heartSamples']:
            self.assertIn(value,s)
        self.assertIn('nil means unavailable',s.lower())
    def test_sleep_algorithm(self):
        s=source('SleepAnalysisCore.swift')
        self.assertIn('max(lastEnd, interval.start)',s)
        self.assertIn('reliable.count >= 3',s)
        self.assertIn('baseline',s)
    def test_google_count_api_not_grid_allocation(self):
        s=source('GoogleSheets.swift')
        self.assertIn('countFilledRecords',s)
        self.assertIn('values:batchGet',s)
        self.assertIn('A2:A',s)
    def test_ranking_optin_and_no_raw_health_export(self):
        s=source('LeaderboardService.swift')
        self.assertIn('func publish(name:',s)
        self.assertIn('func revoke()',s)
        self.assertIn('leaderboard_config',s)
        self.assertNotIn('service_role',s)
        self.assertNotIn('rawHealth',s)
        sql=(P/'supabase/01_leaderboard.sql').read_text(encoding='utf-8')
        for pattern in ['enable row level security','auth.uid()','published=true','for delete to authenticated']:
            self.assertIn(pattern,sql)
        self.assertNotIn('service_role',sql)
    def test_config_is_placeholder_not_live(self):
        data=json.loads((P/'ios/Resources/leaderboard_config.json').read_text(encoding='utf-8'))
        self.assertIn('YOUR_',data['supabase_url'])
    def test_profile_and_run_sharing(self):
        s=source('OraNaploApp.swift')
        for name in ['profileHub','rankingName','rankings.publish','rankings.revoke','healthProfilePage','settings']:
            self.assertIn(name,s)
        self.assertIn('oranaplo.leaderboard.name',source('RunShareCard.swift'))
    def test_preview_map_current_location(self):
        s=source('RunTrackerView.swift')
        self.assertIn('UserAnnotation()',s)
        self.assertIn('requestMapPosition()',s)
    def test_localizations_all_keys(self):
        txt=source('NewScreenStrings.swift')
        # Parse key declarations within each language's dictionary by block boundaries.
        groups=[txt.split('"'+n+'": [',1)[1].split('\n        ],',1)[0] for n in ('hu','en','de')]
        keys=[set(re.findall(r'"([a-z][a-zA-Z.]+)"\s*:',g)) for g in groups]
        self.assertEqual(keys[0],keys[1]);self.assertEqual(keys[1],keys[2])
        self.assertGreaterEqual(len(keys[0]),70)
    def test_windows_push_includes_leaderboard(self):
        s=(P/'tools/cloud_build.ps1').read_text('utf-8')
        self.assertIn("Add-Approved 'ios\\Resources\\leaderboard_config.json'",s)
        self.assertIn("Add-ByExtension 'supabase'",s)
    def test_plist(self):
        with (P/'ios/Resources/Info.plist').open('rb') as f: data=plistlib.load(f)
        self.assertIn('location',data['UIBackgroundModes'])
        self.assertEqual(data['CFBundleShortVersionString'],'0.8.0')
