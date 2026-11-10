# ÓraNapló 0.3.6 — prémium iOS-felület és fiókonkénti Sheets-megnyitás

## Új
- Teljes SwiftUI kezdőfelület újratervezve: sötét grafit, acélkék, ezüst és finom átmenetek.
- Négy áttekinthető fül: Áttekintés, Mérések, Napló, Beállítások.
- A kezdőlapon kiemelt **Saját Google Sheets megnyitása** gomb. Valódi `https://docs.google.com/spreadsheets/d/{id}/edit` URL-t nyit.
- A táblázat ID-ja Google-fiókonként külön tárolódik; kilépés/fiókváltás után nem marad kint másik fiók linkje.
- A helyi, függő exportadatok fiókonként elkülönített könyvtárba kerülnek. Ez fontos, hogy a következő fiók ne kapja az előző fiók adatait.
- Meglévő, ugyanazzal a fiókkal elérhető régi táblázat felismerése, valamint opcionális Google Drive API-s helyreállítás újratelepítéskor (a Drive API külön engedélyezése esetén).
- `docs/ELONEZET_036.html`: Windows böngészőből megnyitható, interaktív statikus felület-előnézet.

## Telepítés
1. Csomagold ki a teljes ZIP-et egy új `OraNaplo-iOS-Windows` mappába.
2. Tartsd meg / ellenőrizd a `google_oauth.json` iOS kliensazonosítóját és Bundle ID-ját.
3. Futtasd `01_WINDOWS_ELOKESZITES.bat`, majd `02_FELHOS_IPA_EPITES.bat`.
4. A GitHub Actions sikeres fordítása után Sideloadly-val tesztelheted az új IPA-t.
5. A telefonon először csatlakoztasd a Google-fiókodat, majd az Áttekintés képernyőn hozd létre vagy nyisd meg a táblázatodat.

## Fontos
- A **Google Sheets létrehozása és megnyitása** nem igényel HealthKit-jogosultságot.
- A **HealthKit-engedély** továbbra is aláírásfüggő; egy ingyenes Sideloadly-s tanúsítvány nem feltétlenül tartalmazza a `com.apple.developer.healthkit` jogosultságot.
- A régi `OraNaplo/queue.json` fájlban lévő korábbi függő exportadatokat **nem kapcsoljuk automatikusan másik Google-fiókhoz**, így nem kerülhetnek véletlenül rossz fiókba. A régi fájlt nem töröljük.
- Az új SwiftUI-források helyileg csak szintaktikailag ellenőrizhetők; valódi Xcode/iPhone-fordítást GitHub Actions-ben szükséges futtatni.
- A Google Drive API-s felderítés opcionális. Ha a Drive API nincs engedélyezve, a saját korábban eltárolt táblázatazonosító továbbra is működik; újratelepítés után viszont nem minden helyzetben állítható helyre automatikusan a fájl.
