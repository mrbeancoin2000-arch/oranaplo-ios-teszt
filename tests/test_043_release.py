import unittest, re, pathlib, subprocess, sys
R=pathlib.Path(__file__).resolve().parents[1]

class ReleaseTests(unittest.TestCase):
    def test_all_three_languages_have_complete_legal_keys(self):
        s=(R/'ios/Sources/L10n.swift').read_text(encoding='utf8')
        names=[]
        for lang in ('hu','en','de'):
            m=re.search(r'"'+lang+r'": \[([\s\S]*?)\n        \],',s)
            self.assertIsNotNone(m)
            keys=set(re.findall(r'^\s+"([\w.]+)":',m.group(1),re.M))
            self.assertIn('legal.subscription.summary',keys)
            self.assertIn('legal.privacy.open',keys)
            self.assertIn('legal.terms.open',keys)
            self.assertIn('legal.support.open',keys)
            names.append(keys)
        self.assertEqual(names[0],names[1]);self.assertEqual(names[1],names[2])
    def test_native_paywall_legal_screen_and_real_storekit(self):
        app=(R/'ios/Sources/OraNaploApp.swift').read_text(encoding='utf8')
        store=(R/'ios/Sources/SubscriptionManager.swift').read_text(encoding='utf8')
        self.assertIn('legalInformationSheet',app)
        self.assertIn('Link(t("legal.privacy.open")',app)
        self.assertIn('Link(t("legal.terms.open")',app)
        self.assertIn('showLegalInformation = true',app)
        self.assertIn('Transaction.currentEntitlements',store)
        self.assertIn('product.purchase(options: options)',store)
        self.assertNotIn('proActive = true',store)
    def test_html_pages_exist_and_are_protected_drafts(self):
        for lang in ('hu','en','de'):
            for p in ('index','privacy','terms','support'):
                data=(R/'website'/lang/(p+'.html')).read_text(encoding='utf8')
                self.assertIn('lang="'+lang+'"',data)
                self.assertIn('../style.css',data)
                self.assertIn('<main>',data)
            self.assertIn('[' ,(R/'website'/lang/'privacy.html').read_text(encoding='utf8'))
    def test_release_preflight_in_draft_mode(self):
        x=subprocess.run([sys.executable,str(R/'tools/release_preflight.py')],text=True,capture_output=True)
        self.assertEqual(x.returncode,0,x.stdout+x.stderr)
    def test_release_preflight_blocks_incomplete_publication(self):
        x=subprocess.run([sys.executable,str(R/'tools/release_preflight.py'),'--strict'],text=True,capture_output=True)
        self.assertNotEqual(x.returncode,0)
        self.assertIn('KIADÁS NEM KÉSZ',x.stdout)
if __name__=='__main__':unittest.main()
