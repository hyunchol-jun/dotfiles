---
name: security-scan
description: Run security scanning tools appropriate to the project
---

Run security scans appropriate to this project. Detect the ecosystem, run available tools, and summarize findings.

Follow these steps:

1. **Detect the project ecosystem** — check config files to determine the language and package manager (npm/yarn/pnpm, pip/poetry, cargo, go, etc.).

2. **Run dependency audit** — use the appropriate tool for the ecosystem:
   - Node.js → `npm audit` / `yarn audit` / `pnpm audit`
   - Python → `pip-audit` (if installed) or check for known vulnerability databases
   - Rust → `cargo audit` (if installed)
   - Go → `govulncheck ./...` (if installed)
   - Ruby → `bundle audit` (if installed)
   - If the audit tool is not installed, note that and skip rather than installing it.

3. **Run static security analysis** (if tools are available):
   - `semgrep` — run with `--config auto` if installed
   - Python → `bandit -r .` if installed
   - If no SAST tool is available, skip this step and note it in the summary.

4. **Run secret detection** — check for accidentally committed secrets:
   - Use `gitleaks detect --source .` if installed
   - Otherwise, use Grep to search for common patterns: API keys, tokens, passwords in config files, `.env` files committed to git, private keys, hardcoded credentials. Focus on patterns like `AKIA`, `sk-`, `ghp_`, `-----BEGIN.*PRIVATE KEY-----`, `password\s*=\s*['"][^'"]+['"]`.

5. **Summarize findings** — organize results by severity:
   - **Critical/High** — vulnerabilities that need immediate attention
   - **Medium** — issues worth addressing soon
   - **Low/Info** — minor or informational findings
   - **Clean** — explicitly note categories with no findings
   - Include actionable next steps for any issues found (e.g., `npm audit fix`, upgrade specific packages).
