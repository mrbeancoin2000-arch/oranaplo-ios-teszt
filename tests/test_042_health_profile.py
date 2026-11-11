from pathlib import Path
import json, re, subprocess, shutil, unittest
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT/'ios'/'Sources'

class HealthProfileTests(unittest.TestCase):
    def test_profile_has_separate_permission_and_no_made_up_values(self):
        code=(SRC/'HealthProfile.swift').read_text(encoding='utf8')
        reader=(SRC/'HealthReader.swift').read_text(encoding='utf8')
        self.assertIn('dateOfBirthComponents()',code)
        self.assertIn('biologicalSex()',code)
        self.assertIn('quantity.doubleValue(for: unit)',code)
        self.assertIn('func authorizeProfile()',reader)
        self.assertIn('.dateOfBirth',reader)
        self.assertIn('.biologicalSex',reader)
        self.assertIn('weightKG: latestWeight?.0',code)

    def test_health_rules_are_not_unjustified_diagnosis(self):
        code=(SRC/'HealthProfile.swift').read_text(encoding='utf8')
        self.assertIn('profile.adult',code)
        self.assertIn('high > 180 || low > 120',code)
        self.assertIn('high >= 140 || low >= 90',code)
        self.assertIn('profile.alert.bp.urgent',code)
        self.assertIn('history.count >= 5',code)
        self.assertIn('oranaplo.water.allRecorded',code)
        self.assertIn('!samples.isEmpty',code)

    def test_three_languages_and_fifth_tab(self):
        loc=(SRC/'L10n.swift').read_text(encoding='utf8')
        ui=(SRC/'OraNaploApp.swift').read_text(encoding='utf8')
        blocks={}
        for language in ('hu','en','de'):
            m=re.search(r'"'+language+r'": \[([\s\S]*?)\n        \],',loc)
            self.assertIsNotNone(m,language)
            blocks[language]=set(re.findall(r'^\s+"([\w.]+)":',m.group(1),re.M))
        self.assertEqual(blocks['hu'],blocks['en'])
        self.assertEqual(blocks['en'],blocks['de'])
        self.assertIn('healthProfilePage.tabItem',ui)
        self.assertIn('tag(4)',ui)
        self.assertTrue({'profile.alert.bp.urgent.title','profile.alert.steps.body','profile.water.all','profile.export.confirm.message'}.issubset(blocks['de']))

    def test_profile_export_is_opt_in_pro_only_and_without_date_of_birth(self):
        code=(SRC/'SyncEngine.swift').read_text(encoding='utf8')
        sheets=(SRC/'GoogleSheets.swift').read_text(encoding='utf8')
        self.assertIn('func exportProfileToOwnSheet()',code)
        self.assertIn('guard SubscriptionManager.shared.proActive else',code)
        self.assertIn('func updateProfile(',sheets)
        self.assertNotIn('birthDate',sheets)
        self.assertIn('profile.ageYears',sheets)
        self.assertIn('ensureProfileTabs',sheets)

    def test_apps_script_offline_rule_checks(self):
        if not shutil.which('node'):
            self.skipTest('Node unavailable')
        run=subprocess.run(['node',str(ROOT/'tests'/'test_042_apps_script.js')],
                           text=True,capture_output=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    def test_apps_script_syntax(self):
        if not shutil.which('node'):
            self.skipTest('Node unavailable')
        path=ROOT/'scripts'/'Ertekeles.gs'
        self.assertTrue(path.is_file())
        check=subprocess.run(['node','--check','-'],input=path.read_text(encoding='utf8'),text=True,capture_output=True)
        self.assertEqual(check.returncode,0,check.stderr)
        data=path.read_text(encoding='utf8')
        self.assertIn('function frissitMegfigyelesek()',data)
        self.assertIn('function telepitNapiEllenorzes()',data)
        self.assertIn("String(settings.teljes_folyadeknaplo)",data)
        self.assertIn('Number(profile.age_years) >= 18',data)

if __name__=='__main__': unittest.main()
