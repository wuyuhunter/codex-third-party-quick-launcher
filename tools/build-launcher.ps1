param()

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
$project = Join-Path $repoRoot 'src\launcher\CodexSwitcherLauncher.csproj'
$program = Join-Path $repoRoot 'src\launcher\Program.cs'
$icon = Join-Path $repoRoot 'src\launcher\codex-danger.ico'
$publishDir = Join-Path $repoRoot 'artifacts\launcher'
$launcherExeName = "Codex $([char]0x4FBF)$([char]0x6377)$([char]0x542F)$([char]0x52A8)$([char]0x5668).exe"
$rootExe = Join-Path $repoRoot $launcherExeName

function Get-FrameworkCSharpCompiler {
    $candidates = @(
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
        (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

if (-not (Test-Path -LiteralPath $project)) {
    throw "Launcher project not found: $project"
}
if (-not (Test-Path -LiteralPath $program)) {
    throw "Launcher source not found: $program"
}

if (Test-Path -LiteralPath $publishDir) {
    Remove-Item -LiteralPath $publishDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $publishDir | Out-Null

$publishedExe = Join-Path $publishDir $launcherExeName
$csc = Get-FrameworkCSharpCompiler

if ($csc) {
    $compilerArgs = @(
        '/nologo',
        '/target:winexe',
        '/optimize+',
        "/out:$publishedExe",
        '/reference:System.dll',
        '/reference:System.Core.dll',
        '/reference:System.Windows.Forms.dll',
        '/reference:System.Drawing.dll'
    )
    if (Test-Path -LiteralPath $icon) {
        $compilerArgs += "/win32icon:$icon"
    }
    $compilerArgs += $program

    & $csc @compilerArgs
    if ($LASTEXITCODE -ne 0) {
        throw "csc.exe failed with exit code $LASTEXITCODE"
    }
} else {
    if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        throw '.NET Framework csc.exe and dotnet SDK were not found. Install .NET Framework 4.8 Developer Pack or a compatible .NET SDK.'
    }

    dotnet publish $project `
        -c Release `
        -p:DebugType=None `
        -p:DebugSymbols=false `
        -o $publishDir

    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE"
    }

    if (-not (Test-Path -LiteralPath $publishedExe)) {
        $publishedExe = Get-ChildItem -LiteralPath $publishDir -Filter '*.exe' | Select-Object -First 1 -ExpandProperty FullName
    }
}

if (-not $publishedExe -or -not (Test-Path -LiteralPath $publishedExe)) {
    throw "Published exe was not found in: $publishDir"
}

Copy-Item -LiteralPath $publishedExe -Destination $rootExe -Force

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $rootExe
Write-Host "Built: $rootExe"
Write-Host "SHA256: $($hash.Hash)"
