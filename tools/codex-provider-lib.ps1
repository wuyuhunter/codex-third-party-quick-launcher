$script:CodexSwitcherProductName = "Codex 便捷启动器"
$script:CodexSwitcherVersion = "v0.3.15"
$script:CodexSwitcherAuthors = "夏小曦 & 知晴 & 砚行"
$script:CodexSwitcherGitHub = "GitHub: 待创建"
$script:CodexSwitcherGitee = "Gitee: 待创建"
$script:CodexSwitcherLicense = "MIT 协议"
$script:DefaultCodexSwitcherModels = @("gpt-5.5", "gpt-5.4")
$script:DefaultCodexSwitcherReasoningEfforts = @("high", "xhigh", "medium", "low")
$script:DefaultCodexSwitcherPermissionMode = "safe"

function Resolve-CodexSwitcherRuntimeRoot {
    $installedRoot = Join-Path $env:USERPROFILE ".omx"
    if ($env:CODEX_QUICK_LAUNCHER_HOME) {
        return [Environment]::ExpandEnvironmentVariables($env:CODEX_QUICK_LAUNCHER_HOME)
    }
    if ($env:AI_QUICK_LAUNCHER_HOME) {
        return [Environment]::ExpandEnvironmentVariables($env:AI_QUICK_LAUNCHER_HOME)
    }
    if ($env:CODEX_SWITCHER_HOME) {
        return [Environment]::ExpandEnvironmentVariables($env:CODEX_SWITCHER_HOME)
    }

    $toolDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $candidateRoot = Split-Path -Parent $toolDir
    if ((Test-Path -LiteralPath (Join-Path $candidateRoot "codex-quick-launcher.portable")) -or
        (Test-Path -LiteralPath (Join-Path $candidateRoot "ai-quick-launcher.portable")) -or
        (Test-Path -LiteralPath (Join-Path $candidateRoot "codex-switcher.portable"))) {
        return $candidateRoot
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

function Get-CodexSwitcherBuildInfo {
    [pscustomobject]@{
        Version = $script:CodexSwitcherVersion
        Product = $script:CodexSwitcherProductName
        Authors = $script:CodexSwitcherAuthors
        GitHub = $script:CodexSwitcherGitHub
        Gitee = $script:CodexSwitcherGitee
        License = $script:CodexSwitcherLicense
        RuntimeRoot = $script:CodexSwitcherRuntimeRoot
        Portable = $script:CodexSwitcherIsPortable
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
        Move-Item -LiteralPath $tempPath -Destination $script:CodexSwitcherConfigPath -Force
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
        reasoningEfforts = @($reasoningEfforts)
        defaultModel = $defaultModel
        defaultReasoningEffort = $defaultReasoningEffort
    }

    $config = Get-CodexSwitcherConfig
    Set-CodexObjectProperty -Object $config -Name "settings" -Value ([pscustomobject]$normalized)
    Save-CodexSwitcherConfig -Config $config | Out-Null
    return [pscustomobject]$normalized
}

function New-DefaultCodexSwitcherSettings {
    [pscustomobject]@{
        models = @($script:DefaultCodexSwitcherModels)
        reasoningEfforts = @($script:DefaultCodexSwitcherReasoningEfforts)
        defaultModel = $script:DefaultCodexSwitcherModels[0]
        defaultReasoningEffort = $script:DefaultCodexSwitcherReasoningEfforts[0]
    }
}

function Get-CodexSwitcherSettings {
    try {
        $config = Get-CodexSwitcherConfig
        $settings = Get-CodexObjectProperty -Object $config -Name "settings"
        if (-not $settings) {
            $settings = New-DefaultCodexSwitcherSettings
        }
        return Save-CodexSwitcherSettings -Settings $settings
    } catch {
        return Save-CodexSwitcherSettings -Settings (New-DefaultCodexSwitcherSettings)
    }
}

function Set-CodexSwitcherSettings {
    param(
        [Parameter(Mandatory = $true)][string[]]$Models,
        [Parameter(Mandatory = $true)][string[]]$ReasoningEfforts,
        [string]$DefaultModel,
        [string]$DefaultReasoningEffort
    )

    Save-CodexSwitcherSettings -Settings ([pscustomobject]@{
        models = @($Models)
        reasoningEfforts = @($ReasoningEfforts)
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
    Set-CodexSwitcherSettings -Models @($settings.models) -ReasoningEfforts @($settings.reasoningEfforts) -DefaultModel $Model -DefaultReasoningEffort $settings.defaultReasoningEffort
}

function Move-CodexSwitcherModel {
    param(
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][ValidateSet("Up", "Down")][string]$Direction
    )

    $settings = Get-CodexSwitcherSettings
    $models = Move-CodexSwitcherListItem -Items @($settings.models) -Value $Model -Direction $Direction
    Set-CodexSwitcherSettings -Models $models -ReasoningEfforts @($settings.reasoningEfforts) -DefaultModel $settings.defaultModel -DefaultReasoningEffort $settings.defaultReasoningEffort
}

function Set-CodexSwitcherDefaultReasoningEffort {
    param([Parameter(Mandatory = $true)][string]$ReasoningEffort)

    $settings = Get-CodexSwitcherSettings
    Set-CodexSwitcherSettings -Models @($settings.models) -ReasoningEfforts @($settings.reasoningEfforts) -DefaultModel $settings.defaultModel -DefaultReasoningEffort $ReasoningEffort
}

function Move-CodexSwitcherReasoningEffort {
    param(
        [Parameter(Mandatory = $true)][string]$ReasoningEffort,
        [Parameter(Mandatory = $true)][ValidateSet("Up", "Down")][string]$Direction
    )

    $settings = Get-CodexSwitcherSettings
    $reasoningEfforts = Move-CodexSwitcherListItem -Items @($settings.reasoningEfforts) -Value $ReasoningEffort -Direction $Direction
    Set-CodexSwitcherSettings -Models @($settings.models) -ReasoningEfforts $reasoningEfforts -DefaultModel $settings.defaultModel -DefaultReasoningEffort $settings.defaultReasoningEffort
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
            baseUrl = $provider.BaseUrl
            envKey = $(if ($provider.EnvKey) { $provider.EnvKey } else { "OPENAI_API_KEY" })
            profile = $provider.ProfileName
            wireApi = $provider.WireApi
            requiresOpenAIAuth = [bool]$provider.RequiresOpenAIAuth
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

        Set-CodexObjectProperty -Object $provider -Name "id" -Value $providerId
        Set-CodexObjectProperty -Object $provider -Name "name" -Value $providerName
        Set-CodexObjectProperty -Object $provider -Name "envKey" -Value $providerEnvKey
        Set-CodexObjectProperty -Object $provider -Name "wireApi" -Value $providerWireApi
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
            $catalog = New-CodexCatalogFromExisting
        }
        return Save-CodexProviderCatalog -Catalog $catalog
    } catch {
        $catalog = New-CodexCatalogFromExisting
        return Save-CodexProviderCatalog -Catalog $catalog
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
        [Parameter(Mandatory = $true)][ValidateSet("Up", "Down")][string]$Direction
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
        [string]$WireApi = "responses"
    )

    $catalog = Get-CodexProviderCatalog
    if (-not $Id) { $Id = ConvertTo-CatalogId $Name }
    $existing = @($catalog.providers) | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if ($existing) {
        $existing.name = $Name
        $existing.baseUrl = $BaseUrl
        $existing.envKey = $EnvKey
        $existing.profile = $Profile
        $existing.wireApi = $WireApi
    } else {
        $catalog.providers += [pscustomobject]@{
            id = $Id
            name = $Name
            baseUrl = $BaseUrl
            envKey = $EnvKey
            profile = $Profile
            wireApi = $WireApi
            requiresOpenAIAuth = $false
            defaultKeySource = ""
            keys = @()
        }
    }
    Save-CodexProviderCatalog -Catalog $catalog | Out-Null
    Sync-CodexConfigProvider -ProviderId $Id -Name $Name -BaseUrl $BaseUrl -EnvKey $EnvKey -WireApi $WireApi
}

function Sync-CodexConfigProvider {
    param(
        [Parameter(Mandatory = $true)][string]$ProviderId,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [string]$EnvKey = "OPENAI_API_KEY",
        [string]$WireApi = "responses"
    )

    if (-not (Test-Path -LiteralPath $script:CodexConfigPath)) {
        New-Item -ItemType Directory -Force (Split-Path -Parent $script:CodexConfigPath) | Out-Null
        Set-Content -LiteralPath $script:CodexConfigPath -Value "" -Encoding UTF8
    }

    $content = Get-Content -LiteralPath $script:CodexConfigPath -Raw -Encoding UTF8
    $sectionPattern = "(?ms)^\[model_providers\.$([regex]::Escape($ProviderId))\]\r?\n.*?(?=^\[|\z)"
    $section = @"
[model_providers.$ProviderId]
name = "$Name"
base_url = "$BaseUrl"
wire_api = "$WireApi"
env_key = "$EnvKey"
supports_websockets = false

"@

    if ($content -match $sectionPattern) {
        $content = [regex]::Replace($content, $sectionPattern, $section)
    } else {
        if ($content -and -not $content.EndsWith("`n")) {
            $content += "`r`n"
        }
        $content += "`r`n$section"
    }

    Set-Content -LiteralPath $script:CodexConfigPath -Value $content -Encoding UTF8
}

function Ensure-CodexBaseConfig {
    if (-not (Test-Path -LiteralPath $script:CodexConfigPath)) {
        New-Item -ItemType Directory -Force (Split-Path -Parent $script:CodexConfigPath) | Out-Null
        $content = @"
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
        Set-Content -LiteralPath $script:CodexConfigPath -Value $content -Encoding UTF8
        return
    }

    $content = Get-Content -LiteralPath $script:CodexConfigPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($content)) {
        Remove-Item -LiteralPath $script:CodexConfigPath -Force
        Ensure-CodexBaseConfig
        return
    }

    $changed = $false
    $prepend = @()
    if ($content -notmatch '(?m)^model_provider\s*=') { $prepend += 'model_provider = "OpenAI"' }
    if ($content -notmatch '(?m)^model\s*=') { $prepend += 'model = "gpt-5.5"' }
    if ($content -notmatch '(?m)^model_reasoning_effort\s*=') { $prepend += 'model_reasoning_effort = "high"' }
    if ($content -notmatch '(?m)^disable_response_storage\s*=') { $prepend += 'disable_response_storage = true' }
    if ($content -notmatch '(?m)^network_access\s*=') { $prepend += 'network_access = "enabled"' }
    if ($content -notmatch '(?m)^windows_wsl_setup_acknowledged\s*=') { $prepend += 'windows_wsl_setup_acknowledged = true' }
    if ($prepend.Count -gt 0) {
        $content = (($prepend -join "`r`n") + "`r`n" + $content)
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
        Set-Content -LiteralPath $script:CodexConfigPath -Value $content -Encoding UTF8
    }
}

function Remove-CodexConfigProvider {
    param([Parameter(Mandatory = $true)][string]$ProviderId)

    if (-not (Test-Path -LiteralPath $script:CodexConfigPath)) {
        return
    }

    $content = Get-Content -LiteralPath $script:CodexConfigPath -Raw -Encoding UTF8
    $sectionPattern = "(?ms)^\[model_providers\.$([regex]::Escape($ProviderId))\]\r?\n.*?(?=^\[|\z)"
    $content = [regex]::Replace($content, $sectionPattern, "")
    Set-Content -LiteralPath $script:CodexConfigPath -Value $content -Encoding UTF8
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
    Remove-CodexConfigProvider -ProviderId $provider.id
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

    Ensure-CodexBaseConfig
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
    $providerId = if ($provider.Id) { $provider.Id } else { $provider.id }
    $providerName = if ($provider.Name) { $provider.Name } else { $provider.name }
    $providerProfile = if ($provider.ProfileName) { $provider.ProfileName } else { $provider.profile }
    $providerBaseUrl = if ($provider.BaseUrl) { $provider.BaseUrl } else { $provider.baseUrl }
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
        $configArgs = @("-c", "model_provider=`"$providerId`"")
    }

    $state = [ordered]@{
        provider = $providerId
        providerName = $providerName
        profile = $providerProfile
        baseUrl = $providerBaseUrl
        envKey = $targetEnvKey
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



