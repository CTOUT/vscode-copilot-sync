# VS Code Copilot Resource Sync

A collection of PowerShell scripts to sync and manage [GitHub Copilot](https://github.com/features/copilot) resources from the [awesome-copilot](https://github.com/github/awesome-copilot) community repository — cherry-picking exactly what each repo needs into `.github/`.

## 🎯 What This Does

1. **Syncs** the latest agents, instructions, hooks, workflows, and skills from [awesome-copilot](https://github.com/github/awesome-copilot) into a local cache (`~/.awesome-copilot/`)
2. **Initialises repos** — intelligently recommends and installs resources into a repo's `.github/` folder based on detected language/framework, with full install/update/remove lifecycle management

### What goes where

| Resource         | Location                |
| ---------------- | ----------------------- |
| **Agents**       | `.github/agents/`       |
| **Instructions** | `.github/instructions/` |
| **Hooks**        | `.github/hooks/<name>/` |
| **Workflows**    | `.github/workflows/`    |
| **Skills**       | `.github/skills/`       |

## 📋 Prerequisites

- **Windows** with PowerShell 7+ ([Download](https://github.com/PowerShell/PowerShell/releases))
- **VS Code** with GitHub Copilot extension
- **`gh` (GitHub CLI) or `git`** — `gh` preferred ([Download](https://cli.github.com/)); handles auth automatically
- **Internet connection** for initial sync

## 🚀 Quick Start

### 1. Clone or Download

```powershell
git clone <your-repo-url>
cd vscode-copilot-sync
```

### 2. Run the Configurator

```powershell
# Sync from GitHub and optionally configure your current repo
.\configure.ps1

# Sync + go straight to install pickers (no Y/N prompt)
.\configure.ps1 -Install

# Sync only (no repo setup)
.\configure.ps1 -SkipInit

# Preview everything without writing any files
.\configure.ps1 -DryRun
```

### 3. Configure a Repo

Run from inside any repo to add agents, instructions, hooks, workflows and skills to `.github/`:

```powershell
cd C:\Projects\my-app
.\configure.ps1

# Or target a repo without cd-ing first
.\configure.ps1 -SkipSync -RepoPath "C:\Projects\my-app"

# Or call the script directly
.\scripts\init-repo.ps1
.\scripts\init-repo.ps1 -RepoPath "C:\Projects\my-app"
```

The picker auto-detects your language/framework and marks relevant items with ★. Items already installed show their status:

| Symbol | Meaning                        |
| ------ | ------------------------------ |
| ★      | Recommended for this repo      |
| `[*]`  | Already installed              |
| `[↑]`  | Update available from upstream |
| `[~]`  | Locally modified since install |
| `[!]`  | Requires additional setup (MCP server, API key, etc.) |

### 4. Remove Installed Resources

```powershell
# Interactive removal picker (only shows script-managed files — never user-created ones)
.\configure.ps1 -Uninstall

# Or directly
.\scripts\init-repo.ps1 -Uninstall
```

Locally modified files are flagged with `[~]` before removal so you don't accidentally discard work.

## 📁 Local Cache Structure

```
~/.awesome-copilot/
├── .git/                  # Git metadata (managed automatically)
├── agents/                # *.agent.md
├── instructions/          # *.instructions.md
├── workflows/             # *.md
├── hooks/                 # <hook-name>/ directories
├── skills/                # <skill-name>/ directories
└── manifest.json          # Sync state (hashes, timestamps, counts)
```

## 📜 Scripts

### `configure.ps1` — Main entry point

Chains sync → user-level → repo init in one command.

```powershell
.\configure.ps1                                    # Full run (sync + both prompts)
.\configure.ps1 -Install                          # Sync + go straight to repo pickers
.\configure.ps1 -User                             # Sync + go straight to user-level picker
.\configure.ps1 -SkipInit                         # Sync + user-level only
.\configure.ps1 -SkipUser                         # Sync + repo only
.\configure.ps1 -SkipSync                         # Repo init only (no sync)
.\configure.ps1 -SkipSync -Uninstall              # Remove repo resources
.\configure.ps1 -UninstallUser                    # Remove user-level agents
.\configure.ps1 -RepoPath "C:\Projects\my-app"   # Target specific repo
.\configure.ps1 -DryRun                           # Preview all changes
```

---

### `scripts/sync-awesome-copilot.ps1` — Sync cache

Clones (first run) or pulls (subsequent runs) `github/awesome-copilot` as a sparse git checkout.

- Only downloads the categories you need (`agents`, `instructions`, `workflows`, `hooks`, `skills` by default)
- SHA256 hash manifest tracks added/updated/removed counts across runs
- Auto-recovers from merge conflicts in the local cache
- Prefers `gh` CLI for auth; falls back to `git`

```powershell
.\scripts\sync-awesome-copilot.ps1                          # Sync all categories
.\scripts\sync-awesome-copilot.ps1 -Plan                    # Dry run
.\scripts\sync-awesome-copilot.ps1 -Categories "agents,instructions"
.\scripts\sync-awesome-copilot.ps1 -GitTool git             # Force git
.\scripts\sync-awesome-copilot.ps1 -Force                   # Skip safety checks
```

**Breaking-change detection** — on subsequent syncs the script runs two safety checks and exits before writing the manifest if either triggers:

| Check | Trigger | Action |
| --- | --- | --- |
| Structural | A previously-synced category folder is absent after pull | `STRUCTURAL CHANGE DETECTED` — lists missing folders, exits 1 |
| Mass-removal | ≥ 25 % of tracked files removed in one pull | `MASS-REMOVAL DETECTED` — shows ratio, exits 1 |

Re-run with `-Force` once you have reviewed the upstream changes and confirmed the new structure is intentional.

---

### `scripts/init-repo.ps1` — Configure a repo

Interactively selects and installs Copilot resources into `.github/`.

**Smart recommendations** — scans repo files for language/framework signals (`.cs`, `package.json`, `go.mod`, `Dockerfile`, `.github/workflows/*.yml`, etc.) and pre-marks relevant items with ★. Falls back to an intent questionnaire for empty repos.

**Full lifecycle** — install, update, and remove, all tracked in `.github/.copilot-subscriptions.json`.

```powershell
.\scripts\init-repo.ps1                                     # Interactive
.\scripts\init-repo.ps1 -RepoPath "C:\Projects\my-app"
.\scripts\init-repo.ps1 -DryRun                             # Preview
.\scripts\init-repo.ps1 -Uninstall                          # Remove resources
.\scripts\init-repo.ps1 -SkipHooks -SkipWorkflows           # Skip categories
.\scripts\init-repo.ps1 -Agents "devops-expert,se-security-reviewer" -Instructions "powershell"
```

---

### `scripts/update-repo.ps1` — Apply upstream updates

Reads `.github/.copilot-subscriptions.json` and applies any upstream changes from the local cache to installed resources.

```powershell
.\scripts\update-repo.ps1                    # Interactive — prompts per item
.\scripts\update-repo.ps1 -DryRun           # Show what would change
.\scripts\update-repo.ps1 -Force            # Apply all without prompting
.\scripts\update-repo.ps1 -RepoPath "C:\Projects\my-app"
```

> **Tip:** The `[↑]` column in `init-repo.ps1` shows update availability inline — run `update-repo.ps1` when you want to apply them all at once.

---

### `scripts/init-user.ps1` — Configure user-level agents

Installs agents into VS Code's user-level prompts folder (`%APPDATA%\Code\User\prompts\`), making them available across **all repos and VS Code windows** — no `.github/` needed.

This is ideal for general-purpose agents (e.g. "beastmode" focused modes, code reviewers, rubber-duck agents) that have no meaningful relationship to a specific project's language or stack.

**Full lifecycle** — install, update, and remove, tracked in `~/.awesome-copilot/user-subscriptions.json`.

```powershell
.\scripts\init-user.ps1                              # Interactive
.\scripts\init-user.ps1 -DryRun                      # Preview
.\scripts\init-user.ps1 -Uninstall                   # Remove user-level agents
.\scripts\init-user.ps1 -Agents "beastmode,se-security-reviewer"

# Non-default VS Code installations
.\scripts\init-user.ps1 -PromptsDir "$env:APPDATA\Code - Insiders\User\prompts"
```

---

### `scripts/update-user.ps1` — Apply upstream updates to user-level agents

Reads `~/.awesome-copilot/user-subscriptions.json` and refreshes installed user-level agents from the local cache.

```powershell
.\scripts\update-user.ps1                    # Interactive
.\scripts\update-user.ps1 -DryRun           # Show what would change
.\scripts\update-user.ps1 -Force            # Apply all without prompting
```

## 🔧 Configuration

### Authentication

`gh` CLI is preferred — inherits from `gh auth login`, no extra setup. If only `git` is available, the public `github/awesome-copilot` repo requires no credentials. For private forks, configure git credentials as usual.

### Custom Source Repository

Edit two variables near the top of `scripts/sync-awesome-copilot.ps1`:

```powershell
$RepoSlug = 'your-username/your-fork'
$RepoUrl  = 'https://github.com/your-username/your-fork.git'
```

## 🛠️ Troubleshooting

### Execution policy error

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Sync fails with merge conflict

The script auto-recovers (`git reset --hard origin/HEAD`). If it persists, delete `~/.awesome-copilot` and re-run — it will re-clone fresh.

## 📊 Logs

Sync logs are written to `scripts/logs/sync-YYYYMMDD-HHMMSS.log`:

```powershell
Get-ChildItem .\scripts\logs\sync-*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content
```

## 🤝 Contributing

Contributions welcome! Fork, branch, test, PR.

## 📄 License

MIT — see [LICENSE](LICENSE)

## 🙏 Acknowledgments

- [awesome-copilot](https://github.com/github/awesome-copilot) — Community resource repository
- [GitHub Copilot](https://github.com/features/copilot) — AI pair programmer

---

**Made with ❤️ for the VS Code + Copilot community**
