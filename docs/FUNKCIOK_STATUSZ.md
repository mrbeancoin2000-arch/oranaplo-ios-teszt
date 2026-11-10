# Funkciók és valós megvalósítási státusz (2026-11-10)

| Funkció | Prototípus forrása | Feltétel / korlát |
|---|---|---|
| Pulzus, nyugalmi pulzus, sétapulzus, HRV SDNN | Implementált HealthKit-olvasó | HealthKit engedély / tényleges minta |
| Szabálytalan / magas / alacsony pulzus esemény | Kategória minták | Eszköz / régió / kor függő |
| EKG felvétel és hullámforma | HKElectrocardiogramQuery | Engedély + kompatibilis EKG |
| Alvás fázisok, légzés, csuklóhőmérséklet | Nyers HealthKit-minták | Napi összegzések még nem számoltak külön |
| Edzés idő, kalória, távolság, pulzus összesítés | HKWorkout + pulzusminták | A minták nem garantáltak |
| Futó / gyalogló 100 m szakasz sebesség, idő, átlag/min/max pulzus | GPS-útvonalszámítás | Csak HKWorkoutRoute, interpolált becslés; nem garantált |
| Sportsebesség, futóteljesítmény, talajérintési idő stb. | Elérhető nyers minták | Nem mindegyik óra és sport támogatja |
| Napi mozgás, steps, járásstabilitás, természetes fény | Nyers minták | Megjelenés Sheetsben, napi aggregátum még fejlesztendő |
| Testsúly, BMI, tápanyag, víz, koffein, vércukor, vérnyomás | HealthKit-minták | Külső eszköz / kézi bevitel lehet |
| iPhone töltöttség / töltési állapot | Appon belüli mintavétel | Szinkron futásakor; nem folyamatos |
| Apple Watch akku | Nincs | Külön watchOS app szükséges |
| iPhone képernyőidő | Nincs | Külön Family Controls jogosultság kell |
| CO₂, szobahőmérséklet | Nincs | Külső szenzor kell |
| Kézi gyógyszer- és közérzetnapló | Implementált saját Naplo munkalap | Saját bejegyzés, nem Apple Gyógyszerek API |
| Google OAuth / saját Sheets | Implementált Google Sign-In + Sheets API | Saját iOS OAuth client ID szükséges |
| Hálózati kimaradás és helyi sor | Implementált alap queue | Nem tranzakciós; bizonytalan API válasz után duplikátum előfordulhat |
| Google Sheets másolat nélküli, egy fájl | Implementált | Új Spreadsheet készül, saját felhasználóé |
| Adattörlések követése | Törlési esemény naplózás | Sheets rekordok nem törlődnek automatikusan |
| Háttérszinkron | BGTaskScheduler kísérleti | Az iOS ütemez, lehet hogy nem fut időben |
| Push/hibaértesítés | Helyi szinkronhibára értesítés | Csak amikor az app kap futási időt |
| 30 nap / 1 év / 5 év export | Beállítható | Nagy adatmennyiségnél lassulhat, limit/kvóta |
| AI-elemzés igénylése, fizetés | NINCS | Külön üzleti és adatvédelmi fejlesztési feladat |
| Ügyfél-aktiváció, 14 990 Ft | NINCS | Ez prototípus, nem értékesítésre kész rendszer |

**A projekt szintaktikai ellenőrzése nem azonos Xcode-fordítással vagy egészségügyi adatokon végzett éles teszttel.**
