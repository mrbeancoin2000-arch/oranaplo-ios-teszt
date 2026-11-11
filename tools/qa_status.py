#!/usr/bin/env python3
"""Inspect release evidence. Never guesses success from a checklist.
Run: python tools/qa_status.py
"""
import json, pathlib, sys
file=pathlib.Path(__file__).resolve().parents[1]/'docs/QA_061/QA_STATUS.json'
try:
    data=json.loads(file.read_text(encoding='utf8'))
except (OSError,ValueError) as exc:
    sys.exit(f'QA error: {exc}')
allowed={'NOT_RUN','PASS','FAIL','BLOCKED'}
invalid=[]
for key,case in data['tests'].items():
    status=case.get('status','NOT_RUN')
    if status not in allowed: invalid.append(key)
    if status=='PASS' and not case.get('evidence','').strip(): invalid.append(key)
    print(f"{status:8}  {key:25}  {case.get('description','')}")
if invalid: sys.exit('HIBA: nincs érvényes státusz vagy bizonyíték: '+', '.join(invalid))
passed=sum(c['status']=='PASS' for c in data['tests'].values())
print(f'\nIgazolt: {passed}/{len(data["tests"])}; kiadható: {"IGEN" if passed==len(data["tests"]) else "NEM"}')
sys.exit(0 if passed==len(data['tests']) else 1)
