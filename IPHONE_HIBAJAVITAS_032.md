# ÓraNapló 0.3.2 – HealthKit és Google hibajavítás

## Mit igazolnak a 4 iPhone-os .ips naplófájl?

- HealthKit: `HKHealthStoreImplementation _validateHealthDataPurposeStringsForSharingTypes` alatt Objective-C kivétel (SIGABRT), a pulzusteszt engedélykérésekor. Az Apple által előírt *Info.plist* leírások vagy az aláírás miatt jelenhet meg. A pontos kivételszöveg az `.ips` fájlokból nem derül ki.
- Google: `GIDSignIn signInWithOptions` Objective-C kivétel. A 0.3.1 már kiírja az URL-séma eltérését a felületen.
- A telepített iPhone-alkalmazás azonosítója a Sideloadly után: `hu.oranaplo.ios.5876FYKDK7`. Ez eltér az eredeti `hu.oranaplo.ios` azonosítótól.

## Mi változott?

- A HealthKit-hívás egy kis Objective-C hídból fut, amely a konfigurációs NSException-t *hibaüzenetté* alakítja. Nem kerüli ki az Apple jogosultságait.
- Az iPhone alkalmazás **telepített** Info.plistjének leírásait előre ellenőrzi.
- A Google OAuth-ban a külön `ios_bundle_id` mezővel megadható a tényleges, Sideloadly által telepített Bundle ID.
- A diagnosztikában láthatók az App ID, HealthKit-leírások és Google URL-sémák.
- A `tools/verify_ipa.py` a buildelt, de még **aláíratlan** IPA-ba csomagolt Info.plistet ellenőrzi.
- A GitHub-feltöltő már a `.m`/`.h` Objective-C forrásokat is viszi.

## Telepítés

1. A *HIBAJAVITAS.zip* tartalmát csomagold a meglévő `OraNaplo-iOS-Windows` mappába, a régi fájlok felülírásával. **Ne töröld a mappád, és ne írd felül a saját `google_oauth.json` fájlodat.**
2. A Google-fiókos próba előtt a Google Cloud Console-ban hozz létre egy **iOS** OAuth-klienst a jelenleg *telepített* Bundle ID-hez, pl. `hu.oranaplo.ios.5876FYKDK7`. Az App ID suffix újratelepítéskor változhat.
3. Frissítsd a helyi `google_oauth.json` fájlt: `{"ios_client_id":"<ÚJ_iOS_CLIENT_ID>.apps.googleusercontent.com","ios_bundle_id":"hu.oranaplo.ios.5876FYKDK7"}`. Az OAuth client ID nyilvános azonosító, ne adj meg client secretet.
4. Futtasd a `01_WINDOWS_ELOKESZITES.bat`, majd a `02_FELHOS_IPA_EPITES.bat` fájlt.
5. Sikeres fordítás után a `03_SIDELOADLY_MEGNYITAS.bat` segítségével telepítsd az új IPA-t **ugyanazzal az Apple ID-val**, a meglévő alkalmazás felülírásával, ha lehetséges.
6. A friss alkalmazásban nézd meg a Diagnosztika részt. Először Google, majd HealthKit pulzusteszt; csak utána teljes engedélyezés.

**Ha a HealthKit továbbra sem működik:** az új verzió várhatóan a kivétel valódi indokát szövegesen írja ki. Másold ki a diagnosztikát. Amennyiben az ingyenes Sideloadly által készített aláírásból hiányzik a HealthKit-entitlement, azt programkód nem tudja megadni: megfelelő Apple provisioning/signing szükséges.

**Ha a Google továbbra sem működik:** ellenőrizd, hogy a telepített App ID, `ios_bundle_id` és a Google iOS OAuth kliens Bundle ID-je egyeznek-e. Ha a Sideloadly új App ID-t ad, új OAuth-klienst vagy stabil aláírási folyamatot kell beállítani.

**Biztonság:** a logokba, GitHubra ne tölts fel személyes egészségadatot, Google access tokent, jelszót, privát kulcsot vagy client secretet.

## Amit itt tesztelni lehetett / nem lehetett

- Fájlstruktúra, Python tesztek, Swift parszolás és a konfigurációgenerátor működése tesztelhető.
- Az iOS SDK és az Apple aláírás nincs jelen Windows/Linux alatt; a tényleges Xcode-fordítást és iPhone-tesztet külön kell futtatni.
