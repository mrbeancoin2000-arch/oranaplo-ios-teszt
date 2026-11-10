#!/usr/bin/env python3
"""Verify *unsigned* IPA configuration before Sideloadly re-signing.
Cannot prove signed entitlements or the final bundle ID of the re-signed app.
"""
import plistlib, sys, zipfile
from pathlib import Path

ipa = Path(sys.argv[1]) if len(sys.argv)>1 else Path('output/OraNaplo-UNSIGNED.ipa')
if not ipa.exists():
    print('HIBA: IPA nem található:', ipa)
    raise SystemExit(2)
with zipfile.ZipFile(ipa) as archive:
    candidates = [n for n in archive.namelist() if n.startswith('Payload/') and n.endswith('.app/Info.plist')]
    if len(candidates)!=1:
        print('HIBA: pontosan 1 app/Info.plist szükséges, találatok:',candidates)
        raise SystemExit(2)
    plist = plistlib.loads(archive.read(candidates[0]))
errors=[]
for k in ('NSHealthShareUsageDescription','NSHealthUpdateUsageDescription'):
    present = isinstance(plist.get(k),str) and bool(plist[k].strip())
    print(f'{k}:', 'OK' if present else 'HIÁNYZIK')
    if not present: errors.append(k)
client=plist.get('GIDClientID','')
expected='.'.join(reversed(client.split('.'))) if client else ''
schemes=[v for d in plist.get('CFBundleURLTypes',[]) for v in d.get('CFBundleURLSchemes',[])]
print('Beépített Bundle ID:',plist.get('CFBundleIdentifier','?'))
print('Google kliensazonosító beállítva:',bool(client) and not client.startswith('ADD_'))
print('Google callback-séma:',schemes)
if client and not client.startswith('ADD_') and expected not in schemes:
    errors.append('GIDClientID-hez tartozó CFBundleURLSchemes')
if errors:
    print('HIBA – konfiguráció:',', '.join(errors))
    raise SystemExit(1)
print('IPA Info.plist: rendben. FIGYELEM: Sideloadly újraaláírás UTÁNI jogosultságot ez nem ellenőrzi.')
