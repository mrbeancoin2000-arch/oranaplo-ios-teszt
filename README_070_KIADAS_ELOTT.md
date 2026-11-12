# ÓraNapló 0.7.0 – fejlesztői előzetes, 2026-11-12

**Kiindulás:** ÓraNapló 0.6.4; az utolsó biztosan sikeres Apple SDK-s GitHub build a régi 0.6.4-es kódhoz tartozik (`43086133874`). Ez az új, 0.7.0 forrás **NEM ment át még új Xcode/Apple SDK-s builden, telepítésen vagy 7 napos valós adatmentési teszten**. A helyi audit önmagában nem helyettesíti ezeket.

## 1. Mit fejlesztettünk?

**Már a 0.6.4-ben létezett, megtartva és helyenként bővítve:**
- HealthKit háttérfigyelés és BGTaskScheduler – opportunisztikus, **nem** állandó háttérfutás. Új figyelt típusok: HRV, pihenőpulzus, alvás, légzésszám, csuklóhőmérséklet, testsúly, testzsír, víz (csak felhatalmazás szerint).
- Időbélyeg ISO 8601 (UTC, tört másodperc), HealthKit UUID, forrás és eszköz a Sheets nyers sorában; anchored import, helyi feltöltési sor, bizonytalan hálózati ACK egyeztetése. A távoli Sheets-sorok tényleges duplikációmentességét **valódi importtal** kell tesztelni.
- 100 m GPS-futásszakasz, pulzus/statisztika, futásrekordok; meglévő Watch edzés és iPhone-kapcsolat – Watch telepítés ingyenes Sideloadly-val **nem igazolt**.

**0.7.0 új kód:**
- `WellnessCore.swift`, `WellnessInsightsService.swift`: 7/30/90 nap nyugalmi pulzus + HRV SDNN, napi korreláció; legutóbbi edzés után 1/2/3/4/5/10 percnél ténylegesen mérhető pulzusesés. Hiányzó adat `—`, legalább 4 közös nap korrelációhoz.
- Alvás: REM/mély/core/ébrenléti idősor, átfedések figyelembe vétele, rendszeresség, 7 napos becsült alváselmaradás (8h cél), éjszakai légzés, csuklóhőmérséklet eltérése, ébredési szakaszok, következő napi pulzus-/HRV-összefüggés.
- `WellnessDiary.swift`: titkosított iOS eszköztárolási védelemmel (`completeFileProtectionUntilFirstUserAuthentication`) ellátott, **Google-fiókonként elkülönített** kézi alvásértékelés, gyógyszerbevétel/kihagyás, helyiséghőmérséklet/páratartalom/CO₂ és víznapló. **Nem mér automatikusan CO₂-t**, külön szenzorintegráció szükséges.
- `WellnessDashboardView.swift`: Analysis → új egészségelemző oldal; HU/EN/DE feliratok, alvásdiagram, új kezelőszervek, 1000 Ft/év előfizetési logikát nem változtatja.
- `MedicalPDFReport.swift`: a kiválasztott 7/30/90/365 nap vagy összes elérhető HealthKit adatból helyben készülő orvosi PDF, UTC időbélyeg, érték, egység, forrás és eszköz; helyi naplóval. **Max. 4 000 minta/típus, összesen 40 000**; minden csonka PDF jelzi, hogy **RÉSZLEGES**, ezért az „összes” nem korlátlan. Nem küld adatot külső PDF-szolgáltatásnak.
- `AdvancedRunCore.swift` + RunTracker: GPS-sebesség szerint színezett útvonal; rendelkezésre álló magassági pontokból (zajos) emelkedés/lejtés és sebesség összehasonlítás; szakaszonkénti lépésszám alapú becsült kadencia és lépéshossz; azonos kiindulási/végpontú, közel azonos távú útvonalak összehasonlítása; **HealthKitből olvasott, ha létező** futóteljesítmény és futási lépéshossz. Intervallum *tervező* megjelent; **nem automatikus intervallumvezérelt edzés**.
- WatchWorkout + WatchBridge: Apple Watch töltöttség/töltés és +200/+300 ml víz bejegyzések; iPhone tartós írás utáni Watch-ACK, UUID szerinti idempotencia. Watch telepítés és teljes WatchConnectivity életciklus **nincs tesztelve**.
- `WellnessWidgetCache.swift` és `widgets/`: iPhone kezdőképernyő, Lock Screen, Watch complication/Smart Stack **külön tervezett bővítmény forrásai**. Nem részei az alap-IPA-nak; fizetős fejlesztői/App Group-aláírás és widget target/extension kiépítése nélkül **NEM HASZNÁLHATÓK**. Ezt ne jelöld kész funkciónak.
- Opcionális szokatlan *nyugalmi* pulzus értesítés, ha friss HealthKit-mérés és engedélyezett iOS futási lehetőség van; **nem sürgősségi/valós idejű riasztás**.

## 2. A mostani build ellenőrzése Windowson

1. **Először csinálj biztonsági mentést** a 0.6.4 mappáról és az esetleges helyi futásnaplóról. App törlése/újratelepítése helyi adatvesztést okozhat.
2. Csomagold ki az új ZIP-et új mappába `OraNaplo-iOS-Windows` néven.
3. Másold át a korábbi működő `google_oauth.json`-t **csak a számítógépen** a megfelelő helyre. Ne pushold GitHubra; a nyilvános CI kizárólag teszt-only OAuth-metaadatokat állít elő.
4. Futtasd `01_WINDOWS_ELOKESZITES.bat`, aztán `05_FIZETES_ELOTTI_TESZTEK.bat`. Ha sikeres, indítsd `02_FELHOS_IPA_EPITES.bat`-ot; ez **új GitHub Actions macOS Xcode-fordítást** indít.
5. Csak ha az **iOS Simulator**, az **iOS készülék-build**, a **watchOS Simulator**, az IPA-verifikáció **mind zöld**, jöhet a Sideloadly telepítés a készülékre. A Sideloadly telepítés továbbra sem igazolja a HealthKit és Watch aláírt jogosultságait.
6. Ha piros: add át a `output/build-logs-<run>/xcodebuild.log`, `xcodebuild-simulator.log` és `xcodebuild-watchsimulator.log` érintett fájljait. **Ne tölts fel érzékeny tokeneket vagy nyers egészségadatokat.**

## 3. Készülékes tesztlista (minden pont egyelőre KIADÁS-BLOKKOLÓ)

- [ ] Új 0.7.0 iOS telepítés – az iPhone tényleg ezt a verziót futtatja
- [ ] Google bejelentkezés – új és meglévő fiók, fiókváltás, visszavonás
- [ ] Alap és teljes HealthKit-engedély kérés – nincs összeomlás
- [ ] 7/30/90 napos nyugalmi pulzus és HRV számítva, Hiányzó = „—”
- [ ] Alvásdiagram, légzésszám, csuklóhőmérséklet (csak ha minták léteznek)
- [ ] PDF 7/30/90/365/összes; HU/EN/DE betűk, táblázat, oldal törés; nagy PDF csonka jelzése
- [ ] Gyógyszer, víz, szoba, alvásértékelés mentése, újraindítás utáni megmaradása
- [ ] Váltás A→B→A Google-fiókok között, semmilyen másik fiók adata nem látszik
- [ ] Szinkron offline / hálózatkihagyás / többszöri import; egy HK UUID csak egyszer szerepel a Sheetsben
- [ ] 7 nap reggeli/esti ellenőrzés, teljes mintaszámok és hibák nyomon követése
- [ ] Futás zárolt iPhone-nal 100 m-enként; GPS útvonal, sebességszín, szintemelkedés; szünet/folytatás
- [ ] Valódi Apple Watch app aláírva telepítve; víz 200/300 ml kétszeri retranszfer után sem dupla
- [ ] Watch akkumulátorállapot és edzésösszesítés, offline/újracsatlakozás
- [ ] Emlékeztető csak engedély esetén, nem sürgősségi riasztásként
- [ ] Minden képernyő, hibaüzenet, mértékegység HU/EN/DE ellenőrzése
- [ ] Kiadás előtt még Supabase RLS, StoreKit Sandbox, TestFlight 20 emberrel

**Widgetek tesztje csak külön aláírt WidgetKit céllal lehetséges, lásd `widgets/README_HU.md`.**

## 4. Ismert korlátok

1. A HealthKit és az iOS háttérfeladatok nem garantálnak másodpercenkénti frissítést, értesítést vagy 0–24 órás ébren tartást.
2. Az Apple Watch-alkalmazás a régi projektnél sem települt ingyenes Sideloadly-val. A Watchra szánt funkciók ezért továbbra is **nem ellenőrzöttek**.
3. A GPS-magasság és 100 m kadencia/lépéshossz csak mérésekből számított, nem orvosi pontosságú. Az intervallumtervező nem indít önálló intervallumedzést.
4. A CO₂ külső integráció, iOS/Watch widgetek és App Group nem éles funkciók még.
5. A készülékes életciklust, a hét napot és az adatok teljes sértetlenségét helyi teszt nem bizonyítja.
6. Orvosi PDF nem betegségek felismerésére szolgál, hanem mérési adatok tárgyilagos áttekintésére.

**Nem került módosításra a Supabase-ranglista és az éves StoreKit előfizetés éles logikája.**
