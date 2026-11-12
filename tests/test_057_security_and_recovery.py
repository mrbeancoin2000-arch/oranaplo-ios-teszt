import json, plistlib, re, unittest
from pathlib import Path
P=Path(__file__).resolve().parents[1]
S=P/'ios'/'Sources'
def swift(name):return (S/name).read_text(encoding='utf-8')
class ReleaseStabilityTests(unittest.TestCase):
    def test_current_version(self):
        plist=plistlib.loads((P/'ios/Resources/Info.plist').read_bytes())
        self.assertEqual(plist['CFBundleShortVersionString'],'0.7.0')
        self.assertIn('location',plist['UIBackgroundModes'])

    def test_actual_sync_status_is_per_google_account(self):
        src=swift('SyncEngine.swift')
        for marker in ['syncDate.\\(identity)','syncLast.\\(identity)','syncError.\\(identity)',
                       'syncAttempt.\\(identity)','lastAttemptDate','lastFailureKind','syncProgress',
                       'func markFailure(','func markSuccess(','pendingCount = await queue.count()']:
            self.assertIn(marker,src)
        self.assertIn('sync.lastSuccess',swift('OpsText.swift'))
        self.assertIn('engine.lastSuccessfulDate',swift('NewDashboardViews.swift'))
        self.assertIn('engine.lastFailureKind',swift('NewDashboardViews.swift'))

    def test_run_checkpoint_and_interrupted_recovery(self):
        src=swift('RunTracker.swift');ui=swift('RunTrackerView.swift')
        for marker in ['runs.backup.json','storageDamaged','snapshot.interrupted = true',
                       'hasInterruptedWorkout','func discardInterruptedWorkout()',
                       'func eraseAllLocalRuns() throws','storageDamaged else { return }']:
            self.assertIn(marker,src)
        for marker in ['recoveryCard','run.recover.resume','run.recover.discard','run.recover.keep']:
            self.assertIn(marker,ui)
        self.assertIn('if tracker.hasInterruptedWorkout { recoveryCard }',ui)

    def test_explicit_local_data_removal_never_requests_remote_delete(self):
        src=swift('SyncEngine.swift');queue=swift('LocalQueue.swift')
        block=src.split('func eraseLocalHistory() async throws',1)[1].split('func setDays',1)[0]
        self.assertIn('queue.eraseSelectedAccount()',block)
        self.assertIn('RunTracker.shared.eraseAllLocalRuns()',block)
        self.assertIn('UserDefaults.standard.removeObject',block)
        self.assertNotIn('SheetsAPI(',block)
        self.assertNotIn('deleteSpreadsheet',block)
        self.assertIn('FileManager.default.removeItem(at:dir)',queue)
        self.assertIn('showEraseLocalConfirmation',swift('OraNaploApp.swift'))
        self.assertIn('showEraseRankingConfirmation',swift('OraNaploApp.swift'))

    def test_local_queue_can_run_after_first_unlock(self):
        src=swift('LocalQueue.swift')
        self.assertNotIn('.completeFileProtectionUnlessOpen',src)
        self.assertIn('.completeFileProtectionUntilFirstUserAuthentication',src)

    def test_report_contains_no_raw_health_or_route_fields(self):
        payload=swift('SafeSupportPayload.swift')
        self.assertIn('enum Category: String',payload)
        self.assertIn('let reason_code: String',payload)
        for denied in ['latitude:', 'longitude:', 'heartRate:', 'googleToken:', 'email:', 'diagnosticLog:']:
            self.assertNotIn(denied,payload)
        src=swift('LeaderboardService.swift')
        self.assertIn('func submitBugReport(',src)
        self.assertIn('/functions/v1/bug-report',src)
        self.assertIn('reportMessageKey="support.sent"',src)
        self.assertIn('reportMessageKey="support.error"',src)
        self.assertNotIn('RESEND_API_KEY',src)

    def test_server_authenticated_rate_limited_and_secret_storage(self):
        policy=(P/'supabase/functions/bug-report/policy.mjs').read_text('utf8')
        edge=(P/'supabase/functions/bug-report/index.ts').read_text('utf8')
        sql=(P/'supabase/02_bug_report_quota.sql').read_text('utf8')
        self.assertIn("auth: 'user'",edge)
        self.assertIn("Deno.env.get('RESEND_API_KEY')",edge)
        self.assertIn("Deno.env.get('REPORT_TO_EMAIL')",edge)
        self.assertIn(".insert({ user_id: userID, day_utc: day })",edge)
        self.assertIn('parseSafeReport(raw)',edge)
        self.assertIn('makeSafeEmail(report, day)',edge)
        self.assertIn('primary key (user_id, day_utc)',sql)
        self.assertIn('enable row level security',sql)
        self.assertIn('revoke delete, update on public.oranaplo_report_daily from authenticated',sql)
        self.assertIn('ctx.supabaseAdmin.from',edge)
        self.assertNotIn('health_rate',policy)

    def test_backend_sources_are_in_safe_github_push(self):
        cloud=(P/'tools/cloud_build.ps1').read_text('utf8')
        self.assertIn("Add-ByExtension 'supabase' @('.sql','.md','.ts','.mjs','.toml')",cloud)
        self.assertIn("Add-ByExtension 'tests' @('.py','.html','.swift','.js','.mjs','.xml','.json','.storekit')",cloud)
        self.assertNotIn('REPORT_TO_EMAIL=',cloud)

    def test_new_ui_is_localized_in_three_languages(self):
        src=swift('OpsText.swift')
        parts=[src.split(f'"{language}": [',1)[1].split('\n        ],',1)[0] for language in ('hu','en','de')]
        keys=[set(re.findall(r'"([a-z][a-zA-Z.]+)":',part,re.M)) for part in parts]
        self.assertEqual(keys[0],keys[1]);self.assertEqual(keys[1],keys[2])
        self.assertGreater(len(keys[0]),38)

if __name__=='__main__':unittest.main()
