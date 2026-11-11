import test from 'node:test';
import assert from 'node:assert/strict';
import { parseSafeReport, makeSafeEmail } from '../supabase/functions/bug-report/policy.mjs';
const good={category:'running',reason_code:'network',app_version:'0.6.0',platform:'iOS',event_codes:['sync.started','sync.failed']};
test('report strips arbitrary health, GPS, name, token and email fields',()=>{
  const extras={...good,heart_rate:185,lat:47.5,lon:19.1,route:[[47.5,19.1]],
    email:'private@example.com',token:'ya29.SENSITIVE',name:'Private Runner',notes:'medical information'};
  const accepted=parseSafeReport(JSON.stringify(extras));
  assert.deepEqual(accepted,{category:'running',reason:'network',version:'0.6.0',platform:'iOS',events:['sync.started','sync.failed']});
  const email=makeSafeEmail(accepted,'2026-11-11');
  for (const forbidden of ['185','47.5','19.1','private@example.com','SENSITIVE','Private Runner','medical information']){
    assert.ok(!email.includes(forbidden),'unexpected leaked value '+forbidden);
  }
});
test('invalid categories, arbitrary reasons, injection and overlong data rejected',()=>{
  assert.equal(parseSafeReport(JSON.stringify({...good,category:'blood_pressure'})),null);
  assert.equal(parseSafeReport(JSON.stringify({...good,reason_code:'185 bpm'})),null);
  assert.equal(parseSafeReport(JSON.stringify({...good,app_version:'0.6.0\nBCC:attack'})),null);
  assert.equal(parseSafeReport('x'.repeat(1501)),null);
  assert.equal(parseSafeReport(JSON.stringify({...good,event_codes:['GPS: 47.5,19.1']})),null);
  assert.equal(parseSafeReport(JSON.stringify({...good,event_codes:['sync.started','token: ya29']})),null);
  assert.equal(parseSafeReport('{}'),null);
  assert.equal(parseSafeReport('[]'),null);
});
test('every category and reason in the supported contract validates',()=>{
  for(const category of ['sync','running','google','watch','purchase','other']){
    for(const reason_code of ['none','network','authorization','quota','unknown']){
      assert.ok(parseSafeReport(JSON.stringify({...good,category,reason_code})));
    }
  }
});
