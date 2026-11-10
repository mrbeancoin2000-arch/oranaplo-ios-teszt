# ÓraNapló – iPhone-os összeomlások diagnosztikai javítása

## Mit változtat?

- A Google-bejelentkezés előtt ellenőrzi a konfigurált iOS OAuth kliensazonosítót, a bejegyzett visszahívási URL-sémát és az app telepítés utáni Bundle ID-ját. Ezek eltérése esetén a Google SDK meghívása helyett magyar hibaüzenetet mutat (az SDK egyes hibákra Objective-C kivételt dob, amelyet egy sima Swift `do/catch` nem kezel).
- Az Info.plist most a `GIDClientID` kulcsot is tartalmazza, amelyet a `tools/configure.py` generál a saját `google_oauth.json` fájlodból.
- A HealthKit teszt két lépcsős: előbb **csak pulzus**, majd ha az működött, **teljes engedélykérés**. Így elválasztható a hiányzó aláírási jogosultság egy adatkategória specifikus hibájától.
- Az app elmenti az utolsó művelet nevét és megjeleníti a Diagnosztika résznél. Nem naplóz egészségméréseket, Google tokent vagy jelszót.
- A Sheets-szinkron a teljes engedélykérés lefutása előtt le van tiltva.

## Telepítés Windows alatt

1. Készíts biztonsági másolatot a `OraNaplo-iOS-Windows` mappádról.
2. E ZIP-ben az `ios/Sources` és `tools` mappákat másold a projekted azonos mappáiba, a meglévő fájlokat írd felül. A saját `google_oauth.json` fájlodat **ne töröld** és **ne töltsd fel sehová**.
3. Futtasd a `02_FELHOS_IPA_EPITES.bat` fájlt. A BAT a Google OAuth beállításaidból ismét előállítja az Info.plistet, majd elindítja a felhőbeli Xcode-buildet.
4. A sikeres IPA-t Sideloadly segítségével, **ugyanazzal az Apple-fiókkal és Bundle ID-val** telepítsd, lehetőleg a korábbi telepítés felülírásával. Ha Sideloadly megváltoztatja a Bundle ID-t, a Google OAuth kliensazonosítóval való eltérés hibaüzenetben látható lesz.
5. Először a **Google-fiók csatlakoztatása** gombot teszteld. Ha nem lép ki az app, olvasd el a Rendszerállapot kártyát. Ezután az **Apple Egészség alapteszt (pulzus)** gombot próbáld ki. Ha sikerül, tesztelheted a teljes jogosultságkérést.

## Ha ismét kilép az alkalmazás

1. iPhone: Beállítások → Adatvédelem és biztonság → Elemzések és fejlesztések → Elemzési adatok (az elnevezések iOS-verziótól függhetnek).
2. Keresd a legfrissebb `OraNaplo-...ips` vagy az ÓraNapló alkalmazás Bundle ID-jával kezdődő naplót; a kilépés időpontja segít.
3. A Megosztás menüvel mentsd a naplót, és küldd el. **Ellenőrizd, tartalmaz-e számodra érzékeny adatot**, mielőtt megosztod.
4. Alternatíva Windows alatt: `Win+R` → `%APPDATA%\Apple Computer\Logs\CrashReporter\MobileDevice` (ha a számítógéped már letöltött iPhone-crashnaplókat).
5. Mondd meg, melyik gombra nyomtál (Google / Health alapteszt / Health teljes), és hogy a kilépés azonnali volt-e.

## Ismert korlát

A HealthKithez az Apple által jóváhagyott, a ténylegesen aláírt alkalmazásban jelen lévő `com.apple.developer.healthkit` entitlement szükséges. Egy aláíratlan IPA Xcode-buildje ettől még sikeres lehet. Az ingyenes Sideloadly-aláírás nem garantálja a HealthKit-entitlementet; ezt **nem lehet kóddal megkerülni**. A javítás önmagában nem garantálja a HealthKit működését.

Hivatalos dokumentáció:
- https://developer.apple.com/documentation/xcode/configuring-healthkit-access
- https://developers.google.com/identity/sign-in/ios/start-integrating
- https://developer.apple.com/documentation/bundleresources/diagnosing-issues-with-entitlements
