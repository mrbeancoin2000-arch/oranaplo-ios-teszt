# ÓraNapló 0.5.6 – a kért öt képernyő

A sötét grafit–acélkék dizájnhoz SF Symbols ikonokat használunk: az ikonok méretarányosak és nem igényelnek jogvédett képfájlokat.

1. **Ma:** nagy gyűrűs lépésszám, alatta kcal, km, mozgásidő. Alvás: legutóbbi esti alvás időtartama, vizuális sáv és legalább 3 korábbi éjszaka esetén saját történeti mediánhoz való hasonlítás. Utána aznapi átlagos, legkisebb és legnagyobb **tényleges** pulzus. Hiányzó HealthKit-mérés „—”, sosem hamis 0.
2. **Elemzés:** helyi első használat óta eltelt napok; Google Sheets tényleges kitöltött A-oszlopbeli adatsorainak száma (kézi újraszámolás), táblázat megnyitása, mentésállapot. Az API olvasása nagy táblázatnál időt/kérést fogyaszthat.
3. **Futás:** Apple MapKit-térkép már indítás előtt (helyengedéllyel), élő GPS-útvonal, km, idő, tempó, pulzus ha ténylegesen elérhető, szünet/folytatás/befejezés, 100 m szakaszok, személyes rekordok, GPX és megosztható kártya. Az órás fejlesztés továbbra is előzetes kód, nem élőben igazolt.
4. **Ranglista:** 2 mód – összes lépés az app használata óta, valamint legnagyobb egyszeri futás km. Saját helyezés és valódi top felhasználók **csak beállított Supabase szerverrel**, opt-in publikálással. A rangsor nem hitelesített verseny.
5. **Profil:** Google-fiók csatlakoztatása/leválasztása, HealthKit engedélyezés (az Apple kategóriánként kér engedélyt), helyi megjelenített név, a futásmegosztó kártyán szereplő név, személyes futórekordok, külön nyilvános közzététel/törlés, korábbi részletes egészségprofil és beállítások (nyelvek, Pro, diagnosztika).

### Valósághű működési korlátok

- A Google-fiók a személyes adatexporthoz kell, nem a helyi futásrögzítéshez.
- A szerver csak a publikus ranglistát kezeli, a Google Sheets nem kerül ki semmilyen más szerverre.
- A HealthKit a jelenlegi aláíratlan/Sideloadly változatban korábban jogosultsághiba miatt nem működött; az SDK szintaxisvizsgálata nem igazolja az éles hozzáférést.
- A 99 USD fejlesztői tagság és az előfizetés/App Store Connect még nincs beállítva.
- A ranglistához (a korábbi „nincs szerver” állítással ellentétben) **működő Supabase-backend szükséges**. A felhasználó ezt külön csatlakoztatja.

### Próba / további teendők

1. `00_MINDENT_INDIT.bat` egygombos előkészítés, teszt, GitHub-fordítás, IPA letöltése.
2. MacOS Xcode típusellenőrzés és a tényleges iOS/watchOS alkalmazásfordítás ellenőrzése szükséges.
3. Valódi iPhone-on és Watch-on adatelérés, GPS és akkumulátor-teszt.
4. Supabase-schema, anon auth, RLS és külön két fiókos adatvédelmi teszt (ld. `supabase/README_HU.md`).
5. Google OAuth éles iOS bundle ID-ra állítása, Google API hívások valós fiókkal.
6. Apple Developer-tagság, előfizetés, TestFlight, App Store Review.
