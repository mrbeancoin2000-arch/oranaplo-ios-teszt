# ÓraNapló 0.6.1 — teljes, bizonyítékalapú tesztelési terv

**Állapot: fejlesztői tesztjelölt, NEM kész App Store-alkalmazás.** A ZIP tartalmazza az iOS/watchOS forrását, offline ellenőrzéseket és a tesztjegyzőkönyvet. A `0.6.1` nem jelent átment Apple SDK-buildet, valódi egészségadatokkal elvégzett ellenőrzést vagy publikálható aláírást. A kötelező külső teszteket nem lehet helyi kóddal helyettesíteni.

## 0. Biztonságos indulás Windowsról

1. Készíts másolatot a korábbi `OraNaplo-iOS-Windows` mappádról, különösen a `google_oauth.json` konfigurációról. A korábbi teszt-IPA telepítése vagy az app letörlése előtt **mentsd el az eredeti Google Sheets-azonosítót**, és ne töröld a korábbi helyi adatokat.
2. Csomagold ki az új ZIP-et egy **új mappába**, ne írd felül a régit, amíg az új kiadás nem felel meg az ellenőrzéseknek.
3. Ellenőrizd: `google_oauth.json` tartalmazza a saját **iOS Client ID**-dat és a `hu.oranaplo.ios` Bundle ID-t. A `google_oauth.json` nem kerül GitHubra. Semmilyen Google-jelszót, access tokent, privát Supabase/Resend kulcsot, valódi pulzusadatot, GPS-útvonalat nem szabad a GitHub projektbe tölteni.
4. A GitHub-teszt előtt ellenőrizd, hogy a tárhelynek van-e **privát** alternatívája: az eredeti `00_MINDENT_INDIT.bat` jelenleg egy **nyilvános** repót is létrehozhat, és csak az általad jóváhagyott kódot tölti fel. Ha a nyilvános megosztást nem akarod, **ne indítsd ezt a BAT-ot**; előbb kézzel hozz létre privát repót és manuálisan töltsd fel a biztonságos projektfájlokat.
5. A projekt gyökerében: `python -m unittest discover -s tests -p "test_*.py" -v`; `node --test tests/test_057_support_policy.mjs`; `python tools/qa_status.py`. Utóbbi a **nem igazolt** feladatokat is kiírja.

## 1. Kötelező iOS + watchOS Xcode fordítás (fizetés előtt)

Mac esetén: telepítsd az Xcode-ot és a Homebrew + XcodeGen eszközt. A projekt gyökerében:

```bash
brew install xcodegen
xcodegen generate --spec project.watch.yml
bash tools/ci_xcode_build.sh simulator
bash tools/ci_xcode_build.sh watch
```

Windows esetén: a saját GitHub-repóban **Actions → Prepayment audit + unsigned iOS simulator build → Run workflow**. A frissített workflow az **iOS-szimulátor és watchOS-szimulátor fordítását egyaránt kötelezővé teszi**. Az `iOS unsigned IPA (teszt)` workflow is a watchOS-célt használja, a Watch fordítása blokkoló. GitHub **Actions → megfelelő futás → Artifacts** alatt nyisd meg: `xcodebuild-simulator.log`, `xcodebuild-watchsimulator.log`, `prepayment-run.log`, `RESULT.json`. **Elfogadási feltétel:** mindkét build sikeres, nincs `error:`, és a futtatott tesztek PASS állapotúak. Az aláíratlan IPA nem tekinthető App Store-kiadásnak; a tényleges embedded Watch app jelenlétét is ellenőrizni kell a kiadásjelöltben.

**Ha hiba van:** NE vásárolj tagságot pusztán a javításhoz. Küldd el a két teljes Xcode-buildnaplót (titkok/azonosítók kitakarásával). Az aktuális csomag helyben nem volt Apple SDK-val lefordítható, mert nincs Xcode ezen a gépen.

## 2. Google bejelentkezés új tesztfelhasználóval

1. Google Cloud Console → új vagy meglévő projekt → **Google Sheets API** és a fájlkereséshez **Google Drive API** engedélyezése.
2. Google Auth Platform → Branding, Audience, Data Access: iOS OAuth Client ID, Bundle ID = `hu.oranaplo.ios`; teszt felhasználókhoz hozzáadni a külön **teszt-Google-fiókot**. A Google által megjelenített alkalmazásellenőrzési kéréseket a valódi publikálás előtt rendezni kell.
3. Telepítsd a sikeresen lefordult és megfelelően aláírt appot. Jelentkezz be új Google-fiókkal; engedélyezd a `drive.file` hozzáférést. Hozz létre egy új Sheetset az appból.
4. Ellenőrizd a Google Drive-ban: a létrehozott `ÓraNapló – Egészségadatok` fájl a tesztfióké, a megnyitás ugyanahhoz a fájlhoz tér vissza. Jelentkezz ki, jelentkezz be másik tesztfiókkal: az előző fiók fájlja **nem nyílhat meg**, az adatai **nem töltődhetnek fel másik fiókba**. Az első fiókba visszalépve a régi azonosítót kell visszakapni.
5. Szándékosan utasítsd el az OAuth-scope-ot, majd próbálj újra belépni; az app nem omolhat össze és nem írhat hamis sikert. Teszteld megszakított Google-bejelentkezéssel is.

## 3. Valódi HealthKit iPhone + Watch, kizárólag saját teszthez

1. Csak **saját** egészségadatokkal tesztelj. iPhone: Apple Egészség alkalmazás → Profil → Alkalmazások és szolgáltatások / Adathozzáférés (iOS-verziótól függ a menü) → ÓraNapló. Engedélyezd a kívánt **olvasási** típusokat: pulzus, HRV SDNN, edzés, lépések stb. A Read-jogosultság megtagadása nem feltétlenül állapítható meg egyértelműen API-n; a hiányzó minta nem automatikusan programhiba.
2. Az Egészségben keress három valós pulzusmérést és legalább egy HRV-értéket a tényleges dátummal. Az app és a Google Sheet időpontjának/értékének kell megfelelnie. A Free mód **csak a Pulzus típus feltöltését** teszi lehetővé; a Pro működését helyi StoreKit tesztben lehet modellezni.
3. Ellenőrizd: nincs megalapozatlan orvosi diagnózis vagy téves sürgősségi riasztás, az órán nem támogatott szenzorhoz az app nem talál ki adatot, az időzóna egyezik. A HealthKit-háttérébresztés iOS-től függ: nem garantál perces, folyamatos mérést vagy feltöltést.
4. Airplane mode / Wi-Fi leállítás / újraindítás / iPhone zárolás mellett a feltöltési sor nem tűnhet el. Az Apple Egészség adatai külön változatlanok maradnak.

## 4. Legalább 7 nap adatmentési próba (valóban ki kell várni)

Minden nap **reggel és este**: nézd meg az Egészségben az utolsó elérhető pulzus és HRV mintát; futtasd a szinkront; nyisd meg a saját Google Sheetset; írd be a *tesztjegyzőkönyvbe* a minták számát, a várakozó sorok számát, utolsó sikeres időpontot és a hibakódot, de **ne másold ki nyilvánosan a pulzusértékeidet**. Legalább egyszer okozz hálózatkimaradást, egyszer zárd le hosszabb időre a telefont, egyszer indítsd újra, és egyszer térj vissza az apphoz több nap után. A mérések időpontjai és az egyedi ID-k maradjanak konzisztensen meg, az elutasított engedély és a nem létező minták nem számítanak elveszett adatnak.

A `docs/QA_061/NAPI_SZINKRON_NAPLO.csv` sablonban 7 nap × 2 ellenőrzésre előkészített sorok vannak. Ne igazolj „7 napos PASS” állapotot az első nap végén.

## 5. Google Sheets duplikációmentes import és megszakítás utáni helyreállítás

1. Egy **tesztfiókban** készíts elő sok — lehetőleg 10 000+ — szintetikus Apple Health XML-rekordot, vagy importálj saját korábbi exportot, ha a privát Google Sheetset használod. A nyilvános CI-be csak **szintetikus** adat kerülhet.
2. Importáld ugyanazt a fájlt kétszer. A Sheets megfelelő lapjának **A oszlopában** az `id`-k mindegyike egyszer fordulhat elő. Kisebb teszttáblában képlettel ellenőrizheted: `=COUNTA(A2:A50000)` és `=COUNTUNIQUE(FILTER(A2:A50000;A2:A50000<>""))` (lokális függvényelválasztó változhat). A két számnak egyeznie kell.
3. Szimulálj bizonytalan feltöltést: a futó szinkron közben kapcsold ki a hálózatot, azonnal kapcsold vissza, és indíts új szinkront. Nem szabad vakon duplán feltöltenie; előbb a távoli A oszlopot ellenőrzi. A sorok nem veszhetnek el helyi fájl sérülése miatt (a sérült queue jelenleg hibát jelez; nincs garantált automatikus helyreállítás minden helyzetből).
4. Jelentkezz ki és vissza, majd importáld újra ugyanazt az XML-t. A frissített 0.6.1 már a korábbi Google Spreadsheet ID-hez is tárol előzetes egyeztetés jelölést. A lejárt Pro alatt a várakozó fizetős sorok helyben maradnak, de nem tölthetők fel, amíg nincs újra igazolt jogosultság.
5. **Óvatosan:** valódi egészségadataidat soha ne használd nyilvános GitHub-tesztmintának. Ne töröld az eredeti Google Sheetset vagy az appot az adatmentési próba közben.

## 6. GPS-edzés lezárt iPhone-nal

1. iPhone beállítások → ÓraNapló → Helyzet: az app számára engedélyezett, **Pontos helyzet** bekapcsolva, Helymeghatározás rendszerszinten aktív. Először **nyisd meg az appot, és az iPhone-on indítsd el a futást**, csak utána zárd le a készüléket. A `UIBackgroundModes: location` és a `allowsBackgroundLocationUpdates=true` szerepel a projektben.
2. Kültéren futtass legalább 15–20 perces próbaedzést. Képernyő lezárás, zsebbe tétel, Wi-Fi megszakadás közben ellenőrizd: megtett útvonal, idő, 100 m szakaszok, megfelelő szünet és folytatás, mentés, GPX-export. A 100 m pontosság GPS-függő, ezért reális hibahatáron belül és hibás GPS-pontok kihagyásával értékeld.
3. Futás közben indíts újra egy appot / szimulálj megszakítást. Az ÓraNapló nem indít magától új GPS-edzést: megszakított, szüneteltetett állapotból **kézzel** folytatható. Túl régi / pontatlan koordináták nem számolhatók bele új szakaszba.
4. Külön mérd normál és energiatakarékos módban; iPhone kijelzőzár nem ugyanaz, mint az app kényszerített bezárása. **A Watchról indított futás önmagában nem garantál iPhone-GPS rögzítést, ha a telefon app nem tud futni.** Ez jelenleg ismert funkcionális korlát.

## 7. Apple Watch edzés és iPhone szinkron

1. A **watchOS alkalmazásnak valóban meg kell jelennie az órán** a megfelelően aláírt, Watch companiont tartalmazó buildből. Ellenőrizd a Watch app HealthKit jogosultságát.
2. Indíts edzést az órán, mérj pulzust, távot, időt. Párosított és elérhető iPhone mellett látszik-e az élő adat? A WatchConnectivity valós idejű `sendMessage` csak elérhető kapcsolatnál működik.
3. A próba felénél kapcsold ki a telefon kapcsolatát, fejezd be az órán az edzést, majd állítsd vissza a kapcsolatot. A 0.6.1 `transferUserInfo` mechanizmusa a végső összesítést sorban küldi; az iPhone oldala `id` szerint kihagyja az ismételt összesítést. **Ez nem helyettesíti a teljes GPS-útvonal / összes pulzusminta utólagos átvitelét**, az külön fejlesztési és eszközös tesztfeladat.
4. Ellenőrizd, hogy a tényleges Watch edzés az Apple Egészségben egyszer szerepel, és nem keveredik az iPhone-on külön elindított GPS-edzéssel.

## 8. Supabase-ranglista jogosultságok

1. Supabase → Authentication → **Anonymous Sign-ins** bekapcsolása; SQL Editorban futtasd a `supabase/01_leaderboard.sql` fájlt. Az `ios/Resources/leaderboard_config.json` fájlban CSAK a Supabase **publishable/anon** kulcsot add meg; `service_role`, `secret` és Resend privát kulcs **soha** ne kerüljön az iOS-kódba/GitHubra.
2. Hozz létre két külön **tesztfelhasználót** (külön anon JWT), A és B. A közzétesz egy tesztsort, B lekérdezi; ez megengedett. A privát (`published=false`) sorát B nem olvashatja. B nem módosíthatja vagy törölheti A sorát. B a saját sorát módosíthatja és törölheti. `anon` (bejelentkezés nélkül) nem férhet hozzá a táblához.
3. A két JWT-s tesztet a `tools/live_supabase_rls_test.py` szkripttel is futtathatod: állítsd be a `SUPABASE_URL` és `SUPABASE_PUBLISHABLE_KEY` környezeti változókat kizárólag helyben egy **teszt** Supabase projekthez, majd futtasd: `python tools/live_supabase_rls_test.py`. A szkript csak szintetikus sorokat ír, nem nyomtat tokent, és a tesztsort törli. A SQL Editor gyakran emelt jogosultsággal fut, **önmagában nem bizonyítja az RLS működését**. Tesztelj valódi JWT-s REST/API-kérésekkel vagy korlátozott felhasználói sessionből. A tesztsorokat utána töröld.
4. `supabase/functions/bug-report` Edge Function csak beállított szerveroldali secret mellett működik. Ellenőrizd a 401/429 választ, napi kvótát, e-mail kézbesítést; a szerverlogba ne kerülhessen pulzus, GPS, Google token.

## 9. Ingyenes mód, Pro és éves 1000 Ft-os előfizetés

**Fizetés előtt, ha van Mac/Xcode:** `tests/storekit/OraNaplo_Annual_Offline.storekit` → Xcode scheme → Edit Scheme → Run → Options → StoreKit Configuration. Futtasd a helyi StoreKit tesztet: kezdetben Free → próba-vásárlás → Pro → újraindítás → Restore → megújítás → lemondás / lejárat → vissza Free → újbóli aktiválás. Teszteld a megszakadt fizetést, pendinget, sikertelen tranzakciót és refundot is. **Itt semmilyen valódi díj nem keletkezik, nem Apple Sandbox tranzakciót küldünk.**

**Tagság után:** App Store Connect → auto-renewable yearly subscription; Product ID pontosan `hu.oranaplo.pro.yearly`, magyar árazásnál az adott bolti árkategória ellenőrzése (az 1000 Ft-os célár nem garantált kód alapján). App Store Connect Sandbox Testers → külön sandbox Apple-fiók, majd valódi Apple Sandbox vásárlás, lejárat, refund, Restore, több eszköz, internetkimaradás. **Xcode helyi StoreKit teszt nem helyettesíti az Apple Sandboxot.** Ne fogadj el olyan képernyőt, ahol a Pro stádium puszta, kézzel beállítható kapcsolóval állítható.

## 10. Magyar / angol / német felület

1. ÓraNapló és Watch külön-külön mindhárom nyelven: kezdőképernyő, engedélykérések, bejelentkezés, Sheets hiba, GPS futás, 100 m, Watch-állapot, ranglista, napló, törlésmegerősítés, vásárlás, Restore, adatvédelem.
2. Állíts nagyobb betűméretet és próbáld ki VoiceOverrel; ne legyen levágott vagy megtévesztő gomb. Az app saját nyelvbeállítása és az iOS nyelvi/lokalizált rendszerpárbeszéde eltérhet.
3. A SyncEngine 35 korábban magyar nyelvű státuszelőfordulása is HU/EN/DE formát kapott, és `python tools/localization_audit.py` jelenleg 0 jelzett magyar státuszt talál. Ez csak szűrt, statikus vizsgálat: más felületelemek, rendszerüzenetek és természetes fordítások még kézi ellenőrzést igényelnek.
4. Az automatikus forráskódos kulcsegyezés **nem** bizonyítja, hogy a német mondat természetes vagy a gombon elfér. A tényleges készülékes ellenőrzés kötelező.

## 11. TestFlight: 20 külső tesztelő (csak Developer tagság után)

1. App Store Connectben felvitt alkalmazás + aláírt feltöltött build, adatkezelési URL-ek, szükséges tesztinformációk.
2. TestFlight → External Testing → új csoport, build kiválasztás; első külső tesztelés előtt Apple Beta App Review. Meghívás e-maillel vagy megosztható linkkel.
3. Legalább **20 ténylegesen telepítő és funkciót kipróbáló** külső tesztelőt szerezz; az önmagában kiküldött 20 meghívó nem elég.
4. Eltérő iPhone/Watch, magyar/angol/német nyelv, különböző engedélyek, rossz internet, 7 nap mentés; visszajelzés és javítás után új build, majd ismételt ellenőrzés. Az egészségadatokat ne kérd a tesztelőktől nyilvános csatornában.

## 12. Élesítés előtti biztonsági kapu — csak bizonyítékkal PASS

Minden kritikus hiba megoldva: nincs ismert adatvesztés, duplikált feltöltés, idegen Sheets-fájlba írás, jogosulatlan ranglista-módosítás, téves előfizetésaktiválás, hibás Restore. A szerveroldali RLS ténylegesen ellenőrzött, Google OAuth élesítve, privát kulcsok nem klienskódban, adatkezelési és törlési folyamat tesztelt, App Store adatvédelmi nyilatkozat és jogi/fizetési adatok rendben. A `release_manifest.json` értékei **szándékosan false** maradnak, amíg külön bizonyíték nincs. A "zöld" statikus teszt és a helyi StoreKit-szimuláció nem bizonyítja a "nulla éles hiba" állítást.

## 13. Készülék nélküli és készülékes tesztmátrix

| Teszt | Most ingyen Windowsról | Ingyen Mac/Xcode-dal | Valódi eszköz/engedély | Fizetős tagság később |
|---|---|---|---|---|
| Python/JS logika, fordítás előellenőrzés | igen | igen | nem | nem |
| iOS és watchOS SDK-s szimulátor-build GitHub Actions | igen | igen | nem | nem |
| OAuth + Sheets fiók/jogosultság API | részben | igen | app-telepítéssel igen | nem minden esetben |
| Valódi HealthKit és GPS zárolt képernyővel | nem | eszközzel | **igen** | entitlement/provisioning szükséges lehet |
| Watch edzés és WatchConnectivity | nem | párosított eszközzel | **igen** | aláírási képességtől függ |
| RLS két független Supabase-felhasználóval | igen, élő Supabase fiókkal | igen | nem | nem |
| StoreKit Xcode lokális teszt | nem natívan | igen | nem feltétlenül | nem |
| Valódi Apple Sandbox, TestFlight 20 külső tesztelő | nem | nem | igen | **igen** |

**Sikeres végső kiadás:** minden sort dokumentálni kell. Ezt a fájlt és a kitöltött `docs/QA_061/QA_STATUS.json` állapotfájlt küldd vissza a hiba-logokkal. Ne küldj hitelesítő adatot vagy valódi egészségügyi nyersadatot.
