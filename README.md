# VS Code Copilot Resource Sync Scripts

A collection of PowerShell scripts to automatically sync, combine, and publish [GitHub Copilot](https://github.com/features/copilot) resources from the [awesome-copilot](https://github.com/github/awesome-copilot) community repository to your local VS Code profiles.

## 🎯 What This Does

These scripts automate the management of VS Code Copilot custom agents, instructions, skills, hooks, and workflows from the [awesome-copilot](https://github.com/github/awesome-copilot) community repository:

1. **Syncing** all resources from the awesome-copilot GitHub repository to a local cache
2. **Publishing globally** — agents to VS Code's user agents folder (available in all workspaces), skills to `~/.copilot/skills/`
3. **Initialising repos** — interactively adding agents, instructions, hooks and agentic workflows to a specific repo's `.github/` folder
4. **Automating** the sync + publish cycle via Windows Task Scheduler

### What goes where

| Resource | Scope | Location |
|---|---|---|
| **Agents** | 🌐 Global | `%APPDATA%\Code\User\prompts\` — available in Copilot Chat across all workspaces |
| **Skills** | 🌐 Global | `~/.copilot/skills/` — loaded on-demand by Copilot coding agent & CLI |
| **Instructions** | 📁 Per-repo | `.github/instructions/` — chosen via `scripts/init-repo.ps1` |
| **Hooks** | 📁 Per-repo | `.github/hooks/<name>/` — chosen via `scripts/init-repo.ps1` |
| **Workflows** | 📁 Per-repo | `.github/workflows/` — chosen via `scripts/init-repo.ps1` |

## 📋 Prerequisites

- **Windows** with PowerShell 7+ ([Download here](https://github.com/PowerShell/PowerShell/releases))
- **VS Code** with GitHub Copilot extension installed
- **`gh` (GitHub CLI) or `git`** — `gh` is preferred ([Download here](https://cli.github.com/)); handles auth automatically
- **Internet connection** for GitHub access
- **Administrator privileges** (for creating scheduled tasks)

## 🚀 Quick Start

### 1. Clone or Download

```powershell
# Clone this repository
git clone <your-repo-url>
cd vscode-copilot-sync
```

### 2. Run the Configurator

For first-time setup or an on-demand refresh, `configure.ps1` chains all steps:

```powershell
# Sync from GitHub, publish globally, and optionally init your repo
.\configure.ps1

# Or step by step:
.\configure.ps1 -SkipInit                 # sync + publish only
.\configure.ps1 -InstallTask              # sync + publish + install scheduled task
.\configure.ps1 -DryRun                   # preview everything
```

### 3. Initialise a Repo (optional, interactive)

> **Note:** `configure.ps1` also prompts for this step automatically — you only need to run it directly for a targeted repo setup.

```powershell
# Run from inside any repo to add instructions/hooks/workflows
cd C:\Projects\my-app
.\scripts\init-repo.ps1

# Or specify the path explicitly
.\scripts\init-repo.ps1 -RepoPath "C:\Projects\my-app"
```

A selection UI will appear for each category (Out-GridView on Windows, or a numbered console menu). Items already installed in the repo are marked with `[*]`.

### 4. Install Automated Sync (Optional)

```powershell
# Install a scheduled task that syncs + publishes globally every 4 hours
.\configure.ps1 -InstallTask

# Customize the interval (re-run to overwrite; configure.ps1 prompts before replacing)
.\configure.ps1 -InstallTask -Every "2h"   # Every 2 hours
.\configure.ps1 -InstallTask -Every "30m"  # Every 30 minutes

# Or run it directly (called internally by configure.ps1)
.\scripts\install-scheduled-task.ps1 -Every "2h"
```

## 📁 What Gets Created

```
$HOME\.awesome-copilot\          # Local cache (git sparse clone)
├── .git\                        # Git metadata (managed automatically)
├── agents\                      # Custom agents (.agent.md)
├── instructions\                # Custom instructions (.instructions.md)
├── workflows\                   # Agentic workflow definitions
├── hooks\                       # Automated hooks (with .json + .sh scripts)
│   └── <hook-name>\
├── skills\                      # Skill packages
│   └── <skill-name>\
│       └── SKILL.md
└── manifest.json                # Sync state tracking

%APPDATA%\Code\User\
└── prompts\                     # Junction → ~/.awesome-copilot/agents/
```

## 📜 Scripts Overview

### `configure.ps1`
Main entry point at the repo root. Chains sync → publish → init-repo in one command, and can install/uninstall the scheduled task via `-InstallTask` / `-UninstallTask` / `-Every` switches.

**Features:**
- Shows last sync time from the local cache manifest before running
- Runs each step in sequence; any step can be skipped independently
- Prompts before running `scripts/init-repo.ps1` (with option to skip via `-SkipInit`)
- `-DryRun` passes through to all child scripts
- `-InstallTask` / `-UninstallTask` delegate to `scripts/install-scheduled-task.ps1` / `scripts/uninstall-scheduled-task.ps1`
- `-Every` sets the scheduled task interval (e.g. `"2h"`, `"30m"`)

**Usage:**
```powershell
# Full update: sync + publish + prompt for init-repo
.\configure.ps1

# Sync + publish only
.\configure.ps1 -SkipInit

# Re-publish only (skip sync if cache is already fresh)
.\configure.ps1 -SkipSync -SkipInit

# Preview without writing any files
.\configure.ps1 -DryRun

# Install scheduled task
.\configure.ps1 -SkipSync -SkipPublish -InstallTask -Every "2h"
```

---

### `scripts/sync-awesome-copilot.ps1`
Syncs resources from the awesome-copilot GitHub repository using a sparse git clone.

**Features:**
- Clones `github/awesome-copilot` with sparse checkout (first run) — only downloads the categories you need
- Pulls updates on subsequent runs — git transfers only the diff, making updates near-instant
- SHA256 hash-based change detection against previous manifest (added/updated/unchanged/removed counts)
- Prefers `gh` (GitHub CLI) for automatic auth; falls back to `git`
- Automatically migrates from the old API-based cache if detected

**Usage:**
```powershell
.\scripts\sync-awesome-copilot.ps1

# Dry-run: show what would change without writing files
.\scripts\sync-awesome-copilot.ps1 -Plan

# Sync specific categories only
.\scripts\sync-awesome-copilot.ps1 -Categories "agents,instructions"

# Force a specific tool
.\scripts\sync-awesome-copilot.ps1 -GitTool git
```

Syncs these categories by default: `agents`, `instructions`, `workflows`, `hooks`, `skills`.
Add `plugins` or `cookbook` explicitly via `-Categories` for those larger opt-in collections.

---

### `scripts/publish-global.ps1`
Publishes agents globally to VS Code and skills to `~/.copilot/skills/`.

**Features:**
- Creates a junction/symlink from VS Code's user agents folder to the local cache (no re-running needed after each sync)
- Incrementally copies skills to `~/.copilot/skills/`
- Dry-run mode for previewing changes
- Individual skip flags for each resource type

**Usage:**
```powershell
.\scripts\publish-global.ps1

# Preview changes without applying
.\scripts\publish-global.ps1 -DryRun

# Skills only (agents already published)
.\scripts\publish-global.ps1 -SkipAgents

# Custom target path (e.g. named VS Code profile)
.\scripts\publish-global.ps1 -AgentsTarget "$env:APPDATA\Code\User\profiles\Work\prompts"
```

---

### `scripts/init-repo.ps1`
Interactively initialises a repository with agents, instructions, hooks, and agentic workflows.

**Features:**
- Auto-detects language/framework from repo file signals and pre-marks recommendations with ★ in the picker
- Prompts for intent (language, project type, concerns) for new/empty repos
- Presents available resources in a selection UI (Out-GridView on Windows, with `-- none / skip --` row to prevent accidental installs)
- Falls back to a numbered console menu where Out-GridView is unavailable
- Copies selected items to the correct `.github/` subfolder
- Marks already-installed items so you can see what's new
- Dry-run mode for previewing

**Usage:**
```powershell
# Run inside a repo (uses current directory)
.\scripts\init-repo.ps1

# Target a specific repo
.\scripts\init-repo.ps1 -RepoPath "C:\Projects\my-app"

# Preview without writing any files
.\scripts\init-repo.ps1 -DryRun

# Skip categories you don't need
.\scripts\init-repo.ps1 -SkipHooks -SkipWorkflows

# Non-interactive: specify items by name
.\scripts\init-repo.ps1 -Agents "devops-expert,se-security-reviewer" -Instructions "powershell"
```

### `scripts/install-scheduled-task.ps1`
Creates a Windows scheduled task for automatic syncing and global publishing. Called internally by `configure.ps1 -InstallTask`.

**Features:**
- Runs `sync-awesome-copilot.ps1` then `publish-global.ps1` on a schedule
- Default: every 4 hours
- Customizable interval via `-Every`

**Usage:**
```powershell
# Recommended: use configure.ps1 (prompts before overwriting an existing task)
.\configure.ps1 -InstallTask
.\configure.ps1 -InstallTask -Every "2h"

# Or run directly
.\scripts\install-scheduled-task.ps1

# Custom intervals (supports h = hours, m = minutes)
.\scripts\install-scheduled-task.ps1 -Every "2h"   # Every 2 hours
.\scripts\install-scheduled-task.ps1 -Every "30m"  # Every 30 minutes

# Check task status
Get-ScheduledTask -TaskName "AwesomeCopilotSync"
```

### `scripts/uninstall-scheduled-task.ps1`
Removes the scheduled task. Called internally by `configure.ps1 -UninstallTask`.

**Usage:**
```powershell
# Recommended: use configure.ps1
.\configure.ps1 -UninstallTask

# Or run directly
.\scripts\uninstall-scheduled-task.ps1
```

## 🔧 Configuration

### Authentication

The sync script uses `gh` (GitHub CLI) by default, which inherits authentication from `gh auth login` — no extra setup needed for most users.

If only `git` is available, the sync targets a public repo (`github/awesome-copilot`) so no credentials are required. For private forks, configure git credentials as usual (`git config credential.helper`).

To force a specific tool:
```powershell
.\scripts\sync-awesome-copilot.ps1 -GitTool git
.\scripts\sync-awesome-copilot.ps1 -GitTool gh
```

### Custom Source Repository

To sync from a fork or alternative repo, edit the two variables near the top of `scripts/sync-awesome-copilot.ps1`:
```powershell
$RepoSlug = 'your-username/your-repo'
$RepoUrl  = 'https://github.com/your-username/your-repo.git'
```

## 🗂️ File Naming Conventions

Resources follow naming patterns for automatic categorization:

- `*.agent.md` — Custom agents
- `*.instructions.md` — Custom instructions
- `SKILL.md` (inside a named subdirectory) — Skills
- Hook and workflow directories contain a mix of `.md`, `.json`, and `.sh` files

## 🛠️ Troubleshooting

### Scripts Not Running
```powershell
# Check PowerShell version (must be 7+)
$PSVersionTable.PSVersion

# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Junction/Symlink Fails
Scripts automatically fall back to copying files. Check logs for details.

### Scheduled Task Not Running
```powershell
# Check task status
Get-ScheduledTask -TaskName "AwesomeCopilotSync" | Get-ScheduledTaskInfo

# View logs
Get-Content ".\scripts\logs\sync-*.log" | Select-Object -Last 50

# Manually run task
Start-ScheduledTask -TaskName "AwesomeCopilotSync"
```

### Files Not Appearing in VS Code
1. Restart VS Code
2. Check VS Code profile is correct: `Ctrl+Shift+P` → "Preferences: Show Profiles"
3. Verify files exist in `%APPDATA%\Code\User\prompts\`

## 📊 Logs

Sync logs are always written to `scripts/logs/` (next to the script itself, regardless of where you invoke it from):
```powershell
# View latest sync log
Get-ChildItem .\scripts\logs\sync-*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content
```

Log format: `sync-YYYYMMDD-HHMMSS.log`

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test your changes thoroughly
4. Submit a pull request

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details

## 🙏 Acknowledgments

- [awesome-copilot](https://github.com/github/awesome-copilot) - Community resource repository
- [GitHub Copilot](https://github.com/features/copilot) - AI pair programmer

## ⚠️ Disclaimer

These scripts are community-maintained and not officially supported by GitHub or Microsoft. Use at your own risk. Always review synced content before using in production environments.

---

**Made with ❤️ for the VS Code + Copilot community**
