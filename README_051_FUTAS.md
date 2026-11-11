# ÓraNapló 0.5.1 — Élő iPhone futásmérő (HU)

## Funkciók és források
- Új **Futás** fül: indítás / szünet / folytatás / leállítás, GPS, MapKit útvonal, idő, 100 m-es szakaszok, km/h, min/km, lépésszám, helyi edzésnapló, GPX-megosztás.
- CoreLocation GPS valós helyadatokból méri a távolságot. 30 méternél pontatlanabb helyadatokat és valószínűtlen ugrásokat eldob. Szünetben leáll a helymeghatározás.
- CoreMotion CMPedometer adja a lépéseket, **nem** a magasságból számolunk lépéseket. A magasságot/tömeget az Apple Egészségprofilból olvassuk (ha engedélyezted); testsúly kézzel is megadható. A kcal `tömeg(kg) × távolság(km)` egyszerű, **becsült** futóérték, nem mért aktív energia. Súly nélkül nincs kalóriaérték.
- A 100 m-es szakaszok időhatárát GPS-pontok közötti interpoláció adja. A split aktív időt használ, tehát szünetet nem számol bele. Nem állítunk be kitalált pulzust.
- **Pulzus:** a jelenlegi iPhone-app nem képes megbízható, folyamatos, élő Apple Watch-pulzusmérésre. A futás végén, megfelelő HealthKit-engedéllyel a valóban már tárolt mintákból egészíti ki az edzést és a szakaszokat. Az órás edzésalkalmazás és WatchConnectivity a következő, Apple Developer-tagságos szakasz.
- **Adatvédelem:** a részletes GPS-útvonal alapértelmezetten a telefonon marad. A GPX-megosztást a felhasználó indítja; a Google Sheetsbe csak **kézi jóváhagyással, ellenőrzött Pro** mellett kerül az edzés összefoglalója és a 100 m-es szakaszok, GPS-koordináták nélkül. A helyi futásrögzítés ingyenes.

## Engedélyek
- `NSLocationWhenInUseUsageDescription` (csak elindított futás alatt); `UIBackgroundModes=location`; `NSMotionUsageDescription`.
- Az iOS a háttérhelymeghatározást is korlátozhatja; nem garantált a megszakítás nélküli GPS. A mobiltelefon legyen nálad, lehetőleg megfelelő GPS-látómezőben.
- A HealthKit és StoreKit éles működése továbbra is megfelelő Apple-aláírást, tesztelést és előfizetéses terméket igényel.

## Windowsos ellenőrzés
1. `05_FIZETES_ELOTTI_TESZTEK.bat` — egységtesztek, Swift futásidejű teszt és napló.
2. `01_WINDOWS_ELOKESZITES.bat` — források ellenőrzése.
3. GitHub → Actions → `Prepayment audit + unsigned iOS simulator build` — **tényleges iOS SDK-s fordítás**; ilyen fordítást ebben a környezetben nem igazoltunk.
4. Valódi iPhone GPS, CoreMotion, háttérfutás és később HealthKit/StoreKit próba szükséges.

## Kiadás előtti feladat
A végleges live Apple Watch pulzushoz watchOS társkomponens, WatchConnectivity, HealthKit HKWorkoutSession, aláírás és többkészülékes tesztelés szükséges. Ezt ne állítsuk késznek.

## Tesztnaplók
`TESTJELENTES_051/JELENTES.html`, `RESULT.json`, az összes helyi test `.log` fájl. `logs/` mappában a futtatás dátumával együtt új riportok képződnek. A tesztek nem helyettesítik a GitHub macOS Xcode-buildet.

## A felhasználói lépések
1. A **Futás** fülön engedélyezd az iPhone helyhozzáférését. A lépésszámhoz a mozgásadat-hozzáférést is.
2. Ha nincs HealthKit profil, opcionálisan add meg a testsúlyt a kalóriabecsléshez.
3. Indítás után a GPS-térképen az első pontos helyek jelennek meg. Szüneteltetés idején nincs GPS-felvétel és a szünet idejét nem számoljuk a mozgásidőbe.
4. Leállítás után elérhetők a 100 m-es szakaszok, a pulzusadatok külön lekérdezése (csak ha engedélyezett és valóban elérhető), a GPX és az előzmények.
5. A Google Sheetsbe küldés külön, Pro-jogosultsággal jóváhagyandó.
