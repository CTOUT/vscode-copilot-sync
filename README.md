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
| **Instructions** | 📁 Per-repo | `.github/instructions/` — chosen via `init-repo.ps1` |
| **Hooks** | 📁 Per-repo | `.github/hooks/<name>/` — chosen via `init-repo.ps1` |
| **Workflows** | 📁 Per-repo | `.github/workflows/` — chosen via `init-repo.ps1` |

## 📋 Prerequisites

- **Windows** with PowerShell 7+ ([Download here](https://github.com/PowerShell/PowerShell/releases))
- **VS Code** with GitHub Copilot extension installed
- **Internet connection** for GitHub API access
- **Administrator privileges** (for creating scheduled tasks)

## 🚀 Quick Start

### 1. Clone or Download

```powershell
# Clone this repository
git clone <your-repo-url>
cd scripts
```

### 2. Publish Agents and Skills Globally

```powershell
# Publish agents to VS Code + skills to ~/.copilot/skills/
.\publish-global.ps1
```

### 3. Initialise a Repo (optional, interactive)

```powershell
# Run from inside any repo to add instructions/hooks/workflows
cd C:\Projects\my-app
.\init-repo.ps1

# Or specify the path explicitly
.\init-repo.ps1 -RepoPath "C:\Projects\my-app"
```

A selection UI will appear for each category (Out-GridView on Windows, or a numbered console menu). Items already installed in the repo are marked with `[*]`.

### 4. Install Automated Sync (Optional)

```powershell
# Install a scheduled task that syncs + publishes globally every 4 hours
.\install-scheduled-task.ps1

# Skip the publish-global step if you manage that manually
.\install-scheduled-task.ps1 -SkipPublishGlobal

# Also include plugins (opt-in — large download)
.\install-scheduled-task.ps1 -IncludePlugins

# Or customize the interval
.\install-scheduled-task.ps1 -Every "2h"  # Every 2 hours
.\install-scheduled-task.ps1 -Every "30m" # Every 30 minutes
```

## 📁 What Gets Created

```
$HOME\.awesome-copilot\          # Local cache
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

### `sync-awesome-copilot.ps1`
Syncs resources from the awesome-copilot GitHub repository.

**Features:**
- Downloads latest resources via GitHub API
- SHA256 hash-based change detection
- Incremental updates (only downloads changed files)
- Manifest tracking for sync state
- Optional GITHUB_TOKEN support for higher rate limits

**Usage:**
```powershell
.\sync-awesome-copilot.ps1
```

Syncs these categories by default: `agents`, `instructions`, `workflows`, `hooks`, `skills`.
Add `plugins` or `cookbook` explicitly via `-Categories` for those larger opt-in collections.

**Environment Variables:**
- `GITHUB_TOKEN` (optional) - Personal access token for higher API rate limits

---

### `publish-global.ps1`
Publishes agents globally to VS Code and skills to `~/.copilot/skills/`.

**Features:**
- Creates a junction/symlink from VS Code's user agents folder to the local cache (no re-running needed after each sync)
- Incrementally copies skills to `~/.copilot/skills/`
- Dry-run mode for previewing changes
- Individual skip flags for each resource type

**Usage:**
```powershell
.\publish-global.ps1

# Preview changes without applying
.\publish-global.ps1 -DryRun

# Skills only (agents already published)
.\publish-global.ps1 -SkipAgents

# Custom target path (e.g. named VS Code profile)
.\publish-global.ps1 -AgentsTarget "$env:APPDATA\Code\User\profiles\Work\prompts"
```

---

### `init-repo.ps1`
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
.\init-repo.ps1

# Target a specific repo
.\init-repo.ps1 -RepoPath "C:\Projects\my-app"

# Preview without writing any files
.\init-repo.ps1 -DryRun

# Skip categories you don't need
.\init-repo.ps1 -SkipHooks -SkipWorkflows

# Non-interactive: specify items by name
.\init-repo.ps1 -Agents "devops-expert,se-security-reviewer" -Instructions "powershell"
```

---

### `normalize-copilot-folders.ps1`
Cleans up misplaced or duplicated files in VS Code directories.

**Features:**
- Moves files to correct category folders based on suffix
- Removes duplicate files (keeps newest version)
- Handles renamed copies (file.1.md, chatmodes__file.md)

**Usage:**
```powershell
.\normalize-copilot-folders.ps1

# Normalize a specific profile root
.\normalize-copilot-folders.ps1 -ProfileRoot "C:\Users\me\AppData\Roaming\Code\User\profiles\abc123" -NoDryRun

# Normalize all profiles (dry run)
.\normalize-copilot-folders.ps1 -AllProfiles

# Apply across all profiles
.\normalize-copilot-folders.ps1 -AllProfiles -NoDryRun
```

---

### `install-scheduled-task.ps1`
Creates a Windows scheduled task for automatic syncing and global publishing.

**Features:**
- Runs `sync-awesome-copilot.ps1` then `publish-global.ps1` on a schedule
- Default: every 6 hours
- Customizable interval

**Usage:**
```powershell
# Install with defaults (sync + publish-global every 4 hours)
.\install-scheduled-task.ps1

# Custom intervals (supports h = hours, m = minutes)
.\install-scheduled-task.ps1 -Every "2h"   # Every 2 hours
.\install-scheduled-task.ps1 -Every "30m"  # Every 30 minutes

# Sync only (skip publish-global)
.\install-scheduled-task.ps1 -SkipPublishGlobal

# Check task status
Get-ScheduledTask -TaskName "AwesomeCopilotSync"
```

### `uninstall-scheduled-task.ps1`
Removes the scheduled task.

**Usage:**
```powershell
.\uninstall-scheduled-task.ps1
```

## 🔧 Configuration

### GitHub Rate Limits

Without authentication, GitHub API allows 60 requests/hour. For heavy usage:

1. Create a [Personal Access Token](https://github.com/settings/tokens) (no scopes needed for public repos)
2. Set environment variable:

```powershell
# Temporary (current session)
$env:GITHUB_TOKEN = "ghp_your_token_here"

# Permanent (user environment)
[Environment]::SetEnvironmentVariable("GITHUB_TOKEN", "ghp_your_token_here", "User")
```

### Custom Source Repository

By default, scripts sync from `github/awesome-copilot`. To use a different source:

Edit `sync-awesome-copilot.ps1` line 57:
```powershell
$Repo = "your-username/your-repo"
```

## 🗂️ File Naming Conventions

Resources follow naming patterns for automatic categorization:

- `*.agent.md` - Custom agents
- `*.instructions.md` - Custom instructions
- `*.chatmode.md` - Chat mode definitions (legacy)
- `*.prompt.md` - Prompt templates (legacy)

Files without these suffixes in the combined folder are preserved (assumed to be user-created).
Skills and hooks are directory-based packages and are not combined into the prompts folder.

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
Get-Content "$HOME\.awesome-copilot\logs\sync-*.log" -Tail 50

# Manually run task
Start-ScheduledTask -TaskName "AwesomeCopilotSync"
```

### Files Not Appearing in VS Code
1. Restart VS Code
2. Check VS Code profile is correct: `Ctrl+Shift+P` → "Preferences: Show Profiles"
3. Verify files exist in `%APPDATA%\Code\User\prompts\`

## 📊 Logs

Sync logs are stored in `$HOME\.awesome-copilot\logs\`:
```powershell
# View latest sync log
Get-Content "$HOME\.awesome-copilot\logs\sync-*.log" -Tail 20
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
