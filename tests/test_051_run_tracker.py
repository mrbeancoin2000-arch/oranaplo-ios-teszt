"""Static integration gate for iPhone-specific APIs, plus the separate compiled Swift runtime gate."""
import pathlib, plistlib, re, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
SRC=ROOT/'ios'/'Sources'

class RunTrackerIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.loc=(SRC/'L10n.swift').read_text('utf8')
        cls.view=(SRC/'RunTrackerView.swift').read_text('utf8')
        cls.tracker=(SRC/'RunTracker.swift').read_text('utf8')
        cls.core=(SRC/'RunMathCore.swift').read_text('utf8')
        cls.sync=(SRC/'SyncEngine.swift').read_text('utf8')
        cls.sheets=(SRC/'GoogleSheets.swift').read_text('utf8')
        cls.models=(SRC/'Models.swift').read_text('utf8')
        with (ROOT/'ios/Resources/Info.plist').open('rb') as f:cls.plist=plistlib.load(f)

    def test_native_view_is_connected(self):
        root=(SRC/'OraNaploApp.swift').read_text('utf8')
        self.assertIn('RunTrackerView().tabItem',root)
        self.assertIn('showJournal = true',root)
        self.assertNotIn('journal.tabItem',root)
        self.assertEqual(root.count('.tabItem {'),5)

    def test_location_motion_permission_and_background_mode(self):
        for key in ['NSLocationWhenInUseUsageDescription','NSMotionUsageDescription']:
            self.assertGreater(len(self.plist[key]),30)
        self.assertIn('location',self.plist['UIBackgroundModes'])
        self.assertIn('fetch',self.plist['UIBackgroundModes'])

    def test_system_permission_localized_in_three_languages(self):
        for lang in ('hu','en','de'):
            path=ROOT/f'ios/Resources/{lang}.lproj/InfoPlist.strings'
            self.assertTrue(path.is_file())
            content=path.read_text('utf8')
            for key in ['NSLocationWhenInUseUsageDescription','NSMotionUsageDescription',
                        'NSHealthShareUsageDescription','NSHealthUpdateUsageDescription']:
                self.assertIn('"'+key+'"',content)

    def test_all_run_ui_translations_present(self):
        keys=set(re.findall(r't\("(run\.[a-zA-Z0-9_.]+|tab\.run)"\)',self.view))
        # Plus state-generated localization keys; track every label in 3 languages.
        keys.update(('run.phase.ready','run.phase.recording','run.phase.paused','run.phase.finished'))
        keys.update(('run.status.recording','run.status.paused','run.status.saved','run.status.restored',
            'run.status.saveError','run.status.locationOff','run.status.permissionDenied',
            'run.status.gpsUnavailable','run.status.noHeart','run.status.heartLoaded'))
        keys.update(('run.metric.time','run.metric.distance','run.metric.speed','run.metric.pace',
            'run.metric.steps','run.metric.calories','run.metric.hr','run.metric.splits'))
        # Only compare key presence in each dictionary's source-range.
        blocks={}
        for lang,start,end in [('hu','"hu": [','"en": ['),('en','"en": [','"de": ['),('de','"de": [',']\n    ]')]:
            text=self.loc.split(start,1)[1]
            if end in text: text=text.split(end,1)[0]
            blocks[lang]=set(re.findall(r'^\s*"([a-zA-Z0-9_.]+)"\s*:',text,re.M))
        for lang in ('hu','en','de'):
            missing=keys-blocks[lang]
            self.assertFalse(missing,f'Missing {lang}: {missing}')
        self.assertGreaterEqual(len(keys),35)

    def test_gps_and_pedometer_real_sensor_apis(self):
        for marker in ('startUpdatingLocation()','stopUpdatingLocation()','horizontalAccuracy <= 30',
                       'CMPedometer.isStepCountingAvailable()','startUpdates(from: date)',
                       'queryPedometerData(from:','manager.allowsBackgroundLocationUpdates = true'):
            self.assertIn(marker,self.tracker)

    def test_run_can_pause_resume_finish_and_resume_interrupted(self):
        for name in ('func pause()','func resume()','func finish()','func newRun()','func load()','func persist()'):
            self.assertIn(name,self.tracker)
        self.assertIn('snapshot.interrupted = true',self.tracker)
        self.assertIn('breakBefore:awaitingFixAfterPause',self.tracker)

    def test_no_fake_live_apple_watch_heart(self):
        self.assertIn('HealthReader.shared.heartSamples(from:',self.tracker)
        self.assertNotIn('HKWorkoutSession(',self.tracker)
        self.assertIn('run.heart.later',self.view)
        self.assertIn('RunPulsePoint',self.core)

    def test_distance_splits_and_pace_use_actual_gps(self):
        for marker in ('func splits(', '100.0','func pace(', 'func speed(',
                       'func wallDate(forActive','func activeTime(of','estimatedRunningKcal('):
            self.assertIn(marker,self.core)
        self.assertIn('MapPolyline(coordinates:tracker.routeSegments[index])',self.view)
        self.assertIn('if point.breakBefore && !segment.isEmpty',self.tracker)
        self.assertIn('activeSeconds',self.core)

    def test_exports_only_pro_and_no_raw_gps_upload(self):
        self.assertIn('func exportRecordedRun(_ run: RecordedRun)',self.sync)
        snip=self.sync.split('func exportRecordedRun(_ run: RecordedRun)',1)[1].split('func addJournalEntry',1)[0]
        self.assertIn('SubscriptionManager.shared.proActive',snip)
        self.assertIn('guard account.loggedIn',snip)
        self.assertIn('sheet: "Edzesek"',snip)
        self.assertIn('sheet: "100m"',snip)
        self.assertNotIn('p.latitude',snip)
        self.assertNotIn('p.longitude',snip)
        self.assertIn('func gpxURL(for run: RecordedRun)',self.tracker)

    def test_sheet_schema_migration(self):
        self.assertIn('lepes_100m_becsult',self.models)
        self.assertIn('kaloria_kcal_becsult',self.models)
        self.assertIn('func ensureRunSplitColumns(',self.sheets)
        self.assertIn("'100m'!O1:P1",self.sheets)

    def test_runner_included_in_swift_runtime_audit(self):
        audit=(ROOT/'tools/prepayment_audit.py').read_text('utf8')
        self.assertIn('RunMathCore.swift',audit)
        self.assertIn('runtime_run_main.swift',audit)
        self.assertTrue((ROOT/'tests/runtime_run_main.swift').is_file())

    def test_privacy_and_usage_notes(self):
        readme=(ROOT/'README_051_FUTAS.md').read_text('utf8')
        self.assertIn('GPS',readme)
        self.assertIn('HealthKit',readme)
        self.assertIn('Apple Developer',readme)
        self.assertIn('WatchConnectivity',readme)

if __name__=='__main__': unittest.main()
