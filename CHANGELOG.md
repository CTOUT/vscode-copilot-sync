# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.2] - 2026-02-27

### Added
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

### Changed
- `publish-global.ps1`: updated inline comment from "CCA" to "VS Code Agent mode / Copilot CLI"
- `README.md`: corrected all `-Interval` references to `-Every`; fixed `-ProfileName` → `-ProfileRoot`/`-AllProfiles`; updated agents path to `%APPDATA%\Code\User\prompts\`; updated `init-repo.ps1` section to reflect agents category and smart detection; fixed custom `-AgentsTarget` example path
- `.github/copilot-instructions.md`: corrected agents path from `%APPDATA%\Code\User\agents\` to `%APPDATA%\Code\User\prompts\`



### Fixed
- `sync-awesome-copilot.ps1`: changed `$ErrorActionPreference` from `Inquire` to `Stop` — `Inquire` caused the script to hang waiting for interactive input when run as a scheduled task

### Changed
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
