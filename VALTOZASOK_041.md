# ÓraNapló 0.4.1 – Windows UTF-8 teszthibajavítás

## A javított hiba

A 0.4.0 csomag `tests/test_040_features.py` fájlja `Path.read_text()` hívásokat használt explicit kódolás nélkül. A Windows magyar beállításai mellett a Python 3.14 `cp1250` kódolást választott, ezért a Swift-fájlok egyes UTF-8 karaktereivel `UnicodeDecodeError` keletkezett, és a 27 tesztből kettő hibára futott.

## Módosítások

- Minden szövegolvasás a `tests/test_040_features.py` fájlban kifejezetten UTF-8-at használ.
- A Windows-előkészítő PowerShell folyamata a futtatott Python-folyamatokra UTF-8 módot állít be (`PYTHONUTF8=1`). Ez csak a futtatási folyamatra vonatkozik, nem módosítja a Windows rendszerbeállításait.
- Új regressziós teszt: `tests/test_text_encoding.py` figyeli, hogy a tesztkódokból ne maradjon ki az explicit `read_text` kódolás.
- **A Swift-kódot, StoreKit 2-t, Google Sheets-integrációt, HealthKit-kezelést és a Google OAuth-azonosítót nem módosítottuk.**

## Windowsos lépések

1. Készíts biztonsági másolatot a korábbi `OraNaplo-iOS-Windows` mappádról.
2. A **teljes 0.4.1 ZIP-et** csomagold ki külön mappába az Asztalon.
3. Indítsd el a `01_WINDOWS_ELOKESZITES.bat` fájlt.
4. Sikeres helyi tesztek után futtasd a `02_FELHOS_IPA_EPITES.bat` fájlt.
5. Sikeres GitHub-fordítás után tesztelhető az IPA a Sideloadly-val, de a HealthKit használatához továbbra is megfelelő aláírási jogosultság szükséges.

## Megjegyzés

Az ellenőrzés nem helyettesíti az Xcode-on végzett fordítást, és nem bizonyítja az Apple HealthKit jogosultságát. A Pro-vásárlás sem működhet éles előfizetésként az App Store Connect termék létrehozása és Apple jóváhagyása előtt.
