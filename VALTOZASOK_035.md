# ÓraNapló 0.3.5 – Google Sheets / HealthKit szétválasztása

## Javítás
- A Google Sheets táblázat létrehozása önálló gombot kapott, amelyhez **nem kell HealthKit-engedély**.
- A „Google Sheets létrehozása” és „Google Sheets / napló szinkronizálása” gomb a sikeres Google-bejelentkezés után aktív.
- A kézi naplóbejegyzések továbbra is helyben mentődnek, és sikeres Google-kapcsolat esetén HealthKit nélkül is szinkronizálódnak.
- Az egészségadat-export külön gombon maradt; hiányzó HealthKit-engedélynél érthető üzenet jelenik meg, nem történik újabb jogosultságkérés.
- A korábbi 0.3.4 források, hibakezelés, Google-konfiguráció és GitHub Actions buildfolyamat megmaradt.

## Útmutató
1. `01_WINDOWS_ELOKESZITES.bat` → helyi tesztek.
2. `02_FELHOS_IPA_EPITES.bat` → GitHub macOS-fordítás.
3. Sikeres IPA esetén telepítsd Sideloadly-val, az előző változatra.
4. Google-fiók csatlakoztatása → **Google Sheets létrehozása** → **Saját Google Sheets megnyitása**.
5. Az Egészség-adatok mentése továbbra sem fog működni, ha a Sideloadly-aláírásból hiányzik a HealthKit entitlement.

A Google Sheets API-nál a `drive.file` jogosultság alkalmas saját táblázat létrehozására és kezelésére, ha a Sheets API engedélyezve van a Google Cloud-projektben.

### Fontos
A helyi Python-tesztek nem egyenértékűek a tényleges Xcode-fordítással vagy iPhone-os Google Sheets-teszttel. A telepített HealthKit-jogosultság hiányát ez a javítás nem tudja pótolni.
