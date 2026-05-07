param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$project = Join-Path $repoRoot 'src\launcher\CodexSwitcherLauncher.csproj'
$publishDir = Join-Path $repoRoot 'artifacts\launcher'
$launcherExeName = "Codex $([char]0x4FBF)$([char]0x6377)$([char]0x542F)$([char]0x52A8)$([char]0x5668).exe"
$rootExe = Join-Path $repoRoot $launcherExeName

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw '.NET SDK was not found. Install .NET 8 SDK first, then rerun this script.'
}

if (-not (Test-Path -LiteralPath $project)) {
    throw "Launcher project not found: $project"
}

if (Test-Path -LiteralPath $publishDir) {
    Remove-Item -LiteralPath $publishDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $publishDir | Out-Null

dotnet publish $project `
    -c Release `
    -r win-x64 `
    --self-contained false `
    -p:PublishSingleFile=true `
    -o $publishDir

if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE"
}

$publishedExe = Join-Path $publishDir $launcherExeName
if (-not (Test-Path -LiteralPath $publishedExe)) {
    $publishedExe = Get-ChildItem -LiteralPath $publishDir -Filter '*.exe' | Select-Object -First 1 -ExpandProperty FullName
}

if (-not $publishedExe -or -not (Test-Path -LiteralPath $publishedExe)) {
    throw "Published exe was not found in: $publishDir"
}

Copy-Item -LiteralPath $publishedExe -Destination $rootExe -Force

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $rootExe
Write-Host "Built: $rootExe"
Write-Host "SHA256: $($hash.Hash)"
