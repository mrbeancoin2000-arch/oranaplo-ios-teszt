# ÓraNapló – E-mailes hibabejelentés beállítása

**Cél:** a Profilban leadott hibabejelentés után az üzemeltető automatikus e-mailt kapjon. Az iPhone nem tartalmaz e-mailküldő kulcsot vagy megadott célcímet.

## 1. Supabase

- Hozz létre Supabase-projektet a https://supabase.com/dashboard oldalon.
- Engedélyezd az **Anonymous Sign-Ins** funkciót, és konfigurálj CAPTCHA / felhasználó- és IP-alapú rate limit védelmet. Egy anonim fiók 1 hibajelentést küldhet naponta; új anonim fiókokkal ezt külön védeni kell.
- Az SQL Editorban futtasd `supabase/01_leaderboard.sql` és `supabase/02_bug_report_quota.sql` állományokat.
- Az iOS `ios/Resources/leaderboard_config.json` fájlban állítsd be a **Project URL** és **publishable** API key értékeit. **Soha ne service_role vagy secret API kulcsot!**
- SQL-ben maradjon engedélyezve a Row Level Security (RLS). A quota sorokat a kliens NEM törölheti; egy sikertelen e-mail után csak a hitelesített Edge Function admin kliense szabadíthatja fel a kvótát.

## 2. Resend

- Hozz létre fiókot a https://resend.com oldalon.
- Igazolj egy küldő domaint (DNS). A szolgáltató saját tesztfeladójával nem garantált, hogy külső címre tudsz levelet küldeni.
- Hozz létre privát API-kulcsot. **Csak a Supabase Dashboard titkos Edge Function beállításába másold**, ne a forráskódba, ne GitHubra, ne ide a chatbe.

## 3. Edge Function deployment

Az `supabase/functions/bug-report/index.ts` és `policy.mjs` fájl már benne van a projektben. A Supabase CLI-vel a projekt gyökeréből:

```powershell
npx supabase login
npx supabase link --project-ref A_TE_SUPABASE_PROJECT_REF_ED
npx supabase functions deploy bug-report
```

A Supabase Dashboardban állítsd be az alábbi **secret** értékeket:

- `RESEND_API_KEY`: a privát Resend API-kulcs
- `REPORT_FROM_EMAIL`: igazolt domainről küldő e-mail, például `alerts@te-domainod.hu`
- `REPORT_TO_EMAIL`: **az általad megadott e-mail-cím, ahová a hibabejelentéseket kéred**

Ne állítsd be `verify_jwt=false` értékre a funkciót pusztán egy 401-es hiba miatt. A felhasználó anonim Supabase JWT-jét ténylegesen ellenőrizni kell.

## 4. Éles ellenőrzés

1. Az alkalmazás Profil → Hibabejelentés részén válassz hibatípust.
2. Küldd el, ellenőrizd, hogy **valóban megérkezett** a címzett postaládájába.
3. Próbálj meg második jelentést küldeni ugyanazzal a felhasználóval ugyanazon UTC-napon: a szerver 429-et adjon.
4. Egy másik fiók ne olvashassa vagy törölhesse a kvótákat. Másik felhasználó rangsorát sem módosíthatja.
5. Teszteld a rossz JWT-t, a hiányzó API-kulcsot, a hibás kategóriát, a hosszú JSON-t és a levélküldő API hibáját.
6. Vizsgáld meg a kapott emailt: csak kategória, általános hibakód, appverzió, platform, nap és maximum 12 engedélyezett eseménykód szerepelhet benne.

**A helyi teszt NEM küld valódi e-mailt.** Ha a Supabase/Resend nincs konfigurálva, az app egyértelműen jelzi, hogy a küldés nem lehetséges. Nem állítható sikeresnek az éles küldés.

## 5. Adatvédelem

A Supabase egy pszeudonim felhasználói azonosítót és jelentési napot tárol a kvótához. A szolgáltatók a HTTP-kapcsolat metaadatait is feldolgozhatják. A szöveg és az e-mail kizárólag megengedett technikai hibakódokból készül; nincs szabad szöveges megjegyzés. A háromnyelvű weboldalak adatvédelmi részét frissítettük, de a tényleges fiók- és adatszolgáltatói szerződéseket élesítés előtt ellenőrizni kell.
