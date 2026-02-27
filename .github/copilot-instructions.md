# Copilot Instructions

This repository contains PowerShell scripts that sync Copilot resources from [github/awesome-copilot](https://github.com/github/awesome-copilot) to a local machine and distribute them to the right VS Code/Copilot locations.

## Script Workflow

Scripts are designed to be run in this order:

```
sync-awesome-copilot.ps1       # 1. Fetch from GitHub API → ~/.awesome-copilot/
publish-global.ps1             # 2. Publish agents + skills globally
init-repo.ps1                  # 3. Interactive per-repo setup → .github/
install-scheduled-task.ps1     # 4. Automate steps 1+2 on a schedule
```

**Resource scopes:**
- **Global** (machine-wide): Agents → `%APPDATA%\Code\User\prompts\`; Skills → `~/.copilot/skills/`
- **Per-repo** (committed to `.github/`): Instructions, Hooks, Workflows

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

- **GitHub API**: `https://api.github.com/repos/github/awesome-copilot/contents/{category}`
- **`$env:GITHUB_TOKEN`** (optional): raises rate limit from 60 → 5000 req/hr. Set this when running the sync script manually or via scheduled task to avoid 403 errors.
- **`Out-GridView`**: used in `init-repo.ps1` for interactive picking; automatically falls back to a numbered console menu if unavailable.

## Local Cache Structure

`sync-awesome-copilot.ps1` writes to `~/.awesome-copilot/`:
```
~/.awesome-copilot/
  agents/          *.agent.md
  instructions/    *.instructions.md
  workflows/       *.md
  hooks/           <hook-name>/ (directories)
  skills/          <skill-name>/ (directories)
  manifest.json    tracks hashes/SHAs from last sync
  last-success.json integrity marker
  backups/         pre-delete zip snapshots (last 5 kept)
  logs/            sync-<timestamp>.log (14 day retention)
```

## Scheduled Task

`install-scheduled-task.ps1` chains `sync-awesome-copilot.ps1 → publish-global.ps1` and registers a Windows Scheduled Task named `AwesomeCopilotSync`. The task runs under the current user context — the user must be logged in for it to execute.

## Contributing

- Update `CHANGELOG.md` with every change under the appropriate version
- Test with `-DryRun` / `-Plan` before running live
- Run `sync-awesome-copilot.ps1 -Plan` to verify without writing files
- New parameters must follow the existing `[switch]$Skip*` / `[string]$Target` naming conventions
- See `CONTRIBUTING.md` for the full PR checklist
