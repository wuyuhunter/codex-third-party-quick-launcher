# Release Contents

This project is intended to be published as a clean portable Windows package.

## Include

- `Codex 便捷启动器.exe`
- `启动 Codex 便捷启动器.cmd`
- `codex-quick-launcher.portable`
- `.gitignore`
- `README.md`
- `BUILD.md`
- `RELEASE_CONTENTS.md`
- `CHANGELOG.md`
- `LICENSE`
- `LICENSE.zh-CN.md`
- `SECURITY.md`
- `SUPPORT.md`
- `PROJECT_STRUCTURE.md`
- `tools\build-launcher.ps1`
- `tools\codex-provider-lib.ps1`
- `tools\install-codex-switcher-prereqs.ps1`
- `tools\manage-codex-providers.ps1`
- `tools\start-codex-switcher.ps1`
- `src\launcher\CodexSwitcherLauncher.csproj`
- `src\launcher\Program.cs`
- `src\launcher\codex-danger.ico`
- `state\codex-quick-launcher-config.example.json`

## Exclude

- `state\codex-quick-launcher-config.json`
- `state\ai-quick-launcher-config.json`
- `state\codex-provider-catalog.json`
- `state\codex-provider-selection.json`
- `state\codex-switcher-settings.json`
- `logs\`
- `secrets\`
- `artifacts\`
- `src\**\bin\`
- `src\**\obj\`
- `*.zip`
- `.git\`
- `.vscode\`
- `Thumbs.db`
- `Desktop.ini`
- local desktop shortcuts such as `codex.lnk`
- local backup folders such as `codex-switcher-backups\`

Do not publish any file that contains real API keys, private URLs, local error logs, local machine paths, or personal test data.
