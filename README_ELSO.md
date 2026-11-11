**ÚJ: GitHub Actions 404 / összefűzött run ID javítás: README_053_GITHUB_FUTAS_JAVITAS.md**

# ÓraNapló 0.4.1 – Windows UTF-8 javítás

Lásd: `VALTOZASOK_041.md`.

# ÓraNapló 0.4.0 – teljes Windows + iOS fejlesztői projekt

## Mit tartalmaz ez a változat?

- **Ingyenes alkalmazás és ingyenes alapcsomag:** egyedi, időbélyeges pulzusminták mentése saját Google Sheetsbe.
- **ÓraNapló Pro:** éves, automatikusan megújuló **1 000 Ft-os magyarországi irányár**; tényleges árát majd App Store Connectben kell megadni. Nincs feloldás külön kóddal vagy Gmail-jelszóval.
- **Pro-export:** HRV (SDNN), további Apple Health-adatkategóriák, edzések, 100 m-es GPS-alapú futó/gyalogló szakaszok, előzményimport, kézi napló. A HealthKitben nem rendelkezésre álló adatokat nem találjuk ki.
- **Áttekintés:** utolsó edzés, tényleges Apple Egészség jelzések (ha vannak), saját korábbi lépésszámhoz viszonyított, nem orvosi megfigyelés.
- **Három teljes felületi nyelv:** magyar / English / Deutsch, külön iOS-engedélykérési szövegekkel.
- Google Sheets létrehozása / megnyitása / fiókonkénti elkülönítés.
- Elmaradt mérések pótlása az alkalmazás következő futásakor vagy iOS által engedélyezett háttérindításban; percre pontos szinkron NEM garantált.

## Windowsos indítás

1. Csomagold ki egy új, könnyen megtalálható mappába. **Ne keverd a régebbi projektverzióval.**
2. A saját `google_oauth.json` fájlodat ellenőrizd; a csomagban a korábban konfigurált **nyilvános iOS Client ID és Bundle ID** található. Ne írj be jelszót vagy client secretet.
3. `01_WINDOWS_ELOKESZITES.bat` – Git / Python / GitHub CLI ellenőrzése, konfiguráció és helyi tesztek naplózása.
4. `04_DEMO_MEGNYITASA.bat` – felületi előnézet Windows alatt (demo, nem Apple Health-szimulátor).
5. `02_FELHOS_IPA_EPITES.bat` – GitHub Actions macOS-fordítás, naplózás és aláíratlan IPA.
6. `03_SIDELOADLY_MEGNYITAS.bat` – próbáld telepíteni az IPA-t saját iPhone-ra.

**Figyelmeztetés:** a korábbi, ingyenesen Sideloadly-val aláírt alkalmazásból hiányzott a `com.apple.developer.healthkit` entitlement. Sikeres IPA-build nem oldja meg ezt. A HealthKit-funkciók teljes tesztjéhez megfelelő Apple provisioning/aláírás szükséges.

## Milyen funkció tesztelhető 99 USD előtt?

- Windowsos kód-, konfiguráció- és nyelvi ellenőrzés.
- A felületi előnézet, a Google-bejelentkezés, táblázat-létrehozás és megnyitás (ha a Google OAuth megfelelő).
- A **StoreKit-előfizetést nem tudod élesen aktiválni** az App Store Connect termék létrehozása és Apple-aláírás nélkül. A hiányzó terméknél az app őszintén jelzi, hogy még nem elérhető; a Pro-funkciókat nem oldja fel.
- A valódi egészségadatok olvasása korlátozott lehet a Sideloadly által aláírt verzióban.

## Éles megjelenés előtti lépések

Lásd `docs/APP_STORE_CONNECT_040.md` és `docs/MINOSEGELLENORZES_040.md`.

**A teljes projekt forráskód-prototípus, nem kipróbált App Store-kiadás.** A Swift-szintaktika és a Windowsos helyi tesztek nem helyettesítik a valódi Xcode-fordítást, Apple-aláírást, StoreKit sandbox-próbát, adatvédelmi és funkcionális ellenőrzéseket.
