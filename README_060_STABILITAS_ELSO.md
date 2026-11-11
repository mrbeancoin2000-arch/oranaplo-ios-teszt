# ÓraNapló 0.6.0 – stabilitási kiadásjelölt (Windows + iOS)

**Ez teljes forrásprojekt, nem éles, aláírt és App Store-ban jóváhagyott alkalmazás.**
A korábbi 0.5.6 összes forrását, build-szkriptjét, Watch-előkészítését, API-ját és a meglévő teszteket tartalmazza.

## Új funkciók

1. **Elemzés / Szinkronállapot**: az utolsó sikeres szinkron, az utolsó próbálkozás, a várakozó sorok, a folyamat állapota és a hiba kategóriája. A szinkronidő és hiba Google-fiókonként külön tárolódik.
2. **Futás / helyreállítás**: az alkalmazás váratlan kilépésekor az utolsó tartósan mentett futás várakozó, szüneteltetett állapotként nyílik meg. Külön folytatható, részfutásként lezárható vagy megerősítés után elvethető. Az újrafelvétel nem indul automatikusan.
3. **Futás / adatsérülés-védelem**: két atomikusan mentett helyi futásállomány. Ha az első sérült, a tartalékot megpróbáljuk beolvasni. Ha mindkettő sérült, a rendszer nem ír rájuk üres adatsort. Ez nem pótolja a rendszeres biztonsági mentést.
4. **Profil / adatkezelés**: a jelenlegi Google-fiók helyi feltöltési sorának és a helyi futások, GPS-útvonalak, rekordok törlése. A nyilvános Supabase-ranglista sorának törlése ettől **külön** művelet, szerverválaszt igényel. A Google-fiók leválasztása továbbra is külön elérhető.
5. **Törlés utáni biztonság**: a helyi törlés után automatikus HealthKit-import nem indul újra, amíg a felhasználó külön engedélyezi; ekkor a még elérhető korábbi mérésadatok visszatölthetők. Az Apple Egészség és a Google Sheets távoli adatait a helyi törlés nem érinti.
6. **Profil / hibabejelentés**: magyarul, angolul és németül: előre meghatározott kategória, hibaosztály, alkalmazásverzió és maximum 12 **allowlistás technikai eseménykód**. NINCS szabad szöveg, sem token, GPS, pulzus, Google-azonosító vagy teljes rendszerlog.
7. **Automatikus email**: Supabase Edge Function + Resend, kizárólag szerveroldali emailkulccsal, érvényes Supabase user-JWT-vel és egynapos kvótával.
8. **iOS zárolás utáni mentés**: a helyi mentési sor iOS fájlvédelme első feloldás után lehetővé teszi a háttérműveleteket.

## Egygombos Windows indítás

1. Régi projektet nevezd át biztonsági másolatnak, ne írd felül a fontos saját beállításokat.
2. A teljes ZIP-et csomagold ki `OraNaplo-iOS-Windows` mappába.
3. A `google_oauth.json` csak nyilvános iOS Client ID-t és Bundle ID-t tartalmazhat, titkos tokent nem.
4. Duplán kattints: **`00_MINDENT_INDIT.bat`**.
5. Helyi tesztek → az általad jóváhagyott forrás GitHubra pusholása → GitHub macOS SDK-s fordítás → siker esetén letöltés / Sideloadly.
6. Hiba esetén: `logs/MINDENT_INDIT_...log`, `logs/build_...log` és `output/build-logs-<run-id>/xcodebuild-simulator.log`.

**Nem automatizálható** a saját fejlesztői profil, a HealthKit aláírás, az App Store Connect szerződése, a valós iPhone+Watch hardverteszt vagy a külső Supabase/Resend fiók megnyitása.

## Éles e-mail-beállítás

Kövesd: `docs/EMAIL_HIBAJELENTES_SUPABASE_060.md`. A címzettet a `REPORT_TO_EMAIL` Supabase-secretben add meg, **nem** a GitHubon és nem a Swift-forrásban. Az e-mail csak a szerver telepítése, a privát kulcsok beállítása és a kézi sikeres küldési teszt után aktív.

## Mit jelentenek a zöld tesztek?

A Python/Swift/JS offline tesztek a kód kiválasztott működését és a titokmentes, szintetikus tesztadatokat ellenőrzik. **Nem** bizonyítják a SwiftUI Xcode-típusellenőrzést, az aláírt IPA működését, a HealthKit valós adatolvasását, a Watch hardverkapcsolatot, a Google Sheets-visszakeresést, a Supabase-RLS-t vagy az éles e-mail kézbesítését. A `release_manifest.json` ezeket külön blokkolóként tartja számon.

Éles kiadás előtt szükséges: teljes iOS/watchOS SDK-build, HealthKit és GPS valós próba, 7+ nap szinkronteszt, szerveroldali ranglista-jogosultságteszt, GDPR/App Privacy dokumentumok, Apple StoreKit Sandbox, TestFlight, Apple Review és jóváhagyott, aláírt kiadás.
