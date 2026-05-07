param(
    [Alias('m')]
    [string]$Model,

    [Alias('c')]
    [string[]]$Config = @(),

    [switch]$NoUi,
    [switch]$InTerminal,
    [string]$Provider,
    [string]$KeySource,
    [string]$ReasoningEffort,
    [ValidateSet("safe", "full")]
    [string]$PermissionMode,
    [switch]$ResumeHistory,
    [string]$ResumeSessionId,
    [string]$ResumeSessionCwd,
    [switch]$ListResumeSessions,
    [switch]$ListConnectivityTargets,
    [switch]$PrintCodexArgs,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CodexArgs = @()
)

$ErrorActionPreference = "Stop"

$script:CodexSwitcherScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$script:CodexSwitcherScriptDir = Split-Path -Parent $script:CodexSwitcherScriptPath
. (Join-Path $script:CodexSwitcherScriptDir "codex-provider-lib.ps1")
Convert-CodexCatalogKeysToPlaintext
$script:CodexSwitcherBuild = Get-CodexSwitcherBuildInfo
$script:CodexSwitcherSettings = Get-CodexSwitcherSettings
try {
    $host.UI.RawUI.WindowTitle = "$($script:CodexSwitcherBuild.Product) $($script:CodexSwitcherBuild.Version) | $($script:CodexSwitcherBuild.Authors)"
} catch {
}

function Normalize-CodexConfigEntry {
    param([string]$Value)

    if ($null -eq $Value) {
        return $Value
    }

    $trimmed = $Value.Trim()
    if ($trimmed.Length -ge 2) {
        $first = $trimmed[0]
        $last = $trimmed[$trimmed.Length - 1]
        if (($first -eq "'" -and $last -eq "'") -or ($first -eq '"' -and $last -eq '"')) {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }
    }

    return $trimmed
}

function Get-CodexPermissionModeLabel {
    param([string]$Mode)

    switch (Normalize-CodexPermissionMode $Mode) {
        "full" { return "全权限模式 (YOLO)" }
        default { return "安全模式" }
    }
}

function Get-CodexPermissionModeDescription {
    param([string]$Mode)

    if ((Normalize-CodexPermissionMode $Mode) -eq "full") {
        return "直接开启 YOLO：不再逐步询问确认，命令不受 Codex 沙箱限制。只在完全信任当前目录和任务时使用。"
    }

    return "显式使用安全参数：需要时会询问确认，命令在 workspace-write 沙箱内执行，不受本机全局 YOLO 配置影响。"
}

function Get-CodexPermissionModeArgs {
    param([string]$Mode)

    if ((Normalize-CodexPermissionMode $Mode) -eq "full") {
        return @("--dangerously-bypass-approvals-and-sandbox")
    }

    return @("-a", "on-request", "-s", "workspace-write")
}

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

function Get-PersistedCodexSelection {
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

function Get-CodexCommandPath {
    param([string[]]$Names)

    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) {
            return $cmd.Source
        }
    }

    return $null
}

function Get-CodexInstallerStatus {
    $npmMirror = "https://registry.npmmirror.com"
    $winget = Get-CodexCommandPath -Names @("winget.exe", "winget")
    $pwsh = Get-CodexCommandPath -Names @("pwsh.exe", "pwsh")
    $wt = Get-CodexCommandPath -Names @("wt.exe", "wt")
    $node = Get-CodexCommandPath -Names @("node.exe", "node")
    $npm = Get-CodexCommandPath -Names @("npm.cmd", "npm.ps1", "npm")
    $codex = Get-CodexCommandPath -Names @("codex.cmd", "codex.ps1", "codex")
    $codexConfig = Test-Path -LiteralPath (Join-Path $env:USERPROFILE ".codex\config.toml")
    $registry = ""
    if ($npm) {
        try { $registry = (& $npm config get registry 2>$null | Select-Object -First 1) } catch { $registry = "" }
    }

    @(
        [pscustomobject]@{ Step = "1"; Name = "系统 PowerShell"; Action = "Win10 / Win11 自带，用来打开本工具"; Status = "已内置" }
        [pscustomobject]@{ Step = "2"; Name = "Node.js LTS / npm"; Action = "从 Node 镜像源下载安装"; Status = if ($node -and $npm) { "已安装" } else { "待安装" } }
        [pscustomobject]@{ Step = "3"; Name = "npm 镜像源"; Action = "使用 registry.npmmirror.com"; Status = if (-not $npm) { "等待 npm" } elseif ($registry -eq $npmMirror) { "已配置" } elseif ($registry) { "待配置：$registry" } else { "待配置" } }
        [pscustomobject]@{ Step = "4"; Name = "Codex CLI"; Action = "npm 全局安装 @openai/codex"; Status = if ($codex) { "已安装" } else { "待安装" } }
        [pscustomobject]@{ Step = "5"; Name = "Codex 初始配置"; Action = "预创建 config.toml，跳过首次配置界面"; Status = if ($codexConfig) { "已初始化" } else { "待初始化" } }
        [pscustomobject]@{ Step = "6"; Name = "Windows Terminal"; Action = "标签页终端，方便查看安装和 Codex 输出"; Status = if ($wt) { "已安装" } else { "完整安装可补" } }
        [pscustomobject]@{ Step = "7"; Name = "PowerShell 7"; Action = "新版 PowerShell，供高级脚本和部分工具使用"; Status = if ($pwsh) { "已安装" } else { "完整安装可补" } }
        [pscustomobject]@{ Step = "8"; Name = "服务和 KEY"; Action = "在维护页填写 base_url 和 KEY"; Status = "核心安装后配置" }
    )
}

function Get-CodexAdvancedComponentStatus {
    param([Parameter(Mandatory = $true)][string]$Component)

    switch ($Component) {
        "omx" {
            if (Get-CodexCommandPath -Names @("omx.cmd", "omx.ps1", "omx")) {
                return "已安装"
            }
            return "未安装"
        }
        "git" {
            if (Get-CodexCommandPath -Names @("git.exe", "git")) {
                return "已安装"
            }
            return "未安装"
        }
        "pwsh" {
            if (Get-CodexCommandPath -Names @("pwsh.exe", "pwsh")) {
                return "已安装"
            }
            return "未安装"
        }
        "wt" {
            if (Get-CodexCommandPath -Names @("wt.exe", "wt")) {
                return "已安装"
            }
            return "未安装"
        }
        default {
            return "未知"
        }
    }
}

function Open-CodexLauncherLicense {
    $root = Split-Path -Parent $script:CodexSwitcherScriptDir
    $licensePath = Join-Path $root "LICENSE"
    if (Test-Path -LiteralPath $licensePath) {
        Start-CodexProcess -FilePath $licensePath
        return
    }

    [System.Windows.MessageBox]::Show("找不到内置 MIT 协议文件：`n$licensePath", "Codex 便捷启动器", "OK", "Warning") | Out-Null
}

function Open-CodexLauncherGitHub {
    Start-CodexProcess -FilePath $script:CodexSwitcherBuild.GitHub
}

function Open-CodexLauncherGitee {
    Start-CodexProcess -FilePath $script:CodexSwitcherBuild.Gitee
}

function Register-CodexLauncherLinks {
    param(
        [Parameter(Mandatory = $true)]$Window,
        [string]$LicenseLinkName,
        [string]$GithubLogoName,
        [string]$GiteeLogoName
    )

    $licenseLink = if ($LicenseLinkName) { $Window.FindName($LicenseLinkName) } else { $null }
    if ($licenseLink) {
        $licenseLink.Add_MouseLeftButtonUp({ Open-CodexLauncherLicense })
    }

    $githubLogo = if ($GithubLogoName) { $Window.FindName($GithubLogoName) } else { $null }
    if ($githubLogo) {
        $githubLogo.Add_MouseLeftButtonUp({ Open-CodexLauncherGitHub })
    }

    $giteeLogo = if ($GiteeLogoName) { $Window.FindName($GiteeLogoName) } else { $null }
    if ($giteeLogo) {
        $giteeLogo.Add_MouseLeftButtonUp({ Open-CodexLauncherGitee })
    }
}

function Get-CodexAdvancedComponentRows {
    $definitions = @(
        [pscustomobject]@{
            Component = "omx"
            Name = "OMX 增强组件"
            Action = "为进阶 Codex 使用提供计划、任务、记忆、插件和协作工作流。"
        }
        [pscustomobject]@{
            Component = "git"
            Name = "Git for Windows"
            Action = "用于拉取 GitHub/Gitee 仓库、提交代码和同步开源项目。"
        }
        [pscustomobject]@{
            Component = "pwsh"
            Name = "PowerShell 7"
            Action = "给高级脚本和部分工具提供新版 PowerShell 环境；启动器核心功能不依赖它。"
        }
        [pscustomobject]@{
            Component = "wt"
            Name = "Windows Terminal"
            Action = "提供标签页终端窗口，安装或启动 Codex 时更容易查看输出。"
        }
    )

    foreach ($item in $definitions) {
        $status = Get-CodexAdvancedComponentStatus -Component $item.Component
        $canInstall = ($status -eq "未安装")
        [pscustomobject]@{
            Component = $item.Component
            Name = $item.Name
            Action = $item.Action
            Status = $status
            CanInstall = $canInstall
            ButtonText = if ($canInstall) { "安装" } else { "已安装" }
        }
    }
}

function Start-CodexInstallerTerminalFromUi {
    param(
        [Parameter(Mandatory = $true)][string]$InstallerScript,
        [object]$InfoBox,
        [switch]$Full,
        [ValidateSet("omx", "git", "pwsh", "wt")]
        [string]$AdvancedComponent,
        [string]$AdvancedComponentName
    )

    if (-not (Test-Path -LiteralPath $InstallerScript)) {
        [System.Windows.MessageBox]::Show("找不到安装脚本：`n$InstallerScript", "Codex 便捷启动器", "OK", "Error") | Out-Null
        return
    }

    $psExe = Get-CodexCommandPath -Names @("pwsh.exe", "pwsh", "powershell.exe", "powershell")
    if (-not $psExe) {
        [System.Windows.MessageBox]::Show("找不到 PowerShell，无法启动安装。", "Codex 便捷启动器", "OK", "Error") | Out-Null
        return
    }

    $installerArgs = @(
        "-NoExit",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $InstallerScript
    )
    if ($Full) {
        $installerArgs += "-Full"
    }
    if ($AdvancedComponent) {
        $installerArgs += @("-AdvancedComponent", $AdvancedComponent)
    }

    $title = if ($AdvancedComponentName) { "Codex 高级组件 - $AdvancedComponentName" } elseif ($Full) { "Codex 完整安装" } else { "Codex 核心安装" }
    $wtExe = Get-CodexCommandPath -Names @("wt.exe", "wt")
    if ($wtExe) {
        $wtArgs = @(
            "new-tab",
            "--title", $title,
            $psExe
        )
        $wtArgs += $installerArgs
        Start-CodexProcess -FilePath $wtExe -Arguments $wtArgs
    } else {
        Start-CodexProcess -FilePath $psExe -Arguments $installerArgs
    }

    if ($InfoBox) {
        $InfoBox.Text = if ($AdvancedComponentName) {
            "$AdvancedComponentName 安装终端已打开。请等待终端显示「高级组件安装完成」，然后关闭终端并点击「重新检测」。"
        } elseif ($Full) {
            "完整安装终端已打开。它会先保证核心环境可用，再安装 PowerShell 7 和 Windows Terminal。请等待终端显示「完整环境安装完成」，然后关闭终端并点击「重新检测」。"
        } else {
            "核心安装终端已打开。请等待终端显示「核心环境安装完成」，然后关闭终端并点击「重新检测」。"
        }
    }
}

function Show-CodexAdvancedComponentsDialog {
    param(
        [Parameter(Mandatory = $true)]$Owner,
        [Parameter(Mandatory = $true)][string]$InstallerScript,
        [object]$InfoBox
    )

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    [xml]$advancedXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="高级组件"
        Width="940"
        Height="560"
        MinWidth="860"
        MinHeight="500"
        WindowStartupLocation="CenterOwner"
        ResizeMode="CanResize"
        Background="#F4F6F8"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#1E293B"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Height" Value="32"/>
            <Setter Property="MinWidth" Value="96"/>
            <Setter Property="Padding" Value="10,0"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="ListViewItem">
            <Setter Property="MinHeight" Value="54"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,14">
            <TextBlock Text="高级组件" FontSize="22" FontWeight="SemiBold"/>
            <TextBlock Text="这些组件面向进阶用户，不影响核心启动能力。请按需安装；安装过程会打开终端并可能修改全局工具环境。"
                       Margin="0,6,0,0"
                       Foreground="#64748B"
                       FontSize="13"
                       TextWrapping="Wrap"/>
        </StackPanel>

        <Border Grid.Row="1"
                Background="White"
                BorderBrush="#E2E8F0"
                BorderThickness="1"
                CornerRadius="8"
                Padding="12">
            <ListView x:Name="AdvancedComponentList"
                      BorderThickness="0"
                      ScrollViewer.VerticalScrollBarVisibility="Auto"
                      ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                <ListView.View>
                    <GridView>
                        <GridViewColumn Header="名称" DisplayMemberBinding="{Binding Name}" Width="185"/>
                        <GridViewColumn Header="用途" Width="440">
                            <GridViewColumn.CellTemplate>
                                <DataTemplate>
                                    <TextBlock Text="{Binding Action}"
                                               TextWrapping="Wrap"
                                               VerticalAlignment="Center"/>
                                </DataTemplate>
                            </GridViewColumn.CellTemplate>
                        </GridViewColumn>
                        <GridViewColumn Header="状态" DisplayMemberBinding="{Binding Status}" Width="100"/>
                        <GridViewColumn Header="操作" Width="120">
                            <GridViewColumn.CellTemplate>
                                <DataTemplate>
                                    <Button Content="{Binding ButtonText}"
                                            IsEnabled="{Binding CanInstall}"
                                            Width="82"
                                            HorizontalAlignment="Center"/>
                                </DataTemplate>
                            </GridViewColumn.CellTemplate>
                        </GridViewColumn>
                    </GridView>
                </ListView.View>
            </ListView>
        </Border>

        <Grid Grid.Row="2" Margin="0,14,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="AdvancedStatusText" Foreground="#64748B" VerticalAlignment="Center" TextWrapping="Wrap"/>
            <Button x:Name="AdvancedRefreshButton"
                    Grid.Column="1"
                    Content="重新检测"
                    Background="#FFFFFF"
                    BorderBrush="#CBD5E1"
                    Foreground="#334155"
                    Margin="0,0,10,0"/>
            <Button x:Name="AdvancedCloseButton"
                    Grid.Column="2"
                    Content="关闭"
                    Background="#FFFFFF"
                    BorderBrush="#CBD5E1"
                    Foreground="#334155"/>
        </Grid>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $advancedXaml
    $advancedWindow = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) {
        $advancedWindow.Owner = $Owner
    }
    $componentList = $advancedWindow.FindName("AdvancedComponentList")
    $advancedStatus = $advancedWindow.FindName("AdvancedStatusText")
    $advancedRefresh = $advancedWindow.FindName("AdvancedRefreshButton")
    $advancedClose = $advancedWindow.FindName("AdvancedCloseButton")

    $refreshAdvancedRows = {
        $componentList.ItemsSource = $null
        $componentList.ItemsSource = @(Get-CodexAdvancedComponentRows)
        $advancedStatus.Text = "已检测本机高级组件状态。未安装的组件可点击「安装」。"
    }

    $componentList.AddHandler([System.Windows.Controls.Button]::ClickEvent, [System.Windows.RoutedEventHandler]{
        param($sender, $eventArgs)
        try {
            $button = $eventArgs.OriginalSource
            if (-not ($button -is [System.Windows.Controls.Button])) {
                return
            }

            $row = $button.DataContext
            if (-not $row -or -not $row.CanInstall) {
                return
            }

            $component = [string]$row.Component
            $name = [string]$row.Name
            $message = "$name 属于高级组件，安装过程会联网并可能修改全局工具环境。`n`n确定安装吗？"
            $result = [System.Windows.MessageBox]::Show($message, "安装高级组件", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
            if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
                return
            }

            Start-CodexInstallerTerminalFromUi -InstallerScript $InstallerScript -InfoBox $InfoBox -AdvancedComponent $component -AdvancedComponentName $name
            $button.IsEnabled = $false
            $button.Content = "已打开"
            $advancedStatus.Text = "$name 安装终端已打开。安装完成后关闭终端，再回到安装环境页重新检测。"
        } catch {
            $advancedStatus.Text = "启动安装失败：$($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("启动安装失败：`n$($_.Exception.Message)", "Codex 便捷启动器", "OK", "Error") | Out-Null
        }
    })

    $advancedRefresh.Add_Click($refreshAdvancedRows)
    $advancedClose.Add_Click({ $advancedWindow.Close() })

    & $refreshAdvancedRows
    [void]$advancedWindow.ShowDialog()
}

function Show-CodexInstallerUi {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $switcherVersionForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Version)
    $launcherProductForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Product)
    $launcherAuthorsForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Authors)

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$launcherProductForXaml - 安装运行环境 $switcherVersionForXaml"
        Width="860"
        Height="640"
        MinWidth="780"
        MinHeight="560"
        ResizeMode="CanResize"
        WindowStartupLocation="CenterScreen"
        Background="#F4F6F8"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#1E293B"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Height" Value="34"/>
            <Setter Property="MinWidth" Value="96"/>
            <Setter Property="Padding" Value="12,0"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
    </Window.Resources>
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <TextBlock Text="安装运行环境" FontSize="22" FontWeight="SemiBold"/>
            <TextBlock Text="从空白 Win10 / Win11 到可启动 Codex：使用镜像源安装 Node.js/npm、配置 npm 镜像、安装 Codex CLI。Windows Terminal 用来更方便查看终端输出，PowerShell 7 供高级脚本和部分工具使用。"
                       Margin="0,6,0,0"
                       Foreground="#64748B"
                       TextWrapping="Wrap"
                       FontSize="13"/>
            <TextBlock Text="版本：$switcherVersionForXaml    作者：$launcherAuthorsForXaml"
                       Margin="0,6,0,0"
                       Foreground="#94A3B8"
                       FontSize="12"/>
            <TextBlock Text="MIT 协议 · GitHub · Gitee"
                       Margin="0,3,0,0"
                       Foreground="#CBD5E1"
                       FontSize="11"/>
        </StackPanel>

        <Border Grid.Row="1"
                Background="White"
                BorderBrush="#E2E8F0"
                BorderThickness="1"
                CornerRadius="8"
                Padding="10">
            <ListView x:Name="Checklist" BorderThickness="0">
                <ListView.View>
                    <GridView>
                        <GridViewColumn Header="顺序" DisplayMemberBinding="{Binding Step}" Width="48"/>
                        <GridViewColumn Header="项目" DisplayMemberBinding="{Binding Name}" Width="180"/>
                        <GridViewColumn Header="用途" DisplayMemberBinding="{Binding Action}" Width="330"/>
                        <GridViewColumn Header="状态" DisplayMemberBinding="{Binding Status}" Width="220"/>
                    </GridView>
                </ListView.View>
            </ListView>
        </Border>

        <TextBox x:Name="InfoBox"
                 Grid.Row="2"
                 Margin="0,12,0,0"
                 MinHeight="72"
                 IsReadOnly="True"
                 TextWrapping="Wrap"
                 VerticalScrollBarVisibility="Auto"
                 Background="#F8FAFC"
                 BorderBrush="#CBD5E1"
                 Foreground="#475569"/>

        <Grid Grid.Row="3"
              Margin="0,12,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="AdvancedComponentsButton"
                    Grid.Column="0"
                    Content="高级组件"
                    HorizontalAlignment="Left"
                    Background="#FFFFFF"
                    BorderBrush="#CBD5E1"
                    Foreground="#334155"/>
            <StackPanel Grid.Column="1"
                        Orientation="Horizontal"
                        HorizontalAlignment="Right">
                <Button x:Name="RefreshButton"
                        Content="重新检测"
                        Background="#FFFFFF"
                        BorderBrush="#CBD5E1"
                        Foreground="#334155"
                        Margin="0,0,10,0"/>
                <Button x:Name="CoreInstallButton"
                        Content="核心安装"
                        Background="#16A34A"
                        BorderBrush="#16A34A"
                        Foreground="#FFFFFF"
                        Margin="0,0,10,0"/>
                <Button x:Name="FullInstallButton"
                        Content="完整安装"
                        Background="#2563EB"
                        BorderBrush="#2563EB"
                        Foreground="#FFFFFF"
                        Margin="0,0,10,0"/>
                <Button x:Name="CloseButton"
                        Content="关闭"
                        Background="#FFFFFF"
                        BorderBrush="#CBD5E1"
                        Foreground="#334155"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $checklist = $window.FindName("Checklist")
    $infoBox = $window.FindName("InfoBox")
    $refresh = $window.FindName("RefreshButton")
    $coreInstall = $window.FindName("CoreInstallButton")
    $fullInstall = $window.FindName("FullInstallButton")
    $advancedComponents = $window.FindName("AdvancedComponentsButton")
    $close = $window.FindName("CloseButton")
    $installerScript = Join-Path $script:CodexSwitcherScriptDir "install-codex-switcher-prereqs.ps1"

    $refreshView = {
        $checklist.ItemsSource = $null
        $checklist.ItemsSource = @(Get-CodexInstallerStatus)
        $infoBox.Text = "核心安装：从 Node 镜像源安装 Node.js LTS/npm、配置 npm 镜像为 https://registry.npmmirror.com、安装 @openai/codex，并预创建 Codex config.toml。完整安装：先完成核心安装，再补 Windows Terminal（标签页终端，方便看输出）和 PowerShell 7（高级脚本环境）。"
    }

    function Start-InstallerTerminal {
        param(
            [switch]$Full,
            [string]$AdvancedComponent,
            [string]$AdvancedComponentName
        )

        if (-not (Test-Path -LiteralPath $installerScript)) {
            [System.Windows.MessageBox]::Show("找不到安装脚本：`n$installerScript", "Codex 便捷启动器", "OK", "Error") | Out-Null
            return
        }

        $psExe = Get-CodexCommandPath -Names @("pwsh.exe", "pwsh", "powershell.exe", "powershell")
        if (-not $psExe) {
            [System.Windows.MessageBox]::Show("找不到 PowerShell，无法启动安装。", "Codex 便捷启动器", "OK", "Error") | Out-Null
            return
        }

        $installerArgs = @(
            "-NoExit",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $installerScript
        )
        if ($Full) {
            $installerArgs += "-Full"
        }
        if ($AdvancedComponent) {
            $installerArgs += @("-AdvancedComponent", $AdvancedComponent)
        }

        $title = if ($AdvancedComponentName) { "Codex 高级组件 - $AdvancedComponentName" } elseif ($Full) { "Codex 完整安装" } else { "Codex 核心安装" }
        $wtExe = Get-CodexCommandPath -Names @("wt.exe", "wt")
        if ($wtExe) {
            $wtArgs = @(
                "new-tab",
                "--title", $title,
                $psExe
            )
            $wtArgs += $installerArgs
            Start-CodexProcess -FilePath $wtExe -Arguments $wtArgs
        } else {
            Start-CodexProcess -FilePath $psExe -Arguments $installerArgs
        }

        $infoBox.Text = if ($AdvancedComponentName) {
            "$AdvancedComponentName 安装终端已打开。请等待终端显示「高级组件安装完成」，然后关闭终端并点击「重新检测」。"
        } elseif ($Full) {
            "完整安装终端已打开。它会先保证核心环境可用，再安装 PowerShell 7 和 Windows Terminal。请等待终端显示「完整环境安装完成」，然后关闭终端并点击「重新检测」。"
        } else {
            "核心安装终端已打开。请等待终端显示「核心环境安装完成」，然后关闭终端并点击「重新检测」。"
        }
    }

    $refresh.Add_Click($refreshView)
    $coreInstall.Add_Click({ Start-InstallerTerminal })
    $fullInstall.Add_Click({ Start-InstallerTerminal -Full })
    $advancedComponents.Add_Click({
        try {
            Show-CodexAdvancedComponentsDialog -Owner $window -InstallerScript $installerScript -InfoBox $infoBox
        } catch {
            [System.Windows.MessageBox]::Show("高级组件窗口打开失败：`n$($_.Exception.Message)", "Codex 便捷启动器", "OK", "Error") | Out-Null
        }
    })
    $close.Add_Click({ $window.Close() })

    & $refreshView
    [void]$window.ShowDialog()
}

function Get-CodexResumeSessions {
    param([int]$Limit = 200)

    $sessionRoot = Join-Path $env:USERPROFILE ".codex\sessions"
    if (-not (Test-Path -LiteralPath $sessionRoot)) {
        return @()
    }

    $rows = @()
    $files = Get-ChildItem -LiteralPath $sessionRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 0 -and $_.Extension -eq ".jsonl" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Limit

    foreach ($file in $files) {
        $meta = $null
        $firstUserMessage = ""
        $lineCount = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue) {
            $lineCount++
            if ($lineCount -gt 160 -and $meta -and $firstUserMessage) {
                break
            }
            try {
                $entry = $line | ConvertFrom-Json
            } catch {
                continue
            }

            if (-not $meta -and $entry.type -eq "session_meta") {
                $meta = $entry.payload
            }
            if ($entry.type -eq "event_msg" -and $entry.payload.type -eq "user_message") {
                $candidateMessage = ([string]$entry.payload.message).Trim()
                if (Test-CodexSessionPreviewText -Text $candidateMessage) {
                    $firstUserMessage = $candidateMessage
                    break
                }
            }
            if (-not $firstUserMessage -and $entry.type -eq "response_item" -and $entry.payload.type -eq "message" -and $entry.payload.role -eq "user") {
                $content = @($entry.payload.content) | Select-Object -First 1
                if ($content -and $content.text) {
                    $candidateMessage = ([string]$content.text).Trim()
                    if (Test-CodexSessionPreviewText -Text $candidateMessage) {
                        $firstUserMessage = $candidateMessage
                    }
                }
            }
        }

        if (-not $meta -or -not $meta.id) {
            if ($file.BaseName -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
                $meta = [pscustomobject]@{ id = $Matches[1]; timestamp = $file.LastWriteTime; cwd = ""; model_provider = "" }
            } else {
                continue
            }
        }

        $started = $file.LastWriteTime
        if ($meta.timestamp) {
            try { $started = [datetime]$meta.timestamp } catch { $started = $file.LastWriteTime }
        }

        if (-not $firstUserMessage) {
            $firstUserMessage = "(无用户消息预览)"
        }
        if ($firstUserMessage.Length -gt 120) {
            $firstUserMessage = $firstUserMessage.Substring(0, 120) + "..."
        }

        $rows += [pscustomobject]@{
            LastActive = $file.LastWriteTime
            LastActiveText = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
            Started = $started
            SessionId = [string]$meta.id
            Preview = $firstUserMessage
            Cwd = [string]$meta.cwd
            Provider = [string]$meta.model_provider
            File = $file.FullName
        }
    }

    return @($rows | Sort-Object LastActive -Descending)
}

function Test-CodexSessionPreviewText {
    param([string]$Text)

    if (-not $Text) {
        return $false
    }

    $trimmed = $Text.Trim()
    if (-not $trimmed) {
        return $false
    }

    if ($trimmed.StartsWith("# AGENTS.md instructions")) {
        return $false
    }
    if ($trimmed.StartsWith("<environment_context>")) {
        return $false
    }
    if ($trimmed.StartsWith("<INSTRUCTIONS>")) {
        return $false
    }

    return $true
}

function Select-CodexResumeSessionWithUi {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="选择历史会话"
        Width="980"
        Height="620"
        MinWidth="860"
        MinHeight="520"
        WindowStartupLocation="CenterOwner"
        Background="#F4F6F8"
        FontFamily="Segoe UI">
    <Grid Margin="22">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,14">
            <TextBlock Text="选择要恢复的历史会话" FontSize="22" FontWeight="SemiBold" Foreground="#1E293B"/>
            <TextBlock Text="列表来自本机 .codex\sessions，选择后会用当前模型服务配置恢复会话。"
                       Margin="0,6,0,0"
                       Foreground="#64748B"
                       FontSize="13"
                       TextWrapping="Wrap"/>
        </StackPanel>

        <DataGrid x:Name="SessionGrid"
                  Grid.Row="1"
                  AutoGenerateColumns="False"
                  CanUserAddRows="False"
                  CanUserDeleteRows="False"
                  IsReadOnly="True"
                  SelectionMode="Single"
                  SelectionUnit="FullRow"
                  GridLinesVisibility="Horizontal"
                  HeadersVisibility="Column"
                  Background="White"
                  BorderBrush="#CBD5E1"
                  BorderThickness="1"
                  RowHeight="34"
                  FontSize="13">
            <DataGrid.Columns>
                <DataGridTextColumn Header="最后活动" Binding="{Binding LastActiveText}" Width="135"/>
                <DataGridTextColumn Header="首条消息" Binding="{Binding Preview}" Width="*"/>
                <DataGridTextColumn Header="目录" Binding="{Binding Cwd}" Width="230"/>
                <DataGridTextColumn Header="原模型服务" Binding="{Binding Provider}" Width="105"/>
                <DataGridTextColumn Header="Session ID" Binding="{Binding SessionId}" Width="230"/>
            </DataGrid.Columns>
        </DataGrid>

        <Border x:Name="LoadingPanel"
                Grid.Row="1"
                Background="#EFFFFFFF"
                BorderBrush="#CBD5E1"
                BorderThickness="1"
                Padding="28">
            <StackPanel VerticalAlignment="Center" HorizontalAlignment="Center" Width="360">
                <TextBlock Text="正在加载历史会话..." FontSize="16" FontWeight="SemiBold" Foreground="#1E293B" HorizontalAlignment="Center"/>
                <ProgressBar IsIndeterminate="True" Height="14" Margin="0,18,0,0"/>
                <TextBlock x:Name="LoadingText"
                           Text="正在读取本机 .codex\sessions"
                           Margin="0,12,0,0"
                           Foreground="#64748B"
                           TextAlignment="Center"
                           TextWrapping="Wrap"/>
            </StackPanel>
        </Border>

        <StackPanel Grid.Row="2"
                    Orientation="Horizontal"
                    HorizontalAlignment="Right"
                    Margin="0,16,0,0">
            <Button x:Name="CancelButton"
                    Content="取消"
                    Width="92"
                    Height="36"
                    Margin="0,0,10,0"
                    Background="#FFFFFF"
                    BorderBrush="#CBD5E1"
                    Foreground="#334155"/>
            <Button x:Name="OpenButton"
                    Content="恢复选中会话"
                    Width="132"
                    Height="36"
                    Background="#2563EB"
                    BorderBrush="#2563EB"
                    Foreground="#FFFFFF"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $grid = $window.FindName("SessionGrid")
    $open = $window.FindName("OpenButton")
    $cancel = $window.FindName("CancelButton")
    $loadingPanel = $window.FindName("LoadingPanel")
    $loadingText = $window.FindName("LoadingText")

    $open.IsEnabled = $false

    $open.Add_Click({
        if ($grid.SelectedItem) {
            $script:SelectedCodexResumeSession = $grid.SelectedItem
            $window.DialogResult = $true
            $window.Close()
        }
    })
    $grid.Add_MouseDoubleClick({
        if ($grid.SelectedItem) {
            $script:SelectedCodexResumeSession = $grid.SelectedItem
            $window.DialogResult = $true
            $window.Close()
        }
    })
    $cancel.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })

    $loaderJob = $null
    $loaderTimer = New-Object System.Windows.Threading.DispatcherTimer
    $loaderTimer.Interval = [TimeSpan]::FromMilliseconds(250)
    $loaderTimer.Add_Tick({
        if (-not $script:CodexResumeLoaderJob) {
            return
        }
        if ($script:CodexResumeLoaderJob.State -eq "Running" -or $script:CodexResumeLoaderJob.State -eq "NotStarted") {
            return
        }

        $loaderTimer.Stop()
        try {
            $sessions = @(Receive-Job -Job $script:CodexResumeLoaderJob -ErrorAction Stop)
        } catch {
            $loadingText.Text = "加载失败：$($_.Exception.Message)"
            return
        } finally {
            Remove-Job -Job $script:CodexResumeLoaderJob -Force -ErrorAction SilentlyContinue
            $script:CodexResumeLoaderJob = $null
        }

        if ($sessions.Count -eq 0) {
            $loadingText.Text = "没有找到可恢复的 Codex 历史会话。"
            return
        }

        $grid.ItemsSource = $sessions
        $grid.SelectedIndex = 0
        $loadingPanel.Visibility = "Collapsed"
        $open.IsEnabled = $true
    })
    $window.Add_ContentRendered({
        if (-not $script:CodexResumeLoaderJob) {
            $script:CodexResumeLoaderJob = Start-Job -ScriptBlock {
                function Test-PreviewText {
                    param([string]$Text)
                    if (-not $Text) { return $false }
                    $trimmed = $Text.Trim()
                    if (-not $trimmed) { return $false }
                    if ($trimmed.StartsWith("# AGENTS.md instructions")) { return $false }
                    if ($trimmed.StartsWith("<environment_context>")) { return $false }
                    if ($trimmed.StartsWith("<INSTRUCTIONS>")) { return $false }
                    return $true
                }

                $sessionRoot = Join-Path $env:USERPROFILE ".codex\sessions"
                if (-not (Test-Path -LiteralPath $sessionRoot)) { return @() }

                $rows = @()
                $files = Get-ChildItem -LiteralPath $sessionRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -gt 0 -and $_.Extension -eq ".jsonl" } |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 200

                foreach ($file in $files) {
                    $meta = $null
                    $firstUserMessage = ""
                    $lineCount = 0
                    foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction SilentlyContinue) {
                        $lineCount++
                        if ($lineCount -gt 160 -and $meta -and $firstUserMessage) { break }
                        try { $entry = $line | ConvertFrom-Json } catch { continue }

                        if (-not $meta -and $entry.type -eq "session_meta") {
                            $meta = $entry.payload
                        }
                        if ($entry.type -eq "event_msg" -and $entry.payload.type -eq "user_message") {
                            $candidateMessage = ([string]$entry.payload.message).Trim()
                            if (Test-PreviewText -Text $candidateMessage) {
                                $firstUserMessage = $candidateMessage
                                break
                            }
                        }
                        if (-not $firstUserMessage -and $entry.type -eq "response_item" -and $entry.payload.type -eq "message" -and $entry.payload.role -eq "user") {
                            $content = @($entry.payload.content) | Select-Object -First 1
                            if ($content -and $content.text) {
                                $candidateMessage = ([string]$content.text).Trim()
                                if (Test-PreviewText -Text $candidateMessage) {
                                    $firstUserMessage = $candidateMessage
                                }
                            }
                        }
                    }

                    if (-not $meta -or -not $meta.id) {
                        if ($file.BaseName -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') {
                            $meta = [pscustomobject]@{ id = $Matches[1]; timestamp = $file.LastWriteTime; cwd = ""; model_provider = "" }
                        } else {
                            continue
                        }
                    }

                    if (-not $firstUserMessage) { $firstUserMessage = "(无用户消息预览)" }
                    if ($firstUserMessage.Length -gt 120) {
                        $firstUserMessage = $firstUserMessage.Substring(0, 120) + "..."
                    }

                    $rows += [pscustomobject]@{
                        LastActive = $file.LastWriteTime
                        LastActiveText = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                        SessionId = [string]$meta.id
                        Preview = $firstUserMessage
                        Cwd = [string]$meta.cwd
                        Provider = [string]$meta.model_provider
                        File = $file.FullName
                    }
                }

                return @($rows | Sort-Object LastActive -Descending)
            }
            $loaderTimer.Start()
        }
    })
    $window.Add_Closed({
        $loaderTimer.Stop()
        if ($script:CodexResumeLoaderJob) {
            Remove-Job -Job $script:CodexResumeLoaderJob -Force -ErrorAction SilentlyContinue
            $script:CodexResumeLoaderJob = $null
        }
    })

    if ($window.ShowDialog() -ne $true) {
        return $null
    }

    return $script:SelectedCodexResumeSession
}

function Get-CodexConnectivityTargets {
    $targets = @()
    foreach ($provider in @(Get-CatalogProviders)) {
        foreach ($key in @($provider.keys)) {
            $apiKey = $null
            $resolveError = ""
            try {
                $apiKey = Resolve-CatalogKey -Provider $provider -Key $key
            } catch {
                $resolveError = $_.Exception.Message
            }

            $targets += [pscustomobject]@{
                ProviderId = [string]$provider.id
                ProviderName = [string]$provider.name
                BaseUrl = [string]$provider.baseUrl
                WireApi = [string]$provider.wireApi
                EnvKey = [string]$provider.envKey
                KeyId = [string]$key.id
                KeyName = [string]$key.name
                KeyPrefix = [string]$key.prefix
                ApiKey = $apiKey
                ResolveError = $resolveError
            }
        }
    }
    return @($targets)
}

function Show-CodexConnectivityUi {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $targets = @(Get-CodexConnectivityTargets)

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="测试连通性"
        Width="980"
        Height="660"
        MinWidth="860"
        MinHeight="540"
        WindowStartupLocation="CenterScreen"
        Background="#F4F6F8"
        FontFamily="Segoe UI">
    <Grid Margin="22">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,14">
            <TextBlock Text="测试连通性" FontSize="22" FontWeight="SemiBold" Foreground="#1E293B"/>
            <ProgressBar x:Name="ProgressBar" IsIndeterminate="True" Height="10" Margin="0,10,0,0"/>
        </StackPanel>

        <DataGrid x:Name="ResultGrid"
                  Grid.Row="1"
                  AutoGenerateColumns="False"
                  CanUserAddRows="False"
                  CanUserDeleteRows="False"
                  IsReadOnly="True"
                  SelectionMode="Single"
                  SelectionUnit="FullRow"
                  GridLinesVisibility="Horizontal"
                  HeadersVisibility="Column"
                  Background="White"
                  BorderBrush="#CBD5E1"
                  BorderThickness="1"
                  RowHeight="34"
                  FontSize="13">
            <DataGrid.Columns>
                <DataGridTextColumn Header="状态" Binding="{Binding Status}" Width="95"/>
                <DataGridTextColumn Header="模型服务" Binding="{Binding ProviderName}" Width="105"/>
                <DataGridTextColumn Header="KEY" Binding="{Binding KeyLabel}" Width="170"/>
                <DataGridTextColumn Header="模型" Binding="{Binding Model}" Width="105"/>
                <DataGridTextColumn Header="HTTP" Binding="{Binding HttpStatus}" Width="70"/>
                <DataGridTextColumn Header="耗时" Binding="{Binding DurationMs}" Width="70"/>
                <DataGridTextColumn Header="提示" Binding="{Binding Message}" Width="*"/>
                <DataGridTextColumn Header="地址" Binding="{Binding BaseUrl}" Width="220"/>
            </DataGrid.Columns>
        </DataGrid>

        <Grid Grid.Row="2" Margin="0,16,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="SummaryText"
                       Text="正在检测模型服务和 KEY，不显示完整 KEY。"
                       VerticalAlignment="Center"
                       Foreground="#64748B"
                       FontSize="13"
                       TextWrapping="Wrap"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="RetestButton"
                        Content="重新检测"
                        Width="104"
                        Height="36"
                        Margin="0,0,10,0"
                        Background="#FFFFFF"
                        BorderBrush="#CBD5E1"
                        Foreground="#334155"/>
                <Button x:Name="CloseButton"
                        Content="关闭"
                        Width="92"
                        Height="36"
                        Background="#2563EB"
                        BorderBrush="#2563EB"
                        Foreground="#FFFFFF"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    $grid = $window.FindName("ResultGrid")
    $summary = $window.FindName("SummaryText")
    $progress = $window.FindName("ProgressBar")
    $retest = $window.FindName("RetestButton")
    $close = $window.FindName("CloseButton")

    $rows = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($target in $targets) {
        $rows.Add([pscustomobject]@{
            Status = "等待"
            ProviderName = $target.ProviderName
            KeyLabel = "$($target.KeyName) [$($target.KeyPrefix)...]"
            Model = $script:CodexSwitcherSettings.defaultModel
            HttpStatus = ""
            DurationMs = ""
            Message = if ($target.ResolveError) { "KEY 解析失败：$($target.ResolveError)" } else { "等待检测" }
            BaseUrl = $target.BaseUrl
            ProviderId = $target.ProviderId
            KeyId = $target.KeyId
        }) | Out-Null
    }
    $grid.ItemsSource = $rows

    $script:ConnectivityJobs = @{}
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        if (-not $script:ConnectivityJobs -or $script:ConnectivityJobs.Count -eq 0) {
            return
        }

        $completedKeys = @()
        foreach ($entry in @($script:ConnectivityJobs.GetEnumerator())) {
            $job = $entry.Value
            if ($job.State -eq "Running" -or $job.State -eq "NotStarted") {
                continue
            }

            try {
                $result = Receive-Job -Job $job -ErrorAction Stop
            } catch {
                $target = $entry.Key
                $parts = $target -split '\|', 2
                $result = [pscustomobject]@{
                    ProviderId = $parts[0]
                    KeyId = $parts[1]
                    Status = "失败"
                    HttpStatus = ""
                    DurationMs = ""
                    Message = "检测失败：$($_.Exception.Message)"
                }
            }

            foreach ($row in $rows) {
                if ($row.ProviderId -eq $result.ProviderId -and $row.KeyId -eq $result.KeyId) {
                    $row.Status = $result.Status
                    $row.HttpStatus = $result.HttpStatus
                    $row.DurationMs = $result.DurationMs
                    $row.Message = $result.Message
                    break
                }
            }

            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            $completedKeys += $entry.Key
        }

        foreach ($key in $completedKeys) {
            $script:ConnectivityJobs.Remove($key)
        }

        $doneCount = @($rows | Where-Object { $_.Status -ne "检测中" -and $_.Status -ne "等待" }).Count
        $runningCount = $script:ConnectivityJobs.Count
        $okCount = @($rows | Where-Object { $_.Status -eq "可用" }).Count
        $failCount = @($rows | Where-Object { $_.Status -ne "可用" -and $_.Status -ne "检测中" -and $_.Status -ne "等待" }).Count
        $summary.Text = "检测中：已完成 $doneCount 个，剩余 $runningCount 个。"
        $grid.Items.Refresh()

        if ($runningCount -eq 0) {
            $timer.Stop()
            $progress.IsIndeterminate = $false
            $summary.Text = "检测完成：可用 $okCount 个，异常 $failCount 个。"
            $retest.IsEnabled = $true
        }
    })

    function Start-ConnectivityRun {
        if ($script:ConnectivityJobs -and $script:ConnectivityJobs.Count -gt 0) { return }
        $retest.IsEnabled = $false
        $progress.IsIndeterminate = $true
        $summary.Text = "正在并行检测 provider / KEY..."
        foreach ($row in $rows) {
            $row.Status = "检测中"
            $row.HttpStatus = ""
            $row.DurationMs = ""
            $row.Message = "正在请求 Responses API..."
        }
        $grid.Items.Refresh()

        $script:ConnectivityJobs = @{}
        foreach ($target in $targets) {
            $jobTarget = [pscustomobject]@{
                ProviderId = $target.ProviderId
                ProviderName = $target.ProviderName
                BaseUrl = $target.BaseUrl
                KeyId = $target.KeyId
                KeyName = $target.KeyName
                KeyPrefix = $target.KeyPrefix
                ApiKey = $target.ApiKey
                ResolveError = $target.ResolveError
                Model = $script:CodexSwitcherSettings.defaultModel
            }
            $jobKey = "$($jobTarget.ProviderId)|$($jobTarget.KeyId)"

            $script:ConnectivityJobs[$jobKey] = Start-Job -ArgumentList $jobTarget -ScriptBlock {
            param($target)

            function New-Result {
                param($Target, [string]$Status, [string]$HttpStatus, [string]$DurationMs, [string]$Message)
                [pscustomobject]@{
                    ProviderId = $Target.ProviderId
                    KeyId = $Target.KeyId
                    Status = $Status
                    HttpStatus = $HttpStatus
                    DurationMs = $DurationMs
                    Message = $Message
                }
            }

                if (-not $target.ApiKey) {
                    New-Result -Target $target -Status "失败" -HttpStatus "" -DurationMs "" -Message $(if ($target.ResolveError) { "KEY 解析失败：$($target.ResolveError)" } else { "KEY 为空或不可解析" })
                    return
                }
                if (-not $target.BaseUrl) {
                    New-Result -Target $target -Status "失败" -HttpStatus "" -DurationMs "" -Message "base_url 为空"
                    return
                }

                $baseUrl = ([string]$target.BaseUrl).TrimEnd("/")
                $url = "$baseUrl/responses"
                $headers = @{
                    Authorization = "Bearer $($target.ApiKey)"
                    "Content-Type" = "application/json"
                }
                $body = @{
                    model = [string]$target.Model
                    input = "ping"
                    max_output_tokens = 8
                } | ConvertTo-Json -Depth 5

                $sw = [Diagnostics.Stopwatch]::StartNew()
                try {
                    $response = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -TimeoutSec 20 -UseBasicParsing
                    $sw.Stop()
                    New-Result -Target $target -Status "可用" -HttpStatus ([string][int]$response.StatusCode) -DurationMs ([string]$sw.ElapsedMilliseconds) -Message "Responses API 可用"
                } catch {
                    $sw.Stop()
                    $statusCode = ""
                    $retryAfter = ""
                    $message = $_.Exception.Message
                    if ($_.Exception.Response) {
                        try { $statusCode = [string][int]$_.Exception.Response.StatusCode } catch {}
                        try { $retryAfter = [string]$_.Exception.Response.Headers["Retry-After"] } catch {}
                    }

                    $status = "失败"
                    if ($statusCode -eq "401" -or $statusCode -eq "403") { $status = "鉴权失败" }
                    elseif ($statusCode -eq "404") { $status = "接口不通" }
                    elseif ($statusCode -eq "429") { $status = "限流" }
                    elseif ($statusCode -ge "500") { $status = "服务异常" }

                    if ($retryAfter) { $message = "$message; retry-after=$retryAfter" }
                    if ($message.Length -gt 220) { $message = $message.Substring(0, 220) + "..." }
                    New-Result -Target $target -Status $status -HttpStatus $statusCode -DurationMs ([string]$sw.ElapsedMilliseconds) -Message $message
                }
            }
        }
        $timer.Start()
    }

    $retest.Add_Click({ Start-ConnectivityRun })
    $close.Add_Click({ $window.Close() })
    $window.Add_ContentRendered({ Start-ConnectivityRun })
    $window.Add_Closed({
        $timer.Stop()
        if ($script:ConnectivityJobs) {
            foreach ($job in $script:ConnectivityJobs.Values) {
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            }
            $script:ConnectivityJobs = @{}
        }
    })

    [void]$window.ShowDialog()
}

function Show-CodexAboutDialog {
    param($Owner)

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $switcherVersionForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Version)
    $launcherProductForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Product)
    $launcherAuthorsForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Authors)

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="关于 $launcherProductForXaml"
        Width="520"
        Height="430"
        MinWidth="480"
        MinHeight="380"
        ResizeMode="CanResize"
        WindowStartupLocation="CenterOwner"
        Background="#F8FAFC"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#1E293B"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Height" Value="34"/>
            <Setter Property="MinWidth" Value="86"/>
            <Setter Property="Padding" Value="14,0"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
    </Window.Resources>
    <Grid Margin="22">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,18">
            <TextBlock Text="$launcherProductForXaml" FontSize="24" FontWeight="SemiBold"/>
            <TextBlock Text="版本：$switcherVersionForXaml"
                       Margin="0,8,0,0"
                       Foreground="#475569"
                       FontSize="13"/>
            <TextBlock Text="作者：$launcherAuthorsForXaml"
                       Margin="0,4,0,0"
                       Foreground="#475569"
                       FontSize="13"/>
        </StackPanel>

        <StackPanel Grid.Row="1">
            <TextBlock Text="软件说明"
                       FontSize="15"
                       FontWeight="SemiBold"
                       Margin="0,0,0,8"/>
            <TextBlock Text="这是一个面向 Windows 用户的第三方 Codex 启动入口，把安装环境、模型服务配置、KEY 选择、模型选择、权限模式和历史会话恢复收在一个干净的面板里。它的目标是让普通用户少碰命令行，同时保留进阶用户需要的可控启动参数。"
                       Foreground="#475569"
                       FontSize="13"
                       LineHeight="20"
                       TextWrapping="Wrap"/>
            <TextBlock Text="本项目是第三方社区工具，不是 OpenAI 官方项目，也未获得 OpenAI 赞助、背书或关联授权。OpenAI、Codex、GPT 等名称属于其各自权利人；本项目仅在说明兼容对象和依赖关系时使用这些名称。"
                       Margin="0,10,0,0"
                       Foreground="#64748B"
                       FontSize="12"
                       LineHeight="18"
                       TextWrapping="Wrap"/>

            <Border Height="1" Background="#E2E8F0" Margin="0,18,0,14"/>

            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                <TextBlock x:Name="AboutLicenseLink"
                           Text="MIT 协议"
                           Foreground="#2563EB"
                           FontSize="13"
                           TextDecorations="Underline"
                           Cursor="Hand"
                           ToolTip="打开内置 MIT 协议"/>
                <TextBlock Text="   " FontSize="13"/>
                <StackPanel x:Name="AboutGithubLogo"
                            Orientation="Horizontal"
                            VerticalAlignment="Center"
                            Cursor="Hand"
                            ToolTip="打开 GitHub 仓库">
                    <Viewbox Width="14" Height="14" Stretch="Uniform" VerticalAlignment="Center">
                        <Canvas Width="16" Height="16">
                            <Path Fill="#475569"
                                  Data="M8,0 C3.58,0 0,3.58 0,8 C0,11.54 2.29,14.53 5.47,15.59 C5.87,15.66 6.02,15.42 6.02,15.21 C6.02,15.02 6.01,14.39 6.01,13.72 C4,14.09 3.48,13.23 3.32,12.78 C3.23,12.55 2.84,11.84 2.5,11.65 C2.22,11.5 1.82,11.13 2.49,11.12 C3.12,11.11 3.57,11.7 3.72,11.94 C4.44,13.15 5.59,12.81 6.05,12.6 C6.12,12.08 6.33,11.73 6.56,11.53 C4.78,11.33 2.92,10.64 2.92,7.58 C2.92,6.71 3.23,5.99 3.74,5.43 C3.66,5.23 3.38,4.41 3.82,3.31 C3.82,3.31 4.49,3.1 6.02,4.13 C6.66,3.95 7.34,3.86 8.02,3.86 C8.7,3.86 9.38,3.95 10.02,4.13 C11.55,3.09 12.22,3.31 12.22,3.31 C12.66,4.41 12.38,5.23 12.3,5.43 C12.81,5.99 13.12,6.7 13.12,7.58 C13.12,10.65 11.25,11.33 9.47,11.53 C9.76,11.78 10.01,12.26 10.01,13.01 C10.01,14.08 10,14.94 10,15.21 C10,15.42 10.15,15.67 10.55,15.59 C13.71,14.53 16,11.54 16,8 C16,3.58 12.42,0 8,0 Z"/>
                        </Canvas>
                    </Viewbox>
                    <TextBlock Text="GitHub" Margin="5,0,0,0" Foreground="#2563EB" FontSize="13" TextDecorations="Underline" VerticalAlignment="Center"/>
                </StackPanel>
                <TextBlock Text="   " FontSize="13"/>
                <StackPanel x:Name="AboutGiteeLogo"
                            Orientation="Horizontal"
                            VerticalAlignment="Center"
                            Cursor="Hand"
                            ToolTip="打开 Gitee 仓库">
                    <Viewbox Width="13" Height="13" Stretch="Uniform" VerticalAlignment="Center">
                        <Canvas Width="16" Height="16">
                            <Ellipse Width="11.5" Height="11.5" Canvas.Left="2.25" Canvas.Top="2.25" Stroke="#64748B" StrokeThickness="1.45"/>
                            <Path Stroke="#64748B" StrokeThickness="1.45" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M8.2,8 L12.8,8 L12.8,11.2"/>
                        </Canvas>
                    </Viewbox>
                    <TextBlock Text="Gitee" Margin="5,0,0,0" Foreground="#2563EB" FontSize="13" TextDecorations="Underline" VerticalAlignment="Center"/>
                </StackPanel>
            </StackPanel>
        </StackPanel>

        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
            <Button x:Name="AboutCloseButton"
                    Content="关闭"
                    Background="#2563EB"
                    BorderBrush="#2563EB"
                    Foreground="#FFFFFF"/>
        </StackPanel>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) {
        $window.Owner = $Owner
    }

    Register-CodexLauncherLinks -Window $window -LicenseLinkName "AboutLicenseLink" -GithubLogoName "AboutGithubLogo" -GiteeLogoName "AboutGiteeLogo"
    $close = $window.FindName("AboutCloseButton")
    $close.Add_Click({ $window.Close() })

    [void]$window.ShowDialog()
}

function Select-CodexProviderWithUi {
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase

    $script:SwitcherProviders = @(Get-CatalogProviders)
    $switcherVersionForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Version)
    $launcherProductForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Product)
    $launcherAuthorsForXaml = [System.Security.SecurityElement]::Escape([string]$script:CodexSwitcherBuild.Authors)

    if ($script:SwitcherProviders.Count -eq 0) {
        throw "No Codex providers found in $script:CodexCatalogPath"
    }

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$launcherProductForXaml"
        Width="860"
        Height="650"
        MinWidth="820"
        MinHeight="600"
        ResizeMode="CanResize"
        WindowStartupLocation="CenterScreen"
        Background="#F4F6F8"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TextBlock">
            <Setter Property="Foreground" Value="#1E293B"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Height" Value="36"/>
            <Setter Property="Padding" Value="10,4"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="Background" Value="White"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Height" Value="36"/>
            <Setter Property="MinWidth" Value="92"/>
            <Setter Property="Padding" Value="16,0"/>
            <Setter Property="FontSize" Value="14"/>
        </Style>
    </Window.Resources>
    <Grid Margin="22">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Grid Grid.Row="0" Margin="0,0,0,14">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <StackPanel>
                <TextBlock Text="Codex 便捷启动器" FontSize="26" FontWeight="SemiBold"/>
                <TextBlock Text="选择服务、KEY、模型和权限后打开 Codex。"
                           Margin="0,6,0,0"
                           Foreground="#64748B"
                           TextWrapping="Wrap"
                           FontSize="13"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
                <Button x:Name="AboutButton"
                        Content="关于"
                        Background="#FFFFFF"
                        BorderBrush="#CBD5E1"
                        Foreground="#334155"
                        Margin="0,0,10,0"/>
                <Button x:Name="InstallButton"
                        Content="安装"
                        Background="#FFFFFF"
                        BorderBrush="#CBD5E1"
                        Foreground="#334155"
                        Margin="0,0,10,0"/>
                <Button x:Name="ManageButton"
                        Content="配置"
                        Background="#FFFFFF"
                        BorderBrush="#CBD5E1"
                        Foreground="#334155"/>
            </StackPanel>
        </Grid>

        <Border Grid.Row="1"
                Background="White"
                BorderBrush="#E2E8F0"
                BorderThickness="1"
                CornerRadius="8"
                Padding="22">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="22"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Row="0" Grid.ColumnSpan="3" Margin="0,0,0,12">
                    <TextBlock Text="模型服务提供方" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                    <ComboBox x:Name="ProviderCombo" Margin="0,7,0,0"/>
                </StackPanel>

                <StackPanel Grid.Row="1" Grid.ColumnSpan="3" Margin="0,0,0,12">
                    <TextBlock Text="KEY / 令牌" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                    <ComboBox x:Name="KeyCombo" Margin="0,7,0,0"/>
                </StackPanel>

                <StackPanel Grid.Row="2" Grid.Column="0" Margin="0,0,0,12">
                    <TextBlock Text="模型版本" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                    <ComboBox x:Name="ModelCombo" Margin="0,7,0,0"/>
                </StackPanel>

                <StackPanel Grid.Row="2" Grid.Column="2" Margin="0,0,0,12">
                    <TextBlock Text="推理模式" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                    <ComboBox x:Name="EffortCombo" Margin="0,7,0,0"/>
                </StackPanel>

                <StackPanel Grid.Row="3" Grid.ColumnSpan="3" Margin="0,0,0,12">
                    <TextBlock Text="权限模式" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                    <ComboBox x:Name="PermissionModeCombo" Margin="0,7,0,0"/>
                    <TextBlock x:Name="PermissionModeHelpText"
                               Margin="0,6,0,0"
                               Foreground="#64748B"
                               FontSize="12"
                               TextWrapping="Wrap"/>
                </StackPanel>

                <TextBlock x:Name="StatusText"
                           Grid.Row="4"
                           Grid.ColumnSpan="3"
                           Foreground="#64748B"
                           TextWrapping="Wrap"/>
            </Grid>
        </Border>

        <Grid Grid.Row="2" Margin="0,14,0,0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>
            <Button x:Name="ConnectivityButton"
                    Content="测试连通性"
                    Grid.Column="0"
                    Background="#FFFFFF"
                    BorderBrush="#CBD5E1"
                    Foreground="#334155"/>
            <StackPanel Grid.Column="2" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button x:Name="CancelButton"
                    Content="取消"
                    Background="#FFFFFF"
                    BorderBrush="#CBD5E1"
                    Foreground="#334155"
                    Margin="0,0,10,0"/>
            <Button x:Name="ResumeButton"
                    Content="历史会话"
                    Background="#FFFFFF"
                    BorderBrush="#2563EB"
                    Foreground="#1D4ED8"
                    MinWidth="104"
                    Margin="0,0,10,0"/>
            <Button x:Name="OkButton"
                    Content="启动 Codex"
                    Background="#2563EB"
                    BorderBrush="#2563EB"
                    Foreground="#FFFFFF"/>
            </StackPanel>
        </Grid>
    </Grid>
</Window>
"@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $providerCombo = $window.FindName("ProviderCombo")
    $keyCombo = $window.FindName("KeyCombo")
    $modelCombo = $window.FindName("ModelCombo")
    $effortCombo = $window.FindName("EffortCombo")
    $permissionModeCombo = $window.FindName("PermissionModeCombo")
    $permissionModeHelpText = $window.FindName("PermissionModeHelpText")
    $statusText = $window.FindName("StatusText")
    $ok = $window.FindName("OkButton")
    $resume = $window.FindName("ResumeButton")
    $cancel = $window.FindName("CancelButton")
    $about = $window.FindName("AboutButton")
    $manage = $window.FindName("ManageButton")
    $install = $window.FindName("InstallButton")
    $connectivity = $window.FindName("ConnectivityButton")
    $currentSelection = Get-PersistedCodexSelection

    foreach ($item in @($script:CodexSwitcherSettings.models)) {
        [void]$modelCombo.Items.Add($item)
    }
    foreach ($item in @($script:CodexSwitcherSettings.reasoningEfforts)) {
        [void]$effortCombo.Items.Add($item)
    }
    [void]$permissionModeCombo.Items.Add("安全模式")
    [void]$permissionModeCombo.Items.Add("全权限模式 (YOLO)")

    $preferredModel = $script:CodexSwitcherSettings.defaultModel
    if ($modelCombo.Items.Contains($preferredModel)) {
        $modelCombo.SelectedItem = $preferredModel
    } else {
        $modelCombo.SelectedItem = $script:CodexSwitcherSettings.defaultModel
    }

    $preferredReasoningEffort = $script:CodexSwitcherSettings.defaultReasoningEffort
    if ($effortCombo.Items.Contains($preferredReasoningEffort)) {
        $effortCombo.SelectedItem = $preferredReasoningEffort
    } else {
        $effortCombo.SelectedItem = $script:CodexSwitcherSettings.defaultReasoningEffort
    }

    $preferredPermissionMode = $script:DefaultCodexSwitcherPermissionMode
    if ($currentSelection -and $currentSelection.PermissionMode) {
        $preferredPermissionMode = Normalize-CodexPermissionMode $currentSelection.PermissionMode
    }
    $permissionModeCombo.SelectedItem = Get-CodexPermissionModeLabel $preferredPermissionMode

    function Get-SelectedPermissionMode {
        if ([string]$permissionModeCombo.SelectedItem -like "全权限模式*") {
            return "full"
        }
        return "safe"
    }

    function Update-PermissionModeHelp {
        $permissionModeHelpText.Text = Get-CodexPermissionModeDescription (Get-SelectedPermissionMode)
    }

    function Update-DetailText {
        Update-PermissionModeHelp
        if ($providerCombo.SelectedIndex -lt 0) {
            return
        }
    }

    function Refresh-KeySources {
        param([string]$PreferredKeySource)

        $keyCombo.Items.Clear()
        $selectedProvider = $script:SwitcherProviders[$providerCombo.SelectedIndex]
        $orderedSources = @($selectedProvider.keys)
        foreach ($source in $orderedSources) {
            [void]$keyCombo.Items.Add("$($source.name)  [$($source.prefix)...]")
        }
        $script:VisibleKeySources = @($orderedSources)
        if ($keyCombo.Items.Count -gt 0) {
            $selectedKeyIndex = 0
            $targetKeySource = if ($PreferredKeySource) { $PreferredKeySource } else { [string]$selectedProvider.defaultKeySource }
            for ($i = 0; $i -lt $script:VisibleKeySources.Count; $i++) {
                if ($targetKeySource -and ($script:VisibleKeySources[$i].id -eq $targetKeySource -or $script:VisibleKeySources[$i].name -eq $targetKeySource)) {
                    $selectedKeyIndex = $i
                    break
                }
            }
            $keyCombo.SelectedIndex = $selectedKeyIndex
            $ok.IsEnabled = $true
        } else {
            [void]$keyCombo.Items.Add("(未配置KEY)")
            $keyCombo.SelectedIndex = 0
            $ok.IsEnabled = $false
        }
        Update-DetailText
    }

    function Refresh-ProviderList {
        param([string]$PreferredProvider, [string]$PreferredKeySource)

        $providerCombo.Items.Clear()
        foreach ($p in $script:SwitcherProviders) {
            [void]$providerCombo.Items.Add("$($p.name)  |  $($p.baseUrl)")
        }

        if ($providerCombo.Items.Count -eq 0) {
            $ok.IsEnabled = $false
            return
        }

        $targetProvider = if ($PreferredProvider) { $PreferredProvider } else { Get-DefaultCodexCatalogProviderId }
        $selectedProviderIndex = 0
        for ($i = 0; $i -lt $script:SwitcherProviders.Count; $i++) {
            if ($targetProvider -and ($script:SwitcherProviders[$i].id -eq $targetProvider -or $script:SwitcherProviders[$i].name -eq $targetProvider)) {
                $selectedProviderIndex = $i
                break
            }
        }
        $providerCombo.SelectedIndex = $selectedProviderIndex
        Refresh-KeySources -PreferredKeySource $PreferredKeySource
    }

    $providerCombo.Add_SelectionChanged({ Refresh-KeySources -PreferredKeySource $null })
    $keyCombo.Add_SelectionChanged({ Update-DetailText })
    $modelCombo.Add_SelectionChanged({ Update-DetailText })
    $effortCombo.Add_SelectionChanged({ Update-DetailText })
    $permissionModeCombo.Add_SelectionChanged({ Update-DetailText })
    Update-PermissionModeHelp
    $about.Add_Click({ Show-CodexAboutDialog -Owner $window })
    $install.Add_Click({
        Show-CodexInstallerUi
        $statusText.Text = "安装状态已返回。可点击「安装」重新检测，或继续配置模型服务和 KEY。"
    })
    $connectivity.Add_Click({
        Show-CodexConnectivityUi
    })
    $manage.Add_Click({
        $selectedProviderId = if ($providerCombo.SelectedIndex -ge 0) { $script:SwitcherProviders[$providerCombo.SelectedIndex].id } else { $null }
        & (Join-Path $script:CodexSwitcherScriptDir "manage-codex-providers.ps1")
        $script:SwitcherProviders = @(Get-CatalogProviders)
        $script:CodexSwitcherSettings = Get-CodexSwitcherSettings
        $selectedModel = [string]$modelCombo.SelectedItem
        $modelCombo.Items.Clear()
        foreach ($item in @($script:CodexSwitcherSettings.models)) {
            [void]$modelCombo.Items.Add($item)
        }
        if ($selectedModel -and $modelCombo.Items.Contains($selectedModel)) {
            $modelCombo.SelectedItem = $selectedModel
        } else {
            $modelCombo.SelectedItem = $script:CodexSwitcherSettings.defaultModel
        }

        $selectedReasoningEffort = [string]$effortCombo.SelectedItem
        $effortCombo.Items.Clear()
        foreach ($item in @($script:CodexSwitcherSettings.reasoningEfforts)) {
            [void]$effortCombo.Items.Add($item)
        }
        if ($selectedReasoningEffort -and $effortCombo.Items.Contains($selectedReasoningEffort)) {
            $effortCombo.SelectedItem = $selectedReasoningEffort
        } else {
            $effortCombo.SelectedItem = $script:CodexSwitcherSettings.defaultReasoningEffort
        }

        Refresh-ProviderList -PreferredProvider $selectedProviderId -PreferredKeySource $null
        $statusText.Text = "配置内容已刷新。"
    })

    $ok.Add_Click({
        if ($providerCombo.SelectedIndex -lt 0 -or $keyCombo.SelectedIndex -lt 0 -or $script:VisibleKeySources.Count -eq 0) {
            return
        }

        $script:SelectedCodexProvider = [pscustomobject]@{
            Provider = $script:SwitcherProviders[$providerCombo.SelectedIndex].id
            KeySource = $script:VisibleKeySources[$keyCombo.SelectedIndex].id
            Model = [string]$modelCombo.SelectedItem
            ReasoningEffort = [string]$effortCombo.SelectedItem
            PermissionMode = Get-SelectedPermissionMode
            ResumeHistory = $false
            ResumeSessionId = ""
            ResumeSessionCwd = ""
        }
        $window.DialogResult = $true
        $window.Close()
    })
    $resume.Add_Click({
        if ($providerCombo.SelectedIndex -lt 0 -or $keyCombo.SelectedIndex -lt 0 -or $script:VisibleKeySources.Count -eq 0) {
            return
        }

        $resumeSession = Select-CodexResumeSessionWithUi
        if (-not $resumeSession) {
            return
        }

        $script:SelectedCodexProvider = [pscustomobject]@{
            Provider = $script:SwitcherProviders[$providerCombo.SelectedIndex].id
            KeySource = $script:VisibleKeySources[$keyCombo.SelectedIndex].id
            Model = [string]$modelCombo.SelectedItem
            ReasoningEffort = [string]$effortCombo.SelectedItem
            PermissionMode = Get-SelectedPermissionMode
            ResumeHistory = $true
            ResumeSessionId = [string]$resumeSession.SessionId
            ResumeSessionCwd = [string]$resumeSession.Cwd
        }
        $window.DialogResult = $true
        $window.Close()
    })
    $cancel.Add_Click({
        $window.DialogResult = $false
        $window.Close()
    })

    $initialProvider = Get-DefaultCodexCatalogProviderId
    Refresh-ProviderList -PreferredProvider $initialProvider -PreferredKeySource $null

    if ($window.ShowDialog() -ne $true) {
        return $null
    }

    return $script:SelectedCodexProvider
}

function Start-CodexTerminal {
    param(
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$KeySource,
        [string]$Model,
        [string]$ReasoningEffort,
        [string]$PermissionMode = $script:DefaultCodexSwitcherPermissionMode,
        [switch]$ResumeHistory,
        [string]$ResumeSessionId,
        [string]$ResumeSessionCwd,
        [switch]$PrintCodexArgs,
        [string[]]$Config = @(),
        [string[]]$CodexArgs = @()
    )

    $shellPath = Get-CodexCommandPath -Names @("pwsh.exe", "pwsh", "powershell.exe", "powershell")
    if (-not $shellPath) {
        throw "未找到 PowerShell，无法打开 Codex。"
    }

    $scriptArgs = @(
        "-NoExit",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $script:CodexSwitcherScriptPath,
        "-NoUi",
        "-InTerminal",
        "-Provider", $Provider,
        "-KeySource", $KeySource
    )
    if ($Model) {
        $scriptArgs += @("-m", $Model)
    }
    if ($ReasoningEffort) {
        $scriptArgs += @("-ReasoningEffort", $ReasoningEffort)
    }
    if ($PermissionMode) {
        $scriptArgs += @("-PermissionMode", (Normalize-CodexPermissionMode $PermissionMode))
    }
    if ($ResumeHistory) {
        $scriptArgs += "-ResumeHistory"
    }
    if ($ResumeSessionId) {
        $scriptArgs += @("-ResumeSessionId", $ResumeSessionId)
    }
    if ($ResumeSessionCwd) {
        $scriptArgs += @("-ResumeSessionCwd", $ResumeSessionCwd)
    }
    if ($PrintCodexArgs) {
        $scriptArgs += "-PrintCodexArgs"
    }
    foreach ($entry in $Config) {
        $scriptArgs += @("-c", (Normalize-CodexConfigEntry -Value $entry))
    }
    $scriptArgs += $CodexArgs

    $wtPath = Get-CodexCommandPath -Names @("wt.exe", "wt")
    if (-not $wtPath) {
        Start-CodexProcess -FilePath $shellPath -Arguments $scriptArgs
        return
    }

    $terminalTitle = "$($script:CodexSwitcherBuild.Product) $($script:CodexSwitcherBuild.Version) | $($script:CodexSwitcherBuild.Authors)"
    $terminalArgs = @(
        "-w", "Codex",
        "new-tab",
        "--title", $terminalTitle,
        $shellPath
    )
    $terminalArgs += $scriptArgs

    & $wtPath @terminalArgs
}

if ($ListResumeSessions) {
    Get-CodexResumeSessions | Select-Object -First 50 LastActiveText, SessionId, Provider, Cwd, Preview
    return
}

if ($ListConnectivityTargets) {
    Get-CodexConnectivityTargets | Select-Object ProviderId, ProviderName, BaseUrl, KeyId, KeyName, KeyPrefix, ResolveError
    return
}

if ($NoUi) {
    if ($Provider -and -not $KeySource) {
        $providerRow = Get-CatalogProviderById -ProviderName $Provider
        if (-not $providerRow) {
            throw "Unknown provider: $Provider"
        }
        $KeySource = Get-DefaultKeySourceForProvider -Provider $providerRow
    }

    if (-not $Provider -or -not $KeySource) {
        $selection = Get-PersistedCodexSelection
        if (-not $selection) {
            $selection = Get-CurrentCodexSelection
        }
        if (-not $selection) {
            $defaultProviderId = Get-DefaultCodexCatalogProviderId
            if ($defaultProviderId) {
                $defaultProvider = Get-CatalogProviderById -ProviderName $defaultProviderId
                $selection = [pscustomobject]@{
                    Provider = $defaultProvider.id
                    KeySource = Get-DefaultKeySourceForProvider -Provider $defaultProvider
                    Model = $script:CodexSwitcherSettings.defaultModel
                    ReasoningEffort = $script:CodexSwitcherSettings.defaultReasoningEffort
                    PermissionMode = $script:DefaultCodexSwitcherPermissionMode
                }
            }
        }
        if (-not $selection) {
            throw "No current AI service selection is available. Run the launcher once without -NoUi."
        }
        if (-not $Provider) { $Provider = $selection.Provider }
        if (-not $KeySource) { $KeySource = $selection.KeySource }
        if (-not $Model) { $Model = $selection.Model }
        if (-not $ReasoningEffort) { $ReasoningEffort = $selection.ReasoningEffort }
        if (-not $PermissionMode) { $PermissionMode = $selection.PermissionMode }
    }
} elseif (-not $Provider -or -not $KeySource) {
    $selection = Select-CodexProviderWithUi
    if (-not $selection) {
        return
    }
    $Provider = $selection.Provider
    $KeySource = $selection.KeySource
    if (-not $Model) { $Model = $selection.Model }
    if (-not $ReasoningEffort) { $ReasoningEffort = $selection.ReasoningEffort }
    if (-not $PermissionMode) { $PermissionMode = $selection.PermissionMode }
    if ($selection.PSObject.Properties.Name -contains "ResumeHistory" -and $selection.ResumeHistory) {
        $ResumeHistory = $true
    }
    if ($selection.PSObject.Properties.Name -contains "ResumeSessionId" -and $selection.ResumeSessionId) {
        $ResumeSessionId = [string]$selection.ResumeSessionId
    }
    if ($selection.PSObject.Properties.Name -contains "ResumeSessionCwd" -and $selection.ResumeSessionCwd) {
        $ResumeSessionCwd = [string]$selection.ResumeSessionCwd
    }
}

if (-not $Model) { $Model = $script:CodexSwitcherSettings.defaultModel }
if (-not $ReasoningEffort) { $ReasoningEffort = $script:CodexSwitcherSettings.defaultReasoningEffort }
if (-not $PermissionMode) { $PermissionMode = $script:DefaultCodexSwitcherPermissionMode }
$PermissionMode = Normalize-CodexPermissionMode $PermissionMode

$resolved = Set-CodexSelectionEnvironment -ProviderName $Provider -KeySourceId $KeySource -Model $Model -ReasoningEffort $ReasoningEffort -PermissionMode $PermissionMode -Persist

Write-Host "Codex provider: $($resolved.Provider) <$($resolved.BaseUrl)>" -ForegroundColor Cyan
Write-Host "Key: $($resolved.EnvKey) prefix $($resolved.KeyPrefix)..." -ForegroundColor DarkGray
Write-Host "Model: $Model, reasoning: $ReasoningEffort" -ForegroundColor DarkGray
Write-Host "Permission mode: $(Get-CodexPermissionModeLabel $PermissionMode)" -ForegroundColor DarkGray
Write-Host "Launcher: $($script:CodexSwitcherBuild.Version), authors: $($script:CodexSwitcherBuild.Authors)" -ForegroundColor DarkGray
if ($ResumeHistory) {
    Write-Host "Mode: resume history" -ForegroundColor DarkGray
    if ($ResumeSessionId) {
        Write-Host "Session: $ResumeSessionId" -ForegroundColor DarkGray
    }
    if ($ResumeSessionCwd) {
        Write-Host "Session cwd: $ResumeSessionCwd" -ForegroundColor DarkGray
    }
}

if (-not $InTerminal) {
    Start-CodexTerminal -Provider $resolved.Provider -KeySource $resolved.KeySource -Model $Model -ReasoningEffort $ReasoningEffort -PermissionMode $PermissionMode -ResumeHistory:$ResumeHistory -ResumeSessionId $ResumeSessionId -ResumeSessionCwd $ResumeSessionCwd -PrintCodexArgs:$PrintCodexArgs -Config $Config -CodexArgs $CodexArgs
    return
}

$providerArgs = @()
$resumeProviderOverrideArgs = @()
if ($resolved.ProfileName) {
    $providerArgs += @("--profile", $resolved.ProfileName)
    $resumeProviderOverrideArgs += @("--profile", $resolved.ProfileName)
    $resumeProviderOverrideArgs += @("-c", "model_provider=`"$($resolved.Provider)`"")
} else {
    $providerArgs += $resolved.ConfigArgs
    $resumeProviderOverrideArgs += $resolved.ConfigArgs
}
$providerArgs += Get-CodexPermissionModeArgs $PermissionMode

$forwardedArgs = @()
if ($ResumeHistory) {
    $forwardedArgs += $providerArgs
    $forwardedArgs += "resume"
    if ($ResumeSessionId) {
        $forwardedArgs += $ResumeSessionId
    }
    if ($ResumeSessionCwd -and (Test-Path -LiteralPath $ResumeSessionCwd -PathType Container)) {
        $forwardedArgs += @("-C", $ResumeSessionCwd)
    }
    $forwardedArgs += $resumeProviderOverrideArgs
} else {
    $forwardedArgs += $providerArgs
}

if ($Model) {
    $forwardedArgs += @("-m", $Model)
}
$forwardedArgs += @("-c", "model_reasoning_effort=$ReasoningEffort")
foreach ($entry in $Config) {
    $forwardedArgs += @("-c", (Normalize-CodexConfigEntry -Value $entry))
}
$forwardedArgs += $CodexArgs

if ($PrintCodexArgs) {
    [pscustomobject]@{
        CodexExe = "$env:APPDATA\npm\codex.ps1"
        Args = $forwardedArgs
    } | ConvertTo-Json -Depth 5
    return
}

& "$env:APPDATA\npm\codex.ps1" @forwardedArgs




