param([string]$LogPath = "")
if ($LogPath) { Start-Transcript -Path $LogPath -Append | Out-Null }
$ErrorActionPreference = 'Stop'
Write-Output "=== OraNaplo Windows Setup ==="
Write-Output "Idopont: $(Get-Date -Format o)"
Write-Output "Windows: $([Environment]::OSVersion.VersionString)"
Write-Output "Konyvtar: $PSScriptRoot"
function HasExe($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }
$apps = @(
  @{id='Git.Git'; cmd='git'; name='Git'},
  @{id='Python.Python.3.13'; cmd='py'; name='Python 3'},
  @{id='GitHub.cli'; cmd='gh'; name='GitHub CLI'}
)
foreach ($app in $apps) {
  if (HasExe $app.cmd) { Write-Output "$($app.name): OK"; continue }
  Write-Output "$($app.name): hianyzik. Winget telepites indul ..."
  if (-not (HasExe 'winget')) { Write-Output 'Nincs winget. Kezi telepites szukseges a Microsoft Store App Installer vagy az official oldalrol.'; exit 10 }
  & winget install --id $app.id --exact --accept-source-agreements --accept-package-agreements --silent
  if ($LASTEXITCODE -ne 0) { Write-Output "Winget hibakod: $LASTEXITCODE"; exit 11 }
}
$python = $null
if (HasExe 'py') { $python='py'; $pArgs=@('-3') } elseif (HasExe 'python') { $python='python'; $pArgs=@() }
if (-not $python) { Write-Output 'Python telepitve, de az uj PATH meg nem latszik. Inditsd ujra a terminalt.'; exit 12 }
& $python @pArgs --version
& $python @pArgs tools/configure.py
if ($LASTEXITCODE -ne 0) { exit 13 }
& $python @pArgs -m unittest discover -s tests -p 'test_*.py' -v
if ($LASTEXITCODE -ne 0) { exit 14 }
Write-Output 'Helyi tesztek sikeresek. GitHub-auth az elso felhobuild soran lesz.'
Write-Output 'FIGYELEM: Xcode es Apple HealthKit Windowsra nem telepitheto. A 02-es bat MACOS-os GITHUB RUNNERT hasznal.'
