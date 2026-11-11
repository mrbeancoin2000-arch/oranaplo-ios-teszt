"""Pre-payment structural guards; these do not substitute for actual on-device testing."""
import pathlib, plistlib, re, unittest
R=pathlib.Path(__file__).resolve().parents[1]
S=R/'ios'/'Sources'

class ReadinessTests(unittest.TestCase):
    def test_full_project_keep_windows_and_cloud_build(self):
        for f in ['01_WINDOWS_ELOKESZITES.bat','02_FELHOS_IPA_EPITES.bat','project.yml','.github/workflows/macos-ipa.yml']:
            self.assertTrue((R/f).exists(),f)
    def test_health_xml_file_picker_without_health_entitlement(self):
        app=(S/'OraNaploApp.swift').read_text(encoding='utf8')
        engine=(S/'SyncEngine.swift').read_text(encoding='utf8')
        core=(S/'HealthXMLCore.swift').read_text(encoding='utf8')
        self.assertIn('.fileImporter(', app)
        self.assertIn('importAppleHealthXML',engine)
        self.assertIn('HealthXMLCore.parse',engine)
        self.assertIn('allowedTypes: allowed',engine)
        self.assertIn('metric.id == Catalog.freeSampleIdentifier', engine)
        self.assertIn('InputStream(url: url)',core)
        self.assertIn('shouldResolveExternalEntities = false',core)
        self.assertIn('externalEntityResolvingPolicy = .never',core)
    def test_queue_is_fail_closed_durable_on_crash(self):
        src=(S/'LocalQueue.swift').read_text(encoding='utf8')
        for token in ['uncertain_upload.json','beginUpload','uncertainBatch','accountSwitched','decodeExisting','!incomingCompleted.contains($0.id)','appendCompletedIDs','completed_ids.log','savePending()']:
            self.assertIn(token,src)
        self.assertNotIn('(try? Data(contentsOf: pendingFile))',src)
    def test_append_ack_uncertain_reconciles_before_retry(self):
        api=(S/'GoogleSheets.swift').read_text(encoding='utf8')
        engine=(S/'SyncEngine.swift').read_text(encoding='utf8')
        self.assertIn('allowRetry: false',api)
        self.assertIn('alreadyOnSheet',api)
        self.assertIn('remoteRowIDs',api)
        self.assertIn('needsInitialReconciliation',engine)
        self.assertIn('fields[0] = row.id',api)
        self.assertTrue(engine.index('uncertainBatch()') < engine.index('queue.beginUpload(batch)') < engine.index('sheets.append(batch,'))
    def test_100m_engine_filters_unrealistic_gps(self):
        s=(S/'SplitMath.swift').read_text(encoding='utf8')
        for value in ['meters / seconds > maxSpeedMetersPerSecond','accuracyMeters <= 50','distanceMeters','heartMean: pulse.isEmpty ? nil','started = next.time']:
            self.assertIn(value,s)
    def test_healthkit_background_observer_requires_entitlement(self):
        ent=plistlib.loads((R/'ios/Resources/OraNaplo.entitlements').read_bytes())
        self.assertTrue(ent['com.apple.developer.healthkit'])
        self.assertTrue(ent['com.apple.developer.healthkit.background-delivery'])
        self.assertIn('HKObserverQuery', (S/'HealthReader.swift').read_text(encoding='utf8'))
        self.assertIn('finished()', (S/'HealthReader.swift').read_text(encoding='utf8'))
    def test_local_storekit_one_year_id_and_translations(self):
        import json
        obj=json.loads((R/'tests/storekit/OraNaplo_Annual_Offline.storekit').read_text(encoding='utf8'))
        groups=obj['subscriptionGroups']
        self.assertEqual(len(groups),1)
        product=groups[0]['subscriptions'][0]
        self.assertEqual(product['productID'],'hu.oranaplo.pro.yearly')
        self.assertEqual(product['recurringSubscriptionPeriod'],'P1Y')
        self.assertEqual(product['type'],'RecurringSubscription')
        self.assertEqual({x['locale'] for x in product['localizations']},{'hu_HU','en_US','de_DE'})

    def test_no_fake_pro_unlocked(self):
        store=(S/'SubscriptionManager.swift').read_text(encoding='utf8')
        self.assertIn('case .verified',store)
        self.assertIn('Transaction.currentEntitlements',store)
        self.assertNotIn('proActive = true',store)
        self.assertIn('hu.oranaplo.pro.yearly',store)
    def test_all_l10n_keys_match(self):
        s=(S/'L10n.swift').read_text(encoding='utf8')
        langs=[]
        for lang in ['hu','en','de']:
            m=re.search(r'"'+lang+r'": \[([\s\S]*?)\n        \],',s)
            self.assertIsNotNone(m)
            langs.append(set(re.findall(r'^\s+"([\w.]+)":',m.group(1),re.M)))
        self.assertEqual(langs[0],langs[1]); self.assertEqual(langs[1],langs[2])
        for k in ['xml.title','xml.description','xml.pick','xml.failed']:
            self.assertIn(k, langs[0])
    def test_premium_does_not_upload_profile_implicitly(self):
        s=(S/'SyncEngine.swift').read_text(encoding='utf8')
        self.assertIn('func exportProfileToOwnSheet()',s)
        self.assertNotIn('await exportProfileToOwnSheet()',s)
    def test_no_apple_credentials_in_project(self):
        bad=list(R.rglob('*.p8'))+list(R.rglob('*.p12'))+list(R.rglob('*.mobileprovision'))
        self.assertFalse(bad,str(bad))
    def test_signed_build_is_not_falsely_claimed(self):
        existing=(R/'.github/workflows/macos-ipa.yml').read_text(encoding='utf8')
        self.assertIn('CODE_SIGNING_ALLOWED=NO',(R/'tools/ci_xcode_build.sh').read_text(encoding='utf8'))
        self.assertIn('UNSIGNED',existing)
        self.assertIn('healthkit_distribution_signed_and_tested', (R/'release_manifest.json').read_text(encoding='utf8'))

if __name__=='__main__': unittest.main()
