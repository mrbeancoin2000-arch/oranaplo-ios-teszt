# Minőségellenőrzési terv – ne publikáld próba nélkül

## Fontos tesztforgatókönyvek

- [ ] Aláírt iPhone-buildből valóban megjelenik az Apple Egészség engedélykérés; a kiadott entitlement ellenőrizve.
- [ ] A Google OAuth a végleges App Store bundle ID-val működik; tesztelők, majd ellenőrzött külső hozzáférés.
- [ ] Az ingyenes felhasználó **csak** a nyers, időbélyeges pulzusmintákat tölti fel; HRV, edzés és naplóbejegyzés nem kerül ki.
- [ ] A Pro előfizetés csak StoreKit által **verified** és nem lejárt tranzakciónál aktív; lejárt/visszavont előfizetésnél az új Pro-export leáll.
- [ ] A Pro-ból ingyenesre visszaváltáskor a helyi függő Pro-exportok törlődnek, nem szivárognak be később a Sheetsbe.
- [ ] A korábbi Pro-adatok megmaradhatnak a felhasználó saját Google Sheets-fájljában; nem töröljük automatikusan őket.
- [ ] A pulzus és HRV minden, HealthKitben hozzáférhető mintája bekerül; ugyanaz az adat második körben nem kerül újra helyi sorba.
- [ ] 30 nap → 1 év → 5 év előzményimport, nagy adatmennyiségnél részletekben, szünet utáni folytatással.
- [ ] Internetkapcsolat nélküli mentés, újrapróbálás és időzített folytatás; Google API 429 / quota.
- [ ] App újratelepítése és helyi állapot törlése esetén Google Sheetsben lévő rekordokkal való deduplikálás *még nem teljesen garantált*; ezt éles kiadás előtt javítani kell.
- [ ] Futó/gyalogló 100 m-es szakasz 100 m, GPS-útvonal, valós szakaszpulzus; hibás GPS helyett üres adat.
- [ ] Utolsó edzés (ha elérhető), dátum, sport, időtartam, pulzus, táv és Pro-nál szakaszok.
- [ ] Apple eredetű magas/alacsony pulzus események; a saját lépésmintához viszonyító, nem orvosi felirat nem keveredik diagnózissal.
- [ ] Google-fiók váltásakor nem nyílik meg a másik fiók táblázata; a függő adatok sem kerülnek át.
- [ ] Magyar, angol, német képernyők **mindegyik** gombja, címkéje, figyelmeztetése, menüje és a hosszú szövegek iPhone SE / nagy iPhone méretben.
- [ ] Sikeres Pro, pending, visszamondott vásárlás, Restore Purchases, iPhone offline állapot.
- [ ] Felhasználó adatainak törlése és exportja, GDPR/tájékoztatás, Google Health adatok kezelése.

## Jelenleg nem bizonyított funkciók

- A GitHub Actionsen újra lefuttatott **0.4.0 Xcode build** eredménye.
- A StoreKit termék valódi elérhetősége és teljes fizetési folyamat (App Store Connectben még nincs beállítva).
- A HealthKit működése a felhasználó ingyenesen Sideloadly-val aláírt IPA-jában (az előző próba jogosultsághiányt mutatott).
- Nagy, 5 éves adatokkal stabil teljes import, valamint több eszköz, reinstall és bizonytalan hálózati válasz után távoli duplikátummentesség.
- A valós idejű vagy percre pontos Apple Watch adatátvitel: az iOS nem garantálja.

Ez fejlesztői prototípus. Ne add el működő egészségügyi szolgáltatásként, amíg a fenti tesztek és a jogi felkészülés hiányosak.
