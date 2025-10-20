# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
