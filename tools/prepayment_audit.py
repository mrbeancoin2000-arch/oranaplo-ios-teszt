#!/usr/bin/env python3
"""Offline, repeatable pre-payment readiness audit. Never accesses real health data.
USAGE: python tools/prepayment_audit.py
Generates logs/prepayment_YYYYMMDD_HHMMSS/ with JSON, HTML, and raw command logs.
Windows without Swift compiler: Swift runtime SKIPPED (not PASS). macOS CI will verify it.
"""
from __future__ import annotations
import datetime as dt, hashlib, html, json, os, pathlib, platform, shutil, subprocess, sys, time
ROOT=pathlib.Path(__file__).resolve().parents[1]
DATE=dt.datetime.now(dt.timezone.utc).strftime('%Y%m%d_%H%M%S_UTC')
OUT=ROOT/'logs'/f'prepayment_{DATE}'
OUT.mkdir(parents=True,exist_ok=True)
steps=[]

def step(name,argv,required=True,timeout=240,expected_exit=0):
    if not shutil.which(argv[0]):
        result={'name':name,'status':'SKIPPED' if not required else 'FAIL',
                'explanation':f'{argv[0]} not installed (cannot claim this test passed)',
                'seconds':0,'log':''}
        steps.append(result);print(f"[{result['status']}] {name}: missing {argv[0]}");return
    t0=time.monotonic()
    try:
        call=subprocess.run(argv,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                            encoding='utf-8',errors='replace',timeout=timeout,env={**os.environ,'PYTHONUTF8':'1'})
        output=call.stdout
        code=call.returncode
        passed=code==expected_exit if isinstance(expected_exit,int) else code in expected_exit
        status='PASS' if passed else 'FAIL'
    except subprocess.TimeoutExpired as exc:
        code=None;output=(exc.stdout or b'').decode('utf-8',errors='replace') if isinstance(exc.stdout,bytes) else (exc.stdout or '')
        status='FAIL';output+='\nTIMEOUT: test did not finish within limit\n'
    log_file=OUT/(f'{len(steps)+1:02d}_'+name.lower().replace(' ','_')+'.log')
    log_file.write_text(output,encoding='utf8')
    result={'name':name,'status':status,'exit_code':code,'seconds':round(time.monotonic()-t0,2),
            'log':log_file.name,'required':required,
            'explanation':('Expected blocker confirmed' if name=='Production release gate' and status=='PASS' else '')}
    steps.append(result);print(f'[{status}] {name}: {result["seconds"]} s')
    if status=='FAIL':print(output[-1200:])

step('Python project unit tests',[sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py','-v'])
step('Apps Script offline runtime',['node','tests/test_042_apps_script.js'],required=False)
step('Privacy-safe report runtime',['node','--test','tests/test_057_support_policy.mjs'],required=False)
if shutil.which('swiftc'):
    step('Swift source syntax',['swiftc','-frontend','-parse',*[str(p) for p in sorted((ROOT/'ios/Sources').glob('*.swift'))]])
    runtime=OUT/('offline-core-test.exe' if platform.system()=='Windows' else 'offline-core-test')
    step('Swift core compilation',['swiftc','-O','ios/Sources/HealthXMLCore.swift','ios/Sources/SplitMath.swift',
         'tests/runtime_core_main.swift','-o',str(runtime)],required=True)
    if runtime.exists():
        step('Swift XML and GPS runtime',[str(runtime),'tests/fixtures/apple_health_synthetic.xml'])
else:
    steps.append({'name':'Swift syntax and compiled runtime','status':'SKIPPED','required':False,
                  'explanation':'No swiftc on this computer. Must run on GitHub macOS CI before paying.',
                  'log':'','seconds':0})
    print('[SKIPPED] Swift runtime (Windows: macOS CI required)')
# Pure Foundation run-session test: executable on Linux Swift or GitHub macOS.
if shutil.which('swiftc'):
    run_binary=OUT/('run-math-core-test.exe' if platform.system()=='Windows' else 'run-math-core-test')
    step('Running GPS split core compilation',['swiftc','-O','ios/Sources/RunMathCore.swift','tests/runtime_run_main.swift','-o',str(run_binary)])
    if run_binary.exists(): step('Running GPS split core runtime',[str(run_binary)])
    insight_binary=OUT/('run-insights-test.exe' if platform.system()=='Windows' else 'run-insights-test')
    step('PR and streak core compilation',['swiftc','-O','ios/Sources/RunMathCore.swift','ios/Sources/RunInsightsCore.swift','tests/runtime_insights_main.swift','-o',str(insight_binary)])
    if insight_binary.exists(): step('PR and streak core runtime',[str(insight_binary)])
else:
    steps.append({'name':'Running GPS split core runtime','status':'SKIPPED','required':False,
                  'explanation':'Swift compiler unavailable; macOS GitHub Actions must run this',
                  'log':'','seconds':0})
if shutil.which('swiftc'):
    sleep_binary=OUT/('sleep-core-test.exe' if platform.system()=='Windows' else 'sleep-core-test')
    step('Sleep duration core compilation',['swiftc','-O','ios/Sources/SleepAnalysisCore.swift',
         'tests/runtime_sleep_main.swift','-o',str(sleep_binary)])
    if sleep_binary.exists(): step('Sleep duration comparison runtime',[str(sleep_binary)])
if shutil.which('swiftc'):
    ops_binary=OUT/('ops-safety-test.exe' if platform.system()=='Windows' else 'ops-safety-test')
    step('Support and locale Swift compilation',['swiftc','-O','ios/Sources/L10n.swift','ios/Sources/OpsText.swift',
         'ios/Sources/SafeDiagnosticTrail.swift','ios/Sources/SafeSupportPayload.swift','tests/runtime_ops_main.swift','-o',str(ops_binary)])
    if ops_binary.exists(): step('Support and locale Swift runtime',[str(ops_binary)])
step('Draft release metadata check',[sys.executable,'tools/release_preflight.py'])
# The strict gate MUST fail until post-payment App Store IDs, URL/contact and signing are done.
step('Production release gate',[sys.executable,'tools/release_preflight.py','--strict'],expected_exit=1)

shortcuts={
 'Windows development scripts':(ROOT/'01_WINDOWS_ELOKESZITES.bat').exists() and (ROOT/'02_FELHOS_IPA_EPITES.bat').exists(),
 'Prepared HealthKit background entitlement': 'com.apple.developer.healthkit.background-delivery' in (ROOT/'ios/Resources/OraNaplo.entitlements').read_text(encoding='utf8'),
 'Google OAuth production switched':False,
 'Apple paid membership and signing':False,
 'App Store Connect subscription approved':False,
 'Live HealthKit sensor read tested':False,
 'Google Sheets end-to-end with user auth tested in this audit':False,
 'Public bug-report email successfully delivered (Supabase + Resend)':False,
 'Leaderboard row delete tested against real Supabase RLS':False,
 'Interrupted workout recovered on real iPhone':False,
 'App Store review approved':False
}
necessary_failed=any(x['status']=='FAIL' and x.get('required',True) for x in steps)
run_skips=[x['name'] for x in steps if x['status']=='SKIPPED']
report={
 'project':'OraNaplo 0.6.1',
 'created_utc':dt.datetime.now(dt.timezone.utc).isoformat(),
 'platform':{'os':platform.platform(),'python':sys.version.split()[0],'swift_compiler':shutil.which('swiftc'),'node':shutil.which('node')},
 'result':'PREPAYMENT_CHECKS_FAILED' if necessary_failed else ('LOCAL_PASS_SWIFT_MACOS_PENDING' if run_skips else 'LOCAL_PREPAYMENT_CHECKS_PASSED'),
 'disclaimer':'No real Apple Health, Google OAuth, Google Sheets, StoreKit sandbox, HealthKit entitlement or Xcode iOS build verified by this local audit.',
 'steps':steps,'readiness':shortcuts,
 'next_required':['Run the macOS Xcode iOS-simulator unsigned build in GitHub Actions and inspect artifacts',
                  'Perform actual Google OAuth and Sheets sync/recovery with a test account',
                  'After Apple membership: sign with HealthKit entitlements; run device tests',
                  'Create and sandbox-test 1000 HUF/year subscription in App Store Connect',
                  'Verify production contact/privacy URLs, review and publish']}
(OUT/'RESULT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
css='''body{font:15px system-ui;background:#0b1422;color:#e5eefc;max-width:1000px;margin:40px auto;padding:0 20px}h1{color:#8ab9fd}.p{color:#75d4a3}.f{color:#ff9292}.s{color:#ffd37e}table{width:100%;border-collapse:collapse}td,th{padding:10px;border-bottom:1px solid #354155;text-align:left}code{color:#a9cfff}a{color:#91bfff}aside{padding:15px;border:1px solid #566075;border-radius:12px;background:#192433}'''
rows=''.join(f'<tr><td>{html.escape(x["name"])}</td><td class="{ "p" if x["status"]=="PASS" else "f" if x["status"]=="FAIL" else "s" }">{x["status"]}</td><td>{html.escape(x.get("explanation", ""))}</td><td><code>{html.escape(x.get("log", ""))}</code></td></tr>' for x in steps)
readiness=''.join(f'<tr><td>{html.escape(k)}</td><td>{"Prepared" if v else "NOT VERIFIED / POST-PAYMENT"}</td></tr>' for k,v in shortcuts.items())
page=f'''<!doctype html><html lang="hu"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>ÓraNapló 0.6.1 – Tesztjelentés</title><style>{css}</style><h1>ÓraNapló 0.6.1 – Fizetés előtti tesztek</h1><p><b>{report['result']}</b><br>{report['created_utc']}</p><aside>Fontos: A zöld helyi tesztek nem igazolják az App Store-kiadhatóságot. Nem történt valódi HealthKit-engedélyezés, aláírt iOS-fordítás, Google-fiókos feltöltés vagy Apple-vásárlás. A minták szintetikusak.</aside><h2>Lefutott ellenőrzések</h2><table><tr><th>Vizsgálat</th><th>Eredmény</th><th>Magyarázat</th><th>Napló</th></tr>{rows}</table><h2>Éles kiadás feltételei</h2><table>{readiness}</table><h2>Következő lépések</h2><ol>{''.join('<li>'+html.escape(s)+'</li>' for s in report['next_required'])}</ol></html>'''
(OUT/'JELENTES.html').write_text(page,encoding='utf8')
print('\nReport:',OUT/'RESULT.json')
print('HTML  :',OUT/'JELENTES.html')
print('Status:',report['result'])
sys.exit(1 if necessary_failed else 0)
