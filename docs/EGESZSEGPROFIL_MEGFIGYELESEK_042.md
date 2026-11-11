# ÓraNapló 0.4.2 – Egészségprofil és megfigyelések

## Mit mutat az alkalmazás?

Az **Egészségprofil** fülön, külön HealthKit-engedély után az életkor (születési dátumból számítva), az Apple Egészségben tárolt **biológiai nem**, a legfrissebb magasság és testsúly jelenik meg. Hiányzó adat esetén nem becsülünk értéket. A születési dátumot nem exportáljuk. Az app az adatokat nem írhatja át az Egészségben; az iPhone Egészség appban javíthatók.

Az app a telefonon elérhető adatokból háromféle, **nem diagnosztikai** jelzést állíthat elő:

1. 18 év felett rögzített vérnyomásérték: 140/90 fölött ismételt mérés / orvosi konzultáció, 180/120 fölött sürgős tanács a megismétlésre és orvosi segítség kérésére. A vérnyomást nem az Apple Watch méri; csak a Healthben lévő kompatibilis eszköz vagy manuális bejegyzés adata használható. Panaszokkal együtt a nagyon magas érték sürgősségi helyzet lehet.
2. A szokásosnál kevesebb lépés: csak 20:00 után, legalább öt rögzített korábbi nap és a saját mintához viszonyított csökkenés alapján, nem általános egészségügyi határérték.
3. Folyadéknapló: csak ha a felhasználó külön bekapcsolja, hogy minden italt rögzít, és saját naplózási célt állít be. Hiányzó folyadékadatból nem következtetünk arra, hogy nem ivott.

A kezdeti változat csak megnyitáskor/frissítéskor vizsgálja a feltételeket; **nem folyamatos egészségügyi riasztórendszer**.

## Google Sheets Apps Script (opcionális)

A felhasználó saját táblázata tartalmazhat `Profil`, `Megfigyelesek`, `ElemzesBeallitasok` füleket. A `Profil` fülre az app **csak explicit jóváhagyás után, aktív Pro-előfizetéssel** küld életkort (nem születési dátumot), biológiai nemet, magasságot, testsúlyt.

Ha a tulajdonos szeretné a Google Sheetből történő megfigyeléseket is:

1. Nyissa meg saját ÓraNapló Google Sheets-fájlját.
2. **Bővítmények → Apps Script**. Hozzon létre egy projektet, és másolja be a `scripts/Ertekeles.gs` teljes tartalmát.
3. Mentse, majd futtassa a `frissitMegfigyelesek` függvényt, és hagyja jóvá a Google engedélykérését a **saját fiókjában**.
4. Ha időzítést szeretne, futtassa külön a `telepitNapiEllenorzes` függvényt. Ez egy hozzávetőleges napi ellenőrzést állít be.
5. Az iPhone ÓraNapló alkalmazásban nyissa meg az Egészségprofil fület és nyomja meg a **Megfigyelések frissítése** gombot. Az aktív Pro mellett az alkalmazás a `Megfigyelesek` lapot is beolvassa, ha van ott adat.

A Google Apps Script **nem települ automatikusan** a felhasználó táblázatához, és nem fut helyette az ÓraNapló fejlesztői fiókjában. Az Apps Script nem orvosi szolgáltatás, nem sürgősségi figyelmeztetés. A Sheets-adatok érzékenyek: a táblázatot ne tegye nyilvánossá.

Az `ElemzesBeallitasok` lapon az `IGEN` értékre kell állítani a `teljes_folyadeknaplo` sort, és külön kell megadni egy saját `napi_cel_ml` értéket, ha szeretné a folyadék-összehasonlítást. A script soha nem feltételezi, hogy a hiányzó folyadékbejegyzés nulla fogyasztást jelent.

## Limitációk

- Az ingyenes Sideloadly-val aláírt jelenlegi alkalmazásból a HealthKit-entitlement hiányozhat, ezért a HealthKit-profil és megfigyelések nem működnek, amíg a megfelelő Apple-fejlesztői aláírás nincs meg.
- A profil beolvasásához külön jogosultságok kellenek; az iOS a megtagadott HealthKit-olvasási jogot gyakran nem teszi megkülönböztethetővé a hiányzó adatoktól.
- A vérnyomásértesítés kizárólag rögzített méréshez kapcsolódik, nem alkalmas magas vérnyomás diagnosztizálására. Speciális élethelyzetek (pl. várandósság, kiskorúak, ismert betegségek) eltérő orvosi megítélést igényelnek.
- Az alkalmazás az alapot a 0.4.1 projektből örökli; itt Linuxon csak statikus és Python-tesztek futtathatók. Tényleges iOS-fordítás és készülékes HealthKit-teszt még szükséges.

**Szakmai referenciák:** Apple HealthKit és App Review Guidelines; American Heart Association: Home Blood Pressure Monitoring; CDC: Adult Activity Guidelines; Google Apps Script installable triggers.
