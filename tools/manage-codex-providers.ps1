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
        Width="1250"
        Height="1040"
        MinWidth="1100"
        MinHeight="920"
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
                <TextBlock Text="维护服务、KEY、模型和推理深度。KEY 保存在当前目录。"
                           Margin="0,3,0,0"
                           Foreground="#64748B"
                           FontSize="12"
                           TextWrapping="Wrap"/>
                <TextBlock Text="版本：$switcherVersionForXaml    作者：$launcherAuthorsForXaml"
                           Margin="0,3,0,0"
                           Foreground="#94A3B8"
                           FontSize="11"/>
                <TextBlock Text="MIT 协议 · GitHub · Gitee"
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
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="模型服务提供方" FontSize="14" FontWeight="SemiBold" Margin="0,0,0,6"/>
                            <ListBox x:Name="ProviderList" Grid.Row="1" MinHeight="260"/>
                            <StackPanel Grid.Row="2" Margin="0,8,0,0">
                                <UniformGrid Columns="2">
                                    <Button x:Name="ProviderTopButton"
                                            Content="置顶"
                                            Background="#FFFFFF"
                                            BorderBrush="#CBD5E1"
                                            Foreground="#334155"
                                            Margin="0,0,4,6"/>
                                    <Button x:Name="ProviderBottomButton"
                                            Content="置底"
                                            Background="#FFFFFF"
                                            BorderBrush="#CBD5E1"
                                            Foreground="#334155"
                                            Margin="4,0,0,6"/>
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

                            <StackPanel Grid.Row="1" Grid.Column="0" Margin="0,0,0,8">
                                <TextBlock Text="模型系列" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                <ListBox x:Name="VendorList"
                                         Height="230"
                                         Margin="0,5,0,0"/>
                            </StackPanel>

                            <StackPanel Grid.Row="1" Grid.Column="2" Margin="0,0,0,8">
                                <TextBlock Text="此通道可用模型" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                <ListBox x:Name="ProviderModelsList"
                                         Height="180"
                                         Margin="0,5,0,0"/>
                            </StackPanel>

                            <StackPanel Grid.Row="2" Grid.ColumnSpan="3" Margin="0,0,0,10">
                                <TextBlock Text="默认模型" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                <ComboBox x:Name="ProviderDefaultModelCombo" Margin="0,5,0,0" Height="30"/>
                            </StackPanel>

                            <StackPanel Grid.Row="3" Grid.ColumnSpan="3" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,0,10">
                                <Button x:Name="SaveProviderButton"
                                        Content="保存服务"
                                        Background="#2563EB"
                                        BorderBrush="#2563EB"
                                        Foreground="#FFFFFF"/>
                            </StackPanel>

                            <TextBlock Grid.Row="4"
                                       Grid.ColumnSpan="3"
                                       Text="当前模型服务的 KEY"
                                       FontSize="14"
                                       FontWeight="SemiBold"
                                       Margin="0,0,0,6"/>

                            <ListBox x:Name="KeyList"
                                     Grid.Row="5"
                                     Grid.ColumnSpan="3"
                                     Height="116"
                                     Margin="0,0,0,10"/>

                            <Grid Grid.Row="6" Grid.ColumnSpan="3" Margin="0,0,0,10">
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

                            <UniformGrid Grid.Row="7" Grid.ColumnSpan="3" Columns="3" Rows="2" Margin="0,0,0,0">
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

            <TabItem Header="模型系列和版本">
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
                        </Grid.RowDefinitions>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="1*"/>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="1*"/>
                            <ColumnDefinition Width="16"/>
                            <ColumnDefinition Width="1*"/>
                        </Grid.ColumnDefinitions>

                        <StackPanel Grid.Row="0" Grid.ColumnSpan="3" Margin="0,0,0,18">
                            <TextBlock Text="模型系列和模型版本" FontSize="17" FontWeight="SemiBold"/>
                            <TextBlock Text="这里维护模型系列与模型版本的挂钩；服务配置页会读取这份目录。"
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
                            <TextBlock Text="模型系列" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                            <ListBox x:Name="SeriesList" Grid.Row="1" MinHeight="360" Margin="0,7,0,0"/>
                            <UniformGrid Grid.Row="2" Columns="2" Margin="0,10,0,0">
                                <Button x:Name="SeriesUpButton"
                                        Content="上移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="0,0,6,0"/>
                                <Button x:Name="SeriesDownButton"
                                        Content="下移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="6,0,0,0"/>
                            </UniformGrid>
                            <Grid Grid.Row="3" Margin="0,12,0,0">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="150"/>
                                    <ColumnDefinition Width="12"/>
                                    <ColumnDefinition Width="*"/>
                                </Grid.ColumnDefinitions>
                                <StackPanel Grid.Row="0" Grid.Column="0">
                                    <TextBlock Text="系列 ID" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                    <TextBox x:Name="SeriesIdBox" Margin="0,7,0,0"/>
                                </StackPanel>
                                <StackPanel Grid.Row="0" Grid.Column="2">
                                    <TextBlock Text="系列名称" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                    <TextBox x:Name="SeriesNameBox" Margin="0,7,0,0"/>
                                </StackPanel>
                                <UniformGrid Grid.Row="2" Grid.ColumnSpan="3" Columns="3" Margin="0,12,0,0">
                                    <Button x:Name="NewSeriesButton"
                                            Content="新增系列"
                                            Background="#FFFFFF"
                                            BorderBrush="#CBD5E1"
                                            Foreground="#334155"
                                            Margin="0,0,8,0"/>
                                    <Button x:Name="DeleteSeriesButton"
                                            Content="删除系列"
                                            Background="#FEF2F2"
                                            BorderBrush="#FCA5A5"
                                            Foreground="#991B1B"
                                            Margin="0,0,8,0"/>
                                    <Button x:Name="SaveSeriesButton"
                                            Content="保存系列"
                                            Background="#2563EB"
                                            BorderBrush="#2563EB"
                                            Foreground="#FFFFFF"/>
                                </UniformGrid>
                            </Grid>
                        </Grid>

                        <Grid Grid.Row="1" Grid.Column="2">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="当前系列的模型版本" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                            <ListBox x:Name="SeriesModelsList" Grid.Row="1" MinHeight="360" Margin="0,7,0,0"/>
                            <UniformGrid Grid.Row="2" Columns="2" Margin="0,10,0,0">
                                <Button x:Name="SeriesModelUpButton"
                                        Content="上移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="0,0,6,0"/>
                                <Button x:Name="SeriesModelDownButton"
                                        Content="下移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="6,0,0,0"/>
                            </UniformGrid>
                            <StackPanel Grid.Row="3" Margin="0,12,0,0">
                                <TextBlock Text="默认模型" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                <ComboBox x:Name="SeriesDefaultModelCombo" Height="30" Margin="0,7,0,0"/>
                            </StackPanel>
                            <Grid Grid.Row="4" Margin="0,12,0,0">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <TextBlock Text="模型版本名称" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                <StackPanel Grid.Row="1" Margin="0,7,0,0">
                                    <TextBox x:Name="SeriesModelValueBox"/>
                                    <UniformGrid Columns="4" Margin="0,12,0,0">
                                        <Button x:Name="NewSeriesModelButton"
                                                Content="新增模型"
                                                Background="#FFFFFF"
                                                BorderBrush="#CBD5E1"
                                                Foreground="#334155"
                                                Margin="0,0,8,0"/>
                                        <Button x:Name="DeleteSeriesModelButton"
                                                Content="删除模型"
                                                Background="#FEF2F2"
                                                BorderBrush="#FCA5A5"
                                                Foreground="#991B1B"
                                                Margin="0,0,8,0"/>
                                        <Button x:Name="DefaultSeriesModelButton"
                                                Content="设为默认"
                                                Background="#EFF6FF"
                                                BorderBrush="#93C5FD"
                                                Foreground="#1D4ED8"
                                                Margin="0,0,8,0"/>
                                        <Button x:Name="SaveSeriesModelButton"
                                                Content="保存模型"
                                                Background="#2563EB"
                                                BorderBrush="#2563EB"
                                                Foreground="#FFFFFF"/>
                                    </UniformGrid>
                                </StackPanel>
                            </Grid>
                        </Grid>

                        <Grid Grid.Row="1" Grid.Column="4">
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="*"/>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            <TextBlock Text="当前模型的推理深度" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                            <ListBox x:Name="SeriesModelDepthsList" Grid.Row="1" MinHeight="360" Margin="0,7,0,0"/>
                            <UniformGrid Grid.Row="2" Columns="2" Margin="0,10,0,0">
                                <Button x:Name="SeriesDepthUpButton"
                                        Content="上移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="0,0,6,0"/>
                                <Button x:Name="SeriesDepthDownButton"
                                        Content="下移"
                                        Background="#FFFFFF"
                                        BorderBrush="#CBD5E1"
                                        Foreground="#334155"
                                        Margin="6,0,0,0"/>
                            </UniformGrid>
                            <StackPanel Grid.Row="3" Margin="0,12,0,0">
                                <TextBlock Text="推理深度名称" FontSize="13" FontWeight="SemiBold" Foreground="#475569"/>
                                <TextBox x:Name="SeriesDepthValueBox" Margin="0,7,0,0"/>
                                <UniformGrid Columns="3" Margin="0,12,0,0">
                                    <Button x:Name="NewSeriesDepthButton"
                                            Content="新增"
                                            Background="#FFFFFF"
                                            BorderBrush="#CBD5E1"
                                            Foreground="#334155"
                                            Margin="0,0,8,0"/>
                                    <Button x:Name="DeleteSeriesDepthButton"
                                            Content="删除"
                                            Background="#FEF2F2"
                                            BorderBrush="#FCA5A5"
                                            Foreground="#991B1B"
                                            Margin="0,0,8,0"/>
                                    <Button x:Name="SaveSeriesDepthButton"
                                            Content="保存"
                                            Background="#2563EB"
                                            BorderBrush="#2563EB"
                                            Foreground="#FFFFFF"/>
                                </UniformGrid>
                            </StackPanel>
                        </Grid>

                        <StackPanel Visibility="Collapsed">
                            <ListBox x:Name="ModelsList"/>
                            <TextBox x:Name="ModelValueBox"/>
                            <ListBox x:Name="ModelReasoningEffortsList" SelectionMode="Multiple"/>
                            <Button x:Name="NewModelButton"/>
                            <Button x:Name="DeleteModelButton"/>
                            <Button x:Name="SaveModelButton"/>
                            <Button x:Name="DefaultModelButton"/>
                            <Button x:Name="ModelUpButton"/>
                            <Button x:Name="ModelDownButton"/>
                            <ListBox x:Name="ReasoningEffortsList"/>
                            <TextBox x:Name="ReasoningEffortValueBox"/>
                            <Button x:Name="NewReasoningEffortButton"/>
                            <Button x:Name="DeleteReasoningEffortButton"/>
                            <Button x:Name="SaveReasoningEffortButton"/>
                            <Button x:Name="DefaultReasoningEffortButton"/>
                            <Button x:Name="ReasoningEffortUpButton"/>
                            <Button x:Name="ReasoningEffortDownButton"/>
                            <Button x:Name="ResetSettingsButton"/>
                            <Button x:Name="SaveSettingsButton"/>
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
$vendorList = $window.FindName("VendorList")
$providerModelsList = $window.FindName("ProviderModelsList")
$providerDefaultModelCombo = $window.FindName("ProviderDefaultModelCombo")
$saveProviderButton = $window.FindName("SaveProviderButton")
$newProviderButton = $window.FindName("NewProviderButton")
$deleteProviderButton = $window.FindName("DeleteProviderButton")
$defaultProviderButton = $window.FindName("DefaultProviderButton")
$providerUpButton = $window.FindName("ProviderUpButton")
$providerDownButton = $window.FindName("ProviderDownButton")
$providerTopButton = $window.FindName("ProviderTopButton")
$providerBottomButton = $window.FindName("ProviderBottomButton")
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
$modelReasoningEffortsList = $window.FindName("ModelReasoningEffortsList")
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
$seriesList = $window.FindName("SeriesList")
$seriesIdBox = $window.FindName("SeriesIdBox")
$seriesNameBox = $window.FindName("SeriesNameBox")
$seriesModelsList = $window.FindName("SeriesModelsList")
$seriesModelValueBox = $window.FindName("SeriesModelValueBox")
$seriesDefaultModelCombo = $window.FindName("SeriesDefaultModelCombo")
$seriesModelDepthsList = $window.FindName("SeriesModelDepthsList")
$seriesDepthValueBox = $window.FindName("SeriesDepthValueBox")
$newSeriesButton = $window.FindName("NewSeriesButton")
$deleteSeriesButton = $window.FindName("DeleteSeriesButton")
$saveSeriesButton = $window.FindName("SaveSeriesButton")
$seriesUpButton = $window.FindName("SeriesUpButton")
$seriesDownButton = $window.FindName("SeriesDownButton")
$newSeriesModelButton = $window.FindName("NewSeriesModelButton")
$deleteSeriesModelButton = $window.FindName("DeleteSeriesModelButton")
$defaultSeriesModelButton = $window.FindName("DefaultSeriesModelButton")
$saveSeriesModelButton = $window.FindName("SaveSeriesModelButton")
$seriesModelUpButton = $window.FindName("SeriesModelUpButton")
$seriesModelDownButton = $window.FindName("SeriesModelDownButton")
$newSeriesDepthButton = $window.FindName("NewSeriesDepthButton")
$deleteSeriesDepthButton = $window.FindName("DeleteSeriesDepthButton")
$saveSeriesDepthButton = $window.FindName("SaveSeriesDepthButton")
$seriesDepthUpButton = $window.FindName("SeriesDepthUpButton")
$seriesDepthDownButton = $window.FindName("SeriesDepthDownButton")
$exportConfigButton = $window.FindName("ExportConfigButton")
$importConfigButton = $window.FindName("ImportConfigButton")
$closeButton = $window.FindName("CloseButton")
$statusText = $window.FindName("StatusText")
function Set-Status {
    param([string]$Message)
    $statusText.Text = $Message
}

$script:VendorRows = @(Get-CodexModelVendorCatalog)
function Refresh-VendorChecklist {
    $checkedIds = @()
    foreach ($item in @($vendorList.Items)) {
        if ($item -is [System.Windows.Controls.CheckBox] -and $item.IsChecked) {
            $checkedIds += [string]$item.Tag
        }
    }

    $vendorList.Items.Clear()
    foreach ($vendor in $script:VendorRows) {
        $checkBox = New-Object System.Windows.Controls.CheckBox
        $checkBox.Content = [string]$vendor.name
        $checkBox.Tag = [string]$vendor.id
        $checkBox.Margin = [System.Windows.Thickness]::new(4, 4, 4, 4)
        $checkBox.Padding = [System.Windows.Thickness]::new(4, 0, 0, 0)
        $checkBox.IsChecked = ($checkedIds -contains [string]$vendor.id)
        $checkBox.Add_Checked({
            if (-not $script:SuppressProviderModelRefresh) {
                Refresh-ProviderModelChoices -SelectAllWhenEmpty
            }
        })
        $checkBox.Add_Unchecked({
            if (-not $script:SuppressProviderModelRefresh) {
                Refresh-ProviderModelChoices -SelectAllWhenEmpty
            }
        })
        [void]$vendorList.Items.Add($checkBox)
    }
}
Refresh-VendorChecklist

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
    Refresh-ModelReasoningEffortChoices -Model $value
}

function Set-ReasoningEffortFormFromSelection {
    $value = Get-SelectedReasoningEffortValue
    if ($value) {
        $reasoningEffortValueBox.Text = $value
    } else {
        $reasoningEffortValueBox.Clear()
    }
}

function Refresh-ModelReasoningEffortChoices {
    param([string]$Model)

    $modelReasoningEffortsList.Items.Clear()
    foreach ($reasoningEffort in @($script:ReasoningEffortValues)) {
        [void]$modelReasoningEffortsList.Items.Add($reasoningEffort)
    }

    $allowed = @()
    $map = $script:CodexSwitcherSettings.modelReasoningEfforts
    if ($Model) {
        if ($map -is [System.Collections.IDictionary] -and $map.Contains($Model)) {
            $allowed = @($map[$Model])
        } elseif ($map -and $map.PSObject.Properties.Name -contains $Model) {
            $allowed = @($map.$Model)
        }
    }
    if ($allowed.Count -eq 0) {
        $allowed = @($script:ReasoningEffortValues)
    }

    for ($i = 0; $i -lt $modelReasoningEffortsList.Items.Count; $i++) {
        if ($allowed -contains [string]$modelReasoningEffortsList.Items[$i]) {
            $modelReasoningEffortsList.SelectedItems.Add($modelReasoningEffortsList.Items[$i]) | Out-Null
        }
    }
    if ($modelReasoningEffortsList.SelectedItems.Count -eq 0 -and $modelReasoningEffortsList.Items.Count -gt 0) {
        $modelReasoningEffortsList.SelectedItems.Add($modelReasoningEffortsList.Items[0]) | Out-Null
    }
}

function Get-SelectedModelReasoningEfforts {
    $values = @()
    foreach ($item in @($modelReasoningEffortsList.SelectedItems)) {
        $values += [string]$item
    }
    if ($values.Count -eq 0) {
        $values = @($script:ReasoningEffortValues)
    }
    return @($values)
}

function Get-EditedModelReasoningEffortMap {
    param(
        [string[]]$Models,
        [string]$EditedModel
    )

    $map = [ordered]@{}
    $currentMap = $script:CodexSwitcherSettings.modelReasoningEfforts
    foreach ($model in @($Models)) {
        $values = @()
        if ($EditedModel -and $model -eq $EditedModel) {
            $values = @(Get-SelectedModelReasoningEfforts)
        } elseif ($currentMap -is [System.Collections.IDictionary] -and $currentMap.Contains($model)) {
            $values = @($currentMap[$model])
        } elseif ($currentMap -and $currentMap.PSObject.Properties.Name -contains $model) {
            $values = @($currentMap.$model)
        }
        if ($values.Count -eq 0) {
            $values = @($script:ReasoningEffortValues)
        }
        $map[$model] = @($values)
    }
    return $map
}

function Get-SeriesModelName {
    param($Model)
    if ($Model -is [string]) { return [string]$Model }
    return [string](Get-CodexObjectProperty -Object $Model -Name "name")
}

function Get-SeriesModelDepths {
    param($Model)
    $name = Get-SeriesModelName -Model $Model
    $depths = @()
    if ($Model -and -not ($Model -is [string])) {
        $depths = @((Get-CodexObjectProperty -Object $Model -Name "reasoningDepths"))
    }
    if ($depths.Count -eq 0) {
        $map = Get-DefaultCodexModelReasoningEffortMap
        if ($map.ContainsKey($name)) { $depths = @($map[$name]) }
    }
    if ($depths.Count -eq 0) { $depths = @($script:ReasoningEffortValues) }
    return @($depths)
}

function New-SeriesModelObject {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string[]]$Depths = @()
    )

    if ($Depths.Count -eq 0) {
        $map = Get-DefaultCodexModelReasoningEffortMap
        if ($map.ContainsKey($Name)) { $Depths = @($map[$Name]) }
    }
    if ($Depths.Count -eq 0) { $Depths = @($script:ReasoningEffortValues) }
    return [pscustomobject]@{
        name = $Name
        reasoningDepths = @($Depths)
    }
}

function Get-SelectedSeriesModelIndex {
    if ($seriesModelsList.SelectedIndex -lt 0 -or $seriesModelsList.SelectedIndex -ge @($script:CurrentSeriesModels).Count) {
        return -1
    }
    return $seriesModelsList.SelectedIndex
}

function Refresh-SeriesDepthList {
    param($Model)

    $seriesModelDepthsList.Items.Clear()
    $seriesDepthValueBox.Clear()
    if (-not $Model) { return }
    foreach ($depth in @(Get-SeriesModelDepths -Model $Model)) {
        [void]$seriesModelDepthsList.Items.Add([string]$depth)
    }
    if ($seriesModelDepthsList.Items.Count -gt 0) {
        $seriesModelDepthsList.SelectedIndex = 0
    }
}

function Set-SeriesDepthFormFromSelection {
    if ($seriesModelDepthsList.SelectedIndex -lt 0) {
        $seriesDepthValueBox.Clear()
        return
    }
    $seriesDepthValueBox.Text = [string]$seriesModelDepthsList.SelectedItem
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
    Load-ModelSeriesSettings
}

function Get-SelectedSeriesIndex {
    if ($seriesList.SelectedIndex -lt 0 -or $seriesList.SelectedIndex -ge @($script:SeriesRows).Count) {
        return -1
    }
    return $seriesList.SelectedIndex
}

function Refresh-SeriesModelList {
    param($Series)

    $seriesModelsList.Items.Clear()
    $seriesDefaultModelCombo.Items.Clear()
    $seriesModelValueBox.Clear()
    $script:CurrentSeriesModels = @()
    Refresh-SeriesDepthList
    if (-not $Series) { return }

    foreach ($model in @($Series.models)) {
        $modelName = Get-SeriesModelName -Model $model
        $script:CurrentSeriesModels += (New-SeriesModelObject -Name $modelName -Depths @(Get-SeriesModelDepths -Model $model))
        $label = if ($modelName -eq $Series.defaultModel) { "★ $modelName" } else { "  $modelName" }
        [void]$seriesModelsList.Items.Add($label)
        [void]$seriesDefaultModelCombo.Items.Add([string]$modelName)
    }
    if ($Series.defaultModel -and $seriesDefaultModelCombo.Items.Contains($Series.defaultModel)) {
        $seriesDefaultModelCombo.SelectedItem = $Series.defaultModel
    } elseif ($seriesDefaultModelCombo.Items.Count -gt 0) {
        $seriesDefaultModelCombo.SelectedIndex = 0
    }
    if ($seriesModelsList.Items.Count -gt 0) {
        $seriesModelsList.SelectedIndex = 0
    }
}

function Set-SeriesFormFromSelection {
    $index = Get-SelectedSeriesIndex
    if ($index -lt 0) {
        $seriesIdBox.Clear()
        $seriesNameBox.Clear()
        Refresh-SeriesModelList
        return
    }

    $series = $script:SeriesRows[$index]
    $seriesIdBox.Text = [string]$series.id
    $seriesNameBox.Text = [string]$series.name
    Refresh-SeriesModelList -Series $series
}

function Load-ModelSeriesSettings {
    $script:SeriesRows = @(Normalize-CodexModelSeriesCatalog -Items $script:CodexSwitcherSettings.modelSeries)
    $seriesList.Items.Clear()
    foreach ($series in @($script:SeriesRows)) {
        [void]$seriesList.Items.Add("$($series.name)  [$($series.id)]")
    }
    if ($seriesList.Items.Count -gt 0 -and $seriesList.SelectedIndex -lt 0) {
        $seriesList.SelectedIndex = 0
    } else {
        Set-SeriesFormFromSelection
    }
}

function Get-SeriesModelsFromUi {
    return @($script:CurrentSeriesModels)
}

function Save-ModelSeriesRows {
    param(
        [string]$PreferredSeriesId = ""
    )

    $allModels = @()
    foreach ($series in @($script:SeriesRows)) {
        foreach ($model in @($series.models)) {
            $modelName = Get-SeriesModelName -Model $model
            if ($modelName -and $allModels -notcontains $modelName) { $allModels += [string]$modelName }
        }
    }
    if ($allModels.Count -eq 0) {
        $allModels = @($script:ModelValues)
    }
    $defaultModel = [string]$script:CodexSwitcherSettings.defaultModel
    if (-not $defaultModel -or $allModels -notcontains $defaultModel) {
        $defaultModel = [string]$allModels[0]
    }

    $modelReasoningEfforts = Get-EditedModelReasoningEffortMap -Models $allModels -EditedModel $null
    $script:CodexSwitcherSettings = Set-CodexSwitcherSettings -Models $allModels -ReasoningEfforts @($script:ReasoningEffortValues) -ModelReasoningEfforts $modelReasoningEfforts -ModelSeries @($script:SeriesRows) -DefaultModel $defaultModel -DefaultReasoningEffort $script:CodexSwitcherSettings.defaultReasoningEffort
    $script:VendorRows = @(Get-CodexModelVendorCatalog)
    Refresh-VendorChecklist
    Load-SwitcherSettings -PreferredModel $defaultModel -PreferredReasoningEffort (Get-SelectedReasoningEffortValue)
    if ($PreferredSeriesId) {
        for ($i = 0; $i -lt $script:SeriesRows.Count; $i++) {
            if ($script:SeriesRows[$i].id -eq $PreferredSeriesId) {
                $seriesList.SelectedIndex = $i
                break
            }
        }
    }
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
    $modelReasoningEfforts = Get-EditedModelReasoningEffortMap -Models $models -EditedModel $value

    $defaultModel = [string]$script:CodexSwitcherSettings.defaultModel
    if (-not $defaultModel -or ($oldValue -and $oldValue -eq $defaultModel)) {
        $defaultModel = $value
    }

    $preferredReasoningEffort = Get-SelectedReasoningEffortValue
    $script:CodexSwitcherSettings = Set-CodexSwitcherSettings -Models $models -ReasoningEfforts @($script:ReasoningEffortValues) -ModelReasoningEfforts $modelReasoningEfforts -DefaultModel $defaultModel -DefaultReasoningEffort $script:CodexSwitcherSettings.defaultReasoningEffort
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
            [System.Windows.MessageBox]::Show("请填写推理深度名称。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        }
        return $false
    }

    $reasoningEfforts = @($script:ReasoningEffortValues)
    $selectedIndex = $reasoningEffortsList.SelectedIndex
    $oldValue = if ($selectedIndex -ge 0 -and $selectedIndex -lt $reasoningEfforts.Count) { [string]$reasoningEfforts[$selectedIndex] } else { $null }
    if (Test-SettingDuplicate -Items $reasoningEfforts -Value $value -IgnoreIndex $selectedIndex) {
        if (-not $Quiet) {
            [System.Windows.MessageBox]::Show("推理深度名称已存在。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
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
    $modelReasoningEfforts = Get-EditedModelReasoningEffortMap -Models @($script:ModelValues) -EditedModel (Get-SelectedModelValue)
    $script:CodexSwitcherSettings = Set-CodexSwitcherSettings -Models @($script:ModelValues) -ReasoningEfforts $reasoningEfforts -ModelReasoningEfforts $modelReasoningEfforts -DefaultModel $script:CodexSwitcherSettings.defaultModel -DefaultReasoningEffort $defaultReasoningEffort
    Load-SwitcherSettings -PreferredModel $preferredModel -PreferredReasoningEffort $value
    if (-not $Quiet) {
        Set-Status "推理深度已保存。"
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

function Get-SelectedVendors {
    $vendors = @()
    foreach ($item in @($vendorList.Items)) {
        if ($item -is [System.Windows.Controls.CheckBox] -and $item.IsChecked) {
            $id = ([string]$item.Tag).Trim().ToLowerInvariant()
            $vendor = $script:VendorRows | Where-Object { $_.id -eq $id } | Select-Object -First 1
            if ($vendor) {
                $vendors += $vendor
            }
        }
    }
    return @($vendors)
}

function Get-SelectedVendor {
    return (Get-SelectedVendors | Select-Object -First 1)
}

function Get-SelectedVendorIds {
    $ids = @()
    foreach ($vendor in @(Get-SelectedVendors)) {
        if ($ids -notcontains $vendor.id) {
            $ids += [string]$vendor.id
        }
    }
    return @($ids)
}

function Get-SelectedVendorModels {
    $models = @()
    foreach ($vendor in @(Get-SelectedVendors)) {
        foreach ($model in @($vendor.models)) {
            $modelName = Get-SeriesModelName -Model $model
            if ($modelName -and $models -notcontains $modelName) {
                $models += [string]$modelName
            }
        }
    }
    return @($models)
}

function Set-SelectedVendors {
    param([string[]]$VendorIds)

    $targets = @()
    foreach ($id in @($VendorIds)) {
        $value = ([string]$id).Trim().ToLowerInvariant()
        if ($value -and $targets -notcontains $value) { $targets += $value }
    }
    $script:SuppressProviderModelRefresh = $true
    foreach ($item in @($vendorList.Items)) {
        if ($item -is [System.Windows.Controls.CheckBox]) {
            $id = ([string]$item.Tag).Trim().ToLowerInvariant()
            $item.IsChecked = ($targets -contains $id)
        }
    }
    $script:SuppressProviderModelRefresh = $false
}

function Set-SelectedVendor {
    param([string]$VendorId)
    Set-SelectedVendors -VendorIds @($VendorId)
}

function Refresh-ProviderModelChoices {
    param(
        [string[]]$SelectedModels = @(),
        [string]$DefaultModel = "",
        [switch]$SelectAllWhenEmpty
    )

    $providerModelsList.Items.Clear()
    $providerDefaultModelCombo.Items.Clear()
    $availableModels = @(Get-SelectedVendorModels)
    $selected = @()
    if (@($SelectedModels).Count -gt 0) {
        $selected = @(Normalize-CodexModelList -Items $SelectedModels -Fallback @())
    } elseif ($SelectAllWhenEmpty) {
        $selected = @($availableModels)
    }

    foreach ($model in @($availableModels)) {
        $checkBox = New-Object System.Windows.Controls.CheckBox
        $checkBox.Content = [string]$model
        $checkBox.Tag = [string]$model
        $checkBox.Margin = [System.Windows.Thickness]::new(4, 4, 4, 4)
        $checkBox.Padding = [System.Windows.Thickness]::new(4, 0, 0, 0)
        $checkBox.IsChecked = ($selected -contains [string]$model)
        $checkBox.Add_Checked({
            if (-not $script:SuppressProviderModelRefresh) {
                Refresh-ProviderDefaultModelChoices
            }
        })
        $checkBox.Add_Unchecked({
            if (-not $script:SuppressProviderModelRefresh) {
                Refresh-ProviderDefaultModelChoices
            }
        })
        [void]$providerModelsList.Items.Add($checkBox)
    }
    Refresh-ProviderDefaultModelChoices -PreferredDefaultModel $DefaultModel
}

function Refresh-ProviderDefaultModelChoices {
    param([string]$PreferredDefaultModel = "")

    $currentDefault = if ($PreferredDefaultModel) { $PreferredDefaultModel } else { [string]$providerDefaultModelCombo.SelectedItem }
    $providerDefaultModelCombo.Items.Clear()
    foreach ($item in @($providerModelsList.Items)) {
        if ($item -is [System.Windows.Controls.CheckBox] -and $item.IsChecked) {
            [void]$providerDefaultModelCombo.Items.Add([string]$item.Tag)
        }
    }
    $defaultVendorModel = [string](Get-SelectedVendor).defaultModel
    if ($currentDefault -and $providerDefaultModelCombo.Items.Contains($currentDefault)) {
        $providerDefaultModelCombo.SelectedItem = $currentDefault
    } elseif ($providerDefaultModelCombo.Items.Contains($defaultVendorModel)) {
        $providerDefaultModelCombo.SelectedItem = $defaultVendorModel
    } elseif ($providerDefaultModelCombo.Items.Count -gt 0) {
        $providerDefaultModelCombo.SelectedIndex = 0
    }
}

function Get-SelectedProviderModels {
    $models = @()
    foreach ($item in @($providerModelsList.Items)) {
        if ($item -is [System.Windows.Controls.CheckBox] -and $item.IsChecked) {
            $models += [string]$item.Tag
        }
    }
    if ($models.Count -eq 0) {
        return @()
    }
    return @($models)
}

function Load-Provider {
    param([string]$PreferredKeyId)

    if ($providerList.SelectedIndex -lt 0) {
        $providerNameBox.Clear()
        $providerUrlBox.Clear()
        Set-SelectedVendors -VendorIds @("openai")
        Refresh-ProviderModelChoices -SelectAllWhenEmpty
        $keyList.Items.Clear()
        Clear-KeyForm
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    $providerNameBox.Text = $provider.name
    $providerUrlBox.Text = $provider.baseUrl
    $providerVendorIds = @(Get-CodexObjectProperty -Object $provider -Name "vendorIds" -DefaultValue @($provider.vendorId))
    Set-SelectedVendors -VendorIds $providerVendorIds
    Refresh-ProviderModelChoices -SelectedModels @($provider.models) -DefaultModel ([string]$provider.defaultModel)
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
        [void]$providerList.Items.Add("$displayName  |  $($provider.vendorName)")
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
$providerModelsList.Add_SelectionChanged({ Refresh-ProviderDefaultModelChoices })

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

$providerTopButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0) {
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    Move-CodexCatalogProvider -ProviderName $provider.id -Direction Top | Out-Null
    Refresh-Providers -PreferredProviderId $provider.id
    Set-Status "模型服务已置顶。"
})

$providerBottomButton.Add_Click({
    if ($providerList.SelectedIndex -lt 0) {
        return
    }

    $provider = $script:Providers[$providerList.SelectedIndex]
    Move-CodexCatalogProvider -ProviderName $provider.id -Direction Bottom | Out-Null
    Refresh-Providers -PreferredProviderId $provider.id
    Set-Status "模型服务已置底。"
})

$newProviderButton.Add_Click({
    $providerList.SelectedIndex = -1
    $providerNameBox.Clear()
    $providerUrlBox.Clear()
    Set-SelectedVendors -VendorIds @("openai")
    Refresh-ProviderModelChoices -SelectAllWhenEmpty
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

    $vendorIds = @(Get-SelectedVendorIds)
    if ($vendorIds.Count -eq 0) {
        $vendorIds = @("custom")
    }
    $providerModels = @(Get-SelectedProviderModels)
    $providerDefaultModel = [string]$providerDefaultModelCombo.SelectedItem
    Add-CodexCatalogProvider -Name $name -BaseUrl $url -EnvKey "CODEX_PROVIDER_API_KEY" -Id $existingId -VendorIds $vendorIds -Models $providerModels -DefaultModel $providerDefaultModel -AllowEmptyModels
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
    $modelReasoningEfforts = Get-EditedModelReasoningEffortMap -Models $models -EditedModel $null
    $script:CodexSwitcherSettings = Set-CodexSwitcherSettings -Models $models -ReasoningEfforts @($script:ReasoningEffortValues) -ModelReasoningEfforts $modelReasoningEfforts -DefaultModel $defaultModel -DefaultReasoningEffort $script:CodexSwitcherSettings.defaultReasoningEffort
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
    Set-Status "正在新增推理深度。"
})

$saveReasoningEffortButton.Add_Click({
    Save-ReasoningEffortFromForm | Out-Null
})

$deleteReasoningEffortButton.Add_Click({
    if ($reasoningEffortsList.SelectedIndex -lt 0) {
        [System.Windows.MessageBox]::Show("请先选择一个推理深度。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    if (@($script:ReasoningEffortValues).Count -le 1) {
        [System.Windows.MessageBox]::Show("推理深度列表至少要保留一项。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
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
    $modelReasoningEfforts = Get-EditedModelReasoningEffortMap -Models @($script:ModelValues) -EditedModel (Get-SelectedModelValue)
    $script:CodexSwitcherSettings = Set-CodexSwitcherSettings -Models @($script:ModelValues) -ReasoningEfforts $reasoningEfforts -ModelReasoningEfforts $modelReasoningEfforts -DefaultModel $script:CodexSwitcherSettings.defaultModel -DefaultReasoningEffort $defaultReasoningEffort
    Load-SwitcherSettings -PreferredModel $preferredModel -PreferredReasoningEffort $defaultReasoningEffort
    Set-Status "推理深度已删除。"
})

$defaultReasoningEffortButton.Add_Click({
    $reasoningEffort = Get-SelectedReasoningEffortValue
    if (-not $reasoningEffort) {
        [System.Windows.MessageBox]::Show("请先选择一个推理深度。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $preferredModel = Get-SelectedModelValue
    $script:CodexSwitcherSettings = Set-CodexSwitcherDefaultReasoningEffort -ReasoningEffort $reasoningEffort
    Load-SwitcherSettings -PreferredModel $preferredModel -PreferredReasoningEffort $reasoningEffort
    Set-Status "默认推理深度已设置。"
})

$reasoningEffortUpButton.Add_Click({
    $reasoningEffort = Get-SelectedReasoningEffortValue
    if (-not $reasoningEffort) {
        return
    }

    $preferredModel = Get-SelectedModelValue
    $script:CodexSwitcherSettings = Move-CodexSwitcherReasoningEffort -ReasoningEffort $reasoningEffort -Direction Up
    Load-SwitcherSettings -PreferredModel $preferredModel -PreferredReasoningEffort $reasoningEffort
    Set-Status "推理深度顺序已调整。"
})

$reasoningEffortDownButton.Add_Click({
    $reasoningEffort = Get-SelectedReasoningEffortValue
    if (-not $reasoningEffort) {
        return
    }

    $preferredModel = Get-SelectedModelValue
    $script:CodexSwitcherSettings = Move-CodexSwitcherReasoningEffort -ReasoningEffort $reasoningEffort -Direction Down
    Load-SwitcherSettings -PreferredModel $preferredModel -PreferredReasoningEffort $reasoningEffort
    Set-Status "推理深度顺序已调整。"
})

$saveSettingsButton.Add_Click({
    Save-SwitcherSettingsFromForm
})

$resetSettingsButton.Add_Click({
    $result = [System.Windows.MessageBox]::Show("确定恢复默认模型和推理深度列表吗？", "恢复默认", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    $script:CodexSwitcherSettings = Save-CodexSwitcherSettings -Settings (New-DefaultCodexSwitcherSettings)
    Load-SwitcherSettings
    Set-Status "模型和推理深度已恢复默认。"
})

$seriesList.Add_SelectionChanged({ Set-SeriesFormFromSelection })
$seriesModelsList.Add_SelectionChanged({
    if ($seriesModelsList.SelectedIndex -lt 0) {
        $seriesModelValueBox.Clear()
        Refresh-SeriesDepthList
        return
    }
    $model = $script:CurrentSeriesModels[$seriesModelsList.SelectedIndex]
    $value = Get-SeriesModelName -Model $model
    $seriesModelValueBox.Text = $value
    Refresh-SeriesDepthList -Model $model
})
$seriesModelDepthsList.Add_SelectionChanged({ Set-SeriesDepthFormFromSelection })

$newSeriesButton.Add_Click({
    $seriesList.SelectedIndex = -1
    $seriesIdBox.Clear()
    $seriesNameBox.Clear()
    Refresh-SeriesModelList
    Set-Status "正在新增模型系列。"
})

$saveSeriesButton.Add_Click({
    $id = ConvertTo-CatalogId $seriesIdBox.Text
    $name = $seriesNameBox.Text.Trim()
    if (-not $name) {
        [System.Windows.MessageBox]::Show("请填写模型系列名称。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    $models = @(Get-SeriesModelsFromUi)
    if ($models.Count -eq 0) {
        [System.Windows.MessageBox]::Show("模型系列至少需要一个模型版本。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    $modelNames = @($models | ForEach-Object { Get-SeriesModelName -Model $_ })
    $defaultModel = [string]$seriesDefaultModelCombo.SelectedItem
    if (-not $defaultModel -or $modelNames -notcontains $defaultModel) {
        $defaultModel = [string]$modelNames[0]
    }

    $index = Get-SelectedSeriesIndex
    $duplicate = $false
    for ($i = 0; $i -lt @($script:SeriesRows).Count; $i++) {
        if ($i -ne $index -and $script:SeriesRows[$i].id -eq $id) {
            $duplicate = $true
            break
        }
    }
    if ($duplicate) {
        [System.Windows.MessageBox]::Show("模型系列 ID 已存在。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }

    $row = [pscustomobject]@{ id = $id; name = $name; defaultModel = $defaultModel; models = @($models) }
    if ($index -ge 0) {
        $script:SeriesRows[$index] = $row
    } else {
        $script:SeriesRows += $row
    }
    Save-ModelSeriesRows -PreferredSeriesId $id
    Set-Status "模型系列已保存。"
})

$deleteSeriesButton.Add_Click({
    $index = Get-SelectedSeriesIndex
    if ($index -lt 0) { return }
    if (@($script:SeriesRows).Count -le 1) {
        [System.Windows.MessageBox]::Show("模型系列至少要保留一项。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    $series = $script:SeriesRows[$index]
    $result = [System.Windows.MessageBox]::Show("确定删除模型系列 $($series.name) 吗？", "删除模型系列", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) { return }
    $rows = @()
    for ($i = 0; $i -lt $script:SeriesRows.Count; $i++) {
        if ($i -ne $index) { $rows += $script:SeriesRows[$i] }
    }
    $script:SeriesRows = @($rows)
    Save-ModelSeriesRows
    Set-Status "模型系列已删除。"
})

$seriesUpButton.Add_Click({
    $index = Get-SelectedSeriesIndex
    if ($index -le 0) { return }
    $current = $script:SeriesRows[$index]
    $script:SeriesRows[$index] = $script:SeriesRows[$index - 1]
    $script:SeriesRows[$index - 1] = $current
    Save-ModelSeriesRows -PreferredSeriesId $current.id
    Set-Status "模型系列顺序已调整。"
})

$seriesDownButton.Add_Click({
    $index = Get-SelectedSeriesIndex
    if ($index -lt 0 -or $index -ge ($script:SeriesRows.Count - 1)) { return }
    $current = $script:SeriesRows[$index]
    $script:SeriesRows[$index] = $script:SeriesRows[$index + 1]
    $script:SeriesRows[$index + 1] = $current
    Save-ModelSeriesRows -PreferredSeriesId $current.id
    Set-Status "模型系列顺序已调整。"
})

$newSeriesModelButton.Add_Click({
    $seriesModelsList.SelectedIndex = -1
    $seriesModelValueBox.Clear()
    Set-Status "正在新增模型版本。"
})

$saveSeriesModelButton.Add_Click({
    $model = $seriesModelValueBox.Text.Trim()
    if (-not $model) {
        [System.Windows.MessageBox]::Show("请填写模型版本名称。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    $models = @(Get-SeriesModelsFromUi)
    $selectedIndex = $seriesModelsList.SelectedIndex
    $oldModel = $null
    if ($selectedIndex -ge 0 -and $selectedIndex -lt $models.Count) {
        $oldModel = Get-SeriesModelName -Model $models[$selectedIndex]
    }
    for ($i = 0; $i -lt $models.Count; $i++) {
        if ($i -ne $selectedIndex -and (Get-SeriesModelName -Model $models[$i]).ToLowerInvariant() -eq $model.ToLowerInvariant()) {
            [System.Windows.MessageBox]::Show("模型版本已存在。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
    }
    $depths = if ($selectedIndex -ge 0 -and $selectedIndex -lt $models.Count) { @(Get-SeriesModelDepths -Model $models[$selectedIndex]) } else { @() }
    if ($oldModel) {
        $models[$selectedIndex] = New-SeriesModelObject -Name $model -Depths $depths
    } else {
        $models += (New-SeriesModelObject -Name $model)
    }
    $defaultModel = [string]$seriesDefaultModelCombo.SelectedItem
    if (-not $defaultModel -or ($oldModel -and $oldModel -eq $defaultModel)) {
        $defaultModel = $model
    }
    $series = [pscustomobject]@{ id = $seriesIdBox.Text.Trim(); name = $seriesNameBox.Text.Trim(); defaultModel = $defaultModel; models = @($models) }
    Refresh-SeriesModelList -Series $series
    $seriesModelsList.SelectedIndex = [Math]::Max(0, (Find-StringIndex -Items (@($models | ForEach-Object { Get-SeriesModelName -Model $_ })) -Value $model))
    Set-Status "模型版本已保存到当前编辑。请点击保存系列写入配置。"
})

$deleteSeriesModelButton.Add_Click({
    $models = @(Get-SeriesModelsFromUi)
    if ($seriesModelsList.SelectedIndex -lt 0 -or $seriesModelsList.SelectedIndex -ge $models.Count) { return }
    if ($models.Count -le 1) {
        [System.Windows.MessageBox]::Show("模型系列至少需要一个模型版本。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    $removeIndex = $seriesModelsList.SelectedIndex
    $newModels = @()
    for ($i = 0; $i -lt $models.Count; $i++) {
        if ($i -ne $removeIndex) { $newModels += $models[$i] }
    }
    $defaultModel = [string]$seriesDefaultModelCombo.SelectedItem
    if ($defaultModel -eq (Get-SeriesModelName -Model $models[$removeIndex])) {
        $defaultModel = Get-SeriesModelName -Model $newModels[0]
    }
    $series = [pscustomobject]@{ id = $seriesIdBox.Text.Trim(); name = $seriesNameBox.Text.Trim(); defaultModel = $defaultModel; models = @($newModels) }
    Refresh-SeriesModelList -Series $series
    Set-Status "模型版本已删除。请点击保存系列写入配置。"
})

$defaultSeriesModelButton.Add_Click({
    $models = @(Get-SeriesModelsFromUi)
    if ($seriesModelsList.SelectedIndex -lt 0 -or $seriesModelsList.SelectedIndex -ge $models.Count) { return }
    $seriesDefaultModelCombo.SelectedItem = Get-SeriesModelName -Model $models[$seriesModelsList.SelectedIndex]
    $series = [pscustomobject]@{ id = $seriesIdBox.Text.Trim(); name = $seriesNameBox.Text.Trim(); defaultModel = [string]$seriesDefaultModelCombo.SelectedItem; models = @($models) }
    Refresh-SeriesModelList -Series $series
    Set-Status "默认模型已更新。请点击保存系列写入配置。"
})

$seriesModelUpButton.Add_Click({
    $index = Get-SelectedSeriesModelIndex
    if ($index -le 0) { return }
    $models = @(Get-SeriesModelsFromUi)
    $current = $models[$index]
    $models[$index] = $models[$index - 1]
    $models[$index - 1] = $current
    $series = [pscustomobject]@{ id = $seriesIdBox.Text.Trim(); name = $seriesNameBox.Text.Trim(); defaultModel = [string]$seriesDefaultModelCombo.SelectedItem; models = @($models) }
    Refresh-SeriesModelList -Series $series
    $seriesModelsList.SelectedIndex = $index - 1
    Set-Status "模型版本顺序已调整。请点击保存系列写入配置。"
})

$seriesModelDownButton.Add_Click({
    $index = Get-SelectedSeriesModelIndex
    $models = @(Get-SeriesModelsFromUi)
    if ($index -lt 0 -or $index -ge ($models.Count - 1)) { return }
    $current = $models[$index]
    $models[$index] = $models[$index + 1]
    $models[$index + 1] = $current
    $series = [pscustomobject]@{ id = $seriesIdBox.Text.Trim(); name = $seriesNameBox.Text.Trim(); defaultModel = [string]$seriesDefaultModelCombo.SelectedItem; models = @($models) }
    Refresh-SeriesModelList -Series $series
    $seriesModelsList.SelectedIndex = $index + 1
    Set-Status "模型版本顺序已调整。请点击保存系列写入配置。"
})

$newSeriesDepthButton.Add_Click({
    $seriesModelDepthsList.SelectedIndex = -1
    $seriesDepthValueBox.Clear()
    Set-Status "正在新增推理深度。"
})

$saveSeriesDepthButton.Add_Click({
    $depth = $seriesDepthValueBox.Text.Trim()
    if (-not $depth) {
        [System.Windows.MessageBox]::Show("请填写推理深度名称。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    $modelIndex = Get-SelectedSeriesModelIndex
    if ($modelIndex -lt 0) { return }
    $models = @(Get-SeriesModelsFromUi)
    $depths = @(Get-SeriesModelDepths -Model $models[$modelIndex])
    $selectedDepthIndex = $seriesModelDepthsList.SelectedIndex
    for ($i = 0; $i -lt $depths.Count; $i++) {
        if ($i -ne $selectedDepthIndex -and ([string]$depths[$i]).ToLowerInvariant() -eq $depth.ToLowerInvariant()) {
            [System.Windows.MessageBox]::Show("推理深度已存在。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
    }
    if ($selectedDepthIndex -ge 0 -and $selectedDepthIndex -lt $depths.Count) {
        $depths[$selectedDepthIndex] = $depth
    } else {
        $depths += $depth
    }
    $models[$modelIndex] = New-SeriesModelObject -Name (Get-SeriesModelName -Model $models[$modelIndex]) -Depths $depths
    $series = [pscustomobject]@{ id = $seriesIdBox.Text.Trim(); name = $seriesNameBox.Text.Trim(); defaultModel = [string]$seriesDefaultModelCombo.SelectedItem; models = @($models) }
    Refresh-SeriesModelList -Series $series
    $seriesModelsList.SelectedIndex = $modelIndex
    $seriesModelDepthsList.SelectedIndex = [Math]::Max(0, (Find-StringIndex -Items $depths -Value $depth))
    Set-Status "推理深度已保存到当前编辑。请点击保存系列写入配置。"
})

$deleteSeriesDepthButton.Add_Click({
    $modelIndex = Get-SelectedSeriesModelIndex
    if ($modelIndex -lt 0 -or $seriesModelDepthsList.SelectedIndex -lt 0) { return }
    $models = @(Get-SeriesModelsFromUi)
    $depths = @(Get-SeriesModelDepths -Model $models[$modelIndex])
    if ($depths.Count -le 1) {
        [System.Windows.MessageBox]::Show("推理深度至少要保留一项。", "配置模型服务和 KEY", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        return
    }
    $removeIndex = $seriesModelDepthsList.SelectedIndex
    $newDepths = @()
    for ($i = 0; $i -lt $depths.Count; $i++) {
        if ($i -ne $removeIndex) { $newDepths += $depths[$i] }
    }
    $models[$modelIndex] = New-SeriesModelObject -Name (Get-SeriesModelName -Model $models[$modelIndex]) -Depths $newDepths
    $series = [pscustomobject]@{ id = $seriesIdBox.Text.Trim(); name = $seriesNameBox.Text.Trim(); defaultModel = [string]$seriesDefaultModelCombo.SelectedItem; models = @($models) }
    Refresh-SeriesModelList -Series $series
    $seriesModelsList.SelectedIndex = $modelIndex
    Set-Status "推理深度已删除。请点击保存系列写入配置。"
})

$seriesDepthUpButton.Add_Click({
    $modelIndex = Get-SelectedSeriesModelIndex
    $depthIndex = $seriesModelDepthsList.SelectedIndex
    if ($modelIndex -lt 0 -or $depthIndex -le 0) { return }
    $models = @(Get-SeriesModelsFromUi)
    $depths = @(Get-SeriesModelDepths -Model $models[$modelIndex])
    $current = $depths[$depthIndex]
    $depths[$depthIndex] = $depths[$depthIndex - 1]
    $depths[$depthIndex - 1] = $current
    $models[$modelIndex] = New-SeriesModelObject -Name (Get-SeriesModelName -Model $models[$modelIndex]) -Depths $depths
    $series = [pscustomobject]@{ id = $seriesIdBox.Text.Trim(); name = $seriesNameBox.Text.Trim(); defaultModel = [string]$seriesDefaultModelCombo.SelectedItem; models = @($models) }
    Refresh-SeriesModelList -Series $series
    $seriesModelsList.SelectedIndex = $modelIndex
    $seriesModelDepthsList.SelectedIndex = $depthIndex - 1
    Set-Status "推理深度顺序已调整。请点击保存系列写入配置。"
})

$seriesDepthDownButton.Add_Click({
    $modelIndex = Get-SelectedSeriesModelIndex
    $depthIndex = $seriesModelDepthsList.SelectedIndex
    if ($modelIndex -lt 0) { return }
    $models = @(Get-SeriesModelsFromUi)
    $depths = @(Get-SeriesModelDepths -Model $models[$modelIndex])
    if ($depthIndex -lt 0 -or $depthIndex -ge ($depths.Count - 1)) { return }
    $current = $depths[$depthIndex]
    $depths[$depthIndex] = $depths[$depthIndex + 1]
    $depths[$depthIndex + 1] = $current
    $models[$modelIndex] = New-SeriesModelObject -Name (Get-SeriesModelName -Model $models[$modelIndex]) -Depths $depths
    $series = [pscustomobject]@{ id = $seriesIdBox.Text.Trim(); name = $seriesNameBox.Text.Trim(); defaultModel = [string]$seriesDefaultModelCombo.SelectedItem; models = @($models) }
    Refresh-SeriesModelList -Series $series
    $seriesModelsList.SelectedIndex = $modelIndex
    $seriesModelDepthsList.SelectedIndex = $depthIndex + 1
    Set-Status "推理深度顺序已调整。请点击保存系列写入配置。"
})

$exportConfigButton.Add_Click({ Export-CodexLauncherConfig })
$importConfigButton.Add_Click({ Import-CodexLauncherConfig })
$closeButton.Add_Click({ $window.Close() })

Refresh-Providers
Load-SwitcherSettings
[void]$window.ShowDialog()

