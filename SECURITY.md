# Security Policy

## Supported Versions

Describe which versions of the project are currently supported with security updates.

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability, please **do not** open a public issue.
Instead, report it privately to the maintainers using one of the following:

- Email: `zbillman.work@gmail.com` (PGP key: `PGP_KEY_ID_PLACEHOLDER` — **no PGP key configured**; to enable encrypted reports, replace `PGP_KEY_ID_PLACEHOLDER` with a PGP key ID)
- GitHub Security Advisories (if enabled): https://github.com/ZBH33/.github/security/advisories

What to include in a report:
- Detailed description of the issue and potential impact
- Reproduction steps and test cases
- A patch or suggested mitigation if available

We will:
- Acknowledge receipt within 72 hours
- Triage and provide an estimated remediation timeline
- Coordinate disclosure with the reporter when fixes are prepared

If you are reporting via email, please encrypt the report using our PGP key (PGP_KEY_ID_PLACEHOLDER). Note: there is currently **no PGP key configured**; to add one, replace `PGP_KEY_ID_PLACEHOLDER` with your key ID (e.g., `0x1234ABCD`).

Security key management:
- **Do not store private keys or other secrets in the repository.**
- If you need to use a private PGP key or other secret for workflow automation, create a repository secret (Settings → Secrets) and name it consistently (recommended names: `PGP_PRIVATE_KEY`, `GPG_PRIVATE_KEY`, `GGSHIELD_API_KEY`, etc.).
- Reference these secrets in workflows. Example (safe): `PGP_PRIVATE_KEY` should be used only as a secret in Actions and never committed to source.

---

*Security contact set to `zbillman.work@gmail.com`. To enable encrypted reporting add your PGP key ID for `PGP_KEY_ID_PLACEHOLDER` and store the private key in a GitHub Secret named `PGP_PRIVATE_KEY`.*
