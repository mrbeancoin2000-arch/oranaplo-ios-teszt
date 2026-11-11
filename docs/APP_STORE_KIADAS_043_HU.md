# ÓraNapló 0.4.3 – Apple-előfizetés, egészségügyi tájékoztatás, adatvédelem

**Fejlesztői előkészítés, nem beküldött vagy jóváhagyott App Store-alkalmazás.** Frissítés: 2026. november 11.

## 1. Mi készült el most?

- SwiftUI alkalmazáson belüli **Adatvédelem és feltételek** oldal magyarul, angolul és németül, offline is elérhető a Beállításokból és a Pro-előfizetés melletti gombbal.
- Kötelező előfizetési tájékoztatás: éves időszak, automatikus megújulás, teljes, az Apple által megjelenített ár, az Apple előfizetéskezelőjének linkje, vásárlás visszaállítása.
- Nyilvános megjelenésre **előkészített, de még NEM publikálható** háromnyelvű Cloudflare Pages-weboldal a `website/` mappában. Minden nyelvhez külön adatvédelmi, felhasználási feltételek és támogatási oldal.
- `ReleaseLinks.swift` konfigurálható HTTPS-cím. Amíg nincs valódi weboldalcím, az app nem mutat kitalált külső linkeket.
- `tools/release_preflight.py` szigorú ellenőrzés, amely letiltja a kiadásra kész állapot megjelölését hiányzó kapcsolati adatok, HTTPS-hivatkozás vagy ellenőrizetlen kiadási követelmények esetén. A ténylegesen elvégzett Apple-feladatokat a `release_manifest.json` mezőiben külön jelölheted. A kapcsolók kézi állítása NEM helyettesíti a valódi ellenőrzést.

## 2. Amit az Apple Developer-tagság aktiválása után te végzel az App Store Connectben

1. Lépj be: https://appstoreconnect.apple.com/ . **Business → Agreements → Paid Apps → View and Agree to Terms**. Az Account Holder fogadhatja el.
2. Ugyanitt töltsd ki a kért **Tax Forms** és **Banking** részeket, az Apple tényleges felületének megfelelően. A jogi/adózási részletek kitöltését te intézed. Számlaadatokat, személyes azonosítókat vagy titkos kulcsokat NE küldj el chatben / a nyilvános GitHub-repóban.
3. Apple Developer → Certificates, Identifiers & Profiles: hozz létre végleges App ID-t `hu.oranaplo.ios` az **HealthKit** capabilityvel. Ehhez illeszkedő provisioning profile és tanúsítvány kell. A Sideloadly módosított bundle ID-ja nem használható éles alkalmazáshoz.
4. App Store Connect → My Apps → `+` → New App. Név: ÓraNapló; iOS; végleges bundle ID; a letöltési ár legyen **Free**.
5. Az alkalmazásnál **Subscriptions → Create Subscription Group**: reference name `ÓraNapló Pro`. Ugyanebben a csoportban új **Auto-Renewable Subscription**, Product ID: `hu.oranaplo.pro.yearly`, duration: **1 Year**, reference name például `ÓraNapló Pro Annual`.
6. Magyarországi kezdőár: a rendelkezésre álló árszintek közül válaszd az **1 000 Ft-os** végfelhasználói árat, ha létezik. Más országokban külön árak. Soha ne állítsunk be az appban rögzített euróárat. Nincs bevezető ingyenes próba alapértelmezésben.
7. Töltsd ki mindhárom nyelven a termék nevét és leírását az alábbi szövegek alapján. Add hozzá a kért App Review screenshotot a vásárlási képernyőről, amelyen a valódi StoreKit-ár látszik.
8. Egyesítsd a megfelelően aláírt iOS-buildet az Apple-fiókkal. A jelenlegi GitHub Actions **unsigned teszt-IPA-t** készít; a fizetős tagság után külön kell elvégezni az aláírás és TestFlight-feltöltés fejlesztését.
9. **StoreKit Sandbox / TestFlight** tesztek: sikeres vásárlás, elutasított/pending, lejárat, visszatérítés/revokáció, visszaállítás, újratelepítés és automatikus megújulás. Figyeld, hogy lejárt jogosultságnál csak a pulzus kerüljön exportálásra.
10. **Small Business Program**: az Apple követelményeinek megfelelő fiókkal külön jelentkezz itt: https://developer.apple.com/app-store/small-business-program/ . A 15%-os jutalék nem automatikus és jogosultsághoz kötött.

### App Store Connect lokalizációs szövegek

| Nyelv | Display name | Description |
|---|---|---|
| Magyar | ÓraNapló Pro – Éves | Részletes Apple Egészség-export a saját Google Sheets-táblázatodba, HRV, edzések és előzmények. Éves, automatikusan megújuló előfizetés. |
| English | ÓraNapló Pro – Annual | Export additional Apple Health data, HRV, workouts and history to your own Google spreadsheet. Automatically renewing annual subscription. |
| Deutsch | ÓraNapló Pro – Jährlich | Weitere Apple-Health-Daten, HRV, Trainingsdaten und Verlauf in die eigene Google-Tabelle exportieren. Automatisch verlängerndes Jahresabo. |

## 3. Weboldal, adatok, Apple App Privacy

1. Nyisd meg a `website/hu/privacy.html`, `website/en/privacy.html`, `website/de/privacy.html` és a többi sablont.
2. Cseréld le a **szögletes zárójeles helyőrzőket** a tényleges adatkezelő nevére, valós kapcsolattartási címre, támogatási e-mailre. A kötelező adatvédelmi információkat szükség szerint bővítsd és ellenőriztesd.
3. Cloudflare Pages → új projekt → static assets: töltsd fel a `website` mappa **tartalmát**. Nem kell Supabase a statikus oldalakhoz. Ellenőrizd a publikus HTTPS-elérést minden nyelven.
4. Az `ios/Sources/ReleaseLinks.swift` `websiteRoot` mezőjébe írd a tényleges HTTPS-gyökércímet, például a saját Cloudflare Pages-domainedet. Újrafordítás után a linkek megjelennek az appban.
5. App Store Connect → App Privacy → Privacy Policy URL: `https://[TENYLEGES-DOMAIN]/hu/privacy.html` (több nyelvi lokalizációval). Az app adatkezelési kérdőívét a **tényleges SDK-k és adatáramlások alapján** töltsd ki, NE válaszd automatikusan a „nem gyűjt adatot” választ.
6. App Store Connect → App Information → szükséges támogatási link, Terms of Use link és az előfizetés megjelenítési adatai. Apple szabványos EULA használható, ha illik a termékhez; a saját feltételeket külön is közzéteheted.
7. EU DSA kereskedői státusz: az Apple felületén állítsd be a valós státuszodat. Ha kereskedőként jelenik meg a profil, az Apple **nyilvános cím / P.O. Box, telefonszám, e-mail** adatokat kérhet. Ez nem egyenlő az adózási forma kiválasztásával.

**Adatvédelmi korlátok, amelyeket őszintén közöljünk:** a helyi queue egészségadatokat tarthat, a Google-fájlt az app eltávolítása nem törli, az Apple-előfizetést az app eltávolítása nem mondja le, a HealthKitben törölt minta korábbi exportja nem mindig tűnik el Google Sheetsből. A jelenlegi szinkron még **nem garantál pontosan egyszeri feltöltést** hálózati hiba után: ezt az éles kiadás előtt javítani kell.

## 4. Egészségügyi megfigyelések – termékbiztonsági szabályok

- A vérnyomás csak ténylegesen Apple Egészségbe rögzített külső eszközös / kézi érték lehet; az Apple Watch **nem** vérnyomásmérő.
- Az app nem diagnosztizálhat betegségeket vagy ígérhet állandó vészhelyzeti riasztást. Minden jelzéshez látszódjon a mérés időpontja és a forrás.
- Lépésszám: az egyéni korábbi adatokhoz viszonyító mintázatot jelezzen, nem általános „beteg vagy” figyelmeztetést.
- Vízbevitel: csak akkor értékelhető, ha a felhasználó külön megerősítette, hogy minden ital naplózva van; a nullás napló nem nulla ivás.
- Értékelési küszöbök, szövegek, kritikus esetek és a korcsoportos eltérések szakmai felülvizsgálatát, biztonsági és téves riasztási tesztjeit az éles megjelenés előtt el kell végezni.
- Előfizetéshez kötött funkciók nem kerülhetik meg az Apple App Review szabályait; a jelenlegi lokális megfigyelések ingyenesek, a Pro-export korlátozott.

## 5. Mitől NEM kész még a kiadás?

- Nincs elfogadott Paid Apps Agreement, banki és Apple által kért adatok, élő StoreKit termék.
- Nincs publikált ellenőrzött adatvédelmi és ügyfélszolgálati oldal valós kapcsolati adatokkal.
- Nincs hiteles App Store Distribution aláírás és TestFlight-validáció.
- A HealthKit engedélykérés a jelenlegi Sideloadly-telepítésben nem működik.
- Nincs végigtesztelt import, törlés-szinkron és duplikációvédelmi igazolás.
- Nincs Apple App Review vagy Google OAuth nyilvános működés igazolása.

## Hivatalos Apple-dokumentációk (2026. novemberi ellenőrzés)

- https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/
- https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information/
- https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information/
- https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/
- https://developer.apple.com/app-store/subscriptions/
- https://developer.apple.com/app-store/small-business-program/
- https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/
- https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/
- https://developer.apple.com/app-store/review/guidelines/

## 6. Kiadás előtti kapu

A `release_manifest.json` mezői **kezdetben mind `false` állapotúak**. Csak akkor állíts egy mezőt `true`-ra, ha azt valóban elvégezted és ellenőrizted a megfelelő szolgáltató rendszerében. `python tools/release_preflight.py --strict` hibával kilép, amíg marad kiadási akadály. Ez nem App Store-jóváhagyás, hanem saját ellenőrző lista.
