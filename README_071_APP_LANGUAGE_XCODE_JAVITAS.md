# ÓraNapló 0.7.1 – AppLanguage típushiba javítása

**Kiindulás:** ÓraNapló 0.7.0 CI Widget-javított teljes projekt.

## Miért állt meg a GitHub Actions?

Az iOS-szimulátoros `xcodebuild` hat hibát jelentett a `RunTrackerView.swift` és a `NewDashboardViews.swift` fájlokban. Az alkalmazásban a `language` tulajdonság **`AppLanguage` felsorolt típus**, viszont a frissen hozzáadott nézetek több helyen közvetlenül szöveggel (`"en"`, `"de"`) hasonlították össze.

**Javítás:** a két fájl összes ilyen `language == "en"` / `language == "de"` feltétele `language == .en` / `language == .de` összehasonlításra változott. Nem módosult a Google OAuth, az adatmentési rendszer, a Bundle ID és az Apple Watch csomagolása. A `languageCode` továbbra is szövegként tárolódik, és `AppLanguage(rawValue:)` alakítja át felsorolt típussá.

Új regressziós teszt: `tests/test_071_swift_language_regression.py` (3 ellenőrzés).

## Tesztek

- Python: 151 / 151 sikeres a projekt teljes tesztkönyvtárában.
- Swift: a 37 iOS- és a Watch Swift-forrás szintaktikai elemzése sikeres.
- Teljes fizetés előtti offline audit: sikeres, Swift-alapú runtime-tesztekkel.
- Apple SDK-s iOS/watchOS build: **ezt a javított csomaggal még újra le kell futtatnod GitHub Actionsben**. A lokális szintaktikai ellenőrzés nem helyettesíti az Xcode-fordítást.

## Telepítési lépések

1. A ZIP-et **külön könyvtárba** csomagold ki; a régi, iPhone-on működő példányt még ne töröld.
2. A helyben tárolt `google_oauth.json` fájlt másold át a korábbi mappából az új `OraNaplo-iOS-Windows` mappába. Ez nem lehet része a nyilvános GitHub-repónak.
3. Indítsd a `05_FIZETES_ELOTTI_TESZTEK.bat` programot.
4. Indítsd a `02_FELHOS_IPA_EPITES.bat` programot, és csak a jóváhagyott publikus fájlokat engedd feltölteni.
5. Sikeres GitHub-fordítás után új aláírás és telepítés szükséges a valódi telefonos teszthez.

Ha a következő GitHub-futás más Swift-hibát mutat, töltsd le a `xcodebuild-simulator.log` / `xcodebuild.log` naplókat. Az aktuális hat hibát az új verzió kezeli; **a teljes Apple SDK-s siker még nem igazolt**.

**Adatvédelem:** ne tölts fel személyes mérési adatokat, fióktokeneket, privát OAuth-konfigurációt, vagy titkos hitelesítési kulcsokat nyilvános tárolóba.
