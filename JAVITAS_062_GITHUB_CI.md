# ÓraNapló 0.6.1 – javított CI-csomag hiányzó QA-adatok javítása

A 2026-11-11-i GitHub Actions 43076617859 futás még az Xcode-fordítás előtt megszakadt, mert a `docs/QA_061/QA_STATUS.json` és `docs/QA_061/NAPI_SZINKRON_NAPLO.csv` a szándékosan szűkített publikus GitHub-feltöltésből hiányzott.

## Megoldás
- A tesztek ezentúl kizárólag a `tests/fixtures/qa_061/` alatti **kitöltetlen, szintetikus** QA-mintákat használják.
- A PowerShell-feltöltő csak az egyetlen biztonságos CSV-mintát engedélyezi, a teljes `docs/QA_061/` helyi naplózási mappa kimarad a nyilvános GitHubból.
- A `tools/verify_ci_staging.py` feltöltés előtt ellenőrzi, hogy minden szükséges fájl megvan-e, és nincs-e benne helyi OAuth-konfiguráció vagy privát QA-napló.
- Négy új regressziós teszt ellenőrzi a sikeres és hibás staging-helyzeteket.

## Újrafuttatás Windows alatt
1. A ZIP-et bontsd ki **új mappába**.
2. A saját `google_oauth.json` fájlodat helyben másold át a régi projektből, ne küldd el senkinek és ne töltsd fel nyilvános GitHubra.
3. Futtasd a `00_MINDENT_INDIT.bat` fájlt (vagy előbb `01_WINDOWS_ELOKESZITES.bat`, majd `02_FELHOS_IPA_EPITES.bat`).
4. Engedélyezd a nyilvános GitHub-tároló frissítését, ha ez megfelel. A frissített program új commitot készít és új Actions-futást indít.
5. Ha mégis hibás a futás, küldd el a *legújabb* `github-failed-steps.log`, `xcodebuild.log`, `xcodebuild-simulator.log`, `xcodebuild-watchsimulator.log` fájlokat, amennyiben elkészültek.

**Nem igazolt még:** Apple SDK-s iOS/watchOS-fordítás, IPA-készítés, iPhone/Watch telepítés, HealthKit és előfizetés valós tesztje. A javítás a CI korai fájlhiányát kezeli.

**Biztonsági megjegyzés:** a tároló nyilvános. A tényleges 7 napos szinkronnaplót és a kitöltött QA-státuszokat hagyd helyben. Ne töltsd fel a `docs/QA_061/` fájljait kézzel GitHubra.
