$script:CodexSwitcherProductName = "Codex 便捷启动器"
$script:CodexSwitcherVersion = "v0.5.0"
$script:CodexSwitcherAuthors = "夏小曦 & 知晴 & 砚行"
$script:CodexSwitcherGitHub = "https://github.com/wuyuhunter/codex-third-party-quick-launcher"
$script:CodexSwitcherGitee = "https://gitee.com/wuyuhunter/codex-third-party-quick-launcher"
$script:CodexSwitcherUpdateManifestUrl = "https://gitee.com/wuyuhunter/codex-third-party-quick-launcher/raw/master/update/manifest.json"
$script:CodexSwitcherLicense = "MIT 协议"
$script:DefaultCodexSwitcherModels = @("qwen3.6-plus", "qwen-plus", "qwen-max", "deepseek-v4-pro", "deepseek-v4-flash", "deepseek-chat", "deepseek-reasoner", "glm-5.1", "glm-4-plus", "kimi-k2.6", "minimax2.7", "moonshot-v1-auto", "moonshot-v1-32k", "moonshot-v1-8k", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini")
$script:DefaultCodexSwitcherReasoningEfforts = @("medium", "high", "low", "xhigh")
$script:DefaultCodexSwitcherPermissionMode = "safe"

function Get-DefaultCodexModelVendorCatalog {
    @(
        [pscustomobject]@{
            id = "openai"
            name = "OpenAI / GPT"
            defaultModel = "gpt-5.5"
            models = @("gpt-5.5", "gpt-5.4", "gpt-5.4-mini")
        }
        [pscustomobject]@{
            id = "qwen"
            name = "Qwen / 通义千问"
            defaultModel = "qwen3.6-plus"
            models = @("qwen3.6-plus", "qwen-plus", "qwen-max")
        }
        [pscustomobject]@{
            id = "deepseek"
            name = "DeepSeek"
            defaultModel = "deepseek-v4-pro"
            models = @("deepseek-v4-pro", "deepseek-v4-flash", "deepseek-chat", "deepseek-reasoner")
        }
        [pscustomobject]@{
            id = "glm"
            name = "GLM / 智谱"
            defaultModel = "glm-5.1"
            models = @("glm-5.1", "glm-4-plus")
        }
        [pscustomobject]@{
            id = "kimi"
            name = "Kimi / Moonshot"
            defaultModel = "kimi-k2.6"
            models = @("kimi-k2.6", "moonshot-v1-auto", "moonshot-v1-32k", "moonshot-v1-8k")
        }
        [pscustomobject]@{
            id = "minimax"
            name = "MiniMax"
            defaultModel = "minimax2.7"
            models = @("minimax2.7")
        }
        [pscustomobject]@{
            id = "custom"
            name = "自定义 / OpenAI-compatible"
            defaultModel = "gpt-5.5"
            models = @("gpt-5.5", "gpt-5.4")
        }
    )
}

function Normalize-CodexModelSeriesCatalog {
    param($Items)

    $fallback = @(Get-DefaultCodexModelVendorCatalog)
    $rawItems = @($Items)
    if ($rawItems.Count -eq 0) {
        $rawItems = @($fallback)
    }

    $seen = @{}
    $series = @()
    foreach ($item in @($rawItems)) {
        if (-not $item) { continue }
        $id = ([string](Get-CodexObjectProperty -Object $item -Name "id")).Trim().ToLowerInvariant()
        if (-not $id) {
            $id = ConvertTo-CatalogId ([string](Get-CodexObjectProperty -Object $item -Name "name"))
        }
        if (-not $id -or $seen.ContainsKey($id)) { continue }
        $seen[$id] = $true

        $fallbackItem = $fallback | Where-Object { $_.id -eq $id } | Select-Object -First 1
        $name = ([string](Get-CodexObjectProperty -Object $item -Name "name")).Trim()
        if (-not $name) {
            $name = if ($fallbackItem) { [string]$fallbackItem.name } else { $id }
        }
        $fallbackModels = if ($fallbackItem) { @($fallbackItem.models) } else { @("gpt-5.5") }
        $rawModels = @((Get-CodexObjectProperty -Object $item -Name "models"))
        if ($rawModels.Count -eq 0) {
            $rawModels = @($fallbackModels)
        }
        $models = @()
        $modelNames = @()
        foreach ($rawModel in @($rawModels)) {
            $modelName = ""
            $depths = @()
            if ($rawModel -is [string]) {
                $modelName = ([string]$rawModel).Trim()
            } else {
                $modelName = ([string](Get-CodexObjectProperty -Object $rawModel -Name "name")).Trim()
                $depths = @((Get-CodexObjectProperty -Object $rawModel -Name "reasoningDepths"))
            }
            if (-not $modelName) { continue }
            $key = $modelName.ToLowerInvariant()
            if ($modelNames -contains $key) { continue }
            $modelNames += $key
            $fallbackDepths = @((Get-DefaultCodexModelReasoningEffortMap)[$modelName])
            if ($fallbackDepths.Count -eq 0) { $fallbackDepths = @($script:DefaultCodexSwitcherReasoningEfforts) }
            $depths = Normalize-CodexSwitcherList -Items $depths -Fallback $fallbackDepths
            $models += [pscustomobject]@{
                name = $modelName
                reasoningDepths = @($depths)
            }
        }
        if ($models.Count -eq 0) {
            foreach ($fallbackModel in @($fallbackModels)) {
                $models += [pscustomobject]@{
                    name = [string]$fallbackModel
                    reasoningDepths = @((Get-DefaultCodexModelReasoningEffortMap)[$fallbackModel])
                }
            }
        }
        $modelNameList = @($models | ForEach-Object { [string]$_.name })
        $defaultModel = ([string](Get-CodexObjectProperty -Object $item -Name "defaultModel")).Trim()
        if (-not $defaultModel -or $modelNameList -notcontains $defaultModel) {
            $fallbackDefault = if ($fallbackItem) { [string]$fallbackItem.defaultModel } else { "" }
            $defaultModel = if ($fallbackDefault -and $modelNameList -contains $fallbackDefault) { $fallbackDefault } else { [string]$modelNameList[0] }
        }

        $series += [pscustomobject]@{
            id = $id
            name = $name
            defaultModel = $defaultModel
            models = @($models)
        }
    }

    if ($series.Count -eq 0) {
        return @($fallback)
    }
    return @($series)
}

function Get-CodexModelVendorCatalog {
    try {
        $config = Get-CodexSwitcherConfig
        $settings = Get-CodexObjectProperty -Object $config -Name "settings"
        $configured = Get-CodexObjectProperty -Object $settings -Name "modelSeries"
        return @(Normalize-CodexModelSeriesCatalog -Items $configured)
    } catch {
        return @(Get-DefaultCodexModelVendorCatalog)
    }
}

function Get-DefaultCodexModelReasoningEffortMap {
    @{
        "gpt-5.5" = @("medium", "high", "xhigh", "low")
        "gpt-5.4" = @("medium", "high", "xhigh", "low")
        "gpt-5.4-mini" = @("medium", "high", "low")
        "qwen3.6-plus" = @("medium")
        "qwen-plus" = @("medium")
        "qwen-max" = @("medium")
        "deepseek-v4-pro" = @("medium")
        "deepseek-v4-flash" = @("medium")
        "deepseek-chat" = @("medium")
        "deepseek-reasoner" = @("medium")
        "glm-5.1" = @("medium")
        "glm-4-plus" = @("medium")
        "kimi-k2.6" = @("medium")
        "minimax2.7" = @("medium")
        "moonshot-v1-auto" = @("medium")
        "moonshot-v1-32k" = @("medium")
        "moonshot-v1-8k" = @("medium")
    }
}

function Get-CodexModelVendorById {
    param([string]$VendorId)

    $id = ([string]$VendorId).Trim().ToLowerInvariant()
    $vendor = Get-CodexModelVendorCatalog | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if ($vendor) {
        return $vendor
    }
    return (Get-CodexModelVendorCatalog | Where-Object { $_.id -eq "custom" } | Select-Object -First 1)
}

function Infer-CodexModelVendorId {
    param($Provider)

    $id = ([string](Get-CodexObjectProperty -Object $Provider -Name "id")).Trim().ToLowerInvariant()
    $name = ([string](Get-CodexObjectProperty -Object $Provider -Name "name")).Trim().ToLowerInvariant()
    $baseUrl = ([string](Get-CodexObjectProperty -Object $Provider -Name "baseUrl")).Trim().ToLowerInvariant()

    if ($id -match 'qwen|dashscope' -or $name -match 'qwen|通义|千问' -or $baseUrl -match 'dashscope|aliyuncs') { return "qwen" }
    if ($id -match 'deepseek' -or $name -match 'deepseek' -or $baseUrl -match 'deepseek') { return "deepseek" }
    if ($id -match 'glm|bigmodel' -or $name -match 'glm|智谱' -or $baseUrl -match 'bigmodel') { return "glm" }
    if ($id -match 'kimi|moonshot' -or $name -match 'kimi|moonshot' -or $baseUrl -match 'moonshot') { return "kimi" }
    if ($id -match 'minimax' -or $name -match 'minimax' -or $baseUrl -match 'minimax') { return "minimax" }
    if ($id -match 'openai|yanling|ciii' -or $name -match 'openai|小蓝|延林|yanling|ciii' -or $baseUrl -match 'openai|yanling|ciii|inroi') { return "openai" }
    return "custom"
}

function Normalize-CodexModelList {
    param(
        $Items,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Fallback
    )

    $seen = @{}
    $values = @()
    foreach ($item in @($Items)) {
        $value = ([string]$item).Trim()
        if (-not $value) { continue }
        $key = $value.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $values += $value
        }
    }
    if ($values.Count -eq 0) {
        return @($Fallback)
    }
    return @($values)
}

function Normalize-CodexModelReasoningEffortMap {
    param(
        $Map,
        [Parameter(Mandatory = $true)][string[]]$Models,
        [Parameter(Mandatory = $true)][string[]]$ReasoningEfforts
    )

    $defaults = Get-DefaultCodexModelReasoningEffortMap
    $result = [ordered]@{}
    foreach ($model in @($Models)) {
        $modelName = ([string]$model).Trim()
        if (-not $modelName) { continue }

        $raw = $null
        if ($Map -is [System.Collections.IDictionary] -and $Map.Contains($modelName)) {
            $raw = $Map[$modelName]
        } elseif ($Map -and $Map.PSObject.Properties.Name -contains $modelName) {
            $raw = $Map.$modelName
        }

        $fallback = if ($defaults.ContainsKey($modelName)) { @($defaults[$modelName]) } else { @($ReasoningEfforts) }
        $values = Normalize-CodexSwitcherList -Items $raw -Fallback $fallback
        $valid = @()
        foreach ($value in @($values)) {
            if ($ReasoningEfforts -contains $value -and $valid -notcontains $value) {
                $valid += $value
            }
        }
        if ($valid.Count -eq 0) {
            foreach ($value in @($fallback)) {
                if ($ReasoningEfforts -contains $value -and $valid -notcontains $value) {
                    $valid += $value
                }
            }
        }
        if ($valid.Count -eq 0) {
            $valid = @($ReasoningEfforts[0])
        }
        $result[$modelName] = @($valid)
    }

    return $result
}

function Resolve-CodexSwitcherRuntimeRoot {
    $installedRoot = Join-Path $env:USERPROFILE ".omx"
    $toolDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $candidateRoot = Split-Path -Parent $toolDir
    if ((Test-Path -LiteralPath (Join-Path $candidateRoot "codex-quick-launcher.portable")) -or
        (Test-Path -LiteralPath (Join-Path $candidateRoot "ai-quick-launcher.portable")) -or
        (Test-Path -LiteralPath (Join-Path $candidateRoot "codex-switcher.portable"))) {
        return $candidateRoot
    }

    if ($env:CODEX_QUICK_LAUNCHER_HOME) {
        return [Environment]::ExpandEnvironmentVariables($env:CODEX_QUICK_LAUNCHER_HOME)
    }
    if ($env:AI_QUICK_LAUNCHER_HOME) {
        return [Environment]::ExpandEnvironmentVariables($env:AI_QUICK_LAUNCHER_HOME)
    }
    if ($env:CODEX_SWITCHER_HOME) {
        return [Environment]::ExpandEnvironmentVariables($env:CODEX_SWITCHER_HOME)
    }

    return $installedRoot
}

$script:CodexSwitcherRuntimeRoot = Resolve-CodexSwitcherRuntimeRoot
$script:CodexSwitcherIsPortable = ($script:CodexSwitcherRuntimeRoot -ne (Join-Path $env:USERPROFILE ".omx"))
$script:CodexConfigPath = Join-Path $env:USERPROFILE ".codex\config.toml"
$script:CodexSwitcherConfigPath = Join-Path $script:CodexSwitcherRuntimeRoot "state\codex-quick-launcher-config.json"
$script:CodexSelectionPath = Join-Path $script:CodexSwitcherRuntimeRoot "state\codex-provider-selection.json"
$script:CodexCatalogPath = Join-Path $script:CodexSwitcherRuntimeRoot "state\codex-provider-catalog.json"
$script:CodexSwitcherSettingsPath = Join-Path $script:CodexSwitcherRuntimeRoot "state\codex-switcher-settings.json"
$script:CodexSecretDir = Join-Path $script:CodexSwitcherRuntimeRoot "secrets\codex-provider-keys"

function Get-CodexSwitcherInstallRoot {
    $toolDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    return (Split-Path -Parent $toolDir)
}

function Get-CodexSwitcherBuildInfo {
    [pscustomobject]@{
        Version = $script:CodexSwitcherVersion
        Product = $script:CodexSwitcherProductName
        Authors = $script:CodexSwitcherAuthors
        GitHub = $script:CodexSwitcherGitHub
        Gitee = $script:CodexSwitcherGitee
        UpdateManifest = $script:CodexSwitcherUpdateManifestUrl
        License = $script:CodexSwitcherLicense
        InstallRoot = Get-CodexSwitcherInstallRoot
        RuntimeRoot = $script:CodexSwitcherRuntimeRoot
        Portable = $script:CodexSwitcherIsPortable
    }
}

function Get-CodexSwitcherComparableVersion {
    param([string]$VersionText)

    $text = ([string]$VersionText).Trim()
    if ($text -match '(\d+\.\d+\.\d+)') {
        return [version]$matches[1]
    }
    if ($text -match '(\d+\.\d+)') {
        return [version]("$($matches[1]).0")
    }
    return [version]"0.0.0"
}

function Get-CodexSwitcherUpdateManifestUrl {
    if ($env:CODEX_QUICK_LAUNCHER_UPDATE_MANIFEST) {
        return [Environment]::ExpandEnvironmentVariables($env:CODEX_QUICK_LAUNCHER_UPDATE_MANIFEST)
    }
    return $script:CodexSwitcherUpdateManifestUrl
}

function Get-CodexSwitcherPowerShellPath {
    foreach ($name in @("pwsh.exe", "pwsh", "powershell.exe", "powershell")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) {
            return $cmd.Source
        }
    }
    return $null
}

function Join-CodexSwitcherProcessArguments {
    param([string[]]$Arguments)

    $escaped = @()
    foreach ($arg in @($Arguments)) {
        if ($null -eq $arg) {
            continue
        }
        $value = [string]$arg
        if ($value -notmatch '[\s"`]') {
            $escaped += $value
            continue
        }
        $escaped += '"' + ($value -replace '"', '\"') + '"'
    }
    return ($escaped -join " ")
}

function Read-CodexSwitcherTextResource {
    param([Parameter(Mandatory = $true)][string]$Uri)

    $value = [Environment]::ExpandEnvironmentVariables(([string]$Uri).Trim())
    if (-not $value) {
        throw "更新地址为空。"
    }

    if ($value -match '^file://') {
        $fileUri = [uri]$value
        return Get-Content -LiteralPath $fileUri.LocalPath -Raw -Encoding UTF8
    }
    if ($value -match '^https?://') {
        return (Invoke-WebRequest -Uri $value -UseBasicParsing -TimeoutSec 30).Content
    }
    if (Test-Path -LiteralPath $value) {
        return Get-Content -LiteralPath $value -Raw -Encoding UTF8
    }

    throw "无法读取更新地址：$value"
}

function Save-CodexSwitcherBinaryResource {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )

    $value = [Environment]::ExpandEnvironmentVariables(([string]$Uri).Trim())
    if (-not $value) {
        throw "更新包地址为空。"
    }

    if ($value -match '^file://') {
        $fileUri = [uri]$value
        Copy-Item -LiteralPath $fileUri.LocalPath -Destination $OutFile -Force
        return
    }
    if ($value -match '^https?://') {
        Invoke-WebRequest -Uri $value -OutFile $OutFile -UseBasicParsing -TimeoutSec 120
        return
    }
    if (Test-Path -LiteralPath $value) {
        Copy-Item -LiteralPath $value -Destination $OutFile -Force
        return
    }

    throw "无法下载更新包：$value"
}

function Show-CodexSwitcherMessage {
    param(
        [string]$Message,
        [string]$Title = $script:CodexSwitcherProductName,
        [string]$Icon = "Information",
        $Owner
    )

    Add-Type -AssemblyName PresentationFramework
    $image = [System.Enum]::Parse([System.Windows.MessageBoxImage], $Icon)
    if ($Owner) {
        [System.Windows.MessageBox]::Show($Owner, $Message, $Title, [System.Windows.MessageBoxButton]::OK, $image) | Out-Null
    } else {
        [System.Windows.MessageBox]::Show($Message, $Title, [System.Windows.MessageBoxButton]::OK, $image) | Out-Null
    }
}

function Confirm-CodexSwitcherUpdate {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [string]$CurrentVersion,
        $Owner
    )

    Add-Type -AssemblyName PresentationFramework
    $displayVersion = [string](Get-CodexObjectProperty -Object $Manifest -Name "displayVersion")
    if (-not $displayVersion) {
        $displayVersion = "v$([string](Get-CodexObjectProperty -Object $Manifest -Name "version"))"
    }
    $publishedAt = [string](Get-CodexObjectProperty -Object $Manifest -Name "publishedAt")
    $notes = [string](Get-CodexObjectProperty -Object $Manifest -Name "notes")
    if ($notes.Length -gt 600) {
        $notes = $notes.Substring(0, 600) + "..."
    }

    $message = "发现新版本：$displayVersion`n当前版本：$CurrentVersion"
    if ($publishedAt) {
        $message += "`n发布时间：$publishedAt"
    }
    if ($notes) {
        $message += "`n`n更新说明：`n$notes"
    }
    $message += "`n`n确定下载并覆盖当前安装目录吗？更新器会在下载完成后关闭当前窗口，并保留 state、logs、secrets、.omx 等本机数据目录。"

    if ($Owner) {
        return [System.Windows.MessageBox]::Show($Owner, $message, "检查更新", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
    }
    return [System.Windows.MessageBox]::Show($message, "检查更新", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
}

function Start-CodexSwitcherUpdater {
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    $installRoot = Get-CodexSwitcherInstallRoot
    $updaterScript = Join-Path $installRoot "tools\update-codex-quick-launcher.ps1"
    if (-not (Test-Path -LiteralPath $updaterScript)) {
        throw "找不到更新器脚本：$updaterScript"
    }

    $psExe = Get-CodexSwitcherPowerShellPath
    if (-not $psExe) {
        throw "找不到 PowerShell，无法启动更新器。"
    }

    $launcherExe = Join-Path $installRoot "Codex 便捷启动器.exe"
    $args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $updaterScript,
        "-PackagePath", $PackagePath,
        "-InstallRoot", $installRoot,
        "-ExpectedSha256", $ExpectedSha256,
        "-ParentProcessId", ([string][System.Diagnostics.Process]::GetCurrentProcess().Id)
    )
    if (Test-Path -LiteralPath $launcherExe) {
        $args += @("-RelaunchPath", $launcherExe)
    }

    Start-Process -FilePath $psExe -ArgumentList (Join-CodexSwitcherProcessArguments -Arguments $args) -WorkingDirectory $installRoot | Out-Null
}

function Invoke-CodexSwitcherUpdateCheck {
    param($Owner)

    Add-Type -AssemblyName PresentationFramework
    try {
        $manifestUrl = Get-CodexSwitcherUpdateManifestUrl
        $manifestText = Read-CodexSwitcherTextResource -Uri $manifestUrl
        $manifest = $manifestText | ConvertFrom-Json

        $latestVersionText = [string](Get-CodexObjectProperty -Object $manifest -Name "version")
        if (-not $latestVersionText) {
            throw "更新清单缺少 version 字段。"
        }

        $currentVersion = $script:CodexSwitcherVersion
        $current = Get-CodexSwitcherComparableVersion -VersionText $currentVersion
        $latest = Get-CodexSwitcherComparableVersion -VersionText $latestVersionText
        if ($latest -le $current) {
            $display = [string](Get-CodexObjectProperty -Object $manifest -Name "displayVersion")
            if (-not $display) { $display = "v$latestVersionText" }
            Show-CodexSwitcherMessage -Owner $Owner -Title "检查更新" -Message "当前已是最新版本。`n当前版本：$currentVersion`n更新源版本：$display" -Icon "Information"
            return [pscustomobject]@{ Status = "UpToDate"; Version = $latestVersionText }
        }

        $confirm = Confirm-CodexSwitcherUpdate -Manifest $manifest -CurrentVersion $currentVersion -Owner $Owner
        if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) {
            return [pscustomobject]@{ Status = "Canceled"; Version = $latestVersionText }
        }

        $packageUrl = [string](Get-CodexObjectProperty -Object $manifest -Name "packageUrl")
        $sha256 = ([string](Get-CodexObjectProperty -Object $manifest -Name "sha256")).Trim()
        if (-not $packageUrl) {
            throw "更新清单缺少 packageUrl 字段。"
        }
        if (-not $sha256) {
            throw "更新清单缺少 sha256 字段。为避免覆盖到不完整或被篡改的包，本启动器要求更新包必须带 SHA256。"
        }

        $downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) "CodexQuickLauncherUpdate"
        New-Item -ItemType Directory -Force -Path $downloadRoot | Out-Null
        try {
            $packageName = [System.IO.Path]::GetFileName(([uri]$packageUrl).AbsolutePath)
        } catch {
            $packageName = [System.IO.Path]::GetFileName($packageUrl)
        }
        if (-not $packageName -or $packageName -eq "/") {
            $packageName = "CodexQuickLauncher-$latestVersionText.zip"
        }
        if (-not $packageName.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
            $packageName = "$packageName.zip"
        }
        $packagePath = Join-Path $downloadRoot $packageName
        try {
            Save-CodexSwitcherBinaryResource -Uri $packageUrl -OutFile $packagePath

            $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $packagePath).Hash
            if ($actualHash -ne $sha256) {
                Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
                throw "更新包 SHA256 校验失败。`n期望：$sha256`n实际：$actualHash"
            }
        } catch {
            $notesUrl = [string](Get-CodexObjectProperty -Object $manifest -Name "notesUrl")
            $detail = "更新包下载或校验失败。可能是 Gitee release 还没发布，或者当前网络暂时访问不到下载地址。"
            if ($notesUrl) {
                $detail += "`n发布页：$notesUrl"
            }
            throw "$detail`n`n原始错误：$($_.Exception.Message)"
        }

        Start-CodexSwitcherUpdater -PackagePath $packagePath -ExpectedSha256 $sha256
        Show-CodexSwitcherMessage -Owner $Owner -Title "检查更新" -Message "更新包已下载并校验通过。`n`n更新器已经启动，当前窗口将关闭；更新完成后会尝试重新打开启动器。" -Icon "Information"
        return [pscustomobject]@{ Status = "Started"; Version = $latestVersionText; PackagePath = $packagePath }
    } catch {
        $message = (($_ | Out-String).Trim())
        Show-CodexSwitcherMessage -Owner $Owner -Title "检查更新失败" -Message $message -Icon "Error"
        return [pscustomobject]@{ Status = "Failed"; Error = $message }
    }
}

function Normalize-CodexSwitcherList {
    param(
        $Items,
        [Parameter(Mandatory = $true)][string[]]$Fallback
    )

    $seen = @{}
    $values = @()
    foreach ($item in @($Items)) {
        $value = ([string]$item).Trim()
        if (-not $value) {
            continue
        }
        $key = $value.ToLowerInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $values += $value
        }
    }

    if ($values.Count -eq 0) {
        return @($Fallback)
    }

    return @($values)
}

function Set-CodexObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )

    if ($Object -is [System.Collections.IDictionary]) {
        $Object[$Name] = $Value
        return
    }

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Get-CodexObjectProperty {
    param(
        [Parameter(Mandatory = $true)]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $DefaultValue = $null
    )

    if (-not $Object) {
        return $DefaultValue
    }

    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }
        return $DefaultValue
    }

    if ($Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }

    return $DefaultValue
}

function Normalize-CodexPermissionMode {
    param([string]$PermissionMode)

    $value = ([string]$PermissionMode).Trim().ToLowerInvariant()
    switch ($value) {
        "full" { return "full" }
        "yolo" { return "full" }
        "danger" { return "full" }
        "danger-full-access" { return "full" }
        "unsafe" { return "full" }
        "safe" { return "safe" }
        default { return $script:DefaultCodexSwitcherPermissionMode }
    }
}

function New-DefaultCodexSwitcherSelection {
    [pscustomobject]@{
        permissionMode = $script:DefaultCodexSwitcherPermissionMode
    }
}

function New-DefaultCodexSwitcherConfig {
    [pscustomobject][ordered]@{
        version = 1
        updatedAt = (Get-Date -Format o)
        settings = $null
        catalog = $null
        selection = (New-DefaultCodexSwitcherSelection)
    }
}

function Get-CodexSwitcherConfig {
    if (Test-Path -LiteralPath $script:CodexSwitcherConfigPath) {
        $lastError = $null
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                $config = Get-Content -LiteralPath $script:CodexSwitcherConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if (-not (Get-CodexObjectProperty -Object $config -Name "selection")) {
                    Set-CodexObjectProperty -Object $config -Name "selection" -Value (New-DefaultCodexSwitcherSelection)
                }
                $selection = Get-CodexObjectProperty -Object $config -Name "selection"
                Set-CodexObjectProperty -Object $selection -Name "permissionMode" -Value (Normalize-CodexPermissionMode (Get-CodexObjectProperty -Object $selection -Name "permissionMode"))
                return $config
            } catch {
                $lastError = $_
                Start-Sleep -Milliseconds 120
            }
        }

        throw "Cannot read AI launcher config: $script:CodexSwitcherConfigPath. $($lastError.Exception.Message)"
    }

    $config = New-DefaultCodexSwitcherConfig
    if (Test-Path -LiteralPath $script:CodexSwitcherSettingsPath) {
        try {
            Set-CodexObjectProperty -Object $config -Name "settings" -Value (Get-Content -LiteralPath $script:CodexSwitcherSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
        }
    }
    if (Test-Path -LiteralPath $script:CodexCatalogPath) {
        try {
            Set-CodexObjectProperty -Object $config -Name "catalog" -Value (Get-Content -LiteralPath $script:CodexCatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
        }
    }
    if (Test-Path -LiteralPath $script:CodexSelectionPath) {
        try {
            $selection = Get-Content -LiteralPath $script:CodexSelectionPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if (-not (Get-CodexObjectProperty -Object $selection -Name "permissionMode")) {
                Set-CodexObjectProperty -Object $selection -Name "permissionMode" -Value $script:DefaultCodexSwitcherPermissionMode
            }
            Set-CodexObjectProperty -Object $config -Name "selection" -Value $selection
        } catch {
        }
    }
    return $config
}

function Save-CodexSwitcherConfig {
    param([Parameter(Mandatory = $true)]$Config)

    $selection = Get-CodexObjectProperty -Object $Config -Name "selection"
    if (-not $selection) {
        $selection = New-DefaultCodexSwitcherSelection
        Set-CodexObjectProperty -Object $Config -Name "selection" -Value $selection
    }
    Set-CodexObjectProperty -Object $selection -Name "permissionMode" -Value (Normalize-CodexPermissionMode (Get-CodexObjectProperty -Object $selection -Name "permissionMode"))
    Set-CodexObjectProperty -Object $Config -Name "version" -Value 1
    Set-CodexObjectProperty -Object $Config -Name "updatedAt" -Value (Get-Date -Format o)

    $dir = Split-Path -Parent $script:CodexSwitcherConfigPath
    New-Item -ItemType Directory -Force $dir | Out-Null
    $tempPath = Join-Path $dir ("codex-quick-launcher-config.{0}.{1}.tmp" -f $PID, [guid]::NewGuid().ToString("N"))
    try {
        $Config | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $tempPath -Encoding UTF8
        [System.IO.File]::Copy($tempPath, $script:CodexSwitcherConfigPath, $true)
    } finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
    return $Config
}

function Get-CodexSwitcherSelection {
    $config = Get-CodexSwitcherConfig
    $selection = Get-CodexObjectProperty -Object $config -Name "selection"
    if (-not $selection) {
        return $null
    }
    Set-CodexObjectProperty -Object $selection -Name "permissionMode" -Value (Normalize-CodexPermissionMode (Get-CodexObjectProperty -Object $selection -Name "permissionMode"))
    return $selection
}

function Save-CodexSwitcherSelection {
    param([Parameter(Mandatory = $true)]$Selection)

    Set-CodexObjectProperty -Object $Selection -Name "permissionMode" -Value (Normalize-CodexPermissionMode (Get-CodexObjectProperty -Object $Selection -Name "permissionMode"))
    $config = Get-CodexSwitcherConfig
    Set-CodexObjectProperty -Object $config -Name "selection" -Value $Selection
    Save-CodexSwitcherConfig -Config $config | Out-Null
    return $Selection
}

function Save-CodexSwitcherSettings {
    param([Parameter(Mandatory = $true)]$Settings)

    $models = Normalize-CodexSwitcherList -Items $Settings.models -Fallback $script:DefaultCodexSwitcherModels
    $reasoningEfforts = Normalize-CodexSwitcherList -Items $Settings.reasoningEfforts -Fallback $script:DefaultCodexSwitcherReasoningEfforts
    $modelReasoningEfforts = Normalize-CodexModelReasoningEffortMap -Map (Get-CodexObjectProperty -Object $Settings -Name "modelReasoningEfforts") -Models $models -ReasoningEfforts $reasoningEfforts
    $modelSeries = Normalize-CodexModelSeriesCatalog -Items (Get-CodexObjectProperty -Object $Settings -Name "modelSeries")

    $defaultModel = ([string]$Settings.defaultModel).Trim()
    if (-not $defaultModel -or $models -notcontains $defaultModel) {
        $defaultModel = $models[0]
    }

    $defaultReasoningEffort = ([string]$Settings.defaultReasoningEffort).Trim()
    if (-not $defaultReasoningEffort -or $reasoningEfforts -notcontains $defaultReasoningEffort) {
        $defaultReasoningEffort = $reasoningEfforts[0]
    }

    $normalized = [ordered]@{
        version = 1
        updatedAt = (Get-Date -Format o)
        models = @($models)
        modelSeries = @($modelSeries)
        reasoningEfforts = @($reasoningEfforts)
        modelReasoningEfforts = $modelReasoningEfforts
        defaultModel = $defaultModel
        defaultReasoningEffort = $defaultReasoningEffort
    }

    $config = Get-CodexSwitcherConfig
    Set-CodexObjectProperty -Object $config -Name "settings" -Value ([pscustomobject]$normalized)
    Save-CodexSwitcherConfig -Config $config | Out-Null
    return [pscustomobject]$normalized
}

function New-DefaultCodexSwitcherSettings {
    $modelReasoningEfforts = Normalize-CodexModelReasoningEffortMap -Map $null -Models $script:DefaultCodexSwitcherModels -ReasoningEfforts $script:DefaultCodexSwitcherReasoningEfforts
    $modelSeries = Normalize-CodexModelSeriesCatalog -Items $null
    [pscustomobject]@{
        models = @($script:DefaultCodexSwitcherModels)
        modelSeries = @($modelSeries)
        reasoningEfforts = @($script:DefaultCodexSwitcherReasoningEfforts)
        modelReasoningEfforts = $modelReasoningEfforts
        defaultModel = $script:DefaultCodexSwitcherModels[0]
        defaultReasoningEffort = $script:DefaultCodexSwitcherReasoningEfforts[0]
    }
}

function Get-CodexSwitcherSettings {
    try {
        $config = Get-CodexSwitcherConfig
        $settings = Get-CodexObjectProperty -Object $config -Name "settings"
        if (-not $settings) {
            return New-DefaultCodexSwitcherSettings
        }
        $models = Normalize-CodexSwitcherList -Items $settings.models -Fallback $script:DefaultCodexSwitcherModels
        $reasoningEfforts = Normalize-CodexSwitcherList -Items $settings.reasoningEfforts -Fallback $script:DefaultCodexSwitcherReasoningEfforts
        $modelReasoningEfforts = Normalize-CodexModelReasoningEffortMap -Map (Get-CodexObjectProperty -Object $settings -Name "modelReasoningEfforts") -Models $models -ReasoningEfforts $reasoningEfforts
        $modelSeries = Normalize-CodexModelSeriesCatalog -Items (Get-CodexObjectProperty -Object $settings -Name "modelSeries")
        $defaultModel = ([string]$settings.defaultModel).Trim()
        if (-not $defaultModel -or $models -notcontains $defaultModel) { $defaultModel = $models[0] }
        $defaultReasoningEffort = ([string]$settings.defaultReasoningEffort).Trim()
        if (-not $defaultReasoningEffort -or $reasoningEfforts -notcontains $defaultReasoningEffort) { $defaultReasoningEffort = $reasoningEfforts[0] }
        return [pscustomobject]@{
            models = @($models)
            modelSeries = @($modelSeries)
            reasoningEfforts = @($reasoningEfforts)
            modelReasoningEfforts = $modelReasoningEfforts
            defaultModel = $defaultModel
            defaultReasoningEffort = $defaultReasoningEffort
        }
    } catch {
        return New-DefaultCodexSwitcherSettings
    }
}

function Set-CodexSwitcherSettings {
    param(
        [Parameter(Mandatory = $true)][string[]]$Models,
        [Parameter(Mandatory = $true)][string[]]$ReasoningEfforts,
        $ModelReasoningEfforts = $null,
        $ModelSeries = $null,
        [string]$DefaultModel,
        [string]$DefaultReasoningEffort
    )

    Save-CodexSwitcherSettings -Settings ([pscustomobject]@{
        models = @($Models)
        modelSeries = $ModelSeries
        reasoningEfforts = @($ReasoningEfforts)
        modelReasoningEfforts = $ModelReasoningEfforts
        defaultModel = $DefaultModel
        defaultReasoningEffort = $DefaultReasoningEffort
    })
}

function Move-CodexSwitcherListItem {
    param(
        [Parameter(Mandatory = $true)][string[]]$Items,
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][ValidateSet("Up", "Down")][string]$Direction
    )

    $itemsList = @($Items)
    $index = -1
    for ($i = 0; $i -lt $itemsList.Count; $i++) {
        if ($itemsList[$i] -eq $Value) {
            $index = $i
            break
        }
    }

    if ($index -lt 0) {
        return @($itemsList)
    }

    $targetIndex = if ($Direction -eq "Up") { $index - 1 } else { $index + 1 }
    if ($targetIndex -lt 0 -or $targetIndex -ge $itemsList.Count) {
        return @($itemsList)
    }

    $current = $itemsList[$index]
    $itemsList[$index] = $itemsList[$targetIndex]
    $itemsList[$targetIndex] = $current
    return @($itemsList)
}

function Set-CodexSwitcherDefaultModel {
    param([Parameter(Mandatory = $true)][string]$Model)

    $settings = Get-CodexSwitcherSettings
    Set-CodexSwitcherSettings -Models @($settings.models) -ReasoningEfforts @($settings.reasoningEfforts) -ModelReasoningEfforts $settings.modelReasoningEfforts -ModelSeries $settings.modelSeries -DefaultModel $Model -DefaultReasoningEffort $settings.defaultReasoningEffort
}

function Move-CodexSwitcherModel {
    param(
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][ValidateSet("Up", "Down")][string]$Direction
    )

    $settings = Get-CodexSwitcherSettings
    $models = Move-CodexSwitcherListItem -Items @($settings.models) -Value $Model -Direction $Direction
    Set-CodexSwitcherSettings -Models $models -ReasoningEfforts @($settings.reasoningEfforts) -ModelReasoningEfforts $settings.modelReasoningEfforts -ModelSeries $settings.modelSeries -DefaultModel $settings.defaultModel -DefaultReasoningEffort $settings.defaultReasoningEffort
}

function Set-CodexSwitcherDefaultReasoningEffort {
    param([Parameter(Mandatory = $true)][string]$ReasoningEffort)

    $settings = Get-CodexSwitcherSettings
    Set-CodexSwitcherSettings -Models @($settings.models) -ReasoningEfforts @($settings.reasoningEfforts) -ModelReasoningEfforts $settings.modelReasoningEfforts -ModelSeries $settings.modelSeries -DefaultModel $settings.defaultModel -DefaultReasoningEffort $ReasoningEffort
}

function Move-CodexSwitcherReasoningEffort {
    param(
        [Parameter(Mandatory = $true)][string]$ReasoningEffort,
        [Parameter(Mandatory = $true)][ValidateSet("Up", "Down")][string]$Direction
    )

    $settings = Get-CodexSwitcherSettings
    $reasoningEfforts = Move-CodexSwitcherListItem -Items @($settings.reasoningEfforts) -Value $ReasoningEffort -Direction $Direction
    Set-CodexSwitcherSettings -Models @($settings.models) -ReasoningEfforts $reasoningEfforts -ModelReasoningEfforts $settings.modelReasoningEfforts -ModelSeries $settings.modelSeries -DefaultModel $settings.defaultModel -DefaultReasoningEffort $settings.defaultReasoningEffort
}

function Get-OmxCodexConfig {
    param([string]$Path = $script:CodexConfigPath)

    $providers = @{}
    $profiles = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Providers = @(); Profiles = @() }
    }

    $sectionType = $null
    $sectionName = $null
    foreach ($raw in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith("#")) {
            continue
        }

        if ($line -match '^\[model_providers\.(.+)\]$') {
            $sectionType = "provider"
            $sectionName = $Matches[1].Trim('"')
            if (-not $providers.ContainsKey($sectionName)) {
                $providers[$sectionName] = [ordered]@{ Name = $sectionName; BaseUrl = ""; WireApi = ""; EnvKey = ""; RequiresOpenAIAuth = $false }
            }
            continue
        }

        if ($line -match '^\[profiles\.(.+)\]$') {
            $sectionType = "profile"
            $sectionName = $Matches[1].Trim('"')
            if (-not $profiles.ContainsKey($sectionName)) {
                $profiles[$sectionName] = [ordered]@{ Name = $sectionName; ModelProvider = "" }
            }
            continue
        }

        if ($line -notmatch '^([A-Za-z0-9_\-]+)\s*=\s*(.+)$') {
            continue
        }

        $key = $Matches[1]
        $value = $Matches[2].Trim()
        if ($value -match '^"(.*)"$') {
            $value = $Matches[1]
        } elseif ($value -match "^(true|false)$") {
            $value = [bool]::Parse($value)
        }

        if ($sectionType -eq "provider" -and $providers.ContainsKey($sectionName)) {
            switch ($key) {
                "name" { $providers[$sectionName].Name = [string]$value }
                "base_url" { $providers[$sectionName].BaseUrl = [string]$value }
                "wire_api" { $providers[$sectionName].WireApi = [string]$value }
                "env_key" { $providers[$sectionName].EnvKey = [string]$value }
                "requires_openai_auth" { $providers[$sectionName].RequiresOpenAIAuth = [bool]$value }
            }
        } elseif ($sectionType -eq "profile" -and $profiles.ContainsKey($sectionName)) {
            if ($key -eq "model_provider") {
                $profiles[$sectionName].ModelProvider = [string]$value
            }
        }
    }

    $providerRows = foreach ($entry in $providers.GetEnumerator()) {
        $provider = [pscustomobject]$entry.Value
        $profile = $profiles.GetEnumerator() | Where-Object { $_.Value.ModelProvider -eq $entry.Key } | Select-Object -First 1
        $provider | Add-Member -NotePropertyName Id -NotePropertyValue $entry.Key -Force
        $provider | Add-Member -NotePropertyName ProfileName -NotePropertyValue $(if ($profile) { $profile.Key } else { "" }) -Force
        $provider
    }

    $profileRows = foreach ($entry in $profiles.GetEnumerator()) {
        [pscustomobject]$entry.Value
    }

    [pscustomobject]@{
        Providers = @($providerRows | Sort-Object Id)
        Profiles = @($profileRows | Sort-Object Name)
    }
}

function Get-SecretPrefix {
    param([string]$Value)
    if (-not $Value) {
        return ""
    }
    return $Value.Substring(0, [Math]::Min(12, $Value.Length))
}

function Get-DpapiSecret {
    param([Parameter(Mandatory = $true)][string]$SecretPath)

    if (-not (Test-Path -LiteralPath $SecretPath)) {
        return $null
    }

    $encrypted = (Get-Content -LiteralPath $SecretPath -Raw).Trim()
    if (-not $encrypted) {
        return $null
    }

    $secure = $encrypted | ConvertTo-SecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Set-DpapiSecret {
    param(
        [Parameter(Mandatory = $true)][string]$SecretPath,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $dir = Split-Path -Parent $SecretPath
    New-Item -ItemType Directory -Force $dir | Out-Null
    $secure = ConvertTo-SecureString -String $Value -AsPlainText -Force
    $encrypted = $secure | ConvertFrom-SecureString
    Set-Content -LiteralPath $SecretPath -Value $encrypted -Encoding UTF8
}

function ConvertTo-CatalogId {
    param([Parameter(Mandatory = $true)][string]$Name)

    $id = $Name.Trim().ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $id = $id.Trim('-')
    if (-not $id) {
        $id = "item"
    }
    return $id
}

function Get-CatalogSecretPath {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][string]$KeyId
    )

    Join-Path $script:CodexSecretDir "$ProviderId.$KeyId.dpapi.txt"
}

function Get-OpenAIKeyFromAuthJson {
    $authPath = Join-Path $env:USERPROFILE ".codex\auth.json"
    if (-not (Test-Path -LiteralPath $authPath)) {
        return $null
    }

    try {
        $auth = Get-Content -LiteralPath $authPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($auth.OPENAI_API_KEY) {
            return [string]$auth.OPENAI_API_KEY
        }
    } catch {
        return $null
    }

    return $null
}

function Resolve-CodexKeySource {
    param([Parameter(Mandatory = $true)][string]$SourceId)

    if ($SourceId -eq "auth:OPENAI_API_KEY") {
        return Get-OpenAIKeyFromAuthJson
    }

    if ($SourceId -match '^env:(Process|User|Machine):(.+)$') {
        return [Environment]::GetEnvironmentVariable($Matches[2], $Matches[1])
    }

    throw "Unknown key source: $SourceId"
}

function New-KeySourceRow {
    param(
        [string]$Id,
        [string]$Label,
        [string]$EnvVar,
        [string]$Value
    )

    if (-not $Value) {
        return $null
    }

    [pscustomobject]@{
        Id = $Id
        Label = $Label
        EnvVar = $EnvVar
        Prefix = Get-SecretPrefix $Value
        Length = $Value.Length
        Display = "$Label  [$((Get-SecretPrefix $Value))...]"
    }
}

function Get-CodexKeySources {
    $config = Get-OmxCodexConfig
    $envNames = @("OPENAI_API_KEY", "CODEX_API_KEY")
    foreach ($provider in $config.Providers) {
        if ($provider.EnvKey) {
            $envNames += $provider.EnvKey
        }
    }
    $envNames = @($envNames | Where-Object { $_ } | Sort-Object -Unique)

    $rows = @()
    $authKey = Get-OpenAIKeyFromAuthJson
    $row = New-KeySourceRow -Id "auth:OPENAI_API_KEY" -Label ".codex auth.json OPENAI_API_KEY" -EnvVar "OPENAI_API_KEY" -Value $authKey
    if ($row) { $rows += $row }

    foreach ($name in $envNames) {
        foreach ($scope in @("Process", "User", "Machine")) {
            $value = [Environment]::GetEnvironmentVariable($name, $scope)
            $row = New-KeySourceRow -Id "env:${scope}:$name" -Label "$scope env $name" -EnvVar $name -Value $value
            if ($row) { $rows += $row }
        }
    }

    $seen = @{}
    foreach ($row in $rows) {
        $key = "$($row.Id)|$($row.Prefix)|$($row.Length)"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $row
        }
    }
}

function New-CodexCatalogFromExisting {
    $config = Get-OmxCodexConfig
    $keys = @(Get-CodexKeySources)
    $providers = @()

    foreach ($provider in $config.Providers) {
        $providerKeys = @()
        $preferredEnv = if ($provider.EnvKey) { $provider.EnvKey } else { "OPENAI_API_KEY" }
        $matchingKeys = @($keys | Where-Object { $_.EnvVar -eq $preferredEnv })
        if ($matchingKeys.Count -eq 0 -and ($provider.RequiresOpenAIAuth -or $provider.Id -eq "OpenAI")) {
            $matchingKeys = @($keys | Where-Object { $_.EnvVar -eq "OPENAI_API_KEY" })
        }

        $index = 1
        foreach ($key in $matchingKeys) {
            $keyName = switch -Wildcard ($key.Id) {
                "auth:*" { "auth-json"; break }
                "dpapi:*" { "local-dpapi"; break }
                "file:*" { "nas-file"; break }
                "env:User:*" { "user-env"; break }
                "env:Process:*" { "process-env"; break }
                "env:Machine:*" { "machine-env"; break }
                default { "key-$index" }
            }

            $keyId = ConvertTo-CatalogId "$keyName-$($key.Prefix)"
            $providerKeys += [ordered]@{
                id = $keyId
                name = $keyName
                source = $key.Id
                envKey = $key.EnvVar
                prefix = $key.Prefix
                length = $key.Length
                createdAt = (Get-Date -Format o)
            }
            $index++
        }

        $providers += [ordered]@{
            id = $provider.Id
            name = $provider.Name
            vendorId = (Infer-CodexModelVendorId -Provider $provider)
            baseUrl = $provider.BaseUrl
            envKey = $(if ($provider.EnvKey) { $provider.EnvKey } else { "OPENAI_API_KEY" })
            profile = $provider.ProfileName
            wireApi = $provider.WireApi
            requiresOpenAIAuth = [bool]$provider.RequiresOpenAIAuth
            models = @((Get-CodexModelVendorById -VendorId (Infer-CodexModelVendorId -Provider $provider)).models)
            defaultModel = [string](Get-CodexModelVendorById -VendorId (Infer-CodexModelVendorId -Provider $provider)).defaultModel
            keys = @($providerKeys)
        }
    }

    [ordered]@{
        version = 1
        updatedAt = (Get-Date -Format o)
        defaultProvider = $(if ($providers.Count -gt 0) { $providers[0].id } else { "" })
        providers = @($providers)
    }
}

function New-DefaultCodexProviderCatalog {
    [ordered]@{
        version = 1
        updatedAt = (Get-Date -Format o)
        defaultProvider = "openai"
        providers = @(
            [ordered]@{
                id = "openai"
                name = "OpenAI"
                vendorId = "openai"
                baseUrl = "https://api.openai.com/v1"
                envKey = "OPENAI_API_KEY"
                profile = ""
                wireApi = "responses"
                requiresOpenAIAuth = $true
                models = @("gpt-5.5", "gpt-5.4", "gpt-5.4-mini")
                defaultModel = "gpt-5.5"
                defaultKeySource = ""
                keys = @()
            }
        )
    }
}

function Test-CodexLegacySwitcherState {
    return ((Test-Path -LiteralPath $script:CodexSelectionPath) -or
        (Test-Path -LiteralPath $script:CodexCatalogPath) -or
        (Test-Path -LiteralPath $script:CodexSwitcherSettingsPath))
}

function Normalize-CodexProviderCatalog {
    param([Parameter(Mandatory = $true)]$Catalog)

    $rawProviders = @()
    if ($Catalog -is [System.Collections.IDictionary] -and $Catalog.Contains("providers")) {
        $rawProviders = @($Catalog["providers"])
    } elseif ($Catalog.PSObject.Properties.Name -contains "providers") {
        $rawProviders = @($Catalog.providers)
    }

    $providers = @()
    $seen = @{}
    foreach ($provider in $rawProviders) {
        if (-not $provider) {
            continue
        }

        $providerId = ([string]$provider.id).Trim()
        if (-not $providerId) {
            $providerId = ConvertTo-CatalogId ([string]$provider.name)
        }
        if (-not $providerId) {
            continue
        }

        $providerKey = $providerId.ToLowerInvariant()
        if ($seen.ContainsKey($providerKey)) {
            continue
        }
        $seen[$providerKey] = $true

        $providerName = ([string]$provider.name).Trim()
        if (-not $providerName) {
            $providerName = $providerId
        }

        $providerEnvKey = ([string]$provider.envKey).Trim()
        if (-not $providerEnvKey) {
            $providerEnvKey = "CODEX_PROVIDER_API_KEY"
        }

        $providerWireApi = ([string]$provider.wireApi).Trim()
        if (-not $providerWireApi) {
            $providerWireApi = "responses"
        }

        $providerVendorIds = @()
        foreach ($vendorId in @((Get-CodexObjectProperty -Object $provider -Name "vendorIds"))) {
            $value = ([string]$vendorId).Trim().ToLowerInvariant()
            if ($value -and $providerVendorIds -notcontains $value) {
                $providerVendorIds += $value
            }
        }
        $providerVendorId = ([string](Get-CodexObjectProperty -Object $provider -Name "vendorId")).Trim().ToLowerInvariant()
        if ($providerVendorId -and $providerVendorIds -notcontains $providerVendorId) {
            $providerVendorIds += $providerVendorId
        }
        if ($providerVendorIds.Count -eq 0) {
            $providerVendorIds += (Infer-CodexModelVendorId -Provider $provider)
        }

        $vendors = @()
        foreach ($vendorId in @($providerVendorIds)) {
            $vendor = Get-CodexModelVendorById -VendorId $vendorId
            if (-not ($vendors | Where-Object { $_.id -eq $vendor.id } | Select-Object -First 1)) {
                $vendors += $vendor
            }
        }
        if ($vendors.Count -eq 0) {
            $vendors += (Get-CodexModelVendorById -VendorId "custom")
        }
        $providerVendorIds = @($vendors | ForEach-Object { [string]$_.id })
        $providerVendorId = [string]$providerVendorIds[0]
        $vendorModelFallback = @()
        foreach ($vendor in @($vendors)) {
            foreach ($model in @($vendor.models)) {
                $modelName = if ($model -is [string]) { [string]$model } else { [string](Get-CodexObjectProperty -Object $model -Name "name") }
                if ($modelName -and $vendorModelFallback -notcontains $modelName) {
                    $vendorModelFallback += [string]$modelName
                }
            }
        }
        $hasProviderModelsProperty = (($provider -is [System.Collections.IDictionary] -and $provider.Contains("models")) -or ($provider.PSObject.Properties.Name -contains "models"))
        $rawProviderModels = Get-CodexObjectProperty -Object $provider -Name "models"
        if ($hasProviderModelsProperty -and @($rawProviderModels).Count -eq 0) {
            $providerModels = @()
        } else {
            $providerModels = Normalize-CodexModelList -Items $rawProviderModels -Fallback @($vendorModelFallback)
        }
        $providerDefaultModel = ([string](Get-CodexObjectProperty -Object $provider -Name "defaultModel")).Trim()
        if ($providerModels.Count -eq 0) {
            $providerDefaultModel = ""
        } elseif (-not $providerDefaultModel -or $providerModels -notcontains $providerDefaultModel) {
            if ($providerModels -contains $vendors[0].defaultModel) {
                $providerDefaultModel = [string]$vendors[0].defaultModel
            } else {
                $providerDefaultModel = [string]$providerModels[0]
            }
        }

        Set-CodexObjectProperty -Object $provider -Name "id" -Value $providerId
        Set-CodexObjectProperty -Object $provider -Name "name" -Value $providerName
        Set-CodexObjectProperty -Object $provider -Name "vendorId" -Value $providerVendorId
        Set-CodexObjectProperty -Object $provider -Name "vendorIds" -Value @($providerVendorIds)
        Set-CodexObjectProperty -Object $provider -Name "vendorName" -Value (($vendors | ForEach-Object { [string]$_.name }) -join " / ")
        Set-CodexObjectProperty -Object $provider -Name "envKey" -Value $providerEnvKey
        Set-CodexObjectProperty -Object $provider -Name "wireApi" -Value $providerWireApi
        Set-CodexObjectProperty -Object $provider -Name "models" -Value @($providerModels)
        Set-CodexObjectProperty -Object $provider -Name "defaultModel" -Value $providerDefaultModel
        $providerKeys = @($provider.keys)
        $defaultKeySource = ([string]$provider.defaultKeySource).Trim()
        $validDefaultKey = $false
        foreach ($key in $providerKeys) {
            if ($defaultKeySource -and ($key.id -eq $defaultKeySource -or $key.name -eq $defaultKeySource)) {
                $defaultKeySource = [string]$key.id
                $validDefaultKey = $true
                break
            }
        }
        if (-not $validDefaultKey) {
            $firstKey = $providerKeys | Select-Object -First 1
            $defaultKeySource = if ($firstKey) { [string]$firstKey.id } else { "" }
        }

        Set-CodexObjectProperty -Object $provider -Name "requiresOpenAIAuth" -Value ([bool]$provider.requiresOpenAIAuth)
        Set-CodexObjectProperty -Object $provider -Name "keys" -Value @($providerKeys)
        Set-CodexObjectProperty -Object $provider -Name "defaultKeySource" -Value $defaultKeySource
        $providers += $provider
    }

    $defaultProvider = ""
    if ($Catalog -is [System.Collections.IDictionary] -and $Catalog.Contains("defaultProvider")) {
        $defaultProvider = ([string]$Catalog["defaultProvider"]).Trim()
    } elseif ($Catalog.PSObject.Properties.Name -contains "defaultProvider") {
        $defaultProvider = ([string]$Catalog.defaultProvider).Trim()
    }

    $validDefault = $false
    foreach ($provider in $providers) {
        if ($provider.id -eq $defaultProvider) {
            $validDefault = $true
            break
        }
    }
    if (-not $validDefault) {
        $defaultProvider = if ($providers.Count -gt 0) { [string]$providers[0].id } else { "" }
    }

    [pscustomobject][ordered]@{
        version = 1
        updatedAt = (Get-Date -Format o)
        defaultProvider = $defaultProvider
        providers = @($providers)
    }
}

function Save-CodexProviderCatalog {
    param([Parameter(Mandatory = $true)]$Catalog)

    $normalized = Normalize-CodexProviderCatalog -Catalog $Catalog
    $config = Get-CodexSwitcherConfig
    Set-CodexObjectProperty -Object $config -Name "catalog" -Value $normalized
    Save-CodexSwitcherConfig -Config $config | Out-Null
    return $normalized
}

function Get-CodexProviderCatalog {
    try {
        $config = Get-CodexSwitcherConfig
        $catalog = Get-CodexObjectProperty -Object $config -Name "catalog"
        if (-not $catalog) {
            $catalog = if ($script:CodexSwitcherIsPortable -and -not (Test-CodexLegacySwitcherState)) {
                New-DefaultCodexProviderCatalog
            } else {
                New-CodexCatalogFromExisting
            }
        }
        return Normalize-CodexProviderCatalog -Catalog $catalog
    } catch {
        if (Test-Path -LiteralPath $script:CodexSwitcherConfigPath) {
            throw
        }
        $catalog = if ($script:CodexSwitcherIsPortable -and -not (Test-CodexLegacySwitcherState)) {
            New-DefaultCodexProviderCatalog
        } else {
            New-CodexCatalogFromExisting
        }
        return Normalize-CodexProviderCatalog -Catalog $catalog
    }
}

function Get-CatalogProviders {
    $catalog = Get-CodexProviderCatalog
    return @($catalog.providers)
}

function Get-DefaultCodexCatalogProviderId {
    $catalog = Get-CodexProviderCatalog
    return [string]$catalog.defaultProvider
}

function Get-CatalogProviderById {
    param([Parameter(Mandatory = $true)][string]$ProviderName)

    $provider = Get-CatalogProviders | Where-Object { $_.id -eq $ProviderName -or $_.name -eq $ProviderName } | Select-Object -First 1
    if (-not $provider) {
        return $null
    }
    return $provider
}

function Get-CodexProviderModels {
    param([Parameter(Mandatory = $true)]$Provider)

    $vendor = Get-CodexModelVendorById -VendorId (Get-CodexObjectProperty -Object $Provider -Name "vendorId")
    return @(Normalize-CodexModelList -Items (Get-CodexObjectProperty -Object $Provider -Name "models") -Fallback @($vendor.models))
}

function Get-CodexProviderDefaultModel {
    param([Parameter(Mandatory = $true)]$Provider)

    $models = @(Get-CodexProviderModels -Provider $Provider)
    $defaultModel = ([string](Get-CodexObjectProperty -Object $Provider -Name "defaultModel")).Trim()
    if ($defaultModel -and $models -contains $defaultModel) {
        return $defaultModel
    }
    if ($models.Count -gt 0) {
        return [string]$models[0]
    }
    return [string]$script:DefaultCodexSwitcherModels[0]
}

function Resolve-CodexModelForProvider {
    param(
        [Parameter(Mandatory = $true)]$Provider,
        [string]$Model
    )

    $models = @(Get-CodexProviderModels -Provider $Provider)
    $candidate = ([string]$Model).Trim()
    if ($candidate -and $models -contains $candidate) {
        return $candidate
    }
    return (Get-CodexProviderDefaultModel -Provider $Provider)
}

function Set-CodexCatalogDefaultProvider {
    param([Parameter(Mandatory = $true)][string]$ProviderName)

    $catalog = Get-CodexProviderCatalog
    $provider = @($catalog.providers) | Where-Object { $_.id -eq $ProviderName -or $_.name -eq $ProviderName } | Select-Object -First 1
    if (-not $provider) {
        throw "Unknown provider: $ProviderName"
    }

    $catalog.defaultProvider = $provider.id
    Save-CodexProviderCatalog -Catalog $catalog | Out-Null
}

function Move-CodexCatalogProvider {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [Parameter(Mandatory = $true)][ValidateSet("Top", "Up", "Down", "Bottom")][string]$Direction
    )

    $catalog = Get-CodexProviderCatalog
    $providers = @($catalog.providers)
    $index = -1
    for ($i = 0; $i -lt $providers.Count; $i++) {
        if ($providers[$i].id -eq $ProviderName -or $providers[$i].name -eq $ProviderName) {
            $index = $i
            break
        }
    }

    if ($index -lt 0) {
        throw "Unknown provider: $ProviderName"
    }

    if ($Direction -eq "Top") {
        if ($index -eq 0) { return $catalog }
        $current = $providers[$index]
        $newProviders = @($current)
        for ($i = 0; $i -lt $providers.Count; $i++) {
            if ($i -ne $index) { $newProviders += $providers[$i] }
        }
        $catalog.providers = @($newProviders)
        Save-CodexProviderCatalog -Catalog $catalog | Out-Null
        return $catalog
    }

    if ($Direction -eq "Bottom") {
        if ($index -eq ($providers.Count - 1)) { return $catalog }
        $current = $providers[$index]
        $newProviders = @()
        for ($i = 0; $i -lt $providers.Count; $i++) {
            if ($i -ne $index) { $newProviders += $providers[$i] }
        }
        $newProviders += $current
        $catalog.providers = @($newProviders)
        Save-CodexProviderCatalog -Catalog $catalog | Out-Null
        return $catalog
    }

    $targetIndex = if ($Direction -eq "Up") { $index - 1 } else { $index + 1 }
    if ($targetIndex -lt 0 -or $targetIndex -ge $providers.Count) {
        return $catalog
    }

    $current = $providers[$index]
    $providers[$index] = $providers[$targetIndex]
    $providers[$targetIndex] = $current
    $catalog.providers = @($providers)
    Save-CodexProviderCatalog -Catalog $catalog | Out-Null
}

function Set-CodexCatalogDefaultKey {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [Parameter(Mandatory = $true)][string]$KeyName
    )

    $catalog = Get-CodexProviderCatalog
    $provider = @($catalog.providers) | Where-Object { $_.id -eq $ProviderName -or $_.name -eq $ProviderName } | Select-Object -First 1
    if (-not $provider) {
        throw "Unknown provider: $ProviderName"
    }

    $key = @($provider.keys) | Where-Object { $_.id -eq $KeyName -or $_.name -eq $KeyName } | Select-Object -First 1
    if (-not $key) {
        throw "Unknown key: $KeyName"
    }

    Set-CodexObjectProperty -Object $provider -Name "defaultKeySource" -Value ([string]$key.id)
    Save-CodexProviderCatalog -Catalog $catalog | Out-Null
}

function Move-CodexCatalogKey {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [Parameter(Mandatory = $true)][string]$KeyName,
        [Parameter(Mandatory = $true)][ValidateSet("Up", "Down")][string]$Direction
    )

    $catalog = Get-CodexProviderCatalog
    $provider = @($catalog.providers) | Where-Object { $_.id -eq $ProviderName -or $_.name -eq $ProviderName } | Select-Object -First 1
    if (-not $provider) {
        throw "Unknown provider: $ProviderName"
    }

    $keys = @($provider.keys)
    $index = -1
    for ($i = 0; $i -lt $keys.Count; $i++) {
        if ($keys[$i].id -eq $KeyName -or $keys[$i].name -eq $KeyName) {
            $index = $i
            break
        }
    }

    if ($index -lt 0) {
        throw "Unknown key: $KeyName"
    }

    $targetIndex = if ($Direction -eq "Up") { $index - 1 } else { $index + 1 }
    if ($targetIndex -lt 0 -or $targetIndex -ge $keys.Count) {
        return $catalog
    }

    $current = $keys[$index]
    $keys[$index] = $keys[$targetIndex]
    $keys[$targetIndex] = $current
    $provider.keys = @($keys)
    Save-CodexProviderCatalog -Catalog $catalog | Out-Null
}

function Get-CatalogKeyById {
    param(
        [Parameter(Mandatory = $true)]$Provider,
        [Parameter(Mandatory = $true)][string]$KeyName
    )

    return @($Provider.keys) | Where-Object { $_.id -eq $KeyName -or $_.name -eq $KeyName } | Select-Object -First 1
}

function Resolve-CatalogKey {
    param(
        [Parameter(Mandatory = $true)]$Provider,
        [Parameter(Mandatory = $true)]$Key
    )

    if ($Key.apiKey) {
        return [string]$Key.apiKey
    }

    if ($Key.source -and $Key.source -match '^(auth:|env:|dpapi:|file:)') {
        return Resolve-CodexKeySource -SourceId $Key.source
    }

    if ($Key.secretPath) {
        return Get-DpapiSecret -SecretPath ([Environment]::ExpandEnvironmentVariables([string]$Key.secretPath))
    }

    $fallback = Get-CodexKeySources | Where-Object {
        $_.EnvVar -eq $Key.envKey -and $_.Prefix -eq $Key.prefix -and $_.Length -eq $Key.length
    } | Select-Object -First 1
    if ($fallback) {
        return Resolve-CodexKeySource -SourceId $fallback.Id
    }

    $secretPath = Get-CatalogSecretPath -ProviderId $Provider.id -KeyId $Key.id
    return Get-DpapiSecret -SecretPath $secretPath
}

function Add-CodexCatalogProvider {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [string]$EnvKey = "CODEX_PROVIDER_API_KEY",
        [string]$Id,
        [string]$Profile = "",
        [string]$WireApi = "responses",
        [string]$VendorId = "",
        [string[]]$VendorIds = @(),
        [string[]]$Models = @(),
        [string]$DefaultModel = "",
        [switch]$AllowEmptyModels
    )

    $catalog = Get-CodexProviderCatalog
    if (-not $Id) { $Id = ConvertTo-CatalogId $Name }
    $normalizedVendorIds = @()
    foreach ($item in @($VendorIds)) {
        $value = ([string]$item).Trim().ToLowerInvariant()
        if ($value -and $normalizedVendorIds -notcontains $value) { $normalizedVendorIds += $value }
    }
    if ($VendorId -and $normalizedVendorIds -notcontains $VendorId.Trim().ToLowerInvariant()) {
        $normalizedVendorIds += $VendorId.Trim().ToLowerInvariant()
    }
    if ($normalizedVendorIds.Count -eq 0) {
        $normalizedVendorIds += (Infer-CodexModelVendorId -Provider ([pscustomobject]@{ id = $Id; name = $Name; baseUrl = $BaseUrl }))
    }
    $vendors = @()
    foreach ($item in @($normalizedVendorIds)) {
        $vendor = Get-CodexModelVendorById -VendorId $item
        if (-not ($vendors | Where-Object { $_.id -eq $vendor.id } | Select-Object -First 1)) {
            $vendors += $vendor
        }
    }
    $normalizedVendorIds = @($vendors | ForEach-Object { [string]$_.id })
    $primaryVendor = $vendors[0]
    $fallbackModels = @()
    foreach ($vendor in @($vendors)) {
        foreach ($model in @($vendor.models)) {
            $modelName = if ($model -is [string]) { [string]$model } else { [string](Get-CodexObjectProperty -Object $model -Name "name") }
            if ($modelName -and $fallbackModels -notcontains $modelName) { $fallbackModels += [string]$modelName }
        }
    }
    if ($AllowEmptyModels -and @($Models).Count -eq 0) {
        $normalizedModels = @()
    } else {
        $normalizedModels = Normalize-CodexModelList -Items $Models -Fallback @($fallbackModels)
    }
    if ($normalizedModels.Count -eq 0) {
        $DefaultModel = ""
    } elseif (-not $DefaultModel -or $normalizedModels -notcontains $DefaultModel) {
        $DefaultModel = if ($normalizedModels -contains $primaryVendor.defaultModel) { [string]$primaryVendor.defaultModel } else { [string]$normalizedModels[0] }
    }
    $existing = @($catalog.providers) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if ($existing) {
        $existing.name = $Name
        Set-CodexObjectProperty -Object $existing -Name "vendorId" -Value ([string]$primaryVendor.id)
        Set-CodexObjectProperty -Object $existing -Name "vendorIds" -Value @($normalizedVendorIds)
        Set-CodexObjectProperty -Object $existing -Name "vendorName" -Value (($vendors | ForEach-Object { [string]$_.name }) -join " / ")
        $existing.baseUrl = $BaseUrl
        $existing.envKey = $EnvKey
        $existing.profile = $Profile
        $existing.wireApi = $WireApi
        Set-CodexObjectProperty -Object $existing -Name "models" -Value @($normalizedModels)
        Set-CodexObjectProperty -Object $existing -Name "defaultModel" -Value $DefaultModel
    } else {
        $catalog.providers += [pscustomobject]@{
            id = $Id
            name = $Name
            vendorId = [string]$primaryVendor.id
            vendorIds = @($normalizedVendorIds)
            vendorName = (($vendors | ForEach-Object { [string]$_.name }) -join " / ")
            baseUrl = $BaseUrl
            envKey = $EnvKey
            profile = $Profile
            wireApi = $WireApi
            requiresOpenAIAuth = $false
            models = @($normalizedModels)
            defaultModel = $DefaultModel
            defaultKeySource = ""
            keys = @()
        }
    }
    Save-CodexProviderCatalog -Catalog $catalog | Out-Null
}

function ConvertTo-CodexConfigString {
    param([AllowEmptyString()][string]$Value)

    return '"' + ([string]$Value).Replace('\', '\\').Replace('"', '\"') + '"'
}

function Get-CodexProviderConfigArgs {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [string]$EnvKey = "OPENAI_API_KEY",
        [string]$WireApi = "responses"
    )

    @(
        "-c", "model_provider=$(ConvertTo-CodexConfigString $ProviderId)",
        "-c", "model_providers.$ProviderId.name=$(ConvertTo-CodexConfigString $Name)",
        "-c", "model_providers.$ProviderId.base_url=$(ConvertTo-CodexConfigString $BaseUrl)",
        "-c", "model_providers.$ProviderId.wire_api=$(ConvertTo-CodexConfigString $WireApi)",
        "-c", "model_providers.$ProviderId.env_key=$(ConvertTo-CodexConfigString $EnvKey)",
        "-c", "model_providers.$ProviderId.supports_websockets=false"
    )
}

function Sync-CodexConfigProvider {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [string]$EnvKey = "OPENAI_API_KEY",
        [string]$WireApi = "responses"
    )

    return
}

function Ensure-CodexBaseConfig {
    return
}

function Remove-CodexConfigProvider {
    param([Parameter(Mandatory = $true)][string]$ProviderId)

    return
}

function Clear-CodexSelectionIfMatches {
    param(
        [string]$ProviderId,
        [string]$KeyId
    )

    $state = Get-CodexSwitcherSelection
    if (-not $state) {
        return
    }

    $providerMatches = $ProviderId -and $state.provider -eq $ProviderId
    $keyMatches = $KeyId -and $state.keySource -eq $KeyId
    if ($providerMatches -or $keyMatches) {
        Save-CodexSwitcherSelection -Selection (New-DefaultCodexSwitcherSelection) | Out-Null
    }
}

function Remove-CodexCatalogProvider {
    param([Parameter(Mandatory = $true)][string]$ProviderName)

    $catalog = Get-CodexProviderCatalog
    $provider = @($catalog.providers) | Where-Object { $_.id -eq $ProviderName -or $_.name -eq $ProviderName } | Select-Object -First 1
    if (-not $provider) {
        throw "Unknown provider: $ProviderName"
    }

    if (@($catalog.providers).Count -le 1) {
        throw "At least one Codex provider must remain."
    }

    $catalog.providers = @($catalog.providers | Where-Object { $_.id -ne $provider.id })
    Save-CodexProviderCatalog -Catalog $catalog | Out-Null
    Clear-CodexSelectionIfMatches -ProviderId $provider.id
}

function Add-CodexCatalogKey {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [Parameter(Mandatory = $true)][string]$KeyName,
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [string]$KeyId
    )

    $catalog = Get-CodexProviderCatalog
    $provider = @($catalog.providers) | Where-Object { $_.id -eq $ProviderName -or $_.name -eq $ProviderName } | Select-Object -First 1
    if (-not $provider) {
        throw "Unknown provider: $ProviderName"
    }

    if (-not $KeyId) { $KeyId = ConvertTo-CatalogId $KeyName }
    $keyRow = @($provider.keys) | Where-Object { $_.id -eq $KeyId } | Select-Object -First 1
    if ($keyRow) {
        $keyRow.name = $KeyName
        $keyRow.source = "catalog:$($provider.id):$KeyId"
        $keyRow.envKey = $provider.envKey
        $keyRow.prefix = Get-SecretPrefix $ApiKey
        $keyRow.length = $ApiKey.Length
        if ($keyRow.PSObject.Properties.Name -contains "apiKey") {
            $keyRow.apiKey = $ApiKey
        } else {
            $keyRow | Add-Member -NotePropertyName apiKey -NotePropertyValue $ApiKey
        }
        if ($keyRow.PSObject.Properties.Name -contains "secretPath") {
            $keyRow.PSObject.Properties.Remove("secretPath")
        }
        if ($keyRow.PSObject.Properties.Name -contains "updatedAt") {
            $keyRow.updatedAt = (Get-Date -Format o)
        } else {
            $keyRow | Add-Member -NotePropertyName updatedAt -NotePropertyValue (Get-Date -Format o)
        }
    } else {
        $provider.keys += [pscustomobject]@{
            id = $KeyId
            name = $KeyName
            source = "catalog:$($provider.id):$KeyId"
            envKey = $provider.envKey
            prefix = Get-SecretPrefix $ApiKey
            length = $ApiKey.Length
            apiKey = $ApiKey
            createdAt = (Get-Date -Format o)
        }
    }

    if (-not ([string]$provider.defaultKeySource).Trim()) {
        Set-CodexObjectProperty -Object $provider -Name "defaultKeySource" -Value $KeyId
    }

    Save-CodexProviderCatalog -Catalog $catalog | Out-Null
}

function Remove-CodexCatalogKey {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [Parameter(Mandatory = $true)][string]$KeyName
    )

    $catalog = Get-CodexProviderCatalog
    $provider = @($catalog.providers) | Where-Object { $_.id -eq $ProviderName -or $_.name -eq $ProviderName } | Select-Object -First 1
    if (-not $provider) {
        throw "Unknown provider: $ProviderName"
    }

    $key = @($provider.keys) | Where-Object { $_.id -eq $KeyName -or $_.name -eq $KeyName } | Select-Object -First 1
    if (-not $key) {
        throw "Unknown key: $KeyName"
    }

    $provider.keys = @($provider.keys | Where-Object { $_.id -ne $key.id })
    Save-CodexProviderCatalog -Catalog $catalog | Out-Null
    Clear-CodexSelectionIfMatches -ProviderId $provider.id -KeyId $key.id
}

function Convert-CodexCatalogKeysToPlaintext {
    $catalog = Get-CodexProviderCatalog
    foreach ($provider in @($catalog.providers)) {
        foreach ($key in @($provider.keys)) {
            if ($key.apiKey) {
                continue
            }

            $resolved = $null
            try {
                $resolved = Resolve-CatalogKey -Provider $provider -Key $key
            } catch {
                $resolved = $null
            }

            if ($resolved) {
                if ($key.PSObject.Properties.Name -contains "apiKey") {
                    $key.apiKey = $resolved
                } else {
                    $key | Add-Member -NotePropertyName apiKey -NotePropertyValue $resolved
                }
                $key.prefix = Get-SecretPrefix $resolved
                $key.length = $resolved.Length
                $key.source = "catalog:$($provider.id):$($key.id)"
                if ($key.PSObject.Properties.Name -contains "secretPath") {
                    $key.PSObject.Properties.Remove("secretPath")
                }
                if ($key.PSObject.Properties.Name -contains "updatedAt") {
                    $key.updatedAt = (Get-Date -Format o)
                } else {
                    $key | Add-Member -NotePropertyName updatedAt -NotePropertyValue (Get-Date -Format o)
                }
            }
        }
    }
    Save-CodexProviderCatalog -Catalog $catalog | Out-Null
}

function Get-DefaultKeySourceForProvider {
    param([Parameter(Mandatory = $true)]$Provider)

    if ($Provider.keys) {
        $defaultKeySource = ([string]$Provider.defaultKeySource).Trim()
        if ($defaultKeySource) {
            $defaultKey = @($Provider.keys) | Where-Object { $_.id -eq $defaultKeySource -or $_.name -eq $defaultKeySource } | Select-Object -First 1
            if ($defaultKey) { return [string]$defaultKey.id }
        }

        $firstKey = @($Provider.keys) | Select-Object -First 1
        if ($firstKey) { return [string]$firstKey.id }
    }

    $sources = @(Get-CodexKeySources)
    if ($Provider.EnvKey) {
        $match = $sources | Where-Object { $_.EnvVar -eq $Provider.EnvKey } | Select-Object -First 1
        if ($match) { return $match.Id }
    }

    if ($Provider.RequiresOpenAIAuth -or $Provider.Id -eq "OpenAI" -or $Provider.Name -eq "OpenAI") {
        $match = $sources | Where-Object { $_.Id -eq "auth:OPENAI_API_KEY" } | Select-Object -First 1
        if ($match) { return $match.Id }
        $match = $sources | Where-Object { $_.EnvVar -eq "OPENAI_API_KEY" } | Select-Object -First 1
        if ($match) { return $match.Id }
    }

    if ($sources.Count -gt 0) {
        return $sources[0].Id
    }

    return ""
}

function Get-CodexProviderById {
    param([Parameter(Mandatory = $true)][string]$ProviderName)

    $catalogProvider = Get-CatalogProviderById -ProviderName $ProviderName
    if ($catalogProvider) {
        return $catalogProvider
    }

    $config = Get-OmxCodexConfig
    $provider = $config.Providers | Where-Object { $_.Id -eq $ProviderName -or $_.Name -eq $ProviderName } | Select-Object -First 1
    if (-not $provider) {
        throw "Unknown Codex provider: $ProviderName"
    }
    return $provider
}

function Set-CodexSelectionEnvironment {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderName,
        [Parameter(Mandatory = $true)][string]$KeySourceId,
        [string]$Model,
        [string]$ReasoningEffort,
        [string]$PermissionMode = $script:DefaultCodexSwitcherPermissionMode,
        [switch]$Persist
    )

    $provider = Get-CodexProviderById -ProviderName $ProviderName
    $catalogKey = $null
    if ($provider.keys) {
        $catalogKey = Get-CatalogKeyById -Provider $provider -KeyName $KeySourceId
    }

    if ($catalogKey) {
        $apiKey = Resolve-CatalogKey -Provider $provider -Key $catalogKey
    } else {
        $apiKey = Resolve-CodexKeySource -SourceId $KeySourceId
    }
    if (-not $apiKey) {
        throw "Selected key source has no key: $KeySourceId"
    }

    $targetEnvKey = if ($provider.EnvKey) { $provider.EnvKey } else { $provider.envKey }
    if (-not $targetEnvKey) {
        $targetEnvKey = "OPENAI_API_KEY"
    }

    Set-Item -Path "Env:$targetEnvKey" -Value $apiKey
    if ($targetEnvKey -ne "OPENAI_API_KEY") {
        Set-Item -Path "Env:OPENAI_API_KEY" -Value $apiKey
    }
    $providerId = if ($provider.Id) { $provider.Id } else { $provider.id }
    $providerName = if ($provider.Name) { $provider.Name } else { $provider.name }
    $providerProfile = if ($provider.ProfileName) { $provider.ProfileName } else { $provider.profile }
    $providerBaseUrl = if ($provider.BaseUrl) { $provider.BaseUrl } else { $provider.baseUrl }
    $providerWireApi = if ($provider.WireApi) { $provider.WireApi } else { $provider.wireApi }
    if (-not $providerWireApi) {
        $providerWireApi = "responses"
    }
    $keyName = if ($catalogKey) { $catalogKey.name } else { $KeySourceId }

    $env:OMX_CODEX_SELECTED_PROVIDER = $providerId
    $env:OMX_CODEX_SELECTED_PROFILE = $providerProfile
    $env:OMX_CODEX_SELECTED_ENV_KEY = $targetEnvKey
    $env:OMX_CODEX_SELECTED_KEY_SOURCE = $KeySourceId
    $env:OMX_CODEX_SELECTED_KEY_NAME = $keyName
    $env:OMX_CODEX_SELECTED_BASE_URL = $providerBaseUrl
    $env:OMX_CODEX_SELECTED_KEY_PREFIX = Get-SecretPrefix $apiKey
    if ($Model) { $env:OMX_CODEX_SELECTED_MODEL = $Model }
    if ($ReasoningEffort) { $env:OMX_CODEX_SELECTED_REASONING_EFFORT = $ReasoningEffort }
    $permissionMode = Normalize-CodexPermissionMode $PermissionMode
    $env:OMX_CODEX_SELECTED_PERMISSION_MODE = $permissionMode

    $configArgs = @()
    if (-not $providerProfile) {
        $configArgs = Get-CodexProviderConfigArgs -ProviderId $providerId -Name $providerName -BaseUrl $providerBaseUrl -EnvKey $targetEnvKey -WireApi $providerWireApi
    }

    $state = [ordered]@{
        provider = $providerId
        providerName = $providerName
        profile = $providerProfile
        baseUrl = $providerBaseUrl
        envKey = $targetEnvKey
        codexEnvKey = "OPENAI_API_KEY"
        openAIEnvMirrored = ($targetEnvKey -ne "OPENAI_API_KEY")
        keySource = $KeySourceId
        keyName = $keyName
        keyPrefix = Get-SecretPrefix $apiKey
        keyLength = $apiKey.Length
        model = $Model
        reasoningEffort = $ReasoningEffort
        permissionMode = $permissionMode
        switcherVersion = $script:CodexSwitcherVersion
        switcherAuthors = $script:CodexSwitcherAuthors
        switcherPortable = $script:CodexSwitcherIsPortable
        selectedAt = (Get-Date -Format o)
    }

    if ($Persist) {
        Save-CodexSwitcherSelection -Selection ([pscustomobject]$state) | Out-Null
    }

    [pscustomobject]@{
        Provider = $providerId
        ProviderName = $providerName
        ProfileName = $providerProfile
        BaseUrl = $providerBaseUrl
        EnvKey = $targetEnvKey
        CodexEnvKey = "OPENAI_API_KEY"
        OpenAIEnvMirrored = ($targetEnvKey -ne "OPENAI_API_KEY")
        KeySource = $KeySourceId
        KeyName = $keyName
        KeyPrefix = Get-SecretPrefix $apiKey
        Model = $Model
        ReasoningEffort = $ReasoningEffort
        PermissionMode = $permissionMode
        ConfigArgs = $configArgs
        State = [pscustomobject]$state
    }
}

function Get-CurrentCodexSelection {
    if ($env:OMX_CODEX_SELECTED_PROVIDER -and $env:OMX_CODEX_SELECTED_KEY_SOURCE) {
        return [pscustomobject]@{
            Provider = $env:OMX_CODEX_SELECTED_PROVIDER
            KeySource = $env:OMX_CODEX_SELECTED_KEY_SOURCE
            Model = $env:OMX_CODEX_SELECTED_MODEL
            ReasoningEffort = $env:OMX_CODEX_SELECTED_REASONING_EFFORT
            PermissionMode = Normalize-CodexPermissionMode $env:OMX_CODEX_SELECTED_PERMISSION_MODE
        }
    }

    try {
        $state = Get-CodexSwitcherSelection
        if ($state.provider -and $state.keySource) {
            return [pscustomobject]@{
                Provider = [string]$state.provider
                KeySource = [string]$state.keySource
                Model = [string]$state.model
                ReasoningEffort = [string]$state.reasoningEffort
                PermissionMode = Normalize-CodexPermissionMode ([string]$state.permissionMode)
            }
        }
    } catch {
    }

    return $null
}



