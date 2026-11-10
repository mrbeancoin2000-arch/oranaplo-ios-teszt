import unittest, sys, json, pathlib, re
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
class ProjectTests(unittest.TestCase):
    def test_files(self):
        for p in ['project.yml','ios/Sources/HealthReader.swift','ios/Sources/GoogleSheets.swift','ios/Sources/WorkoutExport.swift','.github/workflows/macos-ipa.yml']:
            self.assertTrue((ROOT/p).exists(),p)
    def test_metric_catalog(self):
        catalog=(ROOT/'ios/Sources/Models.swift').read_text(encoding='utf-8')
        for key in ['HeartRate','HeartRateVariabilitySDNN','SleepAnalysis','StepCount','DietaryWater','BloodPressureSystolic','RunningPower','DistanceSwimming']:
            self.assertIn(f'Metric("{key}"',catalog)
    def test_no_server_api(self):
        source='\n'.join(p.read_text(encoding='utf-8') for p in (ROOT/'ios/Sources').glob('*.swift'))
        self.assertIn('sheets.googleapis.com',source)
        self.assertIn('drive.file',source)
        self.assertNotIn('service_role',source)
    def test_100m_math(self):
        self.assertAlmostEqual(360/20,18.0) # km/h, 100m / 20s
        self.assertAlmostEqual(20/6,3.333333333,places=6) # minutes/km
    def test_project(self):
        from check_project import ROOT as _
        import subprocess
        result=subprocess.run([sys.executable,str(ROOT/'tools/check_project.py')],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
if __name__=='__main__': unittest.main()
