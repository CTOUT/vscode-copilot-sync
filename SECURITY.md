# Security Policy

## Supported Versions

vscode-copilot-sync follows [Semantic Versioning](https://semver.org/). Security fixes are applied to the `main` branch only. There are no separate maintenance branches at this time.

| Version         | Supported |
| --------------- | --------- |
| `main` (latest) | Yes       |
| Older releases  | No        |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Open a [GitHub Security Advisory](https://github.com/CTOUT/vscode-copilot-sync/security/advisories/new) or email **[security@ctout.dev](mailto:security@ctout.dev)**.

Include in your report:

- A description of the vulnerability and its potential impact
- Steps to reproduce or a proof-of-concept
- Any suggested mitigations if you have them

You can expect:

- Acknowledgement within **48 hours**
- A status update within **7 days**
- Credit in the release notes if you would like it

We ask that you give us reasonable time to address the issue before any public disclosure.

## Scope

This repository contains:

- PowerShell scripts (`configure.ps1`, `scripts/*.ps1`) that clone/pull from [github/awesome-copilot](https://github.com/github/awesome-copilot) and write files into a target repository's `.github/` folder and the VS Code user prompts directory
- No agent definitions, installer one-liners, or release workflows at this time

Vulnerabilities in any of these are in scope. Areas of particular interest:

- **Remote content execution**: the sync scripts fetch file content from a third-party repository and write it directly to your local filesystem. A compromised upstream repository could introduce malicious instruction, agent, or workflow files.
- **Path traversal**: filenames sourced from the upstream repository are used to construct destination paths. A crafted filename (e.g. `../../evil.ps1`) could write outside the intended `.github/` or prompts directory.
- **`gh` / `git` invocations**: the scripts shell out to `gh` or `git`. Ensure neither is replaced with a malicious binary on your `PATH`.
- **VS Code user prompts directory**: files written to `%APPDATA%\Code\User\prompts\` (or the platform equivalent) are picked up by GitHub Copilot for all repositories. A malicious file installed here has broad impact.

## Script Security Notes

- All destination paths are resolved with `Resolve-Path` / `Join-Path` and validated to remain within the intended base directory before writing.
- The scripts do **not** execute any of the content they download — they copy files only.
- A `-DryRun` / `-Plan` flag is available on all scripts to preview changes without writing any files:

  ```powershell
  .\configure.ps1 -DryRun
  .\scripts\sync-awesome-copilot.ps1 -Plan
  ```

- A mass-removal safety check is built into `sync-awesome-copilot.ps1` to prevent a sudden large-scale deletion of local files being applied silently. Pass `-Force` only if you have verified the upstream change is intentional.

## Verifying Upstream Content

Because the scripts pull directly from `github/awesome-copilot`, we recommend:

1. Pin the sync to a specific commit or tag using the `-Ref` parameter (where supported) rather than always tracking `main`.
2. Review the diff of any newly synced files before installing them into a repository:

   ```powershell
   # Preview what would be installed without writing anything
   .\configure.ps1 -DryRun
   ```

3. Inspect newly downloaded files in `~/.awesome-copilot/` before running `init-repo.ps1` or `init-user.ps1`.
