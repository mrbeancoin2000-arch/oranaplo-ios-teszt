#!/usr/bin/env python3
"""ÓraNapló 0.8 safe offline diagnostics and release gates (not an Apple SDK substitute)."""
from __future__ import annotations
import argparse, datetime as dt, hashlib, html, json, os, pathlib, re, shutil, subprocess, sys, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
REDACTIONS = [
    (re.compile(r'(?i)(authorization\s*[:=]\s*bearer\s+)[A-Za-z0-9._~+/-]+'), r'\1[REDACTED]'),
    (re.compile(r'(?i)(refresh_token|access_token|id_token|client_secret|service_role|api_key)(["\s:=]+)[^"\s,;}{]+'), r'\1\2[REDACTED]'),
    (re.compile(r'(?i)[\w.\-+]+@[\w.\-]+\.[a-z]{2,}'), '[EMAIL]'),
    (re.compile(r'(?i)(https?://[^\s]+)(?:access_token|refresh_token|id_token)=([^&\s]+)'), '[URL_WITH_TOKEN_REDACTED]'),
]

def clean(data: str) -> str:
    for pattern, replacement in REDACTIONS: data = pattern.sub(replacement, data)
    return data[:4_000_000]

def run(stage: str, cmd: list[str], out: pathlib.Path, timeout: int = 220) -> dict:
    start = time.monotonic()
    try:
        cp = subprocess.run(cmd, cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True,
                            text=True, errors='replace', timeout=timeout)
        code = cp.returncode
        body = cp.stdout + ('\n[STDERR]\n' + cp.stderr if cp.stderr else '')
    except subprocess.TimeoutExpired as exc:
        code = 124
        body = 'TIMEOUT: ' + str(exc)
    except OSError as exc:
        code = 127
        body = 'TOOL_UNAVAILABLE: ' + type(exc).__name__
    output = out / (stage + '.log')
    output.write_text(clean(body) + '\n', encoding='utf-8')
    return {'stage': stage, 'pass': code == 0, 'exit_code': code, 'elapsed_seconds': round(time.monotonic()-start, 2),
            'log': output.name, 'command': cmd[0] + ' ' + ' '.join(cmd[1:])}

def file_manifest() -> dict:
    excludes = {'logs','output','build','__pycache__','.git','.build','.venv'}
    items = {}
    for p in ROOT.rglob('*'):
        if not p.is_file() or any(x in excludes for x in p.relative_to(ROOT).parts): continue
        if p.name in {'google_oauth.json','.env'} or p.suffix in {'.p8','.pem','.key','.ipa','.p12'}: continue
        if p.stat().st_size > 2_000_000: continue
        items[p.relative_to(ROOT).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return items

def safety_scan(root: pathlib.Path = ROOT) -> list[str]:
    """Block sensitive local files, except validated *public* iOS OAuth metadata.

    google_oauth.json is needed by the Windows setup and contains ONLY public
    ios_client_id and ios_bundle_id. Never print its values or ship it in ZIP.
    This is not a substitute for source-code/CI secrets scanning.
    """
    issues: list[str] = []
    ignores = {'logs', 'output', 'build', '.git', '.build', '__pycache__', '.venv'}
    allowed_oauth_fields = {'ios_client_id', 'ios_bundle_id'}
    for p in root.rglob('*'):
        if not p.is_file() or any(part in ignores for part in p.relative_to(root).parts):
            continue
        name = p.name.lower()
        if name == 'google_oauth.json':
            # A local configuration with public Google iOS identifiers is safe.
            # Never allow client_secret, access_token or unknown extra fields.
            try:
                if p.is_symlink() or p.stat().st_size > 8192:
                    raise ValueError('unexpected file type/size')
                data = json.loads(p.read_text(encoding='utf-8-sig'))
                if not isinstance(data, dict) or set(data) != allowed_oauth_fields:
                    raise ValueError('unexpected OAuth fields')
                client = data['ios_client_id']
                bundle = data['ios_bundle_id']
                if not isinstance(client, str) or not re.fullmatch(r'[A-Za-z0-9_-]+\.apps\.googleusercontent\.com', client):
                    raise ValueError('invalid iOS client ID')
                if not isinstance(bundle, str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+)+', bundle):
                    raise ValueError('invalid bundle ID')
            except (OSError, ValueError, UnicodeError, json.JSONDecodeError):
                issues.append(f'UNSAFE_OAUTH_CONFIG: {p.relative_to(root)}')
            continue
        if (name == '.env' or name.startswith('.env.') or
                name.startswith('authkey_') or
                name in {'private_key.pem','service-account.json','service_account.json'} or
                p.suffix.lower() in {'.p8', '.p12', '.pem', '.key', '.mobileprovision'}):
            issues.append(f'CHECK_SECRET_FILE: {p.relative_to(root)}')
    return issues

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--output-dir', default=None, help='Relative to project or absolute directory')
    args = ap.parse_args()
    stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%d_%H%M%S_UTC')
    out = pathlib.Path(args.output_dir) if args.output_dir else ROOT / 'logs' / f'ULTRA_DEBUG_{stamp}'
    out = out.resolve(); out.mkdir(parents=True, exist_ok=True)
    print('ÓraNapló ULTRA DEBUG – privacy-safe / offline / real Apple tests still required', flush=True)
    steps = []
    steps.append(run('python_tests', [sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py','-v'], out))
    steps.append(run('offline_full_audit',[sys.executable,'tools/prepayment_audit.py'],out,timeout=420))
    if shutil.which('swiftc'):
        sources = [str(x.relative_to(ROOT)) for x in list((ROOT/'ios'/'Sources').glob('*.swift'))
                   + list((ROOT/'watchOS'/'Sources').glob('*.swift'))]
        steps.append(run('swift_syntax', ['swiftc','-frontend','-parse',*sources],out,timeout=180))
    else:
        steps.append({'stage':'swift_syntax','pass':None,'reason':'Swift parser not installed on this Windows machine; macOS CI required.'})
    if shutil.which('node'):
        steps.append(run('support_policy',['node','tests/test_057_support_policy.mjs'],out))
    else:
        steps.append({'stage':'support_policy','pass':None,'reason':'Node not installed'})
    issues = safety_scan()
    (out/'security_scan.json').write_text(json.dumps({'issues':issues},indent=2,ensure_ascii=False),encoding='utf-8')
    steps.append({'stage':'secret_file_scan','pass':not issues,'issues':issues,
                  'note':'Public Google iOS OAuth IDs are allowed locally; private credentials are blocked.'})
    checks = [
        ('iOS Apple SDK compiler',False,'Missing verified xcodebuild simulator + device evidence for THIS version'),
        ('watchOS Apple SDK compiler',False,'Missing verified xcodebuild Watch simulator evidence for THIS version'),
        ('iPhone HealthKit device',False,'Requires signed, installed real iPhone and explicit permissions'),
        ('Apple Watch install + WatchConnectivity',False,'Watch app was not installed in latest documented tests'),
        ('Apple StoreKit Sandbox subscription',False,'StoreKit local testing is not a live App Store sandbox'),
        ('Apple offer code real HUF pricing',False,'No App Store Connect 500/1000 HUF offer verified'),
        ('Referral Apple JWS server verification',False,'No deployed App Store signed transaction verification handler'),
        ('Referral anti-Sybil and refund handling',False,'App Attest/DeviceCheck, refund and incident flows not verified'),
        ('Google Sheets and OAuth real device',False,'Google API approval/sync and privacy review not evidenced here'),
        ('7-day background sync and duplicate tests',False,'Requires week-long device observation'),
        ('Legal policy and App Review metadata',False,'Requires published final URLs, privacy labels and App Store Connect')
    ]
    passed = all(s.get('pass') is True for s in steps if s.get('pass') is not None)
    report = {
        'product':'ÓraNapló','version':'0.8.2','generated_utc':dt.datetime.now(dt.timezone.utc).isoformat(),
        'offline_pass':passed,'offline_steps':steps,
        'gate':'BLOCKED_FOR_APP_STORE_RELEASE',
        'developer_account_purchase_decision': 'Code tests alone cannot certify device compatibility; continue signed device test after developer enrollment.',
        'production_checks':[{'name':n,'pass':p,'reason':r} for n,p,r in checks],
        'data_handling':'This package excludes live health records, tokens, account IDs, GPS and request bodies.',
        'manifest_count':len(file_manifest())
    }
    (out/'REPORT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    (out/'MANIFEST_SHA256.json').write_text(json.dumps(file_manifest(),ensure_ascii=False,indent=2),encoding='utf-8')
    trs = ''.join(f'<tr><td>{html.escape(s["stage"])}</td><td>{"PASS" if s.get("pass") is True else "FAIL" if s.get("pass") is False else "NOT RUN"}</td><td>{html.escape(s.get("log",""))}</td></tr>' for s in steps)
    blocks = ''.join(f'<tr><td>{html.escape(n)}</td><td>BLOCKED</td><td>{html.escape(r)}</td></tr>' for n,p,r in checks)
    doc = '''<!doctype html><html lang="hu"><meta charset="utf-8"><title>ÓraNapló 0.8 Diagnosztika</title><style>body{font:16px system-ui;background:#0c1522;color:#edf3ff;max-width:1050px;margin:3em auto;padding:1em}table{border-collapse:collapse;width:100%}td,th{border:1px solid #546070;padding:11px;text-align:left}th{background:#193049}h1{color:#86d6f4}.warn{color:#ffbf83}</style>'''
    doc += '<h1>ÓraNapló 0.8 – ULTRA DEBUG</h1><p>Ez a jelentés csak forrás-/helyi tesztelést igazol. Semmi nem helyettesíti a valódi Apple SDK fordítást és készülékes tesztet.</p>'
    doc += '<h2>Offline ellenőrzések</h2><table><tr><th>Fázis</th><th>Eredmény</th><th>Napló</th></tr>'+trs+'</table>'
    doc += '<h2 class="warn">App Store-kapuk: BLOKKOLVA</h2><table><tr><th>Teszt</th><th>Állapot</th><th>Indok</th></tr>'+blocks+'</table></html>'
    (out/'REPORT.html').write_text(doc,encoding='utf-8')
    print('Offline checks:', 'PASS' if passed else 'FAIL')
    for step in steps: print(' -',step['stage'], step.get('pass'))
    print('Release gate: BLOCKED_FOR_APP_STORE_RELEASE')
    print('Reports:',out)
    return 0 if passed else 1

if __name__ == '__main__': sys.exit(main())
