# ÓraNapló 0.5.4 – Futás Pro / Apple Watch

## Mit tartalmaz a projekt?
- Watch-alkalmazás forrása: `watchOS/Sources/` – HealthKit HKWorkoutSession, élő pulzus, távolság, tempó, start/pause/resume/finish.
- Párosított iPhone-on WatchConnectivity értesítések. A telefon GPS-megfigyelése csak akkor indulhat, amikor a kísérő iOS alkalmazást az iOS ténylegesen futtatja és a helyengedély megvan.
- Telefon GPS: Core Location, háttérhelyzet követése csak aktív futáskor, mozgáshoz alkalmazkodó distanceFilter, megszakítás utáni mentés.
- Futó PR 1/5/10 km, 21 097 m, heti/havi cél és streak; szintetikus GPS-tesztekkel.
- Google Sheets Dashboard (heti táv, szakaszsebesség, pulzusminták eloszlása), Rekordok, Celok lapok; automatikus formázási kísérlet és külön átállás meglévő táblázatnál.
- iPhone-on térképet tartalmazó, grafit/acélkék futáskártya külön megosztási döntéssel.

## Ismert korlátok – fontos
1. A Watch app XcodeGen konfigurációja `project.watch.yml`. A fő `project.yml` egyelőre szándékosan iPhone-only, mert a watchOS beágyazást és aláírást **valódi Apple SDK-val kell validálni**. Nem szabad azt állítani, hogy az IPA már tartalmazza a Watch appot!
2. A GPS és pulzus iPhone–Watch szinkron késhet vagy elmaradhat, ha a telefon nem fut/hatótávon kívül van; Watch önálló HKWorkoutSession adatokat ment, az iPhone nem készít fantom GPS-útvonalat.
3. A Sheets dashboard formázása best-effort. Valódi Google-fiókkal ellenőrizendő: diagramok, képletek, nagyméretű adatok, API-kvóta és lokalizált dátumok. Hiba esetén a nyers adatlap létezik.
4. A teljes GPS-útvonalat tartalmazó `RecordedRun` fájl legfeljebb 25 befejezett futást őriz helyben. A PR-eredmények és a heti/havi cél számításához szükséges útvonal nélküli futás-összesítők külön `record-archive.json` és `run-summary.json` fájlban megmaradnak a későbbiekben is, amíg a felhasználó nem törli az alkalmazás adatait. Újratelepítés vagy készülékcsere után ezt a helyi archívumot nem állítjuk automatikusan vissza; a Google Sheetsben lévő korábbi adatok sem garantálják a helyi PR-archívum visszaállítását.
5. A teljes Google Sheets-szinkron és Pro-export a már meglévő ellenőrzött StoreKit-jogosultságtól függ. Az éles 1 000 Ft-os előfizetés nincs aktiválva.
6. A Watch HealthKit és iPhone GPS együtt történő mentését, a Siri/Apple Watch engedélyeket, a háttérműködést és az energiaköltséget valódi eszközön kell igazolni.
7. Share-kártyán a térképpel megosztható az otthoni címed vagy útvonalad; mindig manuális döntés kell.

## Hogyan építsd Windows alatt?
Indítsd a `00_MINDENT_INDIT.bat` fájlt. A GitHub iOS workflow-t lefordítja, **a Watch app-ot még nem csomagolja bele**. Az Apple-tagság után a watchOS variánst külön XcodeGen/Xcode fordítással kell validálni és a fő workflow-ba beépíteni.

## Xcode-fordítási hibák diagnosztikája
Az új CI `tools/ci_xcode_build.sh` többfázisú, időszakos állapotüzeneteket ír, és a `error:` sorokat kinyeri. A Windowsos `cloud_build.ps1` letölti a log-artifactet és kiírja az első releváns fordítóüzeneteket. Ha továbbra is bukik, a **`output/build-logs-<ID>/xcodebuild-simulator.log` teljes fájlt** kell elküldeni, mert a régi `github-failed-steps.log` csak a SwiftCompile összefoglalót mutatta.

## Következő ellenőrzések
- iOS Xcode Simulator + iPhoneOS build: GitHub Actions futtatandó.
- watchOS target: külön Apple SDK-s, valós iPhone/Watch teszt szükséges.
- Google Sheets dashboard valós fiókkal és StoreKit sandbox vásárlással tesztelendő.

## Adatminták és Google Sheets képletek
- A mért adatokat a feltöltő RAW szövegként mentheti; a Dashboard képletei explicit `VALUE` átalakítást használnak a táv és szakaszsebesség számításakor. Valódi Google-fiókkal a diagramokat és képleteket még ellenőrizni kell.
- A Rekordok és Celok munkalapra a hosszú távú PR-archívum és az összesített korábbi futásokból számított célok kerülnek, nem csak a legutóbbi 25 GPS-útvonal.
- Az éves 1 000 Ft-os előfizetés StoreKit/Apple-fiók nélküli része szimulált; valós pénzügyi tranzakciót még nem teszteltünk.
