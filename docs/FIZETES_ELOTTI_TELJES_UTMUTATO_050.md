# ÓraNapló 0.5.0 – Mit ellenőrzünk a 99 USD-os Apple-tagság előtt?

## A. Folyamatos, valós tesztnaplók Windows alatt

- Csomagold ki a teljes ZIP-et, indítsd `05_FIZETES_ELOTTI_TESZTEK.bat`.
- A `logs/prepayment_<idő>/JELENTES.html` megnyitható böngészőből; `RESULT.json` alkalmas automatizált ellenőrzésre; minden tesztnek külön `.log` állománya van.
- Ha van Node.js, az Apps Script szabályok JavaScript-futtatással tesztelődnek; ha nincs, SKIPPED, nem PASS.
- A Windows általában nem tartalmaz Swift fordítót. Ilyenkor a Swift-fordítás és a valós Swift-algoritmusteszt Windows alatt SKIPPED, külön macOS CI-ben kötelező.
- Az audit nem kér Apple, Google jelszót, nem kér be egészségadatokat, és nem küld adatot saját szerverünkre.

## B. Kötelező Xcode-szimulátorfordítás a GitHub felhőjében

1. GitHubon a forráskódot szinkronizáld a korábbi projekteddel; a ZIP `.github/workflows/prepayment-macos-ci.yml` fájljának is fel kell kerülnie.
2. GitHub → **Actions** → **Prepayment audit + unsigned iOS simulator build** → **Run workflow**.
3. Várd meg a sikeres zöld futást. Ha piros, az **OraNaplo-050-prepayment-evidence** artifact `xcodebuild-simulator.log` naplóját nézd meg; a programot addig nem tekinthetjük fordíthatónak.
4. A CI a Python-tesztek mellett valódi Swift-módon futtatja az XML- és GPS-algoritmust, majd **iPhone szimulátorhoz az Apple SDK-val** fordítja az alkalmazást. Aláírást és HealthKit-hozzáférést ez még nem tesztel.
5. A régi `macos-ipa.yml` változat továbbra is aláíratlan teszt-IPA-t készít. Az új CI külön teszt, nem éles terjesztés.

## C. Valódi egészségadatok kézi importja az alkalmazásban

1. iPhone → **Egészség** → profil → **Összes egészségadat exportálása**.
2. A keletkezett ZIP-et a Fájlok alkalmazásban csomagold ki, keresd meg az `export.xml` fájlt.
3. ÓraNapló → Google-fiók csatlakoztatása → Google Sheets létrehozása → **Mérések** → **Apple Egészség XML-import** → válaszd az `export.xml` fájlt.
4. Ingyenes módban csak a nyers pulzusmérések kerülhetnek a Google Sheets `Pulzus` munkalapjára. A többi rekord kihagyásra kerül. Aktív, ellenőrzött Pro-előfizetés nélkül nem használható a Pro-XML-export sem.
5. A teljes export kényes adat: ne töltsd fel nyilvános repóba, chatbe vagy weboldalra. A saját fájloddal történő tesztet a felhasználónak kell a telefonján elvégeznie.
6. A teszt után vizsgáld meg a sorok számát, mérési időpontokat, egységeket, és futtasd újra ugyanazt az importot. A második import nem eredményezhet duplázást. Internetkimaradás után vizsgáld meg a táblázatot és a helyi várakozási számot.

**Korlát:** az Apple Egészség XML minden rekordjánál nem garantált a szabványos egység és GPS-útvonal. Csak a támogatott rekordtípus és egység menthető; a teljes edzésútvonalat ez nem pótolja.

## D. StoreKit 2 – helyi előfizetési teszt Apple Developer-tagság nélkül

A `tests/storekit/OraNaplo_Annual_Offline.storekit` fájl a tervezett éves Pro terméket írja le: `hu.oranaplo.pro.yearly`, `P1Y`, három nyelvi változat. Ez **helyi tesztadat**, nem élő Apple-termék.

Ha Xcode-hoz férsz hozzá (például GitHubon készített Xcode-projektet macOS-en megnyitva): Xcode: a fájlt előbb add hozzá a generált Xcode-projekthez (File → Add Files to Project), majd Scheme → Edit Scheme → Run → Options → StoreKit Configuration → válaszd a `.storekit` fájlt. Tesztelhető a fizetési képernyő és a helyi tranzakció-életciklus. Az itt beírt `1000` tesztösszeg **nem állítja be az éles magyar App Store-árat**, azt később App Store Connectben kell kiválasztani.

A jelenlegi Windows + GitHub buildből **nem tudunk valódi Apple StoreKit-vásárlást lefolytatni**. A termékazonosító és a StoreKit-kód csak lokálisan ellenőrizhető.

## E. Adatvédelem, felület és Google

- A `website/hu`, `website/en`, `website/de` oldalak vázlatok. Közzététel előtt valódi elérhetőség, adatkezelés és URL szükséges.
- A `google_oauth.json` korábban Sideloadly-os Bundle ID-val működött. **Az éles iOS Bundle ID `hu.oranaplo.ios`**, ehhez még új Google OAuth iOS-kliens kell.
- A helyi napló `CrashCheckpoint` legfeljebb 80 műszaki eseményt tart, és egyszerű e-mail/token kitakarást végez. Nem alkalmas érzékeny exportfájlok közzétételére; elküldés előtt nézd át.
- A HealthKit observer és background entitlement **csak forrásfájlban van**; telepített, ténylegesen aláírt alkalmazás kell az engedély ellenőrzéséhez.

## F. Fizetés előtti döntési kapu

1. Python unit: PASS.
2. Node Apps Script: PASS, vagy ha nincs telepítve: SKIPPED, macOS CI-ben kötelező.
3. Swift XML + GPS futásidő: PASS macOS CI-ben.
4. Valódi iOS Simulator Xcode-build: PASS GitHub Actionsban.
5. Google Sheets saját tesztfiókkal kipróbálva, nincs adatkavarodás, ismételt import nem dupláz.
6. Háromnyelvű felület emberi ellenőrzése, nem csak kulcsegyezés.

Ha ezekből egy fontos ellenőrzés nem sikerült, ne állítsd az alkalmazásról, hogy kész. A 99 USD akkor indokolt, amikor az Apple-aláírásos HealthKit- és Sandbox-vásárlási tesztelés az egyetlen lényegi akadály.
