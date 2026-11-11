# ÓraNapló Ranglista – beüzemelés

Az app **nem tud világméretű rangsort megjeleníteni saját, működő szerver nélkül**. A teljes UI és hálózati kliens be van építve, de nem mutat kitalált résztvevőket.

1. Hozz létre Supabase-projektet (`https://supabase.com/dashboard`). A szolgáltató ingyenes kerete és kvótái változhatnak.
2. Authentication → Providers / Anonymous sign-ins: **engedélyezd az anonim bejelentkezést**; állíts be bot/rate-limit védelmet.
3. SQL Editor → futtasd a `01_leaderboard.sql` fájlt. A RLS szabályait ne kapcsold ki.
4. Project Settings → API → keresd ki a **Project URL** és a **Publishable (public) key** értéket. Soha ne használj service-role/secret kulcsot az iOS-appban.
5. Töltsd ki az `ios/Resources/leaderboard_config.json` megfelelő mezőit.
6. Indítsd újra a `00_MINDENT_INDIT.bat` folyamatot. Ez újrafordítja az iOS-alkalmazást.
7. Két külön teszteszközön ellenőrizd a név megadását, explicit közzétételt, rangokat, módváltást, törlést és azt, hogy a két fiók adatai elkülönülnek.

## Adatvédelem

- A tábla **csak** véletlenszerű belső Auth UUID-t, a felhasználó által megadott 3–24 karakteres nevet, összesített lépést és legnagyobb egy alkalommal lefutott távot tárol.
- Nem kerül ide Google-token, táblázatazonosító, GPS-nyomvonal, pulzus, testmagasság, életkor, alvás vagy e-mail.
- Alapállapot: **nincs publikálás**. A ranglista két módot kínál: „összes lépés az alkalmazás használata óta” és „leghosszabb rögzített futás”.
- Az „Eltávolítás” a szerver rekordját ténylegesen törli. Ha a hálózat hibás, a kliens hibát jelez, nem állítja, hogy sikerült.
- A saját név megváltoztatása önmagában csak helyi, az új név a következő külön közzétételkor kerül a ranglistára.
- Az anonim Supabase fiók Apple-eszközről történő újratelepítésnél/Keychain törlésnél elveszhet; éles változathoz javasolt fiókhelyreállítás és adminisztrációs eszköz.
- Ezek **önbevallott adatok**: a kliens a HealthKit-olvasásból számolja őket, de módosított alkalmazással hamisíthatók. A hiteles ranglistához szükséges később szerveroldali csalásellenőrzés.
- A nyilvános megjelenés előtt aktualizálni kell az adatvédelmi tájékoztatót és az App Privacy nyilatkozatot a Supabase/ranglista adatkezelésének megfelelően.

## Biztonsági kézi tesztek

- Más felhasználó `user_id` értékével `POST/PATCH/DELETE` műveletet a RLS-nek tiltania kell.
- Kijelentkezett / hitelesítetlen kérés nem olvashat publikus sorokat sem (ebben a v1-es sémában).
- `published=false` felhasználó adata másik felhasználó számára nem látható.
- A rangsor egyenlő pontszám esetén közös helyezést ad (1+ a nagyobb pontszámú publikált felhasználók száma).
