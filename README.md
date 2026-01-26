# .github — Repository defaults and community files

This folder contains the default community files, workflow definitions, and automation used across this repository. It is intended to act as an authoritative baseline and be easily forked or copied for other repositories.

Key contents:
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SUPPORT.md`, `SECURITY.md` — community & governance
- `CODEOWNERS` — ownership
- `.github/workflows/` — GitHub Actions workflows for CI, security, and automation
- `ISSUE_TEMPLATE/` and `PULL_REQUEST_TEMPLATE.md` — Issue and PR templates

Notes:
- This repository uses secure defaults (least privilege for workflows, explicit triggers, and reproducible automation).
- **Sensitive values should be stored in GitHub Secrets; do not commit private keys or credentials.**
- Customize placeholders such as `@ZBH33` and the maintainer email (`zbillman.work@gmail.com`) before relying on this in production.

