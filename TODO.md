# TODO

## Open Issues

### DataVerse false ★ recommendations for repos with `.py` files

- `.py` files trigger `python` keyword → `dataverse-python-*` scores 2 (contains `python` as a dash-segment)
- Reproduced with: `.\configure.ps1 -Install -RepoPath ..\Scripts\`
- Root cause: generic language keywords match vendor-prefixed item names
- **Proposed fix:** maintain a known vendor-prefix blocklist (`dataverse`, `salesforce`, `shopify`, `atlassian`, `pimcore`, `amplitude`, etc.). Items whose first segment is in the blocklist should not receive a name-match score from generic language keywords — only from an explicit vendor keyword detected in the repo.

### Cross-platform: auto-detect VS Code user directory on macOS and Linux

- `$env:APPDATA` is Windows-only; `init-user.ps1` and `update-user.ps1` default `-PromptsDir` to `$env:APPDATA\Code\User\prompts`
- macOS path: `~/Library/Application Support/Code/User/prompts`
- Linux path: `~/.config/Code/User/prompts`
- **Proposed fix:** detect platform via `$IsWindows` / `$IsMacOS` / `$IsLinux` and set the default path accordingly; document in README (already done as a manual workaround note)

### OGV opens behind other windows

- Windows UIPI prevents focus-stealing from background processes by design
- Three approaches tried and failed: `SetForegroundWindow`, `keybd_event(Alt)`, `WScript.Shell.AppActivate` from runspace
- Currently mitigated with a yellow hint message in the terminal
- Possible alternative: investigate WinForms-based topmost picker as a drop-in replacement for `Out-GridView`

### Cross-platform: selection without `Out-GridView`

- `Out-GridView` is not available on macOS/Linux, so the install-selection scripts can produce a long, hard-to-manage command-line list
- `sync-awesome-copilot.ps1` works because it avoids the GridView flow, while the other scripts still rely on it for interactive choices
- **Proposed fix:** add a CLI-friendly selection mode that supports interactive choices without `Out-GridView`, including a `Recommended` option so users can install the suggested set without specifying explicit IDs or `All`
- **Proposed validation:** test on macOS/Linux and document the fallback behavior in the README

### Configuration file support

- Users currently configure everything via command-line parameters; there is no persistent config file
- **Proposed approach:** YAML or JSON config file (e.g. `~/.awesome-copilot/config.yml`) storing preferred categories, default paths, and skip flags so they don't need to be passed on every run

### PowerShell module packaging

- Scripts are currently used by cloning this repo directly
- **Proposed approach:** package as a PowerShell module published to the PowerShell Gallery (`Install-Module vscode-copilot-sync`); would remove the clone-and-path requirement and simplify updates
