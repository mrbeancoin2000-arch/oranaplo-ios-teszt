# ÓraNapló – TELJES JAVÍTOTT WINDOWS PROJEKT

Ez a teljes projekt 2026-11-10-i javítása. Nem különálló patch.

## Mi volt a hiba?
A korábbi Windows-csomag kibontásakor elveszett a `google_oauth.json`, és a `configure.py` halkan DEMÓ Google-kliensre állt vissza. Így a teszt már a Google visszairányításának ellenőrzésénél elakadt. Emellett a teszt helyesen hibásnak ítélt egy demó IPA-t, de a tesztkód tévesen sikerre számított.

## Mi változott?
- A teljes projekt tartalmazza a korábban általad megadott *nyilvános iOS OAuth kliensazonosítót* a `google_oauth.json` fájlban. **Jelszó vagy Google OAuth client secret nincs benne.**
- Hiányzó/hibás OAuth fájlnál a konfigurálás megáll, nem generál élesnek tűnő demó IPA-t.
- Az IPA-ellenőrző regressziós teszt mesterséges, megfelelő alakú kliensazonosítóval ellenőrzi a sikeres és a hibás esetet.
- Az alkalmazás `Info.plist` és Swift-konfigurációját a helyi előkészítés újragenerálja.
- A Windows- és GitHub-fordítás naplózása megmaradt.

## Használat
1. A régi `OraNaplo-iOS-Windows` mappádról készíts másolatot.
2. Ezt a ZIP-et **teljes egészében** csomagold ki az Asztalra. Ne keverd össze más korábbi ZIP-ek fájljaival.
3. Ellenőrizd, hogy a `google_oauth.json` tartalmazza a Google Cloudban beállított aktuális iOS Client ID-t és Bundle ID-t. Ha azóta megváltoztattad, frissítsd ezt a két mezőt. Ne adj meg hozzáférési tokent vagy client secretet.
4. Indítsd a `01_WINDOWS_ELOKESZITES.bat`-ot. Minden helyi tesztnek zöldnek kell lennie.
5. Utána indítsd a `02_FELHOS_IPA_EPITES.bat`-ot. A GitHub jóváhagyásnál `IGEN`.
6. Sikeres build után Sideloadly-val telepítsd a letöltött aláíratlan IPA-t.

## Fontos korlátok
- A helyi Python-tesztek **nem jelentik**, hogy az iPhone-on Google-bejelentkezés és HealthKit működni fog.
- A Sideloadly aláíráskor módosíthatja a Bundle ID-t, ezért azt a telepített alkalmazásnál is ellenőrizni kell.
- Ingyenes Apple ID esetén a HealthKit entitlement nem garantált. Ezt szoftveres kerülőúttal nem lehet pótolni.
- A GitHubra csak engedélyezett forrásfájlok kerülhetnek; a helyi `google_oauth.json` kimarad. A beépített nyilvános Client ID a forráskonfigurációban természetesen látható lehet.
- A korábbi 0.3.2 verzió további, készüléken tesztelendő funkcióit nem tekintjük igazoltan működőnek.
