# Build

This repository contains the PowerShell application logic and the small Windows exe wrapper source.

## Requirements

- Windows 10 or later.
- .NET Framework 4.x compiler `csc.exe`, normally available on Win10 / Win11 at `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`.
- Windows PowerShell 5.1 or PowerShell 7.

Verify the compiler:

```powershell
Test-Path "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
```

## Rebuild the exe

Run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\build-launcher.ps1
```

The script compiles `src\launcher\Program.cs` as a .NET Framework WinExe and copies the result to:

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

