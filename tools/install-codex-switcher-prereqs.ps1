param(
    [switch]$Full,
    [ValidateSet("omx", "git", "pwsh", "wt")]
    [string]$AdvancedComponent,
    [switch]$VerifyOnly
)

$ErrorActionPreference = "Stop"
$script:LauncherProductName = "Codex 便捷启动器"
$script:LauncherVersion = "v0.3.16"
$script:LauncherAuthors = "夏小曦 & 知晴 & 砚行"
$script:LauncherLicense = "MIT 协议"
$script:LauncherGitHub = "GitHub: 待创建"
$script:LauncherGitee = "Gitee: 待创建"
$script:NpmMirror = "https://registry.npmmirror.com"
$script:NodeMirrorRoots = @(
    "https://npmmirror.com/mirrors/node",
    "https://mirrors.huaweicloud.com/nodejs"
)
$script:NodeChannels = @("latest-v24.x", "latest-v22.x", "latest-v20.x")

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-CommandPath {
    param([string[]]$Names)

    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) {
            return $cmd.Source
        }
    }

    return $null
}

function Update-CurrentPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $extra = @(
        (Join-Path $env:APPDATA "npm"),
        "C:\Program Files\nodejs",
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps")
    )
    $env:Path = (@($machinePath, $userPath) + $extra | Where-Object { $_ }) -join ";"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Write-Host "> $FilePath $($Arguments -join ' ')" -ForegroundColor DarkGray
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code $LASTEXITCODE`: $FilePath"
    }
}

function Require-Winget {
    $winget = Get-CommandPath -Names @("winget.exe", "winget")
    if ($winget) {
        return $winget
    }

    Write-Host "未找到 winget。完整安装需要 Microsoft App Installer / winget。" -ForegroundColor Yellow
    try {
        Start-Process "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
    } catch {
        Start-Process "https://aka.ms/getwinget"
    }
    throw "缺少 winget / App Installer。"
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Sources = @("winget", "msstore")
    )

    $winget = Require-Winget
    foreach ($source in $Sources) {
        try {
            Write-Step "安装 $Name"
            Invoke-Native -FilePath $winget -Arguments @(
                "install",
                "--id", $Id,
                "--exact",
                "--source", $source,
                "--accept-package-agreements",
                "--accept-source-agreements"
            )
            return
        } catch {
            Write-Host "$Name 从 $source 安装失败，尝试下一个来源。" -ForegroundColor Yellow
        }
    }

    throw "$Name 安装失败。"
}

function Ensure-NodeAndNpm {
    if ((Get-CommandPath -Names @("node.exe", "node")) -and (Get-CommandPath -Names @("npm.cmd", "npm.ps1", "npm"))) {
        Write-Host "Node.js / npm 已安装。" -ForegroundColor Green
        return
    }

    $msiUrl = Resolve-NodeMsiUrl
    $downloadDir = Join-Path $env:TEMP "codex-quick-launcher-install"
    New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null
    $msiPath = Join-Path $downloadDir (Split-Path -Leaf ([uri]$msiUrl).AbsolutePath)

    Write-Step "下载 Node.js LTS / npm（镜像源）"
    Write-Host $msiUrl -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

    Write-Step "安装 Node.js LTS / npm"
    Invoke-Native -FilePath "msiexec.exe" -Arguments @("/i", $msiPath, "/passive", "/norestart")
    Update-CurrentPath

    if (-not ((Get-CommandPath -Names @("node.exe", "node")) -and (Get-CommandPath -Names @("npm.cmd", "npm.ps1", "npm")))) {
        throw "Node.js 安装后仍未找到 node/npm。请重新打开安装窗口或重启电脑后再检测。"
    }
}

function Resolve-NodeMsiUrl {
    $arch = "x64"
    if ($env:PROCESSOR_ARCHITECTURE -match "ARM64") {
        $arch = "arm64"
    } elseif ($env:PROCESSOR_ARCHITECTURE -match "86") {
        $arch = "x86"
    }

    foreach ($root in $script:NodeMirrorRoots) {
        foreach ($channel in $script:NodeChannels) {
            $indexUrl = "$root/$channel/"
            try {
                $response = Invoke-WebRequest -Uri $indexUrl -UseBasicParsing -TimeoutSec 30
                $pattern = "node-v\d+\.\d+\.\d+-$arch\.msi"
                $match = [regex]::Matches($response.Content, $pattern) | Select-Object -First 1
                if ($match) {
                    return "$indexUrl$($match.Value)"
                }
            } catch {
                Write-Host "读取 $indexUrl 失败，尝试下一个镜像。" -ForegroundColor Yellow
            }
        }
    }

    throw "无法从当前镜像源解析 Node.js MSI 下载地址。"
}

function Test-OptionalTools {
    if (Get-CommandPath -Names @("pwsh.exe", "pwsh")) {
        Write-Host "PowerShell 7 已安装。" -ForegroundColor Green
    } else {
        Write-Host "PowerShell 7 未安装：当前工具可用系统自带 Windows PowerShell 5.1 运行，可稍后再装。" -ForegroundColor Yellow
    }

    if (Get-CommandPath -Names @("wt.exe", "wt")) {
        Write-Host "Windows Terminal 已安装。" -ForegroundColor Green
    } else {
        Write-Host "Windows Terminal 未安装：启动 Codex 时会回退到普通 PowerShell 窗口，可稍后再装。" -ForegroundColor Yellow
    }
}

function Ensure-PowerShell7 {
    if (Get-CommandPath -Names @("pwsh.exe", "pwsh")) {
        Write-Host "PowerShell 7 已安装。" -ForegroundColor Green
        return
    }

    Write-Host "准备通过 winget 安装 PowerShell 7。本地网络环境下可能较慢；这是完整安装项，不影响核心功能。" -ForegroundColor Yellow
    Install-WingetPackage -Id "Microsoft.PowerShell" -Name "PowerShell 7" -Sources @("winget")
    Update-CurrentPath
}

function Ensure-WindowsTerminal {
    if (Get-CommandPath -Names @("wt.exe", "wt")) {
        Write-Host "Windows Terminal 已安装。" -ForegroundColor Green
        return
    }

    Write-Host "准备通过 winget / Microsoft Store 安装 Windows Terminal。本地网络环境下可能较慢；这是完整安装项，不影响核心功能。" -ForegroundColor Yellow
    Install-WingetPackage -Id "Microsoft.WindowsTerminal" -Name "Windows Terminal" -Sources @("winget", "msstore")
    Update-CurrentPath
}

function Ensure-FullTools {
    Write-Step "完整安装：PowerShell 7 和 Windows Terminal"
    Ensure-PowerShell7
    Ensure-WindowsTerminal
}

function Ensure-GitForWindows {
    if (Get-CommandPath -Names @("git.exe", "git")) {
        Write-Host "Git for Windows 已安装。" -ForegroundColor Green
        return
    }

    Write-Host "准备通过 winget 安装 Git for Windows，用于 GitHub/Gitee 仓库同步和开源协作。" -ForegroundColor Yellow
    Install-WingetPackage -Id "Git.Git" -Name "Git for Windows" -Sources @("winget")
    Update-CurrentPath
}

function Ensure-OmxCli {
    Ensure-NodeAndNpm
    Ensure-NpmMirror

    $npm = Get-CommandPath -Names @("npm.cmd", "npm.ps1", "npm")
    if (-not $npm) {
        throw "未找到 npm，无法安装 OMX 增强组件。"
    }

    Write-Step "安装或更新 OMX 增强组件"
    Invoke-Native -FilePath $npm -Arguments @("install", "-g", "oh-my-codex", "--registry=$script:NpmMirror")
    Update-CurrentPath

    if (-not (Get-CommandPath -Names @("omx.cmd", "omx.ps1", "omx"))) {
        throw "OMX 安装后仍未找到 omx 命令。请重新打开安装窗口或重启终端后再检测。"
    }
    Write-Host "OMX 增强组件已安装。" -ForegroundColor Green
}

function Install-AdvancedComponent {
    param([Parameter(Mandatory = $true)][string]$Name)

    switch ($Name) {
        "omx" {
            Ensure-OmxCli
        }
        "git" {
            Ensure-GitForWindows
        }
        "pwsh" {
            Ensure-PowerShell7
        }
        "wt" {
            Ensure-WindowsTerminal
        }
        default {
            throw "Unknown advanced component: $Name"
        }
    }
}

function Ensure-NpmMirror {
    Update-CurrentPath
    $npm = Get-CommandPath -Names @("npm.cmd", "npm.ps1", "npm")
    if (-not $npm) {
        throw "未找到 npm，无法配置镜像源。"
    }

    Write-Step "配置 npm 镜像源"
    Invoke-Native -FilePath $npm -Arguments @("config", "set", "registry", $script:NpmMirror)
    Invoke-Native -FilePath $npm -Arguments @("config", "set", "fetch-retries", "5")
    Invoke-Native -FilePath $npm -Arguments @("config", "set", "fetch-retry-maxtimeout", "120000")
}

function Ensure-CodexCli {
    Update-CurrentPath
    if (Get-CommandPath -Names @("codex.cmd", "codex.ps1", "codex")) {
        Write-Host "Codex CLI 已安装。" -ForegroundColor Green
        return
    }

    $npm = Get-CommandPath -Names @("npm.cmd", "npm.ps1", "npm")
    if (-not $npm) {
        throw "未找到 npm，无法安装 Codex CLI。"
    }

    Write-Step "安装 Codex CLI"
    Invoke-Native -FilePath $npm -Arguments @("install", "-g", "@openai/codex", "--registry=$script:NpmMirror")
    Update-CurrentPath
}

function Ensure-CodexFirstRunConfig {
    $codexDir = Join-Path $env:USERPROFILE ".codex"
    $configPath = Join-Path $codexDir "config.toml"
    New-Item -ItemType Directory -Force -Path $codexDir | Out-Null

    $defaultConfig = @"
model_provider = "OpenAI"
model = "gpt-5.5"
model_reasoning_effort = "high"
disable_response_storage = true
network_access = "enabled"
windows_wsl_setup_acknowledged = true

[model_providers.OpenAI]
name = "OpenAI"
base_url = "https://api.openai.com/v1"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
supports_websockets = false

[windows]
sandbox = "unelevated"

[notice]
fast_default_opt_out = true
"@

    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-Step "初始化 Codex 配置"
        Set-Content -LiteralPath $configPath -Value $defaultConfig -Encoding UTF8
        return
    }

    $content = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
    $changed = $false
    if ([string]::IsNullOrWhiteSpace($content)) {
        Set-Content -LiteralPath $configPath -Value $defaultConfig -Encoding UTF8
        return
    }

    $linesToPrepend = @()
    if ($content -notmatch '(?m)^model_provider\s*=') { $linesToPrepend += 'model_provider = "OpenAI"' }
    if ($content -notmatch '(?m)^model\s*=') { $linesToPrepend += 'model = "gpt-5.5"' }
    if ($content -notmatch '(?m)^model_reasoning_effort\s*=') { $linesToPrepend += 'model_reasoning_effort = "high"' }
    if ($content -notmatch '(?m)^disable_response_storage\s*=') { $linesToPrepend += 'disable_response_storage = true' }
    if ($content -notmatch '(?m)^network_access\s*=') { $linesToPrepend += 'network_access = "enabled"' }
    if ($content -notmatch '(?m)^windows_wsl_setup_acknowledged\s*=') { $linesToPrepend += 'windows_wsl_setup_acknowledged = true' }

    if ($linesToPrepend.Count -gt 0) {
        $content = (($linesToPrepend -join "`r`n") + "`r`n" + $content)
        $changed = $true
    }

    if ($content -notmatch '(?m)^\[model_providers\.OpenAI\]') {
        if (-not $content.EndsWith("`n")) { $content += "`r`n" }
        $content += @"

[model_providers.OpenAI]
name = "OpenAI"
base_url = "https://api.openai.com/v1"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
supports_websockets = false
"@
        $changed = $true
    }

    if ($content -notmatch '(?m)^\[windows\]') {
        if (-not $content.EndsWith("`n")) { $content += "`r`n" }
        $content += "`r`n[windows]`r`nsandbox = `"unelevated`"`r`n"
        $changed = $true
    }

    if ($content -notmatch '(?m)^\[notice\]') {
        if (-not $content.EndsWith("`n")) { $content += "`r`n" }
        $content += "`r`n[notice]`r`nfast_default_opt_out = true`r`n"
        $changed = $true
    }

    if ($changed) {
        Write-Step "补全 Codex 初始配置"
        Set-Content -LiteralPath $configPath -Value $content -Encoding UTF8
    } else {
        Write-Host "Codex 初始配置已存在。" -ForegroundColor Green
    }
}

function Test-CodexPrereqs {
    Update-CurrentPath
    $npm = Get-CommandPath -Names @("npm.cmd", "npm.ps1", "npm")
    $registry = ""
    if ($npm) {
        try { $registry = (& $npm config get registry 2>$null | Select-Object -First 1) } catch { $registry = "" }
    }

    [pscustomobject]@{
        Winget = [bool](Get-CommandPath -Names @("winget.exe", "winget"))
        PowerShell7 = [bool](Get-CommandPath -Names @("pwsh.exe", "pwsh"))
        WindowsTerminal = [bool](Get-CommandPath -Names @("wt.exe", "wt"))
        Node = [bool](Get-CommandPath -Names @("node.exe", "node"))
        Npm = [bool]$npm
        NpmMirror = ($registry -eq $script:NpmMirror)
        Codex = [bool](Get-CommandPath -Names @("codex.cmd", "codex.ps1", "codex"))
        CodexConfig = [bool](Test-Path -LiteralPath (Join-Path $env:USERPROFILE ".codex\config.toml"))
        Omx = [bool](Get-CommandPath -Names @("omx.cmd", "omx.ps1", "omx"))
        Git = [bool](Get-CommandPath -Names @("git.exe", "git"))
        NpmRegistry = $registry
    }
}

Write-Host "$script:LauncherProductName 一键安装 $script:LauncherVersion" -ForegroundColor Cyan
Write-Host "npm 镜像：$script:NpmMirror"
Write-Host "Node 镜像：$($script:NodeMirrorRoots -join ' / ')"
Write-Host "$script:LauncherLicense | $script:LauncherGitHub | $script:LauncherGitee | 作者：$script:LauncherAuthors" -ForegroundColor DarkGray
if ($AdvancedComponent) {
    $advancedName = switch ($AdvancedComponent) {
        "omx" { "OMX 增强组件" }
        "git" { "Git for Windows" }
        "pwsh" { "PowerShell 7" }
        "wt" { "Windows Terminal" }
    }
    Write-Host "安装模式：高级组件（$advancedName）"
} elseif ($Full) {
    Write-Host "安装模式：完整安装（核心环境 + PowerShell 7 + Windows Terminal）"
} else {
    Write-Host "安装模式：核心安装（Node/npm + npm 镜像 + Codex CLI）"
}

if ($VerifyOnly) {
    Test-CodexPrereqs | Format-List
    return
}

try {
    Write-Step "检查可选增强项"
    Test-OptionalTools

    if ($AdvancedComponent) {
        Install-AdvancedComponent -Name $AdvancedComponent
    } else {
        Ensure-NodeAndNpm
        Ensure-NpmMirror
        Ensure-CodexCli
        Ensure-CodexFirstRunConfig
        if ($Full) {
            Ensure-FullTools
        }

        Write-Step "最终检查"
        $state = Test-CodexPrereqs
        $state | Format-List

        $ok = ($state.Node -and $state.Npm -and $state.NpmMirror -and $state.Codex -and $state.CodexConfig)
        if ($Full) {
            $ok = ($ok -and $state.PowerShell7 -and $state.WindowsTerminal)
        }

        if (-not $ok) {
            throw "仍有依赖未安装完成，请根据上方输出处理后重试。"
        }
    }

    Write-Host ""
    if ($AdvancedComponent) {
        Write-Host "高级组件安装完成。请关闭这个窗口，回到 Codex 便捷启动器重新检测。" -ForegroundColor Green
    } elseif ($Full) {
        Write-Host "完整环境安装完成。请关闭这个窗口，重新打开 Codex 便捷启动器。" -ForegroundColor Green
    } else {
        Write-Host "核心环境安装完成。请关闭这个窗口，重新打开 Codex 便捷启动器。" -ForegroundColor Green
    }
} catch {
    Write-Host ""
    Write-Host "安装未完成：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "可以保留这个窗口，把上面的错误发给维护者。" -ForegroundColor Yellow
    exit 1
}




