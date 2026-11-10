# ÓraNapló 0.3.4 – teljes javított projekt

**A 2026-11-10 20:37-es sikertelen build valódi oka:** a `Normalize unsigned app Info.plist` lépés `exit code 2` hibával leállt. A felhasználói képernyő nem tartalmazza a normalizáló hibakimenetét, így a közvetlen okot nem lehet 100%-osan igazolni, de a projektből bizonyítható: az XcodeGen `info.path` és `entitlements.path` üres `properties`-szel újragenerálja és felülírja a forrás plist fájlokat. Ez megmagyarázza az elvesző HealthKit/OAuth metaadatokat.

## Változtatások

- `project.yml`: `info`/`entitlements` generálási szekciók eltávolítva. Explicit `INFOPLIST_FILE` és `CODE_SIGN_ENTITLEMENTS` hivatkozás, változatlan forrás plist-ek.
- Új `tools/check_build_inputs.py`: macOS-en a XcodeGen-futtatás után ellenőrzi a HealthKit szövegeket, HealthKit entitlementet és a Google OAuth adatait.
- `.github/workflows/macos-ipa.yml`: hibát hamarabb észleli, és automatikusan feltölti a `build-inputs.txt`, `plist-normalize.txt`, `ipa-verification.txt` diagnosztikát.
- `tools/cloud_build.ps1`: a letöltött diagnosztikát kiírja konzolra is.
- Új helyi tesztek, amelyek védik a build-fájlt a véletlen visszaállítástól.

**Windows teendők:** új mappába csomagold, `01_WINDOWS_ELOKESZITES.bat`, majd `02_FELHOS_IPA_EPITES.bat`. GitHub feltöltés előtt ellenőrizd a változtatásokat. Az eredményét az új `logs/` mappában találod.

**Korlát:** Xcode nem fut Windows alatt; a konkrét 0.3.4 verzió éles macOS fordítása és HealthKit-hozzáférése még nincs igazolva. A Sideloadly HealthKit capability-t nem tudjuk szoftveres trükkel megszerezni.
