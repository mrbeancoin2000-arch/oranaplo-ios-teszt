# ÓraNapló 0.3.6 — teljes Windows + iOS projekt

**Indítás:** `01_WINDOWS_ELOKESZITES.bat`, majd `02_FELHOS_IPA_EPITES.bat`.

A valódi SwiftUI felület a `ios/Sources/OraNaploApp.swift` fájlban van. Az új megjelenést Windows alatt, telepítés nélkül megnézheted: `docs/ELONEZET_036.html` (csak látványterv, nem adatkapcsolat).

A telefonos főképernyőn kiemelt Google Sheets gomb először bejelentkezést, utána táblázatlétrehozást ajánl. Ha az aktuális fiókhoz már tartozik táblázat, a **Saját Google Sheets megnyitása** gomb azonnal elérhető. Az alkalmazás nem kér Gmail-jelszót tőled vagy az üzemeltetőtől, csak Google OAuth-engedélyt.

Google Sheets és napló használatához nem kell HealthKit. Az egészségadatokhoz továbbra is HealthKit-engedélyt tartalmazó megfelelő Apple-aláírás szükséges; ezt az ingyenes Sideloadly nem garantálja.

A `google_oauth.json` fájl iOS OAuth **nyilvános kliensazonosítót** tartalmaz, nem hozzáférési tokent vagy jelszót. A Build a projektet a saját GitHub-repódba tölti fel. Ne helyezz oda egészségadatot, API-titkot, hozzáférési tokent.

A meglévő telepítési útmutatók a `docs` könyvtárban vannak. Részletek: `VALTOZASOK_036.md`.
