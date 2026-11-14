# ÓraNapló 0.8 – Meghívási rendszer, biztonság és indulás előtti tiltások

**NEM éleskedhet**, amíg nincs létrehozott App Store Connect éves előfizetés (évi tervezett 1000 Ft), valóban elérhető kedvezményes Apple offer-code árpont (tervezett 500 Ft), Apple JWS tranzakcióellenőrző szerver, DeviceCheck/App Attest vagy más visszaélésvédelem és végigtesztelt összekapcsolás.

1. Állítsd be Supabase Apple Sign in provider-t, iOS Sign in with Apple capability-t és a hozzátartozó Apple Developer konfigurációt. A ranglista anonim Supabase felhasználója **nem** alkalmas referralra.
2. SQL Editor: `03_referrals.sql`. A táblák RLS-sel védettek; a felhasználó csak szűk, saját fiókos RPC-ket hívhat.
3. Az app `leaderboard_config.json` fájlja tartalmazza a nyilvános Supabase URL-t és publishable kulcsot. A referral funkció alapértelmezésben letiltott, amíg nincs éles App Store ellenőrzés.
4. Az új felhasználó első Apple-bejelentkezésétől 24 órán belül egyszer válthat be egy meghívókódot. Az újratelepítés és a sima anonim auth nem új regisztráció.
5. Minden profilnak egy 12 karakteres saját kódja van. A meghívott számára *függő* grant keletkezik. Csak **valódi App Store Connectből származó, egyenként felhasználható** offer code osztható ki; ezt később az app a StoreKit redemption sheet segítségével nyittatja meg.
6. **Az inviter jutalma csak a meghívott Apple JWS tranzakciójának szerveroldali ellenőrzése után jön létre.** A `oranaplo_referral_confirm_verified_purchase` SQL RPC kizárólag service-role számára fut; NINCS client-side siker-visszaírás. Apple App Store Server Notifications V2 implementáció és a JWS ellenőrzése jelenleg **HIÁNYZIK**, ezért a produkciós kiadási ellenőrzés BLOCKED.
7. A meghívott a valóban visszaigazolt kedvezményes év lejárta után egyszer meghívhat másikat. Egy fiók: max 1 invitee- és max 1 inviter-grant. A következő év standard díjas, ha nincs új jogosult kedvezmény; az Apple végső ára a vásárlási felületen ellenőrizendő.
8. Az azonos személy több Apple ID-val való visszaélését puszta SQL-unique szabály **nem tudja teljesen megakadályozni**; App Attest, DeviceCheck, limit/risk scoring és visszatérítési kezelés szükséges.
9. Az ajánlói kód nem StoreKit kedvezménykód, a két rendszert semmiképpen ne keverd össze. Az app nem írhatja azt, hogy a kedvezmény már aktiválódott, amíg az Apple ajánlat ténylegesen nem érhető el.
10. Szerveroldali Apple transaction ↔ `appAccountToken` azonosítást szükséges bevezetni. Ne tegyél Apple privát `.p8` kulcsot a kliensbe. A backend soha ne kapjon HealthKit-adatot vagy Google OAuth tokent.

**Árképzés:** az App Store Connectben ellenőrizendő, hogy a magyar storefrontnál az 1000/500 Ft tényleges árpontok és a meglévő előfizető megújítására vonatkozó kedvezmény megfelelően beállítható-e. Ha nem, módosítani kell az ajánlatot; a kliens ne ígérjen fix árat ellenőrzés nélkül.
