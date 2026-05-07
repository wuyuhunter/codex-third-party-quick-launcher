# Project Structure

`CodexQuickLauncher-Windows-v0.3.13-availability-button-label` is organized as a small portable Windows package.

## Required

- `Codex 便捷启动器.exe`: double-click entry for ordinary users. It opens the PowerShell launcher in `tools`.
- `tools/`: application scripts. This is the actual source code for installer, launcher UI, provider management, connectivity tests, and Codex argument wiring.
- `src/launcher/`: C# source for the small Windows exe wrapper.
- `codex-quick-launcher.portable`: marker file. It tells the scripts to store runtime config in this folder instead of the user's global OMX directory.
- `state/codex-quick-launcher-config.example.json`: safe example config without real keys.

## Runtime

These paths are created or updated after use and should not be published with real data:

- `state/codex-quick-launcher-config.json`: the only active program config file. It may contain API keys.
- `logs/`: launcher logs.
- `secrets/`: legacy/compatibility credential directory. The current config flow does not require it.

## Documentation

- `README.md`: user-facing usage and distribution notes.
- `CHANGELOG.md`: version history mapped to the new `0.x` product line.
- `LICENSE`: MIT license text.
- `LICENSE.zh-CN.md`: unofficial Simplified Chinese reference translation. The English `LICENSE` remains the legal license text.
- `SUPPORT.md`: support and contact information.
- `SECURITY.md`: publishing and credential handling policy.
- `.gitignore`: keeps local keys, logs, and legacy sensitive files out of Git.
