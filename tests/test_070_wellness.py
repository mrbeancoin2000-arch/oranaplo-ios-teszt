import pathlib, unittest, plistlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
S=ROOT/'ios/Sources'
def code(name): return (S/name).read_text(encoding='utf8')
class Wellness070Tests(unittest.TestCase):
 def test_version_matches(self):
  for f in ['ios/Resources/Info.plist','watchOS/Info.plist']:
   self.assertEqual(plistlib.loads((ROOT/f).read_bytes())['CFBundleShortVersionString'],'0.8.2')
 def test_old_integrations_maintained(self):
  self.assertIn('HKAnchoredObjectQuery',code('HealthReader.swift'))
  self.assertIn('sample.uuid.uuidString',code('HealthReader.swift'))
  self.assertIn('ISO.string(sample.startDate)',code('HealthReader.swift'))
  self.assertIn('sourceRevision.source.name',code('HealthReader.swift'))
  self.assertIn('uncertainUpload',code('LocalQueue.swift'))
 def test_time_series_is_not_faked(self):
  c=code('WellnessCore.swift')
  for name in ['baseline','pearson','recovery','regularity','sleepDebt','dailyPairs']:
   self.assertIn('func '+name,c)
  self.assertIn('return nil',c)
 def test_recovery_timepoints(self):
  self.assertIn('[1,2,3,4,5,10]',code('WellnessCore.swift'))
 def test_detailed_sleep_and_profile(self):
  c=code('WellnessInsightsService.swift')
  for key in ['asleepCore','asleepDeep','asleepREM','respiratoryRate','appleSleepingWristTemperature','bodyMass','bodyFatPercentage','sleepAndNextDayHRVCorrelation']:
   self.assertIn(key,c)
 def test_three_language_clinical_pdf(self):
  c=code('MedicalPDFReport.swift')
  for key in ['UIGraphicsPDFRenderer','lang','ISO.string','WellnessDiary','HealthReader','huText','deText','perMetricLimit','capped']:
   self.assertIn(key,c)
  self.assertNotIn('URLSession',c)
 def test_wearable_durable_water_ack(self):
  w=(ROOT/'watchOS/Sources/WatchWorkout.swift').read_text(encoding="utf8")
  b=code('WatchBridge.swift')
  for x in ['transferUserInfo','waterAck','pending.water','logWater','batteryPercent']:
   self.assertTrue(x in w or x in b)
  self.assertIn('try WellnessDiary.shared.addWater',b)
 def test_diary_atomic_protected(self):
  c=code('WellnessDiary.swift')
  for x in ['.atomic','.completeFileProtectionUntilFirstUserAuthentication','storageError','SleepRating','MedicationEntry','RoomReading','WaterEntry']:
   self.assertIn(x,c)
 def test_running_features(self):
  self.assertIn('MapPolyline(coordinates:segment.coordinates)',code('RunTrackerView.swift'))
  self.assertIn('AdvancedRunMath.compare',code('RunTrackerView.swift'))
  self.assertIn('runningPower',code('RunTrackerView.swift'))
  self.assertIn('altitudeMeters',code('RunTracker.swift'))
 def test_health_notification_not_emergency(self):
  c=code('WellnessInsightsService.swift')
  self.assertIn('unusualPulseEnabled',c)
  self.assertIn('>= 20',c)
  self.assertIn('baseline.samples >= 5',c)
  self.assertIn('Calendar.current.isDate',c)
 def test_widgets_not_added_to_sideload_build(self):
  spec=(ROOT/'project.watch.yml').read_text(encoding="utf8")
  self.assertNotIn('OraNaploWidgetBundle',spec)
  self.assertTrue((ROOT/'widgets/iOS/OraNaploWidgets.swift').exists())
 def test_accessible_new_navigation(self):
  self.assertIn('WellnessDashboardView()',code('NewDashboardViews.swift'))
  self.assertIn('MedicalPDFReport.generate',code('WellnessDashboardView.swift'))
