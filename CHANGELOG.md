# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `scripts/sync-awesome-copilot.ps1`: **Structural change detection** — after each non-first-run pull, verifies every previously-synced category folder still exists on disk. Logs `STRUCTURAL CHANGE DETECTED` (with missing folder list) and exits non-zero if any are absent. Catches upstream category renames or removals before they silently break subscriptions.
- `scripts/sync-awesome-copilot.ps1`: **Mass-removal threshold** — if ≥ 25 % of all previously tracked files disappear in a single pull (min 10 files prior), logs `MASS-REMOVAL DETECTED` with the actual ratio and exits before writing the new manifest. Guards against large upstream restructures being silently applied.
- `scripts/sync-awesome-copilot.ps1`: `-Force` switch — bypasses both safety checks when an upstream restructure is intentional.
- `scripts/init-user.ps1`: **Instructions support** — new `-Instructions` / `-SkipInstructions` parameters; interactive picker installs `.instructions.md` files to `%APPDATA%\Code\User\prompts\`. Only general-purpose (tech-agnostic) items are starred ★ using the same `Measure-GeneralRelevance` scoring as agents. Extended `$GeneralPositiveSegments` with `refactor`, `remember`, `accessibility`, `a11y`, `performance`, `owasp`.
- `scripts/init-user.ps1`: **Skills support** — new `-Skills` / `-SkipSkills` / `-SkillsDir` parameters; interactive picker installs skill directories to `~/.copilot/skills/`. New `Build-UserSkillsCatalogue`, `Get-DirHash`, `Install-Directory`, `Remove-Directory` helpers. Full install/update/remove lifecycle tracked in `user-subscriptions.json` with `type: directory` entries.
- `scripts/init-user.ps1`: **Trust warning** — displayed before the install pickers (not shown on `-Uninstall` or `-DryRun`). Reminds the user that resources written to `%APPDATA%\Code\User\prompts\` and `~/.copilot/skills/` are loaded by Copilot in all VS Code sessions.
- `scripts/update-user.ps1`: `-SkillsDir` parameter; `Get-DirHash` helper; destination routing by subscription `type` field (`directory` → `$SkillsDir`, `file` → `$PromptsDir`); directory-type subscriptions mirrored file-by-file on update.
- `scripts/init-repo.ps1`: **`[U]` status indicator** — agents and instructions now show `[U]` in the OGV Status column and console menu when the item is already installed at user level (`$UserPromptsDir`). New `-UserPromptsDir` parameter (defaults to `%APPDATA%\Code\User\prompts`). `[U]` is additive — combines with `[*]`, `[↑]`, `[~]`, `[!]`.

### Fixed

- `scripts/init-user.ps1`: Added `power`, `flowstudio`, and `powershell` to `$TechSpecificSegments`. `power-bi`, `power-platform`, `power-apps`, `power-automate`, `flowstudio`, and `powershell`-specific resources no longer receive a ★ recommendation in user-level pickers.
- `scripts/init-repo.ps1`: Renamed `$input` → `$rawInput` in `Select-Items` and `Select-ToRemove` console-menu fallbacks. `$input` is PowerShell's automatic pipeline enumerator variable; shadowing it risks silent data loss in pipeline contexts.
- `scripts/sync-awesome-copilot.ps1`: Changed `$Global:LogFile` to `$script:LogFile`. Global scope leaked the log path into the session, risking log corruption if two sync runs overlapped or another script reused the variable name.

### Changed

- `scripts/init-user.ps1`: header, validation log, and summary updated to reflect three resource categories and two destination directories.
- `README.md`: updated `init-user.ps1` section with three-location table, new parameters, and usage examples; updated `update-user.ps1` section with `-SkillsDir` param; added `[U]` entry and clarifying tip to the symbol table.

### Identified (not yet extracted)

- **Shared helper duplication** — `Log`, `Show-OGV`, `Get-DirHash`, `Get-Description`, `Install-File`, `Remove-File`, `Test-RequiresSetup`, and the subscription upsert/remove pattern are defined independently in multiple scripts (`init-repo.ps1`, `init-user.ps1`, `update-repo.ps1`, `update-user.ps1`). Planned fix: extract to a dot-sourced `scripts/Common.ps1` in a follow-up PR.

### Testing

- `sync-awesome-copilot.ps1 -Plan` — exits cleanly; structural/mass-removal checks correctly bypass in plan mode.
- Structural check verified by temporarily renaming `agents/` from the cache: `STRUCTURAL CHANGE DETECTED` fires with correct missing-folder output.
- Mass-removal check verified by inflating manifest item count 5×: `MASS-REMOVAL DETECTED` fires at 80% removal ratio; `-Force` bypasses and restores a clean manifest.
- `init-user.ps1 -DryRun -Agents gem-reviewer -Instructions security-and-owasp -Skills refactor` — all three categories resolve; agent reports unchanged (already installed), instruction and skill report would-add.
- `init-user.ps1 -DryRun -Uninstall -SkipAgents -SkipInstructions` — correctly reports no script-managed skills to remove.
- `update-user.ps1 -DryRun` — reads 67 existing agent subscriptions; `Skills dir` shown in header; all report current.
- `[U]` flag: inline script confirms 67 of 203 agents have `UserInstalled = true`, matching existing user subscriptions; 4 have `AlreadyInstalled = true` (repo-installed).
- `power-bi`, `power-platform`, `flowstudio` confirmed blocked (return 0 from `Measure-GeneralRelevance`); `powershell` also confirmed blocked.
- `init-repo.ps1 -DryRun` — `$rawInput` rename verified; no pipeline variable collision.

## [1.2.2] - 2026-02-27

### Changed

- `configure.ps1`: use `$PSScriptRoot` to locate the `scripts/` folder (replaces `$MyInvocation.MyCommand.Path` which behaves differently when dot-sourced)
- `scripts/sync-awesome-copilot.ps1`: replace manual SHA256 with built-in `Get-FileHash` — cleaner and avoids loading entire file into memory
- `scripts/publish-global.ps1`: emit a `WARN` log when VS Code `settings.json` is not found (was a silent no-op); user is directed to open VS Code once to generate the file

## [1.2.1] - 2026-02-27

### Fixed

- `configure.ps1`: `-InstallTask` / `-UninstallTask` now automatically skip the `init-repo` prompt (validation moved before Step 1 so the flag takes effect)
- `configure.ps1`: prompts to overwrite when the scheduled task already exists, instead of throwing a hard error
- `scripts/install-scheduled-task.ps1`: added `-WorkingDirectory` to both scheduled task actions (was defaulting to `C:\Windows\System32`, causing a permissions error creating the `logs/` directory)
- `scripts/sync-awesome-copilot.ps1`: replaced relative `logs/` path with `$PSScriptRoot/logs/` so logs always land in `scripts/logs/` regardless of working directory
- `scripts/install-scheduled-task.ps1`: updated task description (removed stale "combine" wording)
- `scripts/publish-global.ps1`: fixed named-profile example path (`agents\` → `prompts\`)
- `README.md`: corrected default interval (6h → 4h), log paths, authentication section, and custom-repo instructions
- `.github/copilot-instructions.md`: removed stale GitHub API / `GITHUB_TOKEN` references; updated cache structure

## [1.2.0] - 2026-02-27

### Changed

- `scripts/sync-awesome-copilot.ps1`: **Rewritten** — replaced GitHub API + per-file HTTP download approach with `git sparse-checkout`. First run clones `github/awesome-copilot` shallowly with only the requested categories; subsequent runs run `git pull` for near-instant delta updates. Dramatically faster (single bulk transfer vs 700+ individual HTTP requests) and removes GitHub API rate-limit concerns entirely.
  - Prefers `gh` (GitHub CLI) for automatic auth; falls back to `git`
  - New `-GitTool auto|gh|git` parameter to override tool selection
  - Removed parameters: `-NoDelete`, `-DiffOnly`, `-SkipBackup`, `-BackupRetention` (git handles all of these natively)
  - Migrates automatically from the old API-based cache (renames non-git `~/.awesome-copilot/` to `~/.awesome-copilot-backup-<date>` before cloning)
  - `manifest.json` still written (from local file scan) for backward compatibility with `publish-global.ps1` and `configure.ps1`

### Added

- `README.md`: document `gh`/`git` requirement; update sync section to reflect git-based approach

## [1.1.2] - 2026-02-27

### Added

- `configure.ps1` — interactive orchestrator that chains sync → publish-global → init-repo; each step independently skippable via `-SkipSync`, `-SkipPublish`, `-SkipInit`; `-DryRun` passes through to all child scripts; shows last sync timestamp from cache manifest before running
- `init-repo.ps1`: added Agents as a fourth interactive category (installs to `.github/agents/`)
- `init-repo.ps1`: `Detect-RepoStack` — auto-detects language/framework from file signals and marks relevant items with ★ in the picker
- `init-repo.ps1`: `Prompt-RepoIntent` — interactive fallback for new/empty repos; asks language, project type, and concerns
- `init-repo.ps1`: `-- none / skip --` sentinel row in every OGV picker so clicking OK with no intentional selection installs nothing
- `publish-global.ps1`: auto-configures `chat.useAgentSkills` and `chat.agentSkillsLocations` in VS Code `settings.json` when skills are published
- `.github/copilot-instructions.md`: Copilot instructions for this repository covering script workflow, conventions, and contributing guidelines

### Fixed

- `normalize-copilot-folders.ps1`: `Split-Path -LeafParent` → `Split-Path -Parent` (`-LeafParent` is not a valid parameter and would throw at runtime)
- `install-scheduled-task.ps1`: removed `-Quiet` from `publish-global.ps1` invocation (`publish-global.ps1` has no `-Quiet` parameter; would throw on scheduled runs)
- `init-repo.ps1`: `$Items.IndexOf($_)` → `[Array]::IndexOf($Items, $_)` (`System.Object[]` has no instance `IndexOf` method; affected console-menu fallback path)
- `init-repo.ps1`: fixed OGV column name `[*] Installed` → `Installed` (special characters caused WPF binding errors at runtime)
- `init-repo.ps1`: fixed `return if (...)` runtime error in `Install-File` — replaced with explicit `if/else` branches
- `publish-global.ps1`: corrected agents target path to `%APPDATA%\Code\User\prompts\` (was incorrectly set to `agents\`)
- `sync-awesome-copilot.ps1`: changed `$ErrorActionPreference` from `Inquire` to `Stop` — `Inquire` caused the script to hang waiting for interactive input when run as a scheduled task

### Changed

- `publish-global.ps1`: updated inline comment from "CCA" to "VS Code Agent mode / Copilot CLI"
- `README.md`: corrected all `-Interval` references to `-Every`; fixed `-ProfileName` → `-ProfileRoot`/`-AllProfiles`; updated agents path to `%APPDATA%\Code\User\prompts\`; updated `init-repo.ps1` section to reflect agents category and smart detection; fixed custom `-AgentsTarget` example path
- `.github/copilot-instructions.md`: corrected agents path from `%APPDATA%\Code\User\agents\` to `%APPDATA%\Code\User\prompts\`
- `init-repo.ps1`: removed skills from per-repo initialisation; skills are globally available via `publish-global.ps1` (`~/.copilot/skills/`) and users should reference the source directly at [github/awesome-copilot](https://github.com/github/awesome-copilot) rather than committing point-in-time copies to repos

## [1.1.0] - 2026-02-26

### Added

- `publish-global.ps1` — publishes agents to the VS Code user agents folder (via junction so sync updates are reflected immediately) and skills to `~/.copilot/skills/`; supports `-DryRun`, `-SkipAgents`, `-SkipSkills`, `-AgentsTarget`, `-SkillsTarget`
- `init-repo.ps1` — interactive script to initialise a repo with per-repo resources (instructions, hooks, workflows); uses Out-GridView on Windows with a numbered console-menu fallback; supports `-RepoPath`, `-DryRun`, `-SkipInstructions`, `-SkipHooks`, `-SkipWorkflows`

### Changed

- Updated default sync categories to match current awesome-copilot repository structure:
  - **Added**: `agents`, `workflows`, `hooks`, `skills`
  - **Removed**: `chatmodes`, `prompts` (no longer exist in awesome-copilot)
- Added recursive directory traversal in `sync-awesome-copilot.ps1` to support subdirectory-based categories (`skills/`, `hooks/`, `plugins/`)
- Extended file extension filter to include `.sh` files (required for hooks to function — each hook ships shell scripts alongside its `hooks.json`)
- Updated `combine-and-publish-prompts.ps1` categories from `chatmodes/instructions/prompts` to `agents/instructions/workflows`; added deprecation notice at top (superseded by `publish-global.ps1` + `init-repo.ps1`); kept for backwards compatibility
- Updated `normalize-copilot-folders.ps1` to classify `*.agent.md` → `agents/` and ensure `agents/` directory is created on normalize runs
- Updated `install-scheduled-task.ps1`: default categories now `agents,instructions,workflows,hooks,skills`; `-IncludeCollections` replaced by `-IncludePlugins`; `-SkipCombine` replaced by `-SkipPublishGlobal`; scheduled actions now run `publish-global.ps1` after sync

### Removed

- `normalize-copilot-folders.ps1` — removed (legacy, superseded by junction-based agent publishing and `init-repo.ps1`)

- `plugins/` and `cookbook/` are available but opt-in via `-IncludePlugins` due to their size
- Hooks are synced as complete packages (README.md + hooks.json + .sh scripts) preserving their directory structure
- **Design rationale**: agents and skills are global (agents available in all VS Code workspaces; skills loaded on-demand); instructions/hooks/workflows are per-repo opt-in via `init-repo.ps1` to avoid conflicts between contradicting instruction files

## [1.0.0] - 2025-10-20

### Added

- Initial release of VS Code Copilot Resource Sync Scripts
- `sync-awesome-copilot.ps1` - Sync resources from GitHub awesome-copilot repository
- `combine-and-publish-prompts.ps1` - Combine and publish resources to VS Code
- `publish-to-vscode-profile.ps1` - Publish resources to VS Code profiles
- `normalize-copilot-folders.ps1` - Clean up and organize resource files
- `install-scheduled-task.ps1` - Create automated sync task
- `uninstall-scheduled-task.ps1` - Remove scheduled task
- GitHub API integration with optional GITHUB_TOKEN support
- SHA256 hash-based change detection for efficient syncing
- Automatic junction/symlink creation with copy fallback
- Manifest-based sync state tracking
- Comprehensive logging system
- Support for multiple VS Code profiles

### Features

- Portable paths using environment variables ($HOME, $env:APPDATA)
- Preserves user-created custom files in combined directory
- Incremental updates (only downloads changed files)
- Customizable sync intervals for scheduled task
- Automatic categorization based on file suffixes
- Detailed sync logs with timestamps

### Security

- No hardcoded credentials or personal information
- Optional environment variable for GitHub token
- All sensitive data handled via environment variables

---

## Future Plans

### Planned Features

- [ ] Configuration file support (YAML/JSON)
- [ ] Backup and restore functionality
- [ ] Conflict resolution UI for duplicate resources
- [ ] Support for custom resource categories
- [ ] Integration with other Copilot resource repositories
- [ ] PowerShell module packaging
- [ ] Cross-platform support (macOS, Linux)

### Known Issues

- Junction creation requires appropriate permissions on some systems
- Scheduled task runs under user context (requires user to be logged in)

---

**Note:** Version numbers follow [Semantic Versioning](https://semver.org/):

- MAJOR version for incompatible API changes
- MINOR version for new functionality in a backwards compatible manner
- PATCH version for backwards compatible bug fixes
