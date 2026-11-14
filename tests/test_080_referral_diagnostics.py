"""ÓraNapló v0.8 contractual security checks; no Apple Store or real DB assumed."""
import json, plistlib, re, unittest
from pathlib import Path
R = Path(__file__).resolve().parents[1]
SQL = (R/'supabase/03_referrals.sql').read_text(encoding='utf8')
APP = (R/'ios/Sources/ReferralService.swift').read_text(encoding='utf8')
VIEW = (R/'ios/Sources/ReferralView.swift').read_text(encoding='utf8')
DIAG = (R/'ios/Sources/DiagnosticCenter.swift').read_text(encoding='utf8')

class ReferralSecurityContract(unittest.TestCase):
    def test_one_reward_per_role(self):
        self.assertIn('unique (user_id, role)', SQL.lower())
        self.assertIn('unique (claim_id, role)', SQL.lower())
    def test_one_invitation_per_inviter_and_invitee(self):
        self.assertRegex(SQL.lower(),r'inviter_id uuid not null unique')
        self.assertRegex(SQL.lower(),r'invitee_id uuid not null unique')
    def test_self_invites_rejected(self):
        self.assertIn('inviter_id <> invitee_id',SQL)
        self.assertIn("if sponsor=me then raise exception 'self_invite_not_allowed'",SQL)
    def test_registration_first_only(self):
        self.assertIn("signup + interval '24 hours'",SQL)
        self.assertIn("invitee_already_claimed",SQL)
    def test_chain_after_discount_year(self):
        self.assertIn('invitee_discount_ends_at > now()', SQL)
        self.assertIn("c.state<>'verified'",SQL)
    def test_disallows_anonymous_and_requires_apple(self):
        self.assertIn("auth.jwt()->>'is_anonymous'",SQL)
        self.assertIn("i.provider='apple'",SQL)
    def test_row_level_security(self):
        for name in ['oranaplo_referral_accounts','oranaplo_referral_claims','oranaplo_referral_grants','oranaplo_referral_offer_inventory']:
            self.assertIn('alter table public.'+name+' enable row level security;',SQL)
        self.assertIn('for update skip locked',SQL.lower())
    def test_no_client_confirmation(self):
        self.assertIn("server_only",SQL)
        self.assertIn('grant execute on function public.oranaplo_referral_confirm_verified_purchase(uuid,text,timestamptz) to service_role;',SQL)
        self.assertNotIn('oranaplo_referral_confirm_verified_purchase',APP)
    def test_default_no_offer_until_server(self):
        self.assertIn('static let publicOffersEnabled = false',APP)
        self.assertIn('disabled(referrals.busy || !ReferralService.publicOffersEnabled)',VIEW)
        self.assertIn('offerCodeRedemption',VIEW)
    def test_secure_apple_login_not_google_anon(self):
        self.assertIn('SignInWithAppleButton',VIEW)
        self.assertIn('SHA256.hash',APP)
        self.assertIn('kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly',APP)
        self.assertIn('"provider": "apple"',APP)
    def test_no_private_apple_secret_client(self):
        self.assertNotIn('supabase_service_role',APP.lower())
        self.assertNotIn('app_store_private_key',APP.lower())
        self.assertNotIn('APPLE_SECRET_KEY',APP)
    def test_both_platforms_watch_capability(self):
        entitlement=plistlib.loads((R/'ios/Resources/OraNaplo.entitlements').read_bytes())
        self.assertEqual(entitlement['com.apple.developer.applesignin'],['Default'])
        self.assertTrue(entitlement['com.apple.developer.healthkit.background-delivery'])
        self.assertTrue((R/'watchOS/Sources/WatchDiagnostic.swift').exists())

class DiagnosticSecurityContract(unittest.TestCase):
    def test_logging_has_allowlisted_codes(self):
        self.assertIn('enum DiagnosticCode: String, Codable',DIAG)
        self.assertIn('enum DiagnosticArea: String, Codable, CaseIterable',DIAG)
        self.assertNotIn('requestBody:',DIAG)
        self.assertNotIn('pulseValue:',DIAG)
        self.assertNotIn('latitude:',DIAG)
    def test_bounded_storage_and_protection(self):
        self.assertIn('maxRecords = 750', DIAG)
        self.assertIn('completeUntilFirstUserAuthentication',DIAG)
        self.assertIn('static func erase()',DIAG)
    def test_export_no_old_private_debug(self):
        app=(R/'ios/Sources/OraNaploApp.swift').read_text(encoding='utf8')
        self.assertIn('UIPasteboard.general.string = DiagnosticCenter.exportText()',app)
        self.assertNotIn('UIPasteboard.general.string = "ÓraNapló / "',app)
    def test_release_safety_flags_are_false(self):
        flags=json.loads((R/'release_manifest.json').read_text(encoding='utf8'))
        for key in ['referral_apple_jws_server_verification_deployed','apple_sdk_080_ios_watch_compilation_verified','watch_080_signed_install_verified']:
            self.assertIs(flags[key],False)
    def test_windows_debug_launcher_exists(self):
        self.assertIn('07_ULTRA_DEBUG.bat',(R/'00_MINDENT_INDIT.bat').read_text(encoding='utf8'))
        self.assertTrue((R/'.github/workflows/ultra-debug-macos-080.yml').exists())

if __name__ == '__main__': unittest.main()
