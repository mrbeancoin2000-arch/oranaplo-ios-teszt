#!/usr/bin/env python3
"""Diagnose and verify the UNSIGNED IPA's embedded Info.plist.

Outputs explicit reasons for failures. Does not validate the entitlements of
Sideloadly's eventual signed IPA or guarantee HealthKit authorization.
"""
from __future__ import annotations
import plistlib
import sys
import zipfile
from pathlib import Path

ipa = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("output/OraNaplo-UNSIGNED.ipa")
problems: list[str] = []

def check(condition: bool, description: str) -> None:
    print(("OK: " if condition else "HIBA: ") + description, flush=True)
    if not condition:
        problems.append(description)

if not ipa.is_file():
    check(False, f"IPA nem található: {ipa}")
    raise SystemExit(2)
try:
    with zipfile.ZipFile(ipa) as archive:
        plist_paths = [name for name in archive.namelist()
                       if name.startswith("Payload/") and name.count("/") == 2
                       and name.endswith(".app/Info.plist")]
        print("App Info.plist találatok:", plist_paths, flush=True)
        check(len(plist_paths) == 1, "Az IPA pontosan egy Payload/<App>.app/Info.plist fájlt tartalmaz")
        if len(plist_paths) != 1:
            raise SystemExit(1)
        info = plistlib.loads(archive.read(plist_paths[0]))
except (OSError, zipfile.BadZipFile, ValueError, plistlib.InvalidFileException) as exc:
    print("HIBA: IPA vagy Info.plist olvasási hiba:", exc, flush=True)
    raise SystemExit(2)

bundle_id = str(info.get("CFBundleIdentifier", ""))
print("IPA Bundle ID:", bundle_id or "HIÁNYZIK")
check(bool(bundle_id and "$" not in bundle_id), "CFBundleIdentifier beállítva és feloldva")
for key in ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription",
            "NSLocationWhenInUseUsageDescription", "NSMotionUsageDescription"):
    val = info.get(key)
    check(isinstance(val, str) and bool(val.strip()), f"{key} létezik és nem üres")

for mode in ("fetch", "location"):
    check(mode in info.get("UIBackgroundModes", []), f"iOS background mode: {mode}")

client = str(info.get("GIDClientID", "")).strip()
print("GIDClientID:", client or "HIÁNYZIK")
check(bool(client and client.endswith(".apps.googleusercontent.com") and not client.startswith("ADD_")),
      "GIDClientID valódi Google iOS OAuth kliensazonosító")
expected = ".".join(reversed(client.split("."))) if client else ""
urltypes = info.get("CFBundleURLTypes", [])
schemes = [v for d in urltypes if isinstance(d, dict)
           for v in d.get("CFBundleURLSchemes", []) if isinstance(v, str)]
print("Google visszairányítási URL-séma elvárt:", expected or "HIÁNYZIK")
print("Az IPA tényleges URL-sémái:", schemes)
check(bool(expected and any(s.lower() == expected.lower() for s in schemes)),
      "GIDClientID és a CFBundleURLSchemes egyeznek")

if problems:
    print(f"ÖSSZEGZÉS: {len(problems)} konfigurációs hiba; az IPA nem adható ki tesztelésre.", flush=True)
    raise SystemExit(1)
print("ÖSSZEGZÉS: aláíratlan IPA Info.plist konfiguráció megfelelő.", flush=True)
print("FIGYELEM: A Sideloadly aláírása után a Bundle ID és a HealthKit jogosultság eltérhet.", flush=True)
