"""Strict release metadata gate. Does not affect the unsigned Windows test build.
Run: python tools/release_preflight.py [--strict]
--strict fails until legal contact and live URLs are configured, deliberately.
"""
from pathlib import Path
import argparse, json, re, sys
ROOT = Path(__file__).resolve().parents[1]


def check(strict=False):
    problems=[]
    app=(ROOT/'ios/Sources/OraNaploApp.swift').read_text(encoding='utf8')
    links=(ROOT/'ios/Sources/ReleaseLinks.swift').read_text(encoding='utf8')
    policy=(ROOT/'website/hu/privacy.html').read_text(encoding='utf8')
    if 'showLegalInformation' not in app or 'legalInformationSheet' not in app:
        problems.append('Nincs alkalmazáson belüli adatvédelmi és feltétel-nézet.')
    if 'subscriptions.restore()' not in app or 'apps.apple.com/account/subscriptions' not in app:
        problems.append('Hiányzik a vásárlás-visszaállítás vagy az Apple-előfizetéskezelés.')
    for lang in ('hu','en','de'):
        for page in ('index','privacy','terms','support'):
            if not (ROOT/'website'/lang/(page+'.html')).is_file():
                problems.append(f'Hiányzó oldal: website/{lang}/{page}.html')
    if 'hu.oranaplo.pro.yearly' not in (ROOT/'ios/Sources/SubscriptionManager.swift').read_text(encoding='utf8'):
        problems.append('Nem egyezik a StoreKit termékazonosító.')
    if strict:
        m=re.search(r'static let websiteRoot\s*=\s*"([^"]*)"',links)
        if not m or not m.group(1).startswith('https://') or 'YOUR-VERIFIED-DOMAIN' in m.group(1):
            problems.append('Állítsd be a valódi HTTPS websiteRoot címet a ReleaseLinks.swift fájlban.')
        for h in ROOT.glob('website/**/*.html'):
            s=h.read_text(encoding='utf8')
            if re.search(r'\[[A-ZÁÉÍÓÖŐÚÜŰ][^\]]+\]',s):
                problems.append('Kitöltetlen személyes/kapcsolati helyőrző: '+str(h.relative_to(ROOT)))
            if 'KÖZZÉTÉTEL ELŐTTI' in s or 'PRE-PUBLICATION' in s or 'VOR VERÖFFENTLICHUNG' in s:
                problems.append('A weboldal még közzététel előtti sablon: '+str(h.relative_to(ROOT)))
        manifest=json.loads((ROOT/'release_manifest.json').read_text(encoding='utf8'))
        for key, done in manifest.items():
            if done is not True:
                problems.append('Még nincs megerősítve a release_manifest.json fájlban: '+key)
        # These flags are declarations by the developer, not a substitute for
        # App Store Connect, provisioning profile or on-device verification.
    return problems

if __name__ == '__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--strict',action='store_true');args=ap.parse_args()
    issues=check(args.strict)
    for item in issues: print('HIÁNY:',item)
    if issues: print('KIADÁS NEM KÉSZ' if args.strict else 'PROJEKT ELŐKÉSZÍTÉS HIÁNYOS')
    else: print('Helyi release-metadata ellenőrzés rendben. Apple/Google jóváhagyás külön szükséges.')
    sys.exit(1 if issues else 0)
