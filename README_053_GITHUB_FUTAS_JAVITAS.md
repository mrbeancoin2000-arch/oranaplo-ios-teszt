# ÓraNapló 0.5.3 – GitHub Actions futásazonosító javítása

## Mi okozta a hibát?

2026. november 11-én a Windowsos `00_MINDENT_INDIT.bat` a GitHub Actions
indításakor nem egy, hanem több régi futás azonosítóját fűzte össze.
A `cloud_build.ps1` Windows PowerShell 5.1-ben a `ConvertFrom-Json`
JSON-listáját egy elemnek kezelhette, így a `.databaseId` mező minden
futás ID-ját visszaadta egyetlen karakterláncként.
Ebből GitHub API HTTP 404 keletkezett. **A 404 itt nem bizonyítja, hogy
az Apple Xcode-fordítás megbukott.**

## Mi változott?

- Minden új indítás kap egy egyedi, véletlen `request_id` azonosítót.
- A workflow `run-name` mezője hordozza ezt az azonosítót.
- A `tools/select_github_run.py` csak a megfelelő `request_id`, commit SHA
  és `workflow_dispatch` esemény hármasának megfelelő **egyetlen** futás
  numerikus ID-ját adhatja vissza.
- A BAT megvárja a pontos futás eredményét, ellenőrzi a sikeres állapotot,
  csak utána tölti le annak az IPA-ját.
- Ha a valódi Apple SDK-s fordítás hibázik, a rendszer megpróbálja letölteni
  a build naplóit és az elbukott lépések logját. Az IPA-t nem jelöli késznek.
- 8 új teszt fedezi a régi összefűzési hibát és egyéb téves találatokat.

## Mit tegyél?

1. A régi mappádat nevezd át biztonsági másolatnak.
2. Csomagold ki a **teljes** 0.5.3 ZIP-et új mappába.
3. Indítsd a **`00_MINDENT_INDIT.bat`** fájlt.
4. Hagyd jóvá a GitHub feltöltést `IGEN` válasszal.
5. Ha a GitHub Actions valóban piros, küldd el a `logs/build_*.log` és
   `output/build-logs-*/github-failed-steps.log` fájlokat (ha létrejöttek).

Az ellenőrzések nem garantálják előre a GitHubon futó teljes Xcode build
sikerességét, és nem helyettesítik a későbbi HealthKit-aláírást.
