param([string]$LogPath = "")
if ($LogPath) { Start-Transcript -Path $LogPath -Append | Out-Null }
$ErrorActionPreference = 'Stop'
Write-Output "=== OraNaplo GitHub Actions IPA ==="
Write-Output "Build indult: $(Get-Date -Format o)"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw 'Git nincs PATH-on. Futtasd a 01-es BAT-ot, majd indits uj terminalt.' }
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI nincs PATH-on. Futtasd a 01-es BAT-ot, majd indits uj terminalt.' }
python tools/configure.py
if ($LASTEXITCODE -ne 0) { throw 'Konfiguracios hiba' }
& gh auth status
if ($LASTEXITCODE -ne 0) {
 Write-Output 'Bejelentkezes a GitHub-fiokodba a BONGESZOBEN, nem a BAT-ban taroljuk a jelszavad.'
 & gh auth login --web --git-protocol https
 if ($LASTEXITCODE -ne 0) { throw 'GitHub bejelentkezes megszakadt' }
}
$repo = 'oranaplo-ios-teszt'
$login = (& gh api user --jq '.login').Trim()
if ($LASTEXITCODE -ne 0 -or -not $login) { throw 'Nem sikerult beolvasni a GitHub felhasznaloneved' }
$fullRepo = "$login/$repo"
Write-Output "FIGYELEM: a forraskod NYILVANOS GitHub taroloba kerul: $fullRepo"
Write-Output 'A taroloban semmilyen valos egeszsegadat, bankszamlaadat, Google-jelszo vagy privat token NE legyen.'
$answer = Read-Host 'Engedelyezed a NYILVANOS tarolo letrehozasat / frissiteset? (IGEN)'
if ($answer -ne 'IGEN') { throw 'A nyilvanos GitHub feltoltest nem engedelyezted.' }
if (-not (Test-Path '.git')) { & git init; if ($LASTEXITCODE -ne 0) { throw 'git init hiba' } }
& git branch -M main
# If a previous failed run already staged or committed google_oauth.json,
# remove it from git tracking; the file stays on the customer's PC.
$oldErrorActionPreference = $ErrorActionPreference
try {
 $ErrorActionPreference = 'Continue'
 $null = & git rm --cached --ignore-unmatch -q google_oauth.json 2>$null
} finally { $ErrorActionPreference = $oldErrorActionPreference }
& git add .
& git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
 & git -c user.email='oranaplo-local@users.noreply.github.com' -c user.name='OraNaplo local build' commit -m 'OraNaplo iOS prototipus'
 if ($LASTEXITCODE -ne 0) { throw 'Git commit hiba' }
}
# Windows PowerShell 5.1 converts gh.exe stderr into a terminating error when
# $ErrorActionPreference is Stop. A missing repository is an expected state,
# not an error: check its exit code with a narrowly scoped Continue setting.
$repoExists = $false
$oldErrorActionPreference = $ErrorActionPreference
try {
 $ErrorActionPreference = 'Continue'
 $null = & gh repo view $fullRepo --json name --jq '.name' 2>$null
 $repoExists = ($LASTEXITCODE -eq 0)
} catch {
 $repoExists = $false
} finally {
 $ErrorActionPreference = $oldErrorActionPreference
}

if (-not $repoExists) {
 Write-Output "A GitHub tarolo meg nem letezik: $fullRepo. Letrehozas indul..."
 & gh repo create $fullRepo --public --source . --remote origin --push
 if ($LASTEXITCODE -ne 0) { throw 'GitHub repo letrehozas hiba. Ellenorizd, hogy tudsz-e publikus repot letrehozni.' }
} else {
 Write-Output "Meglevo GitHub tarolo: $fullRepo. Forraskod frissitese..."
 $remoteNames = @(& git remote)
 if ($LASTEXITCODE -ne 0) { throw 'Nem sikerult a git remote-lista kiolvasasa' }
 if ($remoteNames -notcontains 'origin') {
  & git remote add origin "https://github.com/$fullRepo.git"
  if ($LASTEXITCODE -ne 0) { throw 'Git origin tavoli eleres hozzaadasa sikertelen' }
 } else {
  & git remote set-url origin "https://github.com/$fullRepo.git"
  if ($LASTEXITCODE -ne 0) { throw 'Git origin tavoli eleres beallitasa sikertelen' }
 }
 & git push -u origin main
 if ($LASTEXITCODE -ne 0) { throw 'git push hiba' }
}
Write-Output 'macOS-es workflow inditasa ...'
& gh workflow run macos-ipa.yml --repo $fullRepo --ref main
if ($LASTEXITCODE -ne 0) { throw 'Workflow inditas hiba. Ellenorizd Actions engedelyeket a GitHub-on.' }
Start-Sleep -Seconds 8
$runs = & gh run list --repo $fullRepo --workflow macos-ipa.yml --limit 1 --json databaseId --jq '.[0].databaseId'
if ($LASTEXITCODE -ne 0 -or -not $runs) { throw 'A build elindult, de a futasazonosito nem erheto el. Nezd meg a GitHub Actions oldalt.' }
$run = $runs.Trim()
Write-Output "GitHub Actions run: $run"
& gh run watch $run --repo $fullRepo --exit-status
$watchExit=$LASTEXITCODE
New-Item -ItemType Directory -Force -Path output | Out-Null
if ($watchExit -ne 0) {
 Write-Output 'Sikertelen fordítás. A teljes Xcode-hibanaplot a GitHub Actions eszkozben nyisd meg.'
 & gh run download $run --repo $fullRepo --name build-logs --dir 'output\build-logs'
 throw 'macOS xcodebuild hibaval leallt'
}
& gh run download $run --repo $fullRepo --name OraNaplo-unsigned-ipa --dir output
if ($LASTEXITCODE -ne 0) { throw 'IPA letoltes hiba' }
Write-Output 'Kesz: output\OraNaplo-UNSIGNED.ipa (NEM ALAIRT)'
Write-Output 'Kovetkezo: 03_SIDELOADLY_MEGNYITAS.bat, ingyenes Apple ID 7 napos korlatokkal.'
