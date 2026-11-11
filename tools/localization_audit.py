#!/usr/bin/env python3
"""Flag likely nonlocalized user-facing Swift status strings.
An estimate only; native device screenshots and language review are still required.
Run: python tools/localization_audit.py
"""
import pathlib,re,sys
root=pathlib.Path(__file__).resolve().parents[1]/'ios/Sources'
pattern=re.compile(r'(?<![A-Za-z])(?:status|message|info)\s*=\s*"([^"]*[áéíóöőúüűÁÉÍÓÖŐÚÜŰ][^"]*)"')
counts={}
for file in root.glob('*.swift'):
 matches=pattern.findall(file.read_text(encoding='utf8'))
 if matches: counts[file.name]=len(matches)
for file,n in sorted(counts.items()): print(f'{file}: {n} HU-only literals (estimated)')
total=sum(counts.values())
print(f'ÖSSZESEN: {total} magyar státuszüzenet, amelynél 3 nyelvű kézi ellenőrzés / fordítás szükséges')
sys.exit(1 if total else 0)
