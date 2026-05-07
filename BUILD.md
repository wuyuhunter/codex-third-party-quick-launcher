# Build

This repository contains the PowerShell application logic and the small Windows exe wrapper source.

## Requirements

- Windows 10 or later.
- .NET 8 SDK.
- Windows PowerShell 5.1 or PowerShell 7.

Verify the SDK:

```powershell
dotnet --version
```

## Rebuild the exe

Run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-launcher.ps1
```

The script publishes `src\launcher\CodexSwitcherLauncher.csproj` and copies the result to:

```text
Codex 便捷启动器.exe
```

Intermediate output is written to `artifacts\launcher\`. Build folders under `artifacts\`, `src\**\bin\`, and `src\**\obj\` are ignored by Git and should not be included in source packages.

## Source layout

- `tools\start-codex-switcher.ps1` contains the main WPF launcher UI and Codex startup flow.
- `tools\manage-codex-providers.ps1` manages provider configuration and connectivity checks.
- `tools\codex-provider-lib.ps1` contains shared config, logging, portability, and provider helpers.
- `tools\install-codex-switcher-prereqs.ps1` installs runtime prerequisites.
- `src\launcher\Program.cs` is a small wrapper that starts `tools\start-codex-switcher.ps1`.

The exe is a convenience entry point. The scripts remain the primary source of behavior.
