# ÓraNapló 0.8.1 – ULTRA DEBUG Google OAuth hibajavítás

## Miért állt meg a 0.8.0?

A `windows_setup.ps1` helyesen megköveteli a helyi `google_oauth.json`-t a Google Sheets-bejelentkezéshez, de a `tools/ultra_debug.py` korábbi `safety_scan()` ellenőrzése **tévesen titkos fájlként tiltott minden `google_oauth.json`-t**. Így a `secret_file_scan` hibás eredménye leállította a `00_MINDENT_INDIT.bat`-ot.

## Mi változott?

- A két nyilvános mezőt tartalmazó helyi `google_oauth.json`-t a diagnosztika elfogadja: `ios_client_id`, `ios_bundle_id`.
- Továbbra is tiltja a privát kulcsokat (`.p8`, `.pem`, `.p12`, `.env*`), és a Google JSON-ben megjelenő `client_secret`, access/refresh token és bármely extra mezőt.
- +7 automata regressziós tesztet adtunk hozzá.
- A JSON-t a `.gitignore` továbbra is kizárja, a ZIP **nem tartalmazza** a személyes konfigurációdat.
- A `swift_syntax: NOT RUN` Windows alatt normális: az ellenőrzést macOS-en GitHub Actions végzi.

## Mit tegyél?

1. Bontsd ki ezt az új ZIP-et egy külön mappába; ne töröld a korábbi működő változatot.
2. Másold át a korábbi `google_oauth.json` fájlt az **új projekt gyökerébe**, a `00_MINDENT_INDIT.bat` mellé. NE másolj át naplókat és privát kulcsokat.
3. Indítsd el először a `07_ULTRA_DEBUG.bat` fájlt. `Offline checks: PASS` várható, ha nincs más új hiba.
4. Utána indítsd a `00_MINDENT_INDIT.bat`-ot, amely továbbmegy a macOS GitHub buildig.
5. Ha valami hibás: küldd el a friss `logs/ULTRA_DEBUG_*/REPORT.json` és `logs/ULTRA_DEBUG_*/secret_file_scan` releváns kimenetét (ne küldj tokeneket vagy privát kulcsokat).

## Figyelem

A javítás a Windows-os téves riasztást szünteti meg. Az App Store release gate változatlanul `BLOCKED_FOR_APP_STORE_RELEASE`, amíg nincs hiteles iPhone/Watch SDK-build, aláírás, éles HealthKit/StoreKit/Google end-to-end teszt és Apple felülvizsgálat. A jelenlegi diagnosztika nem vizsgálhatja meg magát az App Store jóváhagyást.
