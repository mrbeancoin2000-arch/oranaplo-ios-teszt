# ÓraNapló Git push hibajavítás — 2026.11.10.

## Hibajelenség
`! [rejected] main -> main (fetch first)` – a régi script minden alkalommal új lokális Git-történetet indított és megpróbálta felülírni a távoli `main` ágat.

## Javítás
Az új `tools/cloud_build.ps1` átmeneti mappába klónozza a meglévő GitHub-tárolót, csak a projekt jóváhagyott forrásfájljait másolja bele, commitol, majd normál `git push`-t végez. A távoli előzményeket nem írja felül. A helyi `.git` nem változik.

## Telepítés
1. A ZIP `tools/cloud_build.ps1` fájlját másold a `C:\Users\szabo\Desktop\OraNaplo-iOS-Windows\tools\` mappába.
2. Írd felül a meglévő fájlt.
3. Indítsd újra a `02_FELHOS_IPA_EPITES.bat` fájlt.
4. Ha megkérdezi, jóváhagyod-e a nyilvános feltöltést, csak akkor írd be az `IGEN` szót, ha ellenőrizted, hogy a forrás nem tartalmaz személyes adatot.

## Fontos
A GitHubon már lévő commitokat megőrzi; a jóváhagyott projektfájlok legfrissebb helyi verzióját használja. A `google_oauth.json`, `logs`, `output`, `.git`, egészségadatok és tokenek nem kerülnek újonnan feltöltésre. Az első korábbi feltöltés tartalmát nem módosítja visszamenőleg.

A javítás a git push elutasítását kezeli. Az iOS Xcode-fordítás és a Sideloadly/HealthKit engedélyek működése ettől még nincs igazolva.
