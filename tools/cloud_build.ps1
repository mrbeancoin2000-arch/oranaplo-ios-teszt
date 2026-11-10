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
 @('.gitignore','project.yml','google_oauth.example.json') | ForEach-Object { Add-Approved $_ }
 Get-ChildItem -LiteralPath $projectRoot -File -Force | Where-Object {
  @('.bat','.md') -contains $_.Extension.ToLowerInvariant()
 } | ForEach-Object { Add-Approved $_.Name }
 Add-ByExtension '.github\workflows' @('.yml','.yaml') $false
 Add-ByExtension 'ios\Sources' @('.swift','.m','.h') $true
 Add-Approved 'ios\Resources\Info.plist'
 Add-Approved 'ios\Resources\OraNaplo.entitlements'
 Add-ByExtension 'ios\Resources\Assets.xcassets' @('.json','.png','.jpg','.jpeg') $true
 Add-ByExtension 'tools' @('.ps1','.py') $false
 Add-ByExtension 'tests' @('.py','.html') $false
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
} finally {
 if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output 'macOS-es workflow inditasa ...'
& gh workflow run macos-ipa.yml --repo $fullRepo --ref main -f runner=macos-15-intel
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
 Write-Output "GitHub Actions futas sikertelen: https://github.com/$fullRepo/actions/runs/$run"
 Write-Output 'Ha nincs lepeshistoria / build-logs artifact, a runner valoszinuleg nem indult el (GitHub infrastruktura).'
 Write-Output 'Ha xcodebuild.log keletkezett, abban a tenyleges Swift/Xcode forditasi hiba olvashato.'
 # The runner may fail before any step runs; that case creates no artifacts.
 $prevErrorActionPreference = $ErrorActionPreference
 try {
  $ErrorActionPreference = 'Continue'
  & gh run view $run --repo $fullRepo --json jobs --jq '.jobs[] | [.name, .conclusion, (.steps | length)] | @tsv'
  & gh run download $run --repo $fullRepo --name build-logs --dir 'output\build-logs' 2>$null
 } finally { $ErrorActionPreference = $prevErrorActionPreference }
 throw 'GitHub Actions futas sikertelen (runner foglalasi vagy Xcode forditasi hiba; ellenorizd a GitHub annotations es steps reszt)'
}
& gh run download $run --repo $fullRepo --name OraNaplo-unsigned-ipa --dir output
if ($LASTEXITCODE -ne 0) { throw 'IPA letoltes hiba' }
Write-Output 'Kesz: output\OraNaplo-UNSIGNED.ipa (NEM ALAIRT)'
Write-Output 'Kovetkezo: 03_SIDELOADLY_MEGNYITAS.bat, ingyenes Apple ID 7 napos korlatokkal.'
