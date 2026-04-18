# Copilot Instructions

This repository contains PowerShell scripts that sync Copilot resources from [github/awesome-copilot](https://github.com/github/awesome-copilot) to a local machine and distribute them to the right VS Code/Copilot locations.

## Script Workflow

Scripts are designed to be run in this order:

```text
configure.ps1                      # Main entry point (chains all steps)
scripts/sync-awesome-copilot.ps1   # 1. Clone/pull github/awesome-copilot → ~/.awesome-copilot/
scripts/init-user.ps1              # 2. User-level resources → prompts\ and ~/.copilot/skills/
scripts/init-repo.ps1              # 3. Interactive per-repo setup → .github/
```

**Resource scopes:**

- **User-level** (all VS Code sessions, no .github/ needed): Agents + Instructions → `%APPDATA%\Code\User\prompts\`; Skills → `~/.copilot/skills/`
- **Per-repo** (committed to `.github/`): Agents, Instructions, Hooks, Workflows, Skills

## Key Conventions

### Error Handling

All scripts use `$ErrorActionPreference = 'Stop'` so errors terminate rather than prompt. Use `try/catch` blocks for recoverable errors — do not rely on error preference for expected failure paths.

### Logging

Use the `Log` / `Write-Log` function (not `Write-Host` directly):

```powershell
Log "Message here"           # INFO (Cyan)
Log "Something wrong" 'WARN' # Yellow
Log "Done!" 'SUCCESS'        # Green
Log "Failed" 'ERROR'         # Red
```

### Dry-Run Pattern

Every destructive operation must be guarded by `$DryRun`:

```powershell
if ($DryRun) { Log "[DryRun] Would do X"; return 'would-copy' }
# actual operation here
```

### Change Detection

Always use SHA256 hash comparison before copying — never overwrite blindly:

```powershell
$srcHash = (Get-FileHash $Src -Algorithm SHA256).Hash
$dstHash = if (Test-Path $dest) { (Get-FileHash $dest -Algorithm SHA256).Hash } else { $null }
if ($srcHash -eq $dstHash) { return 'unchanged' }
```

### Portable Paths

Always use `$HOME`, `$env:APPDATA`, and `Join-Path` — never hardcode user paths:

```powershell
# ✅
$cacheDir = Join-Path $HOME '.awesome-copilot'
# ❌
$cacheDir = 'C:\Users\Someone\.awesome-copilot'
```

### Parameter Patterns

- `-DryRun` / `-Plan` — preview without writing
- `-Skip*` switches (e.g. `-SkipAgents`, `-SkipHooks`) — granular opt-out
- Comma-separated strings for lists: `[string]$Categories = 'agents,instructions,workflows,hooks,skills'`
- Default paths always use `$HOME` or `$env:APPDATA`

## External Dependencies

- **`gh` (GitHub CLI)**: preferred tool for cloning/pulling `github/awesome-copilot`; handles authentication automatically via `gh auth login`. Falls back to `git` if `gh` is not available.
- **`Out-GridView`**: used in `init-repo.ps1` and `init-user.ps1` for interactive picking; automatically falls back to a numbered console menu if unavailable.

## Local Cache Structure

`sync-awesome-copilot.ps1` writes to `~/.awesome-copilot/` (a sparse git clone):

```text
~/.awesome-copilot/
  .git/            git metadata (managed automatically)
  agents/          *.agent.md
  instructions/    *.instructions.md
  workflows/       *.md
  hooks/           <hook-name>/ (directories)
  skills/          <skill-name>/ (directories)
  manifest.json    file inventory with hashes (written after each sync)
  status.txt       human-readable summary of last sync run
```

Sync logs are written to `scripts/logs/sync-YYYYMMDD-HHMMSS.log` (always relative to the script's own directory via `$PSScriptRoot`).

## Contributing

- Update `CHANGELOG.md` with every change under the appropriate version
- Test with `-DryRun` / `-Plan` before running live
- Run `sync-awesome-copilot.ps1 -Plan` to verify without writing files
- New parameters must follow the existing `[switch]$Skip*` / `[string]$Target` naming conventions
- See `CONTRIBUTING.md` for the full PR checklist
