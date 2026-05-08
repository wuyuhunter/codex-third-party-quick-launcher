param(
    [Parameter(Mandatory = $true)]
    [string]$PackagePath,

    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedSha256,

    [int]$ParentProcessId = 0,

    [string]$RelaunchPath
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[CodexQuickLauncher Update] $Message" -ForegroundColor Cyan
}

function Assert-PathInside {
    param(
        [Parameter(Mandatory = $true)][string]$Child,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $childFull = [System.IO.Path]::GetFullPath($Child)
    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
    if (-not $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "路径越界，已停止更新：$childFull"
    }
}

function Copy-UpdateTree {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$TargetRoot,
        [string[]]$ProtectedNames = @()
    )

    $protected = @{}
    foreach ($name in @($ProtectedNames)) {
        $protected[$name.ToLowerInvariant()] = $true
    }

    foreach ($item in Get-ChildItem -LiteralPath $SourceRoot -Force) {
        $key = $item.Name.ToLowerInvariant()
        if ($protected.ContainsKey($key)) {
            Write-Step "保留本机目录/文件：$($item.Name)"
            continue
        }

        $target = Join-Path $TargetRoot $item.Name
        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Force) {
                Copy-Item -LiteralPath $child.FullName -Destination $target -Recurse -Force
            }
        } else {
            Copy-Item -LiteralPath $item.FullName -Destination $target -Force
        }
    }
}

function Remove-StaleInstallItems {
    param(
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [string[]]$ProtectedNames = @()
    )

    $protected = @{}
    foreach ($name in @($ProtectedNames)) {
        $protected[$name.ToLowerInvariant()] = $true
    }

    foreach ($item in Get-ChildItem -LiteralPath $InstallRoot -Force) {
        $key = $item.Name.ToLowerInvariant()
        if ($protected.ContainsKey($key)) {
            continue
        }
        Write-Step "删除旧文件/目录：$($item.Name)"
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }
}

$installRootFull = [System.IO.Path]::GetFullPath($InstallRoot)
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "CodexQuickLauncherUpdate"
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

$logDir = Join-Path $installRootFull "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$logPath = Join-Path $logDir ("update-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

try {
    Start-Transcript -LiteralPath $logPath -Force | Out-Null
} catch {
}

try {
    Write-Step "准备更新：$installRootFull"
    if (-not (Test-Path -LiteralPath $PackagePath)) {
        throw "更新包不存在：$PackagePath"
    }
    if (-not (Test-Path -LiteralPath $installRootFull)) {
        throw "安装目录不存在：$installRootFull"
    }

    if ($ParentProcessId -gt 0) {
        $parent = Get-Process -Id $ParentProcessId -ErrorAction SilentlyContinue
        if ($parent) {
            Write-Step "等待当前启动器退出：PID $ParentProcessId"
            Wait-Process -Id $ParentProcessId -Timeout 120 -ErrorAction SilentlyContinue
        }
    }

    Write-Step "校验更新包 SHA256"
    $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PackagePath).Hash
    if ($actualHash -ne $ExpectedSha256) {
        throw "更新包 SHA256 校验失败。期望 $ExpectedSha256，实际 $actualHash"
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $extractRoot = Join-Path $tempRoot "extract-$stamp"
    $backupRoot = Join-Path $tempRoot "backup-$stamp"
    Assert-PathInside -Child $extractRoot -Parent $tempRoot
    Assert-PathInside -Child $backupRoot -Parent $tempRoot

    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

    Write-Step "解压更新包"
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $extractRoot -Force

    $sourceRoot = $extractRoot
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot "tools"))) {
        $children = @(Get-ChildItem -LiteralPath $extractRoot -Force | Where-Object { $_.PSIsContainer })
        if ($children.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $children[0].FullName "tools"))) {
            $sourceRoot = $children[0].FullName
        }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot "tools"))) {
        throw "更新包结构无效：根目录下没有 tools 文件夹。"
    }

    $protected = @("state", "logs", "secrets", ".omx")
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    Write-Step "备份当前程序文件到临时目录"
    Copy-UpdateTree -SourceRoot $installRootFull -TargetRoot $backupRoot -ProtectedNames $protected

    try {
        Write-Step "清理旧版本残留文件"
        Remove-StaleInstallItems -InstallRoot $installRootFull -ProtectedNames $protected
        Write-Step "覆盖安装目录文件"
        Copy-UpdateTree -SourceRoot $sourceRoot -TargetRoot $installRootFull -ProtectedNames $protected
    } catch {
        Write-Step "覆盖失败，尝试恢复临时备份"
        Copy-UpdateTree -SourceRoot $backupRoot -TargetRoot $installRootFull -ProtectedNames @()
        throw
    }

    Write-Step "更新完成"
    if ($RelaunchPath -and (Test-Path -LiteralPath $RelaunchPath)) {
        Write-Step "重新打开启动器"
        Start-Process -FilePath $RelaunchPath -WorkingDirectory $installRootFull | Out-Null
    }
} catch {
    Write-Host "更新失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "日志：$logPath" -ForegroundColor Yellow
    Read-Host "按 Enter 关闭"
    exit 1
} finally {
    try {
        Stop-Transcript | Out-Null
    } catch {
    }
}
