"""Static release guards. These are not substitutes for device or server tests."""
from pathlib import Path
import csv, json, re, unittest
ROOT=Path(__file__).resolve().parents[1]
S=ROOT/'ios/Sources'

class ReleaseSafety061(unittest.TestCase):
    def test_pro_expiry_does_not_drop_queued_health_data(self):
        src=(S/'LocalQueue.swift').read_text('utf8')
        method=src.split('func restrictToFreeTier() throws {',1)[1].split('    }',1)[0]
        self.assertNotIn('removeAll',method)
        self.assertNotIn('pending =',method)
        self.assertIn('allowPremium: Bool',src)
        self.assertIn('&& (allowPremium || freeRow($0))',src)

    def test_uncertain_upload_will_inspect_remote_before_retry(self):
        src=(S/'SyncEngine.swift').read_text('utf8')
        api=(S/'GoogleSheets.swift').read_text('utf8')
        self.assertLess(src.index('sheets.alreadyOnSheet(inFlight'), src.index('queue.beginUpload(batch)'))
        self.assertIn('allowRetry: false',api)
        self.assertIn('needsRemoteReconciliation(for: sheetID)',src)
        self.assertIn('markRemoteReconciled(for: sheetID)',src)

    def test_large_import_cap_signals_error_not_silent_success(self):
        src=(S/'SyncEngine.swift').read_text('utf8')
        self.assertIn('var caughtUp = false',src)
        self.assertIn('if !caughtUp {',src)
        self.assertIn('Nagy HealthKit előzmény',src)

    def test_watch_completed_workout_has_queued_delivery_and_dedupe(self):
        watch=(ROOT/'watchOS/Sources/WatchWorkout.swift').read_text('utf8')
        phone=(S/'WatchBridge.swift').read_text('utf8')
        for term in ['transferUserInfo(payload)','flushCompletedWorkouts()', 'activationState == .activated','workoutID','pending.completed.v1']:
            self.assertIn(term,watch)
        for term in ['didReceiveUserInfo','UUID(uuidString: id)','received.contains(id)','case "completed"']:
            self.assertIn(term,phone)

    def test_iphone_and_watch_are_both_ci_blocking(self):
        spec=(ROOT/'project.watch.yml').read_text('utf8')
        ci=(ROOT/'.github/workflows/prepayment-macos-ci.yml').read_text('utf8')
        ipa_ci=(ROOT/'.github/workflows/macos-ipa.yml').read_text('utf8')
        self.assertIn('embed: true',spec)
        self.assertIn('project.watch.yml',ci)
        self.assertIn('ci_xcode_build.sh simulator',ci)
        self.assertIn('ci_xcode_build.sh watch',ci)
        self.assertIn('project.watch.yml',ipa_ci)
        self.assertNotIn('continue-on-error: true',ipa_ci)
        self.assertIn('WatchKit alkalmazás', (ROOT/'tools/verify_ipa.py').read_text('utf8'))

    def test_qa_status_all_not_run_without_evidence(self):
        data=json.loads((ROOT/'docs/QA_061/QA_STATUS.json').read_text('utf8'))
        self.assertEqual(len(data['tests']),15)
        for item in data['tests'].values():
            self.assertEqual(item['status'],'NOT_RUN')
            self.assertFalse(item['evidence'])

    def test_seven_day_log_has_fourteen_checkpoints(self):
        with (ROOT/'docs/QA_061/NAPI_SZINKRON_NAPLO.csv').open(encoding='utf-8-sig',newline='') as f:
            rows=list(csv.DictReader(f,delimiter=';'))
        self.assertEqual(len(rows),14)
        self.assertEqual(sorted(set(row['nap'] for row in rows)),list('1234567'))

    def test_no_private_keys_needed_for_test_runner(self):
        script=(ROOT/'tools/live_supabase_rls_test.py').read_text('utf8')
        self.assertIn('SUPABASE_PUBLISHABLE_KEY',script)
        self.assertNotIn('service_role',script.lower())
        self.assertIn('finally:',script)

if __name__=='__main__':unittest.main()
