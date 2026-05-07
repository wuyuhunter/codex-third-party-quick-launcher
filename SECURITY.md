# Security Policy

## Sensitive Files

Do not commit real runtime configuration or credentials.

Keep these paths out of GitHub releases and source commits:

- `state/codex-quick-launcher-config.json`
- `logs/`
- `secrets/`
- any copied `auth.json`
- any file containing API keys, bearer tokens, provider secrets, or private base URLs

The repository includes only `state/codex-quick-launcher-config.example.json`, which is a safe example without real keys.

## Before Publishing

Run a secret scan before every public upload. At minimum, check for `sk-` style keys, local-only paths, and private coordination files.

If a real key is committed by mistake, revoke that key immediately and rewrite the public history before sharing the repository.

## Reporting

For security-sensitive reports, use the contact channel listed in `SUPPORT.md`.
