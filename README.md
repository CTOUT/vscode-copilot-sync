# VS Code Copilot Resource Sync

A PowerShell toolkit to sync, install, and manage [GitHub Copilot](https://github.com/features/copilot) agents, instructions, hooks, skills, and workflows from the [awesome-copilot](https://github.com/github/awesome-copilot) community catalogue — cherry-picking exactly what each repo needs, with full lifecycle management. Works on Windows, macOS, and Linux.

## What This Does

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

## Prerequisites

- **PowerShell 7+** — runs on Windows, macOS, and Linux ([Download PowerShell](https://github.com/PowerShell/PowerShell/releases))
- **VS Code** with GitHub Copilot extension
- **`gh` (GitHub CLI) or `git`** — `gh` preferred ([Download GitHub CLI](https://cli.github.com/)); handles auth automatically
- **Internet connection** for initial sync

> **macOS / Linux:** the scripts are compatible with `pwsh` on all platforms. The one difference is the VS Code user directory path — pass `-PromptsDir` explicitly if `init-user.ps1` cannot locate it automatically:
>
> | Platform | `-PromptsDir` value                               |
> | -------- | ------------------------------------------------- |
> | macOS    | `~/Library/Application Support/Code/User/prompts` |
> | Linux    | `~/.config/Code/User/prompts`                     |
>
> `Out-GridView` is also Windows-only; the scripts fall back to a numbered console menu automatically on macOS and Linux.

## Quick Start

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

| Symbol | Meaning                                               |
| ------ | ----------------------------------------------------- |
| ★      | Recommended for this repo                             |
| `[*]`  | Already installed                                     |
| `[↑]`  | Update available from upstream                        |
| `[~]`  | Locally modified since install                        |
| `[U]`  | Already installed at user level (globally)            |
| `[!]`  | Requires additional setup (MCP server, API key, etc.) |

> **Tip:** `[U]` items are already available everywhere via `init-user.ps1`. You can still install them repo-level if you want them committed to `.github/`.

### 4. Remove Installed Resources

```powershell
# Interactive removal picker (only shows script-managed files — never user-created ones)
.\configure.ps1 -Uninstall

# Or directly
.\scripts\init-repo.ps1 -Uninstall
```

Locally modified files are flagged with `[~]` before removal so you don't accidentally discard work.

## Local Cache Structure

```text
~/.awesome-copilot/
├── .git/                  # Git metadata (managed automatically)
├── agents/                # *.agent.md
├── instructions/          # *.instructions.md
├── workflows/             # *.md
├── hooks/                 # <hook-name>/ directories
├── skills/                # <skill-name>/ directories
└── manifest.json          # Sync state (hashes, timestamps, counts)
```

## Common Workflows

### New machine setup

Run this once after cloning the repo on a new machine. It syncs the cache, installs your preferred general-purpose resources globally, then sets up whichever repo you are currently working in.

```powershell
# 1. Sync the awesome-copilot cache
.\scripts\sync-awesome-copilot.ps1

# 2. Install agents, instructions, and skills you want active in every VS Code window
.\scripts\init-user.ps1

# 3. Configure the repo you are currently working in
.\scripts\init-repo.ps1
```

After this, user-level resources are always active. Repo-level resources are committed to `.github/` and available to the whole team.

---

### Configuring a new repo

Run from inside any repo — or pass `-RepoPath` from anywhere. Language and framework are auto-detected; relevant items are pre-marked with ★.

```powershell
# From inside the repo
cd C:\Projects\my-app
.\path\to\vscode-copilot-sync\configure.ps1 -Install

# Or target it directly without cd-ing
.\configure.ps1 -Install -RepoPath "C:\Projects\my-app"

# Preview first without writing anything
.\configure.ps1 -Install -DryRun -RepoPath "C:\Projects\my-app"
```

`-Install` skips the "do you want to configure a repo?" prompt and goes straight to the pickers.

---

### Multi-repo strategy

User-level resources (installed via `init-user.ps1`) are available in **every VS Code window automatically** — no `.github/` commit needed. Repo-level resources are scoped to a single project and are committed for the whole team.

A practical split:

| Use `init-user.ps1` for                                         | Use `init-repo.ps1` for                                            |
| --------------------------------------------------------------- | ------------------------------------------------------------------ |
| General coding standards (security, accessibility, performance) | Framework-specific agents (e.g. `angular-expert`, `dotnet-expert`) |
| Cross-cutting skills (`refactor`, `create-readme`)              | Project-specific hooks and workflows                               |
| Resources you always want, regardless of project                | Resources the whole team should have in their repo                 |

Items already installed at user level are shown with `[U]` in the repo picker — you can still install them repo-level if you want them committed, but it is not required.

---

### Keeping resources current

Run this whenever you want to pull the latest upstream changes for both user-level and repo-level subscriptions.

```powershell
# 1. Pull the latest from awesome-copilot into the local cache
.\scripts\sync-awesome-copilot.ps1

# 2. Update user-level resources (agents, instructions, skills in %APPDATA% / ~/.copilot)
.\scripts\update-user.ps1

# 3. Update repo-level resources in the current repo
.\scripts\update-repo.ps1

# Or do all three non-interactively
.\scripts\sync-awesome-copilot.ps1
.\scripts\update-user.ps1 -Force
.\scripts\update-repo.ps1 -Force
```

`update-repo.ps1` reads `.github/.copilot-subscriptions.json`; `update-user.ps1` reads `~/.awesome-copilot/user-subscriptions.json`. Only items you have previously installed are touched — nothing is added automatically.

---

## Scripts

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
.\configure.ps1 -UninstallUser                    # Remove user-level resources
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

| Check        | Trigger                                                  | Action                                                        |
| ------------ | -------------------------------------------------------- | ------------------------------------------------------------- |
| Structural   | A previously-synced category folder is absent after pull | `STRUCTURAL CHANGE DETECTED` — lists missing folders, exits 1 |
| Mass-removal | ≥ 25 % of tracked files removed in one pull              | `MASS-REMOVAL DETECTED` — shows ratio, exits 1                |

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

### `scripts/init-user.ps1` — Configure user-level resources

Installs agents, instructions, and skills into user-level locations, making them available across **all repos and VS Code windows** — no `.github/` needed.

| Resource     | Location                                        |
| ------------ | ----------------------------------------------- |
| Agents       | `%APPDATA%\Code\User\prompts\*.agent.md`        |
| Instructions | `%APPDATA%\Code\User\prompts\*.instructions.md` |
| Skills       | `~/.copilot/skills/<name>/`                     |

This is ideal for general-purpose, tech-agnostic resources you always want active (e.g. security standards, accessibility guidelines, cross-cutting agents). Tech-specific items are still available in the picker but not pre-starred.

**Full lifecycle** — install, update, and remove, tracked in `~/.awesome-copilot/user-subscriptions.json`.

```powershell
.\scripts\init-user.ps1                                # Interactive (agents + instructions + skills)
.\scripts\init-user.ps1 -DryRun                        # Preview
.\scripts\init-user.ps1 -Uninstall                     # Remove user-level resources
.\scripts\init-user.ps1 -SkipSkills                    # Agents + instructions only
.\scripts\init-user.ps1 -SkipAgents -SkipInstructions  # Skills only
.\scripts\init-user.ps1 -Agents "beastmode,se-security-reviewer"
.\scripts\init-user.ps1 -Instructions "security-and-owasp,markdown-accessibility"
.\scripts\init-user.ps1 -Skills "refactor,create-readme"

# Non-default VS Code installations
.\scripts\init-user.ps1 -PromptsDir "$env:APPDATA\Code - Insiders\User\prompts"
```

---

### `scripts/update-user.ps1` — Apply upstream updates to user-level resources

Reads `~/.awesome-copilot/user-subscriptions.json` and refreshes installed user-level agents, instructions, and skills from the local cache.

```powershell
.\scripts\update-user.ps1                    # Interactive
.\scripts\update-user.ps1 -DryRun           # Show what would change
.\scripts\update-user.ps1 -Force            # Apply all without prompting
.\scripts\update-user.ps1 -SkillsDir "~/custom/skills"  # Non-default skills location
```

## Configuration

### Authentication

`gh` CLI is preferred — inherits from `gh auth login`, no extra setup. If only `git` is available, the public `github/awesome-copilot` repo requires no credentials. For private forks, configure git credentials as usual.

### Custom Source Repository

Edit two variables near the top of `scripts/sync-awesome-copilot.ps1`:

```powershell
$RepoSlug = 'your-username/your-fork'
$RepoUrl  = 'https://github.com/your-username/your-fork.git'
```

## Troubleshooting

### Execution policy error (Windows only)

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

This is a Windows-only restriction. macOS and Linux are unaffected.

### Sync fails with merge conflict

The script auto-recovers (`git reset --hard origin/HEAD`). If it persists, delete `~/.awesome-copilot` and re-run — it will re-clone fresh.

## Logs

Sync logs are written to `scripts/logs/sync-YYYYMMDD-HHMMSS.log`:

```powershell
Get-ChildItem .\scripts\logs\sync-*.log | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | Get-Content
```

## FAQ

**What is awesome-copilot?**
[awesome-copilot](https://github.com/github/awesome-copilot) is the community-maintained catalogue of GitHub Copilot resources — agents, instructions, skills, hooks, and workflows contributed by hundreds of developers. vscode-copilot-sync makes it easy to cherry-pick and manage resources from that catalogue.

**Does vscode-copilot-sync work on macOS and Linux?**
Yes. All scripts run on PowerShell 7+ (`pwsh`), which is available for Windows, macOS, and Linux. The only Windows-specific feature is `Out-GridView`; on other platforms the scripts fall back to a numbered console menu automatically.

**Will it overwrite files I've written myself?**
No. The scripts only track and manage files they installed, recorded in `.github/.copilot-subscriptions.json`. User-created files are never touched. Locally modified files are flagged with `[~]` and require explicit confirmation before any update.

**Do I need a GitHub account?**
No account is needed to sync from the public `awesome-copilot` repository. The scripts use `gh` CLI if available but fall back to unauthenticated `git` for the public source.

**How is this different from VS Code's built-in Settings Sync?**
VS Code Settings Sync backs up editor settings and extensions. vscode-copilot-sync manages Copilot-specific resources (agents, instructions, skills) from the community catalogue — content that Settings Sync does not cover.

**How often should I run the sync?**
Run `.\configure.ps1` whenever you want to pull upstream additions. There is no scheduled sync — you decide when to update.

---

## Related Projects

| Project                                                      | Description                                                                                                                     |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| [Symdicate](https://github.com/CTOUT/Symdicate)              | Composable multi-agent framework for GitHub Copilot — persona grafting, cognitive identity caching, and agent fusion            |
| [ReFrame](https://github.com/CTOUT/ReFrame)                  | GitHub Copilot agent for PC game configuration optimisation — detects hardware and recommends targeted performance improvements |
| [awesome-copilot](https://github.com/github/awesome-copilot) | The community catalogue that vscode-copilot-sync syncs from                                                                     |

---

## Contributing

Contributions welcome! Fork, branch, test, PR.

## License

MIT — see [LICENSE](LICENSE)

## Acknowledgments

- [awesome-copilot](https://github.com/github/awesome-copilot) — Community resource repository
- [GitHub Copilot](https://github.com/features/copilot) — AI pair programmer

---

Made with ❤️ for the VS Code + Copilot community
