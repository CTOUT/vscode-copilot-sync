# VS Code Copilot Resource Sync Scripts

A collection of PowerShell scripts to automatically sync, combine, and publish [GitHub Copilot](https://github.com/features/copilot) resources from the [awesome-copilot](https://github.com/mdundek/awesome-copilot) community repository to your local VS Code profiles.

## 🎯 What This Does

These scripts automate the management of VS Code Copilot custom instructions, chat modes, prompts, and collections by:

1. **Syncing** resources from the awesome-copilot GitHub repository
2. **Combining** multiple resource categories into a unified structure
3. **Publishing** to your VS Code profile(s) via symbolic links or file copies
4. **Normalizing** file organization to prevent duplicates
5. **Automating** the entire process via Windows Task Scheduler

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

### 2. Run Initial Sync

```powershell
# Sync resources from GitHub
.\sync-awesome-copilot.ps1

# Combine resources into unified folder
.\combine-and-publish-prompts.ps1
```

### 3. Install Automated Sync (Optional)

```powershell
# Install scheduled task (runs every 4 hours by default)
.\install-scheduled-task.ps1

# Or customize the interval
.\install-scheduled-task.ps1 -Interval "2h"  # Every 2 hours
.\install-scheduled-task.ps1 -Interval "1d"  # Once daily
```

## 📁 What Gets Created

```
$HOME\.awesome-copilot\          # Local cache
├── chatmodes\                   # Chat mode definitions
├── instructions\                # Custom instructions
├── prompts\                     # Prompt templates
├── collections\                 # Resource collections
├── combined\                    # Unified resources (all categories)
└── manifest.json                # Sync state tracking

%APPDATA%\Code\User\             # VS Code global config
└── prompts\                     # Junction/symlink to combined folder

%APPDATA%\Code\User\profiles\    # VS Code profiles
└── <profile-name>\
    ├── chatmodes\               # Linked/copied resources
    ├── instructions\
    └── prompts\
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

**Environment Variables:**
- `GITHUB_TOKEN` (optional) - Personal access token for higher API rate limits

---

### `combine-and-publish-prompts.ps1`
Combines resources from all categories into a unified folder and publishes to VS Code.

**Features:**
- Merges chatmodes, instructions, and prompts into single directory
- Creates junction/symlink to VS Code prompts directory
- Automatic fallback to file copy if linking fails
- Preserves user-created custom files

**Usage:**
```powershell
.\combine-and-publish-prompts.ps1

# Publish to specific profile
.\combine-and-publish-prompts.ps1 -ProfileName "MyProfile"

# Publish to global VS Code config only
.\combine-and-publish-prompts.ps1 -GlobalOnly
```

---

### `publish-to-vscode-profile.ps1`
Publishes resources to VS Code profile(s) via symbolic links or copies.

**Features:**
- Creates symbolic links (junctions) for efficient syncing
- Automatic fallback to file copy
- Supports multiple profiles or global config

**Usage:**
```powershell
.\publish-to-vscode-profile.ps1

# Publish to specific profile
.\publish-to-vscode-profile.ps1 -ProfileName "Work"

# Publish to global config
.\publish-to-vscode-profile.ps1 -GlobalOnly
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

# Normalize specific profile
.\normalize-copilot-folders.ps1 -ProfileName "MyProfile"
```

---

### `install-scheduled-task.ps1`
Creates a Windows scheduled task for automatic syncing.

**Features:**
- Runs sync and combine scripts on a schedule
- Default: every 4 hours
- Customizable interval
- Runs as current user (no SYSTEM account needed)

**Usage:**
```powershell
# Install with default 4-hour interval
.\install-scheduled-task.ps1

# Custom intervals
.\install-scheduled-task.ps1 -Interval "2h"   # Every 2 hours
.\install-scheduled-task.ps1 -Interval "30m"  # Every 30 minutes
.\install-scheduled-task.ps1 -Interval "1d"   # Once daily

# Check task status
Get-ScheduledTask -TaskName "AwesomeCopilotSync"
```

**Interval Format:**
- `30m` - Minutes
- `2h` - Hours
- `1d` - Days

---

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

By default, scripts sync from `mdundek/awesome-copilot`. To use a different source:

Edit `sync-awesome-copilot.ps1` line 7:
```powershell
$Owner = "your-username"
$Repo = "your-repo"
```

## 🗂️ File Naming Conventions

Resources follow naming patterns for automatic categorization:

- `*.chatmode.md` - Chat mode definitions
- `*.instructions.md` - Custom instructions
- `*.prompt.md` - Prompt templates
- `*.collection.yml` - Resource collections

Files without these suffixes in the combined folder are preserved (assumed to be user-created).

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

- [awesome-copilot](https://github.com/mdundek/awesome-copilot) - Community resource repository
- [GitHub Copilot](https://github.com/features/copilot) - AI pair programmer

## ⚠️ Disclaimer

These scripts are community-maintained and not officially supported by GitHub or Microsoft. Use at your own risk. Always review synced content before using in production environments.

---

**Made with ❤️ for the VS Code + Copilot community**
