# ÓraNapló 0.4.2 – TELJES Windows + iOS projekt

**Új:** Egészségprofil, megfigyelések, opcionális saját Google Sheets Apps Script.

A projekt a 0.4.1-es verzió összes funkcióját megőrzi (Pro évi 1000 Ft-os StoreKit-előkészítés, pulzusmentés ingyen, három nyelv, szinkron, sport, Google Sheets, Windows BAT).

## Telepítés/ellenőrzés

1. Mentsd el a korábbi projektedet külön mappába.
2. Csomagold ki ezt a teljes projektet `OraNaplo-iOS-Windows` mappába.
3. A `01_WINDOWS_ELOKESZITES.bat` futtatja a helyi teszteket.
4. A `04_DEMO_MEGNYITASA.bat` a régi UI-előnézetet nyitja meg; az új Egészségprofil önálló előnézete `docs/EGESZSEGPROFIL_ELONEZET_042.html`.
5. A `02_FELHOS_IPA_EPITES.bat` a GitHubon macOS Xcode-fordítást indít, majd IPA-t próbál letölteni.
6. Sideloadly-val csak aláírási korlátok mellett tesztelhető; a HealthKit jelenleg megfelelő Apple-entitlementet igényel.

**Fontos:** sem a sikeres helyi tesztek, sem a lefordítható Swift-kód nem bizonyítják az egészségadat-olvasás tényleges készülékes működését.

## Új funkciók

- **Egészségprofil**: életkor, biológiai nem, magasság, testsúly, számított BMI tájékoztató jelleggel.
- **Külön engedélykérés**, minden hiányzó értéknél egyértelmű jelzés.
- **Helyi megfigyelések**: rögzített vérnyomás, saját aktivitásmintához viszonyított lépésszám, csak teljesnek jelölt folyadéknapló és személyes cél alapján történő összehasonlítás.
- **Nem automatikus profil-export**: Pro-előfizetéssel, kifejezett megerősítés után, kizárólag a saját Sheet `Profil` lapjára. Születési dátum nem kerül exportálásra.
- **Google Sheets**: `Profil`, `Megfigyelesek`, `ElemzesBeallitasok` fülek; régebbi, meglévő táblázathoz a `Google Sheets létrehozása / felkészítése` funkció hozzáadja a hiányzó új füleket, a régieket nem törli.
- **Opcionális Apps Script**: a felhasználó maga telepítheti a `scripts/Ertekeles.gs` fájlt és engedélyezheti saját Google-fiókjában az időzítést; az alkalmazás a létrehozott megfigyeléseket felolvashatja a saját Sheetből. Részletes magyar leírás a `docs/EGESZSEGPROFIL_MEGFIGYELESEK_042.md` fájlban.
- **Három nyelv** minden új képernyőelemhez: HU, EN, DE.

## Egészségügyi biztonság

Az adatok nem helyettesítik orvosi vizsgálatot. Az Apple Watch nem mér vérnyomást: csak a Healthbe ténylegesen beírt vagy kompatibilis eszköz által küldött értékeket vizsgáljuk. A megfigyelések **nem háttérben futó sürgősségi riasztások**. A vérnyomásos mintaszabály felnőttekre, a Steps csak korábbi saját mintára vonatkozik. Az Apps Scripthez külön engedélyezés szükséges.

Nem állítjuk, hogy az Apple Developer Program befizetése vagy bármely aláírás automatikusan megold minden kompatibilitási, adatvédelmi vagy App Store-ellenőrzési kérdést.
