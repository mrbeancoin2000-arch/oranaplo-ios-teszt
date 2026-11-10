#!/usr/bin/env python3
"""Ensure required Apple Health and Google OAuth metadata survives XcodeGen.

Called on an unsigned .app *before* packaging and signing. It does not add
HealthKit entitlements, cannot replace Apple signing, and never handles tokens.
"""
from __future__ import annotations
import plistlib
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "ios" / "Resources" / "Info.plist"
DEFAULT_BUILT = ROOT / "build" / "Build" / "Products" / "Debug-iphoneos" / "OraNaplo.app" / "Info.plist"


def main() -> int:
    built_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_BUILT
    if not SOURCE.is_file() or not built_path.is_file():
        print(f"HIBA: Info.plist fájl hiányzik. Forrás: {SOURCE}, build: {built_path}")
        return 2
    with SOURCE.open("rb") as f:
        source = plistlib.load(f)
    with built_path.open("rb") as f:
        built = plistlib.load(f)
    changed = []
    keys = (
        "GIDClientID",
        "CFBundleURLTypes",
        "NSHealthShareUsageDescription",
        "NSHealthUpdateUsageDescription",
    )
    for key in keys:
        value = source.get(key)
        if value is None:
            print(f"HIBA: {key} hiányzik a forrás Info.plistből")
            return 2
        if built.get(key) != value:
            built[key] = value
            changed.append(key)
    # IMPORTANT: preserve the built CFBundleIdentifier, executable and signatures.
    # The final bundle ID may change again when Sideloadly re-signs the IPA.
    if changed:
        with built_path.open("wb") as f:
            plistlib.dump(built, f, fmt=plistlib.FMT_BINARY)
        print("Beépített Info.plist javítva:", ", ".join(changed))
    else:
        print("Beépített Info.plist: HealthKit és Google mezők egyeznek.")
    print("Build Bundle ID:", built.get("CFBundleIdentifier", "HIÁNYZIK"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
