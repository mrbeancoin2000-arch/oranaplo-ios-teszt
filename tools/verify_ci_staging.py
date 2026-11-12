#!/usr/bin/env python3
"""Reject missing CI fixtures and inadvertent publication of private QA logs.

Execute on the *staging repository* before git add/push, not on the local
project where the seven-day QA log may contain personal information.
"""
import csv
import json
import sys
from pathlib import Path

REQUIRED = (
    '.github/workflows/macos-ipa.yml',
    'project.watch.yml',
    'tools/prepayment_audit.py',
    'tests/test_061_release_safety.py',
    'tests/fixtures/apple_health_synthetic.xml',
    'tests/fixtures/qa_061/QA_STATUS_TEMPLATE.json',
    'tests/fixtures/qa_061/NAPI_SZINKRON_NAPLO_TEMPLATE.csv',
    # Reference-only WidgetKit source files: required by the v0.7.0 tests.
    # These must be uploaded to CI without being embedded in the IPA.
    'widgets/iOS/OraNaploWidgets.swift',
    'widgets/watchOS/OraNaploWatchWidgets.swift',
)
PRIVATE_FILES = (
    'google_oauth.json',
    'docs/QA_061/QA_STATUS.json',
    'docs/QA_061/NAPI_SZINKRON_NAPLO.csv',
)

def check(root: Path) -> list[str]:
    errors = []
    for rel in REQUIRED:
        if not (root / rel).is_file():
            errors.append(f'Missing GitHub build input: {rel}')
    for rel in PRIVATE_FILES:
        if (root / rel).exists():
            errors.append(f'PRIVATE FILE in public GitHub stage: {rel}')
    if (root / 'docs/QA_061').exists():
        errors.append('PRIVATE QA FOLDER in public GitHub stage: docs/QA_061')
    qa = root / 'tests/fixtures/qa_061/QA_STATUS_TEMPLATE.json'
    if qa.is_file():
        try:
            doc = json.loads(qa.read_text(encoding='utf-8-sig'))
            states = doc['tests']
            if len(states) != 15 or any(
                item.get('status') != 'NOT_RUN' or item.get('evidence') or item.get('notes')
                for item in states.values()
            ):
                errors.append('QA status fixture contains real progress or evidence')
        except (ValueError, KeyError, TypeError) as exc:
            errors.append(f'Invalid QA status template: {exc}')
    csv_file = root / 'tests/fixtures/qa_061/NAPI_SZINKRON_NAPLO_TEMPLATE.csv'
    if csv_file.is_file():
        try:
            with csv_file.open(encoding='utf-8-sig', newline='') as handle:
                rows = list(csv.DictReader(handle, delimiter=';'))
            if len(rows) != 14 or sorted({r.get('nap') for r in rows}) != list('1234567'):
                errors.append('QA checkpoint template must contain 14 rows (two/day for seven days)')
            if any(
                r.get('ellenorzes') not in ('reggel', 'este') or
                any(val.strip() for key, val in r.items() if key not in ('nap','ellenorzes') if val)
                for r in rows
            ):
                errors.append('QA CSV fixture contains non-empty real monitoring fields')
        except (ValueError, OSError) as exc:
            errors.append(f'Invalid QA CSV fixture: {exc}')
    return errors

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: python tools/verify_ci_staging.py PATH_TO_GIT_STAGING')
    issues = check(Path(sys.argv[1]))
    if issues:
        for item in issues:
            print('CI STAGING ERROR:', item, file=sys.stderr)
        raise SystemExit(2)
    print('CI staging OK: required synthetic fixtures present, private QA logs excluded')
