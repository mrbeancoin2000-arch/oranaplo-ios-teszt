from pathlib import Path
import plistlib, re, json, subprocess, shutil
ROOT=Path(__file__).resolve().parents[1]
sources=list((ROOT/'ios/Sources').glob('*.swift'))
assert len(sources)>=6, 'Incomplete Swift sources'
for path in sources:
    s=path.read_text('utf-8')
    assert not '\x00' in s and len(s)>60, path
with (ROOT/'ios/Resources/Info.plist').open('rb') as f:
    p=plistlib.load(f)
assert p['NSHealthShareUsageDescription']
assert p['BGTaskSchedulerPermittedIdentifiers']==['hu.oranaplo.ios.refresh']
assert 'googleClientID' in (ROOT/'ios/Sources/AppConfig.swift').read_text('utf-8')
if shutil.which('swiftc'):
    result=subprocess.run(['swiftc','-frontend','-parse',*[str(s) for s in sources]],capture_output=True,text=True)
    assert result.returncode==0, result.stderr
    print('Swift parser: OK (nem jelent Apple SDK-s forditast)')
print(f'Forrasok: {len(sources)} Swift-fajl, Info.plist OK')
