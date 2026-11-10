# Windows → GitHub macOS → iPhone (Sideloadly): tesztforgatókönyv

## Első lépések

1. Windows 10/11, stabil internet, iPhone + USB-kábel, Apple-fiók, GitHub-fiók.
2. Csomagold ki a ZIP-et egy egyszerű elérési útra, pl. `C:\OraNaplo`. Kerüld a OneDrive szinkronizált mappát, hosszú / ékezetes útvonalakat.
3. Futtasd **`01_WINDOWS_ELOKESZITES.bat`** fájlt. Ha hiányzik Git/Python/gh, a winget megpróbálja telepíteni. Szükség esetén indíts új terminált, majd futtasd újra.
4. Töltsd ki a Google OAuth Client ID-t a `docs/GOOGLE_BEALLITAS.md` szerint. Egy csak dizájn-előnézeten kívüli Google-bejelentkezéshez kötelező.
5. Futtasd a **`02_FELHOS_IPA_EPITES.bat`**-ot. A GitHub CLI böngészőben hitelesít. A script **csak előzetes `IGEN` jóváhagyásodra** hoz létre/ír felül egy **NYILVÁNOS repót**. Soha ne tárolj ebben valódi egészségadatot.
6. A GitHub Actions `macos-ipa.yml` nevű folyamata Xcode-dal elkészíti az **aláíratlan** `.ipa` fájlt, ha nincs fordítási hiba. A build hibák: GitHub Actions → adott run → `build-logs` artefaktum.
7. Siker esetén `output/OraNaplo-UNSIGNED.ipa`, futtasd **`03_SIDELOADLY_MEGNYITAS.bat`**. Telepítsd külön a hivatalos Sideloadly-t: https://sideloadly.io/ ; csatlakoztasd az iPhone-t USB-n; fogadd el a megbízhatósági promptokat; húzd be az IPA-t, majd végezd el a Sideloadly bejelentkezési és telepítési lépéseit.
8. Ingyenes Apple ID-val a személyes telepítés profilja jellemzően **7 napig érvényes**; utána újraaláírás/telepítés kell. Az App Store-ba való kiadáshoz más folyamat szükséges.

## Fontos technikai blokkoló

**HealthKit entitlement:** az Apple HealthKit-kommunikációhoz a binárisnak megfelelő jogosultsággal és érvényes aláírással kell rendelkeznie. Egy aláíratlan felhő-build + ingyenes Sideloadly-aláírás ezt **nem garantálja**. Ha a HealthKit-képernyő hiányzik, vagy az alkalmazás azt jelzi, hogy az Egészség nem elérhető / engedély nincs, a sideload sikeres telepítése *nem bizonyítja* a HealthKit működését. Szükség lehet megfelelő Apple-provisioning és Xcode / fizetős Developer Program alapú aláírásra. Nem javaslunk jogosultságok kijátszását.

## Ellenőrzések valódi készüléken

- A főképernyő megjelenik.
- Az Apple Egészség engedélykérés megjelenik. **Ha nem, itt állj meg.**
- Google Sign-In működik (tesztfelhasználó a Google Cloudban); nem kér Gmail-jelszót tőled.
- Az app létrehozza az `ÓraNapló – Egészségadatok` táblázatot.
- A Pulzus és HRV füleken valódi, időbélyegzett rekordok vannak.
- Próbálj egy GPS-es **kültéri futást vagy gyaloglást** az Apple Watch Edzés alkalmazásával. A `100m` munkalapon csak akkor lesz szakasz, ha HealthKitből elérhetők a megfelelő pontok. Nem automatikus 100 m mérés GPS hiányában.
- Kapcsold ki az internetet, indíts szinkront; a helyi sorok ne vesszenek el. Kapcsold vissza, és próbáld újra.
- Ellenőrizd a naplót és a Google Sheets-szinkront.

## Mikor jelez hiba?

- BAT setup: `logs/setup_<dátum>.log`
- GitHub indítás és letöltés: `logs/build_<dátum>.log`
- iOS-fordítás: GitHub → Actions → `macos-ipa.yml` → `build-logs/xcodebuild.log`
- Sideloadly: saját felülete / logjai; a BAT csak segédprogramot indít, nem helyettesíti a telepítést.

NEM biztosított az iPhone-on futtatható IPA az aláírás/entitlement/Google beállítások nélkül.
