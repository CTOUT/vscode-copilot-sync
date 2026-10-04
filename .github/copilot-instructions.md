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

### Logging & Common Primitives

All shared primitives, path assertions, and logging functions reside in `scripts/lib/Common.ps1`.
Use `Log` or `Write-CopilotLog` (not raw `Write-Host`):

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

### Portable Paths & Boundary Validation

Always use `$HOME`, `$env:APPDATA`, and `Join-Path` — never hardcode user paths. Validate write targets with `Assert-PathWithin`:

```powershell
# ✅
$cacheDir = Join-Path $HOME '.awesome-copilot'
Assert-PathWithin -Path $targetPath -ParentDirectory $baseDir
# ❌
$cacheDir = 'C:\Users\Someone\.awesome-copilot'
```

### Parameter Patterns

- `-DryRun` / `-Plan` — preview without writing
- `-Skip*` switches (e.g. `-SkipAgents`, `-SkipHooks`) — granular opt-out
- Comma-separated strings for lists: `[string]$Categories = 'agents,hooks,instructions,skills,workflows'`
- Default paths always use `$HOME` or `$env:APPDATA`

## External Dependencies

- **`gh` (GitHub CLI)**: preferred tool for cloning/pulling `github/awesome-copilot`; handles authentication automatically via `gh auth login`. Falls back to `git` if `gh` is not available.
- **`Out-GridView`**: used on Windows for GUI picking; automatically alerts the user if backgrounded.
- **`fzf`**: optional terminal fuzzy multi-select picker used automatically on macOS, Linux, and Windows if present on PATH. Falls back to numbered console menu.

## Local Cache Structure

`sync-awesome-copilot.ps1` writes to `~/.awesome-copilot/` (a sparse git clone alongside the curated catalogue):

```text
~/.awesome-copilot/
  .git/            git metadata (managed automatically)
  agents/          *.agent.md
  instructions/    *.instructions.md
  skills/          <skill-name>/ (directories)
  catalogue.json   curated metadata index from llms.txt
  config.json      persistent user configuration
  llms.txt         offline cache of upstream llms.txt
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
