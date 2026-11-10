# ÓraNapló – iPhone / Apple Health → saját Google Sheets (Windows projekt)

**Állapot: fejlesztői prototípus.** Korábbi verziója sikeresen lefordult és iPhone-on megnyílt, de a Google OAuth és a HealthKit hozzáférés még nem működik megbízhatóan. A mostani 0.3.4 változat valós Xcode-fordítása még ellenőrzésre szorul. A GitHub Actions-alapú fordítás hiba esetén Xcode-naplót ad. Ez NEM ígéret arra, hogy a Sideloadly ingyenes aláírás HealthKit-hozzáférést fog biztosítani.

## Melyik fájlt indítsam Windowson?

**Elsőként a `00_MINDENT_INDIT.bat` fájlt próbáld.** Ez sorban elindítja az alábbi lépéseket, de nem tudja átugrani a személyes Google/GitHub/Apple hozzájárulásokat. Ha még nincs Google OAuth Client ID-d, megnyitja a beállítási leírást, majd megáll; beállítás után futtasd újra.

1. **`01_WINDOWS_ELOKESZITES.bat`** – megpróbálja telepíteni a Git, Python, GitHub CLI eszközöket `winget` segítségével; ellenőrzi a forrásprojektet, futtatja a Python-teszteket; minden kimenet a `logs` könyvtárba megy. A PATH frissítéshez a terminált néha újra kell indítani.
2. **`04_DEMO_MEGNYITASA.bat`** – böngészős, teljesen offline **csak dizájn-előnézet**. Nem iOS, nem fér hozzá az Apple Egészséghez.
3. **`google_oauth.example.json`** másolása `google_oauth.json` néven, `ios_client_id` mező kitöltése saját **iOS típusú Google OAuth Client ID**-val. Lásd `docs/GOOGLE_BEALLITAS.md`.
4. **`02_FELHOS_IPA_EPITES.bat`** – megkérdezi, engeded-e a forráskód **nyilvános** GitHub repóba feltöltését, majd a GitHub macOS gépén próbál Xcode-projektet generálni és **aláíratlan IPA-t** fordítani. A végső eredmény, ha sikerül: `output/OraNaplo-UNSIGNED.ipa`. Minden építési log letölthető GitHub Actionsről.
5. **`03_SIDELOADLY_MEGNYITAS.bat`** – megnyitja az IPA helyét és a hivatalos Sideloadly-weboldalt. Az USB csatlakoztatás, Apple-fiókos aláírás és telepítés **kézzel történik**. Sideloadly nem tud HealthKit-jogosultságot automatikusan biztosítani.

**A BAT nem telepít Xcode-ot Windowsra**, mert az nem fut Windows alatt. A Macet a GitHub felhőjében használjuk. A GitHub ingyenes standard macOS-futtatói **nyilvános repókhoz** jelenleg díjmentesek. Privát repónál díjak / kvóták lehetnek.

## Mit tartalmaz?

- `ios/Sources/`: SwiftUI app, HealthKit olvasás, Google Sign-In, Google Sheets API, időzített háttérfeladat, helyi hibakímélő sor, edzésenkénti 100 méteres GPS-szakaszok, EKG mérések, iPhone akku és kézi napló.
- `project.yml`: XcodeGen-projekt (az Xcodeprojektet a macOS build generálja).
- `.github/workflows/macos-ipa.yml`: aláírás nélküli iOS build kísérlet.
- `tools/`, `tests/`: Windows telepítés, CI indítás, forrásellenőrzések.
- `docs/`: Google Cloud beállítás, képességmátrix, adatbiztonság, tesztforgatókönyv.

## Mi az, amit NEM állíthatunk késznek?

- A GitHubos iOS fordítás és Sideloadly/HealthKit jogosultság kombinációja **nincs próbálva**.
- Az App Store/ügyfeleknek történő terjesztéshez külön Apple Developer fiók, jogi megfelelés, részletes tesztelés kell.
- A háttérszinkron nem garantálható percenként. Az iOS dönt a háttérfutásról.
- Az Apple Watch akkumulátorszintje, képernyőidő, szoba CO₂, külső hőmérséklet nem érhető el ebből a HealthKit-alapú iPhone-appból; nincs implementálva. GPS hiányában nincs 100 m-es szakasz.
- A nyers adatok nem alkotnak orvosi diagnózist; az EKG-adat különösen érzékeny.
- A Google Sheets nagyméretű adatoknál elérheti kapacitását és kvótáit. A prototípus nem garantálja az összes múltbeli minta teljes betöltését és a hálózati bizonytalanság esetén teljesen duplikációmentes működést.

## Hibák elküldése

Küldd el a **`logs/setup_...log`**, **`logs/build_...log`** vagy a GitHub Actionsből letölthető **`build-logs/xcodebuild.log`** fájl releváns részét. **Google access tokent, Apple-jelszót, egészségadatot ne küldj.**

## A tesztelés legelső sorrendje

1. Helyi BAT ellenőrzések → 2. GitHub macOS fordítás → 3. Sideloadly aláírás → 4. HealthKit engedélyezési képernyő → 5. Google OAuth → 6. 1 nap adat export → 7. 1 GPS-es futás 100 m szakaszok.

Részletek: `docs/TELEPITES_IPHONE.md`.

## 0.3.4 – Google / HealthKit Info.plist javítás

A korábbi XcodeGen `info.path` (és `entitlements.path`) beállítás **felülírta** a forrás plist fájlokat macOS-en, mert nem volt `properties` megadva. A `project.yml` most `INFOPLIST_FILE` és `CODE_SIGN_ENTITLEMENTS` használatával közvetlenül a változatlan forrásfájlokra mutat. A workflow az `xcodegen generate` után külön ellenőrzi a Google/HealthKit adatait **még az Xcode-fordítás előtt**. A `plist-normalize.txt` és `build-inputs.txt` a hibákhoz mostantól letölthető.

Az ingyenes Sideloadly aláírás továbbra sem garantálja a HealthKit entitlementet. Sem az Apple, sem a Google részéről nem történt éles jóváhagyás. A Cloud build sikerének ellenőrzését az ügyfél Windows-gépén kell végrehajtani.
