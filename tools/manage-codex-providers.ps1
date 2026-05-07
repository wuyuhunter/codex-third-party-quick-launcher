$ErrorActionPreference = "Stop"

function ConvertTo-CodexProcessArgument {
    param([AllowEmptyString()][string]$Argument)

    if ($null -eq $Argument) {
        return '""'
    }
    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') {
        return $Argument
    }

    $result = '"'
    $backslashCount = 0
    foreach ($char in $Argument.ToCharArray()) {
        if ($char -eq '\') {
            $backslashCount++
            continue
        }
        if ($char -eq '"') {
            if ($backslashCount -gt 0) {
                $result += '\' * ($backslashCount * 2)
                $backslashCount = 0
            }
            $result += '\"'
            continue
        }
        if ($backslashCount -gt 0) {
            $result += '\' * $backslashCount
            $backslashCount = 0
        }
        $result += $char
    }
    if ($backslashCount -gt 0) {
        $result += '\' * ($backslashCount * 2)
    }
    $result += '"'
    return $result
}

function Join-CodexProcessArguments {
    param([string[]]$Arguments)

    $quoted = foreach ($argument in @($Arguments)) {
        ConvertTo-CodexProcessArgument -Argument ([string]$argument)
    }
    return ($quoted -join " ")
}

function Start-CodexProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    if ($Arguments.Count -gt 0) {
        Start-Process -FilePath $FilePath -ArgumentList (Join-CodexProcessArguments -Arguments $Arguments) | Out-Null
    } else {
        Start-Process -FilePath $FilePath | Out-Null
    }
}

function Get-CodexLocalCommandPath {
    param([string[]]$Names)

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return $command.Source
        }
    }
    return $null
}

if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne "STA") {
    $psExe = Get-CodexLocalCommandPath -Names @("pwsh.exe", "pwsh", "powershell.exe", "powershell")
    if (-not $psExe) {
        throw "找不到 PowerShell，无法启动配置窗口。"
    }
    Start-CodexProcess -FilePath $psExe -Arguments @(
        "-Sta",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        $PSCommandPath
    ) | Out-Null
    return
}

$script:CodexSwitcherScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$script:CodexSwitcherScriptDir = Split-Path -Parent $script:CodexSwitcherScriptPath
. (Join-Path $script:CodexSwitcherScriptDir "codex-provider-lib.ps1")
Convert-CodexCatalogKeysToPlaintext
$script:CodexSwitcherBuild = Get-CodexSwitcherBuildInfo
$script:CodexSwitcherSettings = Get-CodexSwitcherSettings

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$switcherVersionForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Version)
$launcherProductForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Product)
$launcherAuthorsForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Authors)

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$launcherProductForXaml - 配置模型服务 $switcherVersionForXaml"
        Width="1000"
        Height="700"
        MinWidth="940"
        MinHeight="660"
        ResizeMode="CanResize"
        WindowStartupLocation="CenterScreen"
        Background="#F4F6F8"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#1E293B"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Height" Value="32"/>
            <Setter Property="Padding" Value="10,4"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Background" Value="White"/>
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Height" Value="34"/>
            <Setter Property="MinWidth" Value="86"/>
            <Setter Property="Padding" Value="10,0"/>
            <Setter Property="FontSize" Value="14"/>
        </Style>
        <Style TargetType="ListBox">
            <Setter Property="BorderBrush" Value="#CBD5E1"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
    </Window.Resources>
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="0,0,0,8">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock Text="配置模型服务提供方和 KEY" FontSize="20" FontWeight="SemiBold"/>
                <TextBlock Text="维护服务、KEY、模型和推理强度。KEY 保存在当前目录。"
                           Margin="0,3,0,0"
                           Foreground="#64748B"
                           FontSize="12"
                           TextWrapping="Wrap"/>
                <TextBlock Text="版本：$switcherVersionForXaml    作者：$launcherAuthorsForXaml"
                           Margin="0,3,0,0"
                           Foreground="#94A3B8"
                           FontSize="11"/>
                <TextBlock Text="MIT 协议 · GitHub 待创建 · Gitee 待创建"
                           Margin="0,3,0,0"
                           Foreground="#CBD5E1"
                           FontSize="11"/>
            </StackPanel>
            <StackPanel Grid.Column="1"
                        Orientation="Horizontal"
                        VerticalAlignment="Top"
                        Margin="16,0,0,0">
                <Button x:Name="ExportConfigButton"
                        Content="导出配置"
                        Background="#FFFFFF"
                        BorderBrush="#CBD5E1"
                        Foreground="#334155"
                        Margin="0,0,8,0"/>
                <Button x:Name="ImportConfigButton"
                        Content="导入配置"
                        Background="#FFFFFF"
                        BorderBrush="#CBD5E1"
                        Foreground="#334155"/>
            </StackPanel>
        </Grid>

        <TabControl x:Name="MainTabs" Grid.Row="1" Background="Transparent" BorderBrush="#CBD5E1">
            <TabItem Header="模型服务提供方和 KEY">
                <Grid Margin="0,8,0,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="250"/>
                        <ColumnDefinition Width="14"/>
                        <ColumnDefinition Width="*"/>
                    </Grid.ColumnDefinitions>

                    <Border Grid.Column="0"
                            Background="White"
                            BorderBrush="#E2E8F0"
                            BorderThickness="1"
                            CornerRadius="8"
                            Padding="12">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="模型服务提供方" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,6"/>
                            <ListBox x:Name="ProviderList" Grid.Row="1" Height="116"/>
                            <StackPanel Grid.Row="2" Margin="0,8,0,0">
                                <UniformGrid Columns="2">
                                    <Button x:Name="ProviderUpButton"
                                            Content="上移"
                                            Background="#FFFFFF"
                                            BorderBrush="#CBD5E1"
                                            Foreground="#334155"
                                            Margin="0,0,4,0"/>
                                    <Button x:Name="ProviderDownButton"
                                            Content="下移"
                                            Background="#FFFFFF"
                                            BorderBrush="#CBD5E1"
                                            Foreground="#334155"
                                            Margin="4,0,0,0"/>
                                </UniformGrid>
                                <Button x:Name="DefaultProviderButton"
                                        Content="设为默认"
                                        Margin="0,6,0,0"
                                        Background="#EFF6FF"
                                        BorderBrush="#93C5FD"
                                        Foreground="#1D4ED8"/>
                                <Button x:Name="NewProviderButton"
                                        Content="新增服务"
                                        Margin="0,6,0,0"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"/>
                                <Button x:Name="DeleteProviderButton"
                                        Content="删除服务"
                                        Margin="0,6,0,0"
                                        Background="#FEF2F2"
                                        BorderBrush="#FCA5A5"
                                        Foreground="#991B1B"/>
                            </StackPanel>
                        </Grid>
                    </Border>

                    <Border Grid.Column="2"
                            Background="White"
                            BorderBrush="#E2E8F0"
                            BorderThickness="1"
                            CornerRadius="8"
                            Padding="14">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="14"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Row="0" Grid.Column="0" Margin="0,0,0,8">
                                <TextBlock Text="服务名称" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                <TextBox x:Name="ProviderNameBox" Margin="0,5,0,0"/>
                            </StackPanel>

                            <StackPanel Grid.Row="0" Grid.Column="2" Margin="0,0,0,8">
                                <TextBlock Text="服务地址" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                <TextBox x:Name="ProviderUrlBox" Margin="0,5,0,0"/>
                            </StackPanel>

                            <StackPanel Grid.Row="1" Grid.ColumnSpan="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,0,10">
                                <Button x:Name="SaveProviderButton"
                                        Content="保存服务"
                                        Background="#2563EB"
                                        BorderBrush="#2563EB"
                                        Foreground="#FFFFFF"/>
                            </StackPanel>

                            <TextBlock Grid.Row="2"
                                       Grid.ColumnSpan="3"
                                       Text="当前模型服务的 KEY"
                                       FontSize="14"
                                       FontWeight="SemiBold"
                                       Margin="0,0,0,6"/>

                            <ListBox x:Name="KeyList"
                                     Grid.Row="3"
                                     Grid.ColumnSpan="3"
                                     Height="76"
                                     Margin="0,0,0,10"/>

                            <Grid Grid.Row="4" Grid.ColumnSpan="3" Margin="0,0,0,10">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="220"/>
                                    <ColumnDefinition Width="14"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>

                                <StackPanel Grid.Row="0" Grid.Column="0">
                                    <TextBlock Text="KEY 名称" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                    <TextBox x:Name="KeyNameBox" Margin="0,5,0,0"/>
                                </StackPanel>

                                <StackPanel Grid.Row="0" Grid.Column="2">
                                    <TextBlock Text="KEY" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                    <TextBox x:Name="ApiKeyBox" Margin="0,5,0,0"/>
                                </StackPanel>
                            </Grid>

                            <UniformGrid Grid.Row="5" Grid.ColumnSpan="3" Columns="3" Rows="2" Margin="0,0,0,0">
                                <Button x:Name="KeyUpButton"
                                        Content="上移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="0,0,8,8"/>
                                <Button x:Name="KeyDownButton"
                                        Content="下移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="0,0,8,8"/>
                                <Button x:Name="DefaultKeyButton"
                                        Content="设为默认"
                                        Background="#EFF6FF"
                                        BorderBrush="#93C5FD"
                                        Foreground="#1D4ED8"
                                        Margin="0,0,0,8"/>
                                <Button x:Name="NewKeyButton"
                                        Content="新增 KEY"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="0,0,8,0"/>
                                <Button x:Name="DeleteKeyButton"
                                        Content="删除 KEY"
                                        Background="#FEF2F2"
                                        BorderBrush="#FCA5A5"
                                        Foreground="#991B1B"
                                        Margin="0,0,8,0"/>
                                <Button x:Name="SaveKeyButton"
                                        Content="保存 KEY"
                                        Background="#2563EB"
                                        BorderBrush="#2563EB"
                                        Foreground="#FFFFFF"/>
                            </UniformGrid>
                        </Grid>
                    </Border>
                </Grid>
            </TabItem>

            <TabItem Header="模型和推理模式">
                <Border Background="White"
                        BorderBrush="#E2E8F0"
                        BorderThickness="1"
                        CornerRadius="8"
                        Padding="22"
                        Margin="0,14,0,0">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="18"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Row="0" Grid.ColumnSpan="3" Margin="0,0,0,18">
                            <TextBlock Text="全局模型和推理模式" FontSize="17" FontWeight="SemiBold"/>
                            <TextBlock Text="启动窗口使用同一份全局配置。"
                                       Margin="0,6,0,0"
                                       Foreground="#64748B"
                                       FontSize="13"/>
                        </StackPanel>

                        <Grid Grid.Row="1" Grid.Column="0">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="模型版本" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                            <ListBox x:Name="ModelsList" Grid.Row="1" MinHeight="170" Margin="0,7,0,0"/>
                            <UniformGrid Grid.Row="2" Columns="3" Margin="0,10,0,0">
                                <Button x:Name="DefaultModelButton"
                                        Content="设为默认"
                                        Background="#EFF6FF"
                                        BorderBrush="#93C5FD"
                                        Foreground="#1D4ED8"
                                        Margin="0,0,6,0"/>
                                <Button x:Name="ModelUpButton"
                                        Content="上移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="3,0,3,0"/>
                                <Button x:Name="ModelDownButton"
                                        Content="下移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="6,0,0,0"/>
                            </UniformGrid>
                            <StackPanel Grid.Row="3" Margin="0,12,0,0">
                                <TextBlock Text="模型名称" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                <TextBox x:Name="ModelValueBox" Margin="0,7,0,0"/>
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                                    <Button x:Name="NewModelButton"
                                            Content="新增"
                                            Background="#FFFFFF"
                                            BorderBrush="#CBD5E1"
                                            Foreground="#334155"
                                            Margin="0,0,10,0"/>
                                    <Button x:Name="DeleteModelButton"
                                            Content="删除"
                                            Background="#FEF2F2"
                                            BorderBrush="#FCA5A5"
                                            Foreground="#991B1B"
                                            Margin="0,0,10,0"/>
                                    <Button x:Name="SaveModelButton"
                                            Content="保存"
                                            Background="#2563EB"
                                            BorderBrush="#2563EB"
                                            Foreground="#FFFFFF"/>
                                </StackPanel>
                            </StackPanel>
                        </Grid>

                        <Grid Grid.Row="1" Grid.Column="2">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="推理模式" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                            <ListBox x:Name="ReasoningEffortsList" Grid.Row="1" MinHeight="170" Margin="0,7,0,0"/>
                            <UniformGrid Grid.Row="2" Columns="3" Margin="0,10,0,0">
                                <Button x:Name="DefaultReasoningEffortButton"
                                        Content="设为默认"
                                        Background="#EFF6FF"
                                        BorderBrush="#93C5FD"
                                        Foreground="#1D4ED8"
                                        Margin="0,0,6,0"/>
                                <Button x:Name="ReasoningEffortUpButton"
                                        Content="上移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="3,0,3,0"/>
                                <Button x:Name="ReasoningEffortDownButton"
                                        Content="下移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="6,0,0,0"/>
                            </UniformGrid>
                            <StackPanel Grid.Row="3" Margin="0,12,0,0">
                                <TextBlock Text="推理模式名称" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                <TextBox x:Name="ReasoningEffortValueBox" Margin="0,7,0,0"/>
                                <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,10,0,0">
                                    <Button x:Name="NewReasoningEffortButton"
                                            Content="新增"
                                            Background="#FFFFFF"
                                            BorderBrush="#CBD5E1"
                                            Foreground="#334155"
                                            Margin="0,0,10,0"/>
                                    <Button x:Name="DeleteReasoningEffortButton"
                                            Content="删除"
                                            Background="#FEF2F2"
                                            BorderBrush="#FCA5A5"
                                            Foreground="#991B1B"
                                            Margin="0,0,10,0"/>
                                    <Button x:Name="SaveReasoningEffortButton"
                                            Content="保存"
                                            Background="#2563EB"
                                            BorderBrush="#2563EB"
                                            Foreground="#FFFFFF"/>
                                </StackPanel>
                            </StackPanel>
                        </Grid>

                        <StackPanel Grid.Row="2"
                                    Grid.ColumnSpan="3"
                                    Orientation="Horizontal"
                                    HorizontalAlignment="Right"
                                    Margin="0,18,0,0">
                            <Button x:Name="ResetSettingsButton"
                                    Content="恢复默认"
                                    Background="#FFFFFF"
                                    BorderBrush="#CBD5E1"
                                    Foreground="#334155"
                                    Margin="0,0,10,0"/>
                            <Button x:Name="SaveSettingsButton"
                                    Content="保存当前编辑"
                                    Background="#2563EB"
                                    BorderBrush="#2563EB"
                                    Foreground="#FFFFFF"/>
                        </StackPanel>
                    </Grid>
                </Border>
            </TabItem>
        </TabControl>

        <Grid Grid.Row="2" Margin="0,16,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="StatusText"
                       Foreground="#64748B"
                       VerticalAlignment="Center"
                       TextWrapping="Wrap"/>
            <Button x:Name="CloseButton"
                    Grid.Column="1"
                    Content="关闭"
                    Background="#FFFFFF"
                    BorderBrush="#CBD5E1"
                    Foreground="#334155"/>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$providerList = $window.FindName("ProviderList")
$providerNameBox = $window.FindName("ProviderNameBox")
$providerUrlBox = $window.FindName("ProviderUrlBox")
$saveProviderButton = $window.FindName("SaveProviderButton")
$newProviderButton = $window.FindName("NewProviderButton")
$deleteProviderButton = $window.FindName("DeleteProviderButton")
$defaultProviderButton = $window.FindName("DefaultProviderButton")
$providerUpButton = $window.FindName("ProviderUpButton")
$providerDownButton = $window.FindName("ProviderDownButton")
$keyList = $window.FindName("KeyList")
$keyNameBox = $window.FindName("KeyNameBox")
$apiKeyBox = $window.FindName("ApiKeyBox")
$saveKeyButton = $window.FindName("SaveKeyButton")
$newKeyButton = $window.FindName("NewKeyButton")
$deleteKeyButton = $window.FindName("DeleteKeyButton")
$defaultKeyButton = $window.FindName("DefaultKeyButton")
$keyUpButton = $window.FindName("KeyUpButton")
$keyDownButton = $window.FindName("KeyDownButton")
$modelsList = $window.FindName("ModelsList")
$modelValueBox = $window.FindName("ModelValueBox")
$newModelButton = $window.FindName("NewModelButton")
$deleteModelButton = $window.FindName("DeleteModelButton")
$saveModelButton = $window.FindName("SaveModelButton")
$defaultModelButton = $window.FindName("DefaultModelButton")
$modelUpButton = $window.FindName("ModelUpButton")
$modelDownButton = $window.FindName("ModelDownButton")
$reasoningEffortsList = $window.FindName("ReasoningEffortsList")
$reasoningEffortValueBox = $window.FindName("ReasoningEffortValueBox")
$newReasoningEffortButton = $window.FindName("NewReasoningEffortButton")
$deleteReasoningEffortButton = $window.FindName("DeleteReasoningEffortButton")
$saveReasoningEffortButton = $window.FindName("SaveReasoningEffortButton")
$defaultReasoningEffortButton = $window.FindName("DefaultReasoningEffortButton")
$reasoningEffortUpButton = $window.FindName("ReasoningEffortUpButton")
$reasoningEffortDownButton = $window.FindName("ReasoningEffortDownButton")
$saveSettingsButton = $window.FindName("SaveSettingsButton")
$resetSettingsButton = $window.FindName("ResetSettingsButton")
$exportConfigButton = $window.FindName("ExportConfigButton")
$importConfigButton = $window.FindName("ImportConfigButton")
$closeButton = $window.FindName("CloseButton")
$statusText = $window.FindName("StatusText")
function Set-Status {
    param([string]$Message)
    $statusText.Text = $Message
}

function Test-CodexLauncherConfigShape {
    param($Config)

    if ($null -eq $Config -or $Config -is [array]) {
        return $false
    }

    $propertyNames = @($Config.PSObject.Properties.Name)
    foreach ($name in @("version", "settings", "catalog", "selection")) {
        if ($propertyNames -contains $name) {
            return $true
        }
    }
    return $false
}

function Export-CodexLauncherConfig {
    $warning = "导出的配置可能包含模型服务地址、API KEY、默认模型和权限模式。`n`n请只在自己的设备之间迁移，不要公开上传或转发给别人。`n`n确定继续导出吗？"
    $result = [System.Windows.MessageBox]::Show($warning, "导出配置", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    $dialog = New-Object Microsoft.Win32.SaveFileDialog
    $dialog.Title = "导出 Codex 便捷启动器配置"
    $dialog.Filter = "JSON 配置文件 (*.json)|*.json|所有文件 (*.*)|*.*"
    $dialog.FileName = "codex-quick-launcher-config-export.json"
    $dialog.OverwritePrompt = $true

    if ($dialog.ShowDialog() -ne $true) {
        return
    }

    try {
        $config = Get-CodexSwitcherConfig
        $config | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $dialog.FileName -Encoding UTF8
        Set-Status "配置已导出。请妥善保管，不要外传包含 KEY 的配置文件。"
    } catch {
        [System.Windows.MessageBox]::Show(($_ | Out-String).Trim(), "导出配置失败", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
}

function Import-CodexLauncherConfig {
    $warning = "导入配置会覆盖当前模型服务、KEY、模型列表、默认选择和权限模式。`n`n建议先导出备份当前配置。`n`n确定继续导入吗？"
    $result = [System.Windows.MessageBox]::Show($warning, "导入配置", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = "导入 Codex 便捷启动器配置"
    $dialog.Filter = "JSON 配置文件 (*.json)|*.json|所有文件 (*.*)|*.*"
    $dialog.Multiselect = $false

    if ($dialog.ShowDialog() -ne $true) {
        return
    }

    try {
        $imported = Get-Content -LiteralPath $dialog.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not (Test-CodexLauncherConfigShape -Config $imported)) {
            throw "这不是有效的 Codex 便捷启动器配置文件。"
        }

        Save-CodexSwitcherConfig -Config $imported | Out-Null
        Convert-CodexCatalogKeysToPlaintext
        $script:CodexSwitcherSettings = Get-CodexSwitcherSettings
        Refresh-Providers
        Load-SwitcherSettings
        Set-Status "配置已导入并覆盖当前配置。"
    } catch {
        [System.Windows.MessageBox]::Show(($_ | Out-String).Trim(), "导入配置失败", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
}

function Clear-KeyForm {
    $keyList.SelectedIndex = -1
    $keyNameBox.Clear()
    $apiKeyBox.Clear()
}

function Get-DefaultMarkerText {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [string]$DefaultValue
    )

    if ($Value -eq $DefaultValue) {
        return "★ $Value"
    }
    return "  $Value"
}

function Find-StringIndex {
    param(
        $Items,
        [string]$Value
    )

    $values = @($Items)
    for ($i = 0; $i -lt $values.Count; $i++) {
        if ($values[$i] -eq $Value) {
            return $i
        }
    }
    return -1
}

function Test-SettingDuplicate {
    param(
        [Parameter(Mandatory = $true)]$Items,
        [Parameter(Mandatory = $true)][string]$Value,
        [int]$IgnoreIndex = -1
    )

    $values = @($Items)
    for ($i = 0; $i -lt $values.Count; $i++) {
        if ($i -eq $IgnoreIndex) {
            continue
        }
        if (([string]$values[$i]).ToLowerInvariant() -eq $Value.ToLowerInvariant()) {
            return $true
        }
    }
    return $false
}

function Get-SelectedModelValue {
    $values = @($script:ModelValues)
    if ($modelsList.SelectedIndex -lt 0 -or $modelsList.SelectedIndex -ge $values.Count) {
        return $null
    }
    return [string]$values[$modelsList.SelectedIndex]
}

function Get-SelectedReasoningEffortValue {
    $values = @($script:ReasoningEffortValues)
    if ($reasoningEffortsList.SelectedIndex -lt 0 -or $reasoningEffortsList.SelectedIndex -ge $values.Count) {
        return $null
    }
    return [string]$values[$reasoningEffortsList.SelectedIndex]
}

function Set-ModelFormFromSelection {
    $value = Get-SelectedModelValue
    if ($value) {
        $modelValueBox.Text = $value
    } else {
        $modelValueBox.Clear()
    }
}

function Set-ReasoningEffortFormFromSelection {
    $value = Get-SelectedReasoningEffortValue
    if ($value) {
        $reasoningEffortValueBox.Text = $value
    } else {
        $reasoningEffortValueBox.Clear()
    }
}

function Load-SwitcherSettings {
    param(
        [string]$PreferredModel,
        [string]$PreferredReasoningEffort
    )

    $script:CodexSwitcherSettings = Get-CodexSwitcherSettings
    $script:ModelValues = @($script:CodexSwitcherSettings.models)
    $script:ReasoningEffortValues = @($script:CodexSwitcherSettings.reasoningEfforts)

    $modelsList.Items.Clear()
    foreach ($model in $script:ModelValues) {
        [void]$modelsList.Items.Add((Get-DefaultMarkerText -Value $model -DefaultValue $script:CodexSwitcherSettings.defaultModel))
    }

    if (-not $PreferredModel) {
        $PreferredModel = [string]$script:CodexSwitcherSettings.defaultModel
    }
    $modelIndex = Find-StringIndex -Items $script:ModelValues -Value $PreferredModel
    if ($modelIndex -lt 0 -and $modelsList.Items.Count -gt 0) {
        $modelIndex = 0
    }
    $modelsList.SelectedIndex = $modelIndex
    Set-ModelFormFromSelection

    $reasoningEffortsList.Items.Clear()
    foreach ($reasoningEffort in $script:ReasoningEffortValues) {
        [void]$reasoningEffortsList.Items.Add((Get-DefaultMarkerText -Value $reasoningEffort -DefaultValue $script:CodexSwitcherSettings.defaultReasoningEffort))
    }

    if (-not $PreferredReasoningEffort) {
        $PreferredReasoningEffort = [string]$script:CodexSwitcherSettings.defaultReasoningEffort
    }
    $reasoningEffortIndex = Find-StringIndex -Items $script:ReasoningEffortValues -Value $PreferredReasoningEffort
    if ($reasoningEffortIndex -lt 0 -and $reasoningEffortsList.Items.Count -gt 0) {
        $reasoningEffortIndex = 0
    }
    $reasoningEffortsList.SelectedIndex = $reasoningEffortIndex
    Set-ReasoningEffortFormFromSelection
}

function Save-ModelFromForm {
    param([switch]$Quiet)

    $value = $modelValueBox.Text.Trim()
    if (-not $value) {
        if (-not $Quiet) {
            [System.Windows.MessageBox]::Show("请填写模型名称。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
        return $false
    }

    $models = @($script:ModelValues)
    $selectedIndex = $modelsList.SelectedIndex
    $oldValue = if ($selectedIndex -ge 0 -and $selectedIndex -lt $models.Count) { [string]$models[$selectedIndex] } else { $null }
    if (Test-SettingDuplicate -Items $models -Value $value -IgnoreIndex $selectedIndex) {
        if (-not $Quiet) {
            [System.Windows.MessageBox]::Show("模型名称已存在。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
        return $false
    }

    if ($oldValue) {
        $models[$selectedIndex] = $value
    } else {
        $models += $value
    }

    $defaultModel = [string]$script:CodexSwitcherSettings.defaultModel
    if (-not $defaultModel -or ($oldValue -and $oldValue -eq $defaultModel)) {
        $defaultModel = $value
    }

    $preferredReasoningEffort = Get-SelectedReasoningEffortValue
    $script:CodexSwitcherSettings = Set-CodexSwitcherSettings -Models $models -ReasoningEfforts @($script:ReasoningEffortValues) -DefaultModel $defaultModel -DefaultReasoningEffort $script:CodexSwitcherSettings.defaultReasoningEffort
    Load-SwitcherSettings -PreferredModel $value -PreferredReasoningEffort $preferredReasoningEffort
    if (-not $Quiet) {
        Set-Status "模型已保存。"
    }
    return $true
}

function Save-ReasoningEffortFromForm {
    param([switch]$Quiet)

    $value = $reasoningEffortValueBox.Text.Trim()
    if (-not $value) {
        if (-not $Quiet) {
            [System.Windows.MessageBox]::Show("请填写推理模式名称。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
        return $false
    }

    $reasoningEfforts = @($script:ReasoningEffortValues)
    $selectedIndex = $reasoningEffortsList.SelectedIndex
    $oldValue = if ($selectedIndex -ge 0 -and $selectedIndex -lt $reasoningEfforts.Count) { [string]$reasoningEfforts[$selectedIndex] } else { $null }
    if (Test-SettingDuplicate -Items $reasoningEfforts -Value $value -IgnoreIndex $selectedIndex) {
        if (-not $Quiet) {
            [System.Windows.MessageBox]::Show("推理模式名称已存在。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
        return $false
    }

    if ($oldValue) {
        $reasoningEfforts[$selectedIndex] = $value
    } else {
        $reasoningEfforts += $value
    }

    $defaultReasoningEffort = [string]$script:CodexSwitcherSettings.defaultReasoningEffort
    if (-not $defaultReasoningEffort -or ($oldValue -and $oldValue -eq $defaultReasoningEffort)) {
        $defaultReasoningEffort = $value
    }

    $preferredModel = Get-SelectedModelValue
    $script:CodexSwitcherSettings = Set-CodexSwitcherSettings -Models @($script:ModelValues) -ReasoningEfforts $reasoningEfforts -DefaultModel $script:CodexSwitcherSettings.defaultModel -DefaultReasoningEffort $defaultReasoningEffort
    Load-SwitcherSettings -PreferredModel $preferredModel -PreferredReasoningEffort $value
    if (-not $Quiet) {
        Set-Status "推理模式已保存。"
    }
    return $true
}

function Save-SwitcherSettingsFromForm {
    $modelSaved = Save-ModelFromForm -Quiet
    $reasoningSaved = Save-ReasoningEffortFromForm -Quiet
    if ($modelSaved -or $reasoningSaved) {
        Set-Status "当前编辑已保存。"
    }
}

function Load-Provider {
    param([string]$PreferredKeyId)

    if ($providerList.SelectedIndex -lt 0) {
        $providerNameBox.Clear()
        $providerUrlBox.Clear()
        $keyList.Items.Clear()
        Clear-KeyForm
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    $providerNameBox.Text = $provider.name
    $providerUrlBox.Text = $provider.baseUrl
    $keyList.Items.Clear()
    $keys = @($provider.keys)
    foreach ($key in $keys) {
        $displayName = if ($key.id -eq $provider.defaultKeySource) { "★ $($key.name)" } else { "  $($key.name)" }
        [void]$keyList.Items.Add("$displayName  [$($key.prefix)...]")
    }

    Clear-KeyForm

    if ($keys.Count -gt 0) {
        $targetKeyId = if ($PreferredKeyId) { $PreferredKeyId } else { [string]$provider.defaultKeySource }
        $selectedKeyIndex = 0
        for ($i = 0; $i -lt $keys.Count; $i++) {
            if ($targetKeyId -and ($keys[$i].id -eq $targetKeyId -or $keys[$i].name -eq $targetKeyId)) {
                $selectedKeyIndex = $i
                break
            }
        }
        $keyList.SelectedIndex = $selectedKeyIndex
    }
}

function Refresh-Providers {
    param([string]$PreferredProviderId)

    $script:Providers = @(Get-CatalogProviders)
    $script:DefaultProviderId = Get-DefaultCodexCatalogProviderId
    $providerList.Items.Clear()
    foreach ($provider in $script:Providers) {
        $displayName = if ($provider.id -eq $script:DefaultProviderId) { "★ $($provider.name)" } else { "  $($provider.name)" }
        [void]$providerList.Items.Add("$displayName  |  $($provider.baseUrl)")
    }

    if ($providerList.Items.Count -eq 0) {
        Load-Provider
        return
    }

    $selectedIndex = 0
    if (-not $PreferredProviderId) {
        $PreferredProviderId = $script:DefaultProviderId
    }
    for ($i = 0; $i -lt $script:Providers.Count; $i++) {
        if ($PreferredProviderId -and $script:Providers[$i].id -eq $PreferredProviderId) {
            $selectedIndex = $i
            break
        }
    }
    $providerList.SelectedIndex = $selectedIndex
    Load-Provider
}

$providerList.Add_SelectionChanged({ Load-Provider })

$defaultProviderButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0) {
        [System.Windows.MessageBox]::Show("请先选择一个模型服务提供方。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    Set-CodexCatalogDefaultProvider -ProviderName $provider.id | Out-Null
    Refresh-Providers -PreferredProviderId $provider.id
    Set-Status "默认模型服务提供方已设置。"
})

$providerUpButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0) {
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    Move-CodexCatalogProvider -ProviderName $provider.id -Direction Up | Out-Null
    Refresh-Providers -PreferredProviderId $provider.id
    Set-Status "模型服务顺序已调整。"
})

$providerDownButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0) {
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    Move-CodexCatalogProvider -ProviderName $provider.id -Direction Down | Out-Null
    Refresh-Providers -PreferredProviderId $provider.id
    Set-Status "模型服务顺序已调整。"
})

$newProviderButton.Add_Click({
    $providerList.SelectedIndex = -1
    $providerNameBox.Clear()
    $providerUrlBox.Clear()
    $keyList.Items.Clear()
    Clear-KeyForm
    Set-Status "正在新增模型服务。"
})

$saveProviderButton.Add_Click({
    $name = $providerNameBox.Text.Trim()
    $url = $providerUrlBox.Text.Trim()
    if (-not $name -or -not $url) {
        [System.Windows.MessageBox]::Show("请填写服务名称和服务地址。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $existingId = $null
    if ($providerList.SelectedIndex -ge 0) {
        $existingId = $script:Providers[$providerList.SelectedIndex].id
    }

    Add-CodexCatalogProvider -Name $name -BaseUrl $url -EnvKey "CODEX_PROVIDER_API_KEY" -Id $existingId
    $targetId = if ($existingId) { $existingId } else { ConvertTo-CatalogId $name }
    Refresh-Providers -PreferredProviderId $targetId
    Set-Status "模型服务已保存。"
})

$deleteProviderButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0) {
        [System.Windows.MessageBox]::Show("请先选择一个模型服务提供方。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    $message = "确定删除模型服务提供方 $($provider.name) 吗？它下面的 KEY 也会从本机配置中移除。"
    $result = [System.Windows.MessageBox]::Show($message, "删除模型服务", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    try {
        Remove-CodexCatalogProvider -ProviderName $provider.id
        Refresh-Providers
        Set-Status "模型服务已删除。"
    } catch {
        [System.Windows.MessageBox]::Show(($_ | Out-String).Trim(), "删除模型服务失败", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
})

$keyList.Add_SelectionChanged({
    if ($providerList.SelectedIndex -lt 0 -or $keyList.SelectedIndex -lt 0) {
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    $key = @($provider.keys)[$keyList.SelectedIndex]
    $keyNameBox.Text = $key.name
    $apiKeyBox.Text = $key.apiKey
})

$newKeyButton.Add_Click({
    Clear-KeyForm
    Set-Status "正在新增 KEY。"
})

$defaultKeyButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0 -or $keyList.SelectedIndex -lt 0) {
        [System.Windows.MessageBox]::Show("请先选择一个 KEY。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    $key = @($provider.keys)[$keyList.SelectedIndex]
    Set-CodexCatalogDefaultKey -ProviderName $provider.id -KeyName $key.id | Out-Null
    Refresh-Providers -PreferredProviderId $provider.id
    Load-Provider -PreferredKeyId $key.id
    Set-Status "默认 KEY 已设置。"
})

$keyUpButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0 -or $keyList.SelectedIndex -lt 0) {
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    $key = @($provider.keys)[$keyList.SelectedIndex]
    Move-CodexCatalogKey -ProviderName $provider.id -KeyName $key.id -Direction Up | Out-Null
    Refresh-Providers -PreferredProviderId $provider.id
    Load-Provider -PreferredKeyId $key.id
    Set-Status "KEY 顺序已调整。"
})

$keyDownButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0 -or $keyList.SelectedIndex -lt 0) {
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    $key = @($provider.keys)[$keyList.SelectedIndex]
    Move-CodexCatalogKey -ProviderName $provider.id -KeyName $key.id -Direction Down | Out-Null
    Refresh-Providers -PreferredProviderId $provider.id
    Load-Provider -PreferredKeyId $key.id
    Set-Status "KEY 顺序已调整。"
})

$saveKeyButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0) {
        [System.Windows.MessageBox]::Show("请先选择或保存一个模型服务提供方。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $keyName = $keyNameBox.Text.Trim()
    $apiKey = $apiKeyBox.Text.Trim()
    if (-not $keyName -or -not $apiKey) {
        [System.Windows.MessageBox]::Show("请填写 KEY 名称和 KEY。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    $keyId = if ($keyList.SelectedIndex -ge 0) {
        @($provider.keys)[$keyList.SelectedIndex].id
    } else {
        $null
    }
    Add-CodexCatalogKey -ProviderName $provider.id -KeyName $keyName -ApiKey $apiKey -KeyId $keyId
    Refresh-Providers -PreferredProviderId $provider.id
    Set-Status "KEY 已保存。"
})

$deleteKeyButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0 -or $keyList.SelectedIndex -lt 0) {
        [System.Windows.MessageBox]::Show("请先选择一个 KEY。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    $key = @($provider.keys)[$keyList.SelectedIndex]
    $message = "确定删除 KEY $($key.name) 吗？"
    $result = [System.Windows.MessageBox]::Show($message, "删除 KEY", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    try {
        Remove-CodexCatalogKey -ProviderName $provider.id -KeyName $key.id
        Refresh-Providers -PreferredProviderId $provider.id
        Set-Status "KEY 已删除。"
    } catch {
        [System.Windows.MessageBox]::Show(($_ | Out-String).Trim(), "删除 KEY 失败", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error) | Out-Null
    }
})

$modelsList.Add_SelectionChanged({ Set-ModelFormFromSelection })
$reasoningEffortsList.Add_SelectionChanged({ Set-ReasoningEffortFormFromSelection })

$newModelButton.Add_Click({
    $modelsList.SelectedIndex = -1
    $modelValueBox.Clear()
    Set-Status "正在新增模型。"
})

$saveModelButton.Add_Click({
    Save-ModelFromForm | Out-Null
})

$deleteModelButton.Add_Click({
    if ($modelsList.SelectedIndex -lt 0) {
        [System.Windows.MessageBox]::Show("请先选择一个模型。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    if (@($script:ModelValues).Count -le 1) {
        [System.Windows.MessageBox]::Show("模型列表至少要保留一项。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $removedModel = Get-SelectedModelValue
    $models = @()
    $currentModels = @($script:ModelValues)
    for ($i = 0; $i -lt $currentModels.Count; $i++) {
        if ($i -ne $modelsList.SelectedIndex) {
            $models += $currentModels[$i]
        }
    }
    $defaultModel = if ($removedModel -eq $script:CodexSwitcherSettings.defaultModel) { $models[0] } else { $script:CodexSwitcherSettings.defaultModel }
    $preferredReasoningEffort = Get-SelectedReasoningEffortValue
    $script:CodexSwitcherSettings = Set-CodexSwitcherSettings -Models $models -ReasoningEfforts @($script:ReasoningEffortValues) -DefaultModel $defaultModel -DefaultReasoningEffort $script:CodexSwitcherSettings.defaultReasoningEffort
    Load-SwitcherSettings -PreferredModel $defaultModel -PreferredReasoningEffort $preferredReasoningEffort
    Set-Status "模型已删除。"
})

$defaultModelButton.Add_Click({
    $model = Get-SelectedModelValue
    if (-not $model) {
        [System.Windows.MessageBox]::Show("请先选择一个模型。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $preferredReasoningEffort = Get-SelectedReasoningEffortValue
    $script:CodexSwitcherSettings = Set-CodexSwitcherDefaultModel -Model $model
    Load-SwitcherSettings -PreferredModel $model -PreferredReasoningEffort $preferredReasoningEffort
    Set-Status "默认模型已设置。"
})

$modelUpButton.Add_Click({
    $model = Get-SelectedModelValue
    if (-not $model) {
        return
    }

    $preferredReasoningEffort = Get-SelectedReasoningEffortValue
    $script:CodexSwitcherSettings = Move-CodexSwitcherModel -Model $model -Direction Up
    Load-SwitcherSettings -PreferredModel $model -PreferredReasoningEffort $preferredReasoningEffort
    Set-Status "模型顺序已调整。"
})

$modelDownButton.Add_Click({
    $model = Get-SelectedModelValue
    if (-not $model) {
        return
    }

    $preferredReasoningEffort = Get-SelectedReasoningEffortValue
    $script:CodexSwitcherSettings = Move-CodexSwitcherModel -Model $model -Direction Down
    Load-SwitcherSettings -PreferredModel $model -PreferredReasoningEffort $preferredReasoningEffort
    Set-Status "模型顺序已调整。"
})

$newReasoningEffortButton.Add_Click({
    $reasoningEffortsList.SelectedIndex = -1
    $reasoningEffortValueBox.Clear()
    Set-Status "正在新增推理模式。"
})

$saveReasoningEffortButton.Add_Click({
    Save-ReasoningEffortFromForm | Out-Null
})

$deleteReasoningEffortButton.Add_Click({
    if ($reasoningEffortsList.SelectedIndex -lt 0) {
        [System.Windows.MessageBox]::Show("请先选择一个推理模式。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    if (@($script:ReasoningEffortValues).Count -le 1) {
        [System.Windows.MessageBox]::Show("推理模式列表至少要保留一项。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $removedReasoningEffort = Get-SelectedReasoningEffortValue
    $reasoningEfforts = @()
    $currentReasoningEfforts = @($script:ReasoningEffortValues)
    for ($i = 0; $i -lt $currentReasoningEfforts.Count; $i++) {
        if ($i -ne $reasoningEffortsList.SelectedIndex) {
            $reasoningEfforts += $currentReasoningEfforts[$i]
        }
    }
    $defaultReasoningEffort = if ($removedReasoningEffort -eq $script:CodexSwitcherSettings.defaultReasoningEffort) { $reasoningEfforts[0] } else { $script:CodexSwitcherSettings.defaultReasoningEffort }
    $preferredModel = Get-SelectedModelValue
    $script:CodexSwitcherSettings = Set-CodexSwitcherSettings -Models @($script:ModelValues) -ReasoningEfforts $reasoningEfforts -DefaultModel $script:CodexSwitcherSettings.defaultModel -DefaultReasoningEffort $defaultReasoningEffort
    Load-SwitcherSettings -PreferredModel $preferredModel -PreferredReasoningEffort $defaultReasoningEffort
    Set-Status "推理模式已删除。"
})

$defaultReasoningEffortButton.Add_Click({
    $reasoningEffort = Get-SelectedReasoningEffortValue
    if (-not $reasoningEffort) {
        [System.Windows.MessageBox]::Show("请先选择一个推理模式。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $preferredModel = Get-SelectedModelValue
    $script:CodexSwitcherSettings = Set-CodexSwitcherDefaultReasoningEffort -ReasoningEffort $reasoningEffort
    Load-SwitcherSettings -PreferredModel $preferredModel -PreferredReasoningEffort $reasoningEffort
    Set-Status "默认推理模式已设置。"
})

$reasoningEffortUpButton.Add_Click({
    $reasoningEffort = Get-SelectedReasoningEffortValue
    if (-not $reasoningEffort) {
        return
    }

    $preferredModel = Get-SelectedModelValue
    $script:CodexSwitcherSettings = Move-CodexSwitcherReasoningEffort -ReasoningEffort $reasoningEffort -Direction Up
    Load-SwitcherSettings -PreferredModel $preferredModel -PreferredReasoningEffort $reasoningEffort
    Set-Status "推理模式顺序已调整。"
})

$reasoningEffortDownButton.Add_Click({
    $reasoningEffort = Get-SelectedReasoningEffortValue
    if (-not $reasoningEffort) {
        return
    }

    $preferredModel = Get-SelectedModelValue
    $script:CodexSwitcherSettings = Move-CodexSwitcherReasoningEffort -ReasoningEffort $reasoningEffort -Direction Down
    Load-SwitcherSettings -PreferredModel $preferredModel -PreferredReasoningEffort $reasoningEffort
    Set-Status "推理模式顺序已调整。"
})

$saveSettingsButton.Add_Click({
    Save-SwitcherSettingsFromForm
})

$resetSettingsButton.Add_Click({
    $result = [System.Windows.MessageBox]::Show("确定恢复默认模型和推理模式列表吗？", "恢复默认", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    $script:CodexSwitcherSettings = Save-CodexSwitcherSettings -Settings (New-DefaultCodexSwitcherSettings)
    Load-SwitcherSettings
    Set-Status "模型和推理模式已恢复默认。"
})

$exportConfigButton.Add_Click({ Export-CodexLauncherConfig })
$importConfigButton.Add_Click({ Import-CodexLauncherConfig })
$closeButton.Add_Click({ $window.Close() })

Refresh-Providers
Load-SwitcherSettings
[void]$window.ShowDialog()

