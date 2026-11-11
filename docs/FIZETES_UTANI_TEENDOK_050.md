# ÓraNapló – a fizetős Apple-tagság aktiválása utáni lépések

1. Aktiváld az Apple Developer Program egyéni tagságát. Ellenőrizd az App Store Connect hozzáférését.
2. Apple Developer → Identifiers: explicit `hu.oranaplo.ios` App ID. Engedélyezd a HealthKitet és a HealthKit Background Delivery jogosultságot, ahol támogatott; ezeknek az aláírt IPA entitlements részében is szerepelniük kell.
3. App Store Connect → Agreements/Business: Paid Apps Agreement, banki és Apple által kért adminisztratív adatok. Ezeket biztonságosan kizárólag az Apple felületén add meg.
4. Small Business Program: külön jelentkezés, ha jogosult vagy. A kedvezmény nem automatikus.
5. App Store Connect → Apps → New App, iOS, appnév ÓraNapló, explicit bundle `hu.oranaplo.ios`, Free letöltés.
6. Monetization → Subscriptions: csoport `ÓraNapló Pro`, termék `hu.oranaplo.pro.yearly`, automatikusan megújuló 1 Year. Magyarországi ár: 1 000 Ft, ha az elérhető árszintek között választható. Három nyelvű leírás, screenshot és felhasználási feltételek szükségesek.
7. Google Cloud → Auth → Clients: készíts iOS OAuth klienst `hu.oranaplo.ios` azonosítóval, frissítsd `google_oauth.json`-t, futtasd `01_WINDOWS_ELOKESZITES.bat`, ellenőrizd a callback URL-sémát. Google OAuth élesítés és szükséges ellenőrzés külön folyamat.
8. GitHub Actions éles aláírásra átállítása: Apple Distribution/Developer tanúsítvány, provisioning profil, kulcsok GitHub Secrets-ben. Soha ne commitolj privát kulcsot, `.p12`, `.p8`, `.mobileprovision` fájlt.
9. Valódi iPhone-on HealthKit-jogosultsági képernyő, pulzus és HRV mérések, 100m GPS-edzések, háttérszinkron, repülőgépmód, újraindítás és adatok visszatöltése. Minden eltérést naplózni és kijavítani.
10. App Store Connect Sandbox tesztfiókokkal évi Pro vásárlás, lejárat, megújulás, lemondás, visszatérítés, Restore Purchases. Az offline `.storekit` tesztet nem szabad éles bizonyítéknak tekinteni.
11. TestFlight 10–20 valódi tesztelővel, minimum többnapos szinkron és több Google-fiók. Adatvesztési és jogosultságkezelési hibával nem szabad kiadni.
12. Publikus Cloudflare-adatvédelmi, felhasználási és support oldalak **valós URL-lel, kitöltött elérhetőségekkel**. App Privacy/DSA és Apple Review Notes megfelelő kitöltése.
13. Az első előfizetést az alkalmazás verziójával együtt küldd Apple review-ra. Sikeres jóváhagyás után megjelenés. Bevételek: Apple App Store Connect Payments and Financial Reports.
14. Minden megerősített esemény után csak a megfelelő `release_manifest.json` jelzőt módosítsd true-ra. `python tools/release_preflight.py --strict` addig szándékosan hibát ad, amíg hiányoznak a kötelező éles előfeltételek.

**Figyelmeztetés:** az 1000 Ft/év csak a célár; a végleges országonkénti árszintet az Apple adja. A háttérfutás időpontja továbbra sem garantált. Az alkalmazás nem orvosi diagnosztikai eszköz.
