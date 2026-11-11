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
# The existing repository contains previous commits. Never rewrite its history
# from a freshly unpacked ZIP (that leads to non-fast-forward/fetch-first errors).
# Clone its current main branch into a temporary directory, copy the approved
# source files, then commit and push on top of the remote history.
# This also avoids uploading google_oauth.json, build logs, keys or health data.
function Invoke-Checked([scriptblock]$Command, [string]$Message) {
 $oldPreference = $ErrorActionPreference
 try {
  # Windows PowerShell 5.1 treats stderr from native commands as errors under Stop.
  $ErrorActionPreference = 'Continue'
  & $Command
  $nativeExit = $LASTEXITCODE
 } finally { $ErrorActionPreference = $oldPreference }
 if ($nativeExit -ne 0) { throw "$Message (exit: $nativeExit)" }
}

$repoExists = $false
$oldPreference = $ErrorActionPreference
try {
 $ErrorActionPreference = 'Continue'
 $null = & gh repo view $fullRepo --json name --jq '.name' 2>$null
 $repoExists = ($LASTEXITCODE -eq 0)
} catch { $repoExists = $false } finally { $ErrorActionPreference = $oldPreference }

if (-not $repoExists) {
 Write-Output "A GitHub tarolo meg nem letezik: $fullRepo. Letrehozas indul..."
 Invoke-Checked { gh repo create $fullRepo --public } 'Nem sikerult letrehozni a GitHub tarolot'
} else {
 Write-Output "Meglevo GitHub tarolo: $fullRepo. Aktualis main letoltese a biztonsagos frissiteshez."
}

$projectRoot = (Get-Location).Path.TrimEnd('\','/')
$stage = Join-Path ([System.IO.Path]::GetTempPath()) ('OraNaplo-SafePush-' + [Guid]::NewGuid().ToString('N'))
try {
 Invoke-Checked { git clone "https://github.com/$fullRepo.git" $stage } 'GitHub tarolo letoltese sikertelen'
 # An empty, newly created repo may have no commits yet. Create the main ref.
 & git -C $stage symbolic-ref HEAD refs/heads/main
 if ($LASTEXITCODE -ne 0) { throw 'Nem sikerult beallitani a main agat' }

 $approved = New-Object 'System.Collections.Generic.List[string]'
 function Add-Approved([string]$Relative) {
  $full = Join-Path $projectRoot $Relative
  if (Test-Path -LiteralPath $full -PathType Leaf) { $approved.Add($Relative) }
 }
 function Add-ByExtension([string]$Folder,[string[]]$AllowedExtensions,[bool]$Recursive=$false) {
  $path = Join-Path $projectRoot $Folder
  if (-not (Test-Path -LiteralPath $path -PathType Container)) { return }
  Get-ChildItem -LiteralPath $path -Recurse:$Recursive -File -Force | Where-Object {
   $AllowedExtensions -contains $_.Extension.ToLowerInvariant()
  } | ForEach-Object {
   $relative = $_.FullName.Substring($projectRoot.Length).TrimStart('\','/')
   $approved.Add($relative)
  }
 }
 # Explicit upload allowlist: do not push arbitrary files from customers' PCs.
 @('.gitignore','project.yml','google_oauth.example.json','release_manifest.json') | ForEach-Object { Add-Approved $_ }
 Get-ChildItem -LiteralPath $projectRoot -File -Force | Where-Object {
  @('.bat','.md') -contains $_.Extension.ToLowerInvariant()
 } | ForEach-Object { Add-Approved $_.Name }
 Add-ByExtension '.github\workflows' @('.yml','.yaml') $false
 Add-ByExtension 'ios\Sources' @('.swift','.m','.h') $true
 Add-Approved 'ios\Resources\Info.plist'
 Add-Approved 'ios\Resources\OraNaplo.entitlements'
 Add-ByExtension 'ios\Resources' @('.strings','.stringsdict','.xcstrings') $true
 Add-ByExtension 'ios\Resources\Assets.xcassets' @('.json','.png','.jpg','.jpeg') $true
 Add-ByExtension 'tools' @('.ps1','.py') $false
 Add-ByExtension 'tests' @('.py','.html','.swift','.js','.xml','.json','.storekit') $true
 Add-ByExtension 'scripts' @('.gs','.js','.json') $true
 Add-ByExtension 'website' @('.html','.css','.js','.svg','.txt') $true
 Add-ByExtension 'docs' @('.md') $true
 if ($approved.Count -lt 10) { throw "Tulsagosan keves jovahagyott forrasfajl: $($approved.Count)" }
 foreach ($rel in ($approved | Select-Object -Unique)) {
  $dest = Join-Path $stage $rel
  $parent = Split-Path -Parent $dest
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -Path $parent -ItemType Directory -Force | Out-Null }
  Copy-Item -LiteralPath (Join-Path $projectRoot $rel) -Destination $dest -Force
 }
 Write-Output "Jovahagyott fajlok szama: $($approved.Count). Google-jelszo, OAuth-token, helyi log es egeszsegadat nem kerul feltoltesre."
 Invoke-Checked { git -C $stage add --all } 'git add hiba'
 $oldPreference = $ErrorActionPreference
 try {
  $ErrorActionPreference = 'Continue'
  & git -C $stage diff --cached --quiet
  $hasChanges = ($LASTEXITCODE -eq 1)
  $diffExit = $LASTEXITCODE
 } finally { $ErrorActionPreference = $oldPreference }
 if ($diffExit -gt 1) { throw 'git diff hiba' }
 if ($hasChanges) {
  Invoke-Checked {
   git -C $stage -c user.email='oranaplo-local@users.noreply.github.com' -c user.name='OraNaplo local build' commit -m 'OraNaplo forraskod frissitese (safe sync)'
  } 'git commit hiba'
  Invoke-Checked { git -C $stage push -u origin main } 'GitHub push hiba: a tavoli main idokozben valtozhatott'
  Write-Output 'Sikeres GitHub feltoltes, korabbi commitok megorizve.'
 } else {
  Write-Output 'A GitHub mar a legfrissebb forrast tartalmazza. Nem szukseges uj commit.'
 }
 $expectedSHA = [string](& git -C $stage rev-parse HEAD)
 if ($LASTEXITCODE -ne 0 -or -not $expectedSHA.Trim()) { throw 'Nem olvashato a feltoltott commit SHA-ja' }
 $expectedSHA = $expectedSHA.Trim()
 Write-Output "GitHub commit ellenorzese: $expectedSHA"
} finally {
 if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}
# Each dispatch carries a unique token in the GitHub run displayTitle.
# Do not use @($json | ConvertFrom-Json) on Windows PowerShell 5.1:
# it can wrap the complete array in ONE element, and [string] on the
# databaseId property joins ALL old run IDs (the 2026-11-11 HTTP 404 bug).
$requestID = [Guid]::NewGuid().ToString('N')
$expectedTitle = "OraNaplo CI $requestID"
Write-Output "macOS workflow inditasa. Egyedi request: $requestID"
& gh workflow run macos-ipa.yml --repo $fullRepo --ref main -f runner=macos-15-intel -f "request_id=$requestID"
if ($LASTEXITCODE -ne 0) { throw 'Workflow inditas hiba. Ellenorizd Actions engedelyeket a GitHub-on.' }
$run = ''
for ($attempt = 1; $attempt -le 36 -and -not $run; $attempt++) {
 Start-Sleep -Seconds 5
 $oldPreference = $ErrorActionPreference
 try {
  $ErrorActionPreference = 'Continue'
  $rawLines = & gh run list --repo $fullRepo --workflow macos-ipa.yml --event workflow_dispatch --limit 75 --json databaseId,headSha,event,displayTitle 2>$null
  $listExit = $LASTEXITCODE
 } finally { $ErrorActionPreference = $oldPreference }
 if ($listExit -ne 0 -or -not $rawLines) { continue }
 # Python selects exactly one numeric ID by unique token + exact Git commit.
 # It is tested independently with fake GitHub JSON (including old runs).
 $oldPreference = $ErrorActionPreference
 try {
  $ErrorActionPreference = 'Continue'
  $selected = @(($rawLines -join "`n") | & python tools/select_github_run.py --token $requestID --sha $expectedSHA 2>$null)
  $selectionExit = $LASTEXITCODE
 } finally { $ErrorActionPreference = $oldPreference }
 if ($selectionExit -eq 3) { throw 'Tobb futas egyezik a request azonositojaval. Biztonsagi okbol leallitva.' }
 if ($selectionExit -eq 4) { throw 'Ervenytelen GitHub futaslista vagy kimenet. Nem valasztunk rossz IPA-t.' }
 if ($selectionExit -eq 0) {
  if ($selected.Count -ne 1) { throw 'Hibas valasz a workflow futasvalaszto programtol.' }
  $run = ([string]$selected[0]).Trim()
  if ($run -notmatch '^[0-9]{5,20}$') { throw "Ervenytelen workflow run ID: $run" }
 }
}
if (-not $run) { throw "Nem talalhato a SAJAT uj GitHub Actions futas. Request: $requestID Commit: $expectedSHA. Ne hasznalj regi IPA-t." }
Write-Output "Uj GitHub Actions futasazonosito: $run (commit: $expectedSHA, request: $requestID)"
Write-Output "Futas: https://github.com/$fullRepo/actions/runs/$run"
$oldPreference = $ErrorActionPreference
try {
 $ErrorActionPreference = 'Continue'
 & gh run watch $run --repo $fullRepo --exit-status
 $watchExit = $LASTEXITCODE
} finally { $ErrorActionPreference = $oldPreference }
# Verify the ACTUAL resulting run; never treat a past success as the new result.
$detailsJSON = & gh run view $run --repo $fullRepo --json databaseId,headSha,event,displayTitle,status,conclusion,url
if ($LASTEXITCODE -ne 0 -or -not $detailsJSON) { throw "A pontos Github futas eredmenye nem olvashato: $run" }
$details = ConvertFrom-Json -InputObject ($detailsJSON -join "`n")
if ([string]$details.databaseId -ne $run -or [string]$details.displayTitle -ne $expectedTitle -or
    [string]$details.headSha -ne $expectedSHA -or [string]$details.event -ne 'workflow_dispatch') {
 throw "GitHub run azonositas elteres, letoltes megszakitva. ID: $run"
}
if ([string]$details.status -ne 'completed' -or [string]$details.conclusion -ne 'success') { $watchExit = 1 }
Write-Output "GitHub workflow eredmeny: $($details.status) / $($details.conclusion)"
New-Item -ItemType Directory -Force -Path output | Out-Null
# Every workflow uses its own download directory to avoid stale-file conflicts.
$diagnosticDirectory = Join-Path 'output' ("diagnostics-$run")
$buildLogDirectory = Join-Path 'output' ("build-logs-$run")
$prevErrorActionPreference = $ErrorActionPreference
try {
 $ErrorActionPreference = 'Continue'
 New-Item -ItemType Directory -Force -Path $diagnosticDirectory | Out-Null
 & gh run download $run --repo $fullRepo --name ipa-diagnostics --dir $diagnosticDirectory 2>$null
 $diagnosticExit = $LASTEXITCODE
 if ($diagnosticExit -eq 0) {
  Write-Output "IPA ellenorzes reszletei: $diagnosticDirectory\ipa-verification.txt"
  $diagnosticPath = Join-Path $diagnosticDirectory 'ipa-verification.txt'
  foreach ($name in @('build-inputs.txt','plist-normalize.txt','ipa-verification.txt')) {
   $diagnosticPath = Join-Path $diagnosticDirectory $name
   if (Test-Path -LiteralPath $diagnosticPath) {
    Write-Output "=== $name ==="
    Get-Content -LiteralPath $diagnosticPath | ForEach-Object { Write-Output $_ }
   }
  }
 }
 if ($watchExit -ne 0) {
  New-Item -ItemType Directory -Force -Path $buildLogDirectory | Out-Null
  & gh run download $run --repo $fullRepo --name build-logs --dir $buildLogDirectory 2>$null
  if ($LASTEXITCODE -eq 0) { Write-Output "Build naplo: $buildLogDirectory\xcodebuild.log" }
  $failedStepsLog = Join-Path $buildLogDirectory 'github-failed-steps.log'
  & gh run view $run --repo $fullRepo --log-failed 2>$null | Out-File -LiteralPath $failedStepsLog -Encoding utf8
  if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $failedStepsLog)) {
   Write-Output "Hibas GitHub-lepesek naploja: $failedStepsLog"
   Get-Content -LiteralPath $failedStepsLog -Tail 50 | ForEach-Object { Write-Output $_ }
  }
 }
} finally { $ErrorActionPreference = $prevErrorActionPreference }

if ($watchExit -ne 0) {
 Write-Output "GitHub Actions futas sikertelen: https://github.com/$fullRepo/actions/runs/$run"
 Write-Output 'Ha a Verify IPA configuration lepese piros, az ipa-verification.txt irja le a pontos hibas mezot.'
 Write-Output 'Ha az Unsigned build lepese piros, az xcodebuild.log a relevans naplo.'
 throw 'Github Actions build sikertelen: ellenorizd a fent kiirt pontos hibauzenetet.'
}
# Download the successful IPA into a run-specific folder, then replace output IPA.
$ipaDirectory = Join-Path 'output' ("ipa-$run")
New-Item -ItemType Directory -Force -Path $ipaDirectory | Out-Null
& gh run download $run --repo $fullRepo --name OraNaplo-unsigned-ipa --dir $ipaDirectory
if ($LASTEXITCODE -ne 0) { throw 'IPA letoltes hiba' }
$downloadedIPA = Join-Path $ipaDirectory 'OraNaplo-UNSIGNED.ipa'
if (-not (Test-Path -LiteralPath $downloadedIPA)) { throw "A letoltott IPA hianyzik: $downloadedIPA" }
Copy-Item -LiteralPath $downloadedIPA -Destination 'output\OraNaplo-UNSIGNED.ipa' -Force
Write-Output 'Kesz: output\OraNaplo-UNSIGNED.ipa (NEM ALAIRT)'
Write-Output 'Kovetkezo: 03_SIDELOADLY_MEGNYITAS.bat, ingyenes Apple ID 7 napos korlatokkal.'
