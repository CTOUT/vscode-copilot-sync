# TODO

## Open Issues

### DataVerse false ★ recommendations for repos with `.py` files

- `.py` files trigger `python` keyword → `dataverse-python-*` scores 2 (contains `python` as a dash-segment)
- Reproduced with: `.\configure.ps1 -Install -RepoPath ..\Scripts\`
- Root cause: generic language keywords match vendor-prefixed item names
- **Proposed fix:** maintain a known vendor-prefix blocklist (`dataverse`, `salesforce`, `shopify`, `atlassian`, `pimcore`, `amplitude`, etc.). Items whose first segment is in the blocklist should not receive a name-match score from generic language keywords — only from an explicit vendor keyword detected in the repo.

### OGV opens behind other windows

- Windows UIPI prevents focus-stealing from background processes by design
- Three approaches tried and failed: `SetForegroundWindow`, `keybd_event(Alt)`, `WScript.Shell.AppActivate` from runspace
- Currently mitigated with a yellow hint message in the terminal
- Possible alternative: investigate WinForms-based topmost picker as a drop-in replacement for `Out-GridView`
