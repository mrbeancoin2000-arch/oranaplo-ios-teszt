# ÓraNapló 0.6.4 – WatchKit Extension hibás elvárás javítása

## A 43082666594-es GitHub-futás eredménye

- iOS Simulator: SIKERES (az előző iOS SDK-bekényszerítés már megszűnt).
- Google és HealthKit forrásbeállítások: SIKERESEK.
- iOS device (unsigned): MEGÁLLT az embedded watch app validálásán:
  `WatchKit App doesn't contain any WatchKit Extensions`.
- A külön Watch Simulator-fordítás emiatt nem futott.

## Gyökérok és javítás

A `project.watch.yml` **egyetlen watchOS application targetet** (`type: application`) definiál,
az összes Watch SwiftUI-kód ebben van, nincs WatchKit Extension target. Ez az
Xcode 14 utáni támogatott felépítés (watchOS 11 minimum).

A `watchOS/Info.plist` ennek ellenére `WKWatchKitApp=true` mezőt tartalmazott,
amely a régi két-targetes WatchKit felépítést jelezhette az embedded binary
ellenőrzésnek. Ezt a modern **`WKApplication=true`** mező váltja fel.
Nem adtunk hozzá hamis, üres WatchKit Extensiont: a watchOS 11-en a single-target
felépítés a helyes irány.

Az `tools/verify_ipa.py` már a valódi modern Watch app metaadatot ellenőrzi.
Az `tools/check_build_inputs.py` és `tests/test_064_watch_single_target.py` az új
konfigurációt vizsgálják, és elutasítják a régi WatchKit jelölést.

## Mit tegyél Windowson?

1. Csomagold ki a teljes új ZIP-et külön könyvtárba. Ne keverd a korábbi projektfájlokkal.
2. Másold át a saját `google_oauth.json` fájlt ugyanoda, a projekt gyökerébe.
3. Indítsd el a `02_FELHOS_IPA_EPITES.bat` fájlt.
4. Az új GitHub Actions-futásban ellenőrizd sorban az iOS Simulator, az Unsigned build
   és a Blocking watchOS simulator build lépéseket.
5. Ha még hiba van, küldd el az aktuális futás `xcodebuild.log`, `xcodebuild-watchsimulator.log`
   (ha már készült), illetve `github-failed-steps.log` állományait.

A következő GitHub-futás az egyetlen hiteles ellenőrzés a *teljes* Apple SDK-s
fordításra. A helyi Python- és Swift-ellenőrzések ezt nem helyettesítik.

## Apple-dokumentáció

- https://developer.apple.com/documentation/watchos-apps/migrating-to-a-single-target-watchos-app
- https://developer.apple.com/documentation/bundleresources/information-property-list/wkapplication

**Fontos:** az aláíratlan IPA nem egyenlő az éles, HealthKit-képes, aláírt alkalmazással.
