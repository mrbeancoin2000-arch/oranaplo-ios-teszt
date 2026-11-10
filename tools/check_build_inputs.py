#!/usr/bin/env python3
"""Check XcodeGen did not delete essential Google and HealthKit metadata.

Uses only the Python standard library, works both on Windows and GitHub macOS.
No private tokens, user data, or Google secrets are needed.
"""
from pathlib import Path
import plistlib
import sys

ROOT = Path(__file__).resolve().parents[1]
INFO = ROOT / "ios/Resources/Info.plist"
ENTS = ROOT / "ios/Resources/OraNaplo.entitlements"
SPEC = ROOT / "project.yml"
SWIFT = ROOT / "ios/Sources/AppConfig.swift"


def validate(root=ROOT):
    problems = []
    try:
        info = plistlib.loads((root / "ios/Resources/Info.plist").read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException) as exc:
        return [f"Info.plist olvasási hiba: {exc}"]
    try:
        ent = plistlib.loads((root / "ios/Resources/OraNaplo.entitlements").read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException) as exc:
        return [f"Entitlements olvasási hiba: {exc}"]
    spec = (root / "project.yml").read_text(encoding="utf-8")
    swift = (root / "ios/Sources/AppConfig.swift").read_text(encoding="utf-8")
    for key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"):
        if not str(info.get(key, "")).strip():
            problems.append(f"Hiányzó HealthKit szöveg: {key}")
    if ent.get("com.apple.developer.healthkit") is not True:
        problems.append("A HealthKit entitlement hiányzik a FORRÁS fájlból.")
    client = str(info.get("GIDClientID", ""))
    if not (client.endswith(".apps.googleusercontent.com") and client in swift):
        problems.append("Info.plist / AppConfig.swift: Google iOS Client ID hiányzik vagy eltér.")
    reversed_client = ".".join(reversed(client.split("."))) if client else ""
    types = info.get("CFBundleURLTypes", [])
    schemes = [str(v) for entry in types if isinstance(entry, dict)
               for v in entry.get("CFBundleURLSchemes", [])]
    if not reversed_client or reversed_client not in schemes:
        problems.append("Google callback URL-séma nem egyezik az iOS Client ID-val.")
    for key, value in (
        ("INFOPLIST_FILE", "ios/Resources/Info.plist"),
        ("CODE_SIGN_ENTITLEMENTS", "ios/Resources/OraNaplo.entitlements"),
    ):
        if f"{key}: {value}" not in spec:
            problems.append(f"project.yml nem használja a megőrzött forrásfájlt: {key}")
    import re
    if re.search(r"(?m)^\s+info:\s*$", spec) or re.search(r"(?m)^\s+entitlements:\s*$", spec):
        problems.append("XcodeGen info:/entitlements: szekció felülírhatja a forrás plist fájljait.")
    return problems


def main():
    problems = validate()
    if problems:
        for problem in problems:
            print("HIBA:", problem, flush=True)
        return 2
    print("OK: XcodeGen nem generálja újra az Info.plist és entitlements forrásfájlokat.", flush=True)
    print("OK: Google OAuth és HealthKit forrásbeállítások megfelelnek.", flush=True)
    print("FIGYELEM: Az ingyenes Sideloadly aláírás HealthKit-jogosultságot továbbra sem garantál.", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
