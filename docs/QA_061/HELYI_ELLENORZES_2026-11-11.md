# ÓraNapló 0.6.1 – ellenőrzési jegyzőkönyv

**Dátum:** 2026-11-11  
**Környezet:** Linux futtatókörnyezet; macOS/Xcode, Apple HealthKit és valódi készülék nem volt elérhető.

| Ellenőrzés | Eredmény | Fontos megjegyzés |
|---|---|---|
| Python unit + forrásőrző tesztek | **123/123 PASS** | Swift kódhoz kapcsolódó statikus ellenőrzések és Python-modellek; nem valódi iPhone-futás |
| Node.js support/bug-report contract tesztek | **3/3 PASS** | Szerződés-jellegű ellenőrzések, nem telepített Edge Function-teszt |
| Swift parser iOS és watchOS fájlokra | **PASS** | `swiftc -frontend -parse`, **NEM** Xcode typecheck és SDK-fordítás |
| Magyar SyncEngine státuszok statikus szűrése | **0 jelzett** | A 35 státuszelőfordulás és kapcsolódó üzenetek HU/EN/DE fordítást kaptak. Teljes UI audit és screenshot még nincs |
| iOS simulator Apple SDK-s build | **NOT RUN** | Külön GitHub Actions workflow-ra vár |
| watchOS simulator Apple SDK-s build | **NOT RUN** | Külön GitHub Actions workflow-ra vár |
| Valós HealthKit, GPS, Watch és Sheets | **NOT RUN** | Készülék + hitelesített fiókok kellenek |
| Supabase RLS két valós JWT-vel | **NOT RUN** | Személyes Supabase tesztprojekt szükséges |
| Xcode StoreKit lokális vásárlás | **NOT RUN** | Mac/Xcode szükséges |
| Apple Sandbox, 20 külső TestFlight | **NOT RUN** | Fizetős Apple Developer Program és jóváhagyás szükséges |

## Ismert korlátok

- A Watch végső edzésösszesítése sorba állítható, de a teljes, nyers Watch GPS-útvonal és minden egyes pulzusminta utólagos átadása nincs megvalósítva.
- A háttérben végzett HealthKit/GPS megfigyelés nem garantálható iOS rendszerkorlátozások miatt; 7 napos, valódi naplózás nélkül nem állítható a megbízhatóság.
- Pro/Free működési logika forrása ellenőrzött, de StoreKit vásárlás, lejárat és visszaállítás Macen/eszközön még nem ment végig.
- Google OAuth és Supabase hozzáférések felhasználói kulcsok, fiókok és valós REST-jogosultságpróbák nélkül nem igazolhatók.
- Kritikus hibáktól mentesnek **nem** minősíthető az alkalmazás a kiadáskapuk lezárásáig.

## Következő objektív mérföldkő

GitHub Actions „Prepayment audit + unsigned iOS simulator build” futtatása a 0.6.1 forrásával. Az iOS és watchOS `xcodebuild` **mindkettő** legyen zöld; a `xcodebuild-simulator.log` és `xcodebuild-watchsimulator.log` bizonyítékot mentsd el. Ha hiba lép fel, a konkrét hibalistából javítsuk a kódot; csak ezután érdemes készülékes tesztelésre költeni.
