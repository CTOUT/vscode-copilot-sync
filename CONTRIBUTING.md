# Contributing Guide

Thank you for considering contributing to the VS Code Copilot Resource Sync Scripts project! 🎉

## How to Contribute

### Reporting Bugs

If you find a bug, please create an issue with:
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- PowerShell version (`$PSVersionTable.PSVersion`)
- Windows version
- Relevant log files from `$HOME\.awesome-copilot\logs\`

### Suggesting Enhancements

Feature requests are welcome! Please include:
- Clear use case description
- Why this feature would be useful
- Proposed implementation (if you have ideas)

### Pull Requests

1. **Fork the repository**
2. **Create a feature branch** from `main`:
   ```powershell
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**:
   - Follow existing code style
   - Add comments for complex logic
   - Use meaningful variable names
   - Test thoroughly on your system

4. **Update documentation**:
   - Update README.md if adding new features
   - Update CHANGELOG.md with your changes
   - Add inline comments for complex code

5. **Test your changes**:
   ```powershell
   # Test individual scripts
   .\sync-awesome-copilot.ps1
   .\combine-and-publish-prompts.ps1
   
   # Test scheduled task installation
   .\install-scheduled-task.ps1 -Interval "1h"
   Start-ScheduledTask -TaskName "AwesomeCopilotSync"
   
   # Verify logs
   Get-Content "$HOME\.awesome-copilot\logs\sync-*.log" -Tail 20
   ```

6. **Commit with clear messages**:
   ```powershell
   git commit -m "Add feature: description of what you added"
   ```

7. **Push and create PR**:
   ```powershell
   git push origin feature/your-feature-name
   ```

## Code Style Guidelines

### PowerShell Best Practices

- **Use approved verbs**: `Get-`, `Set-`, `New-`, `Remove-`, etc.
- **PascalCase for functions**: `Invoke-MyFunction`
- **Verbose parameter names**: Prefer clarity over brevity
- **Comment complex logic**: Explain the "why", not the "what"
- **Error handling**: Use `try/catch` for external operations
- **Logging**: Use `Write-Host` with color coding for status messages

### Example:

```powershell
function Get-ResourceFiles {
    <#
    .SYNOPSIS
    Retrieves resource files from a directory.
    
    .PARAMETER Path
    The directory path to search.
    
    .PARAMETER Type
    The type of resource to filter (chatmode, instruction, prompt).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        
        [ValidateSet('chatmode', 'instruction', 'prompt')]
        [string]$Type
    )
    
    try {
        $pattern = "*.$Type.md"
        Get-ChildItem -Path $Path -Filter $pattern -File
    }
    catch {
        Write-Host "[ERROR] Failed to get resource files: $_" -ForegroundColor Red
        throw
    }
}
```

### Portable Paths

Always use environment variables for paths:

```powershell
# ✅ GOOD
$cacheDir = Join-Path $HOME '.awesome-copilot'
$profileDir = Join-Path $env:APPDATA 'Code\User'

# ❌ BAD - Don't hardcode user paths
$cacheDir = 'C:\Users\Someone\.awesome-copilot'
```

### Security

- Never commit credentials or tokens
- Use environment variables for sensitive data
- Validate all user inputs
- Use `-WhatIf` support for destructive operations

## Testing Checklist

Before submitting a PR, verify:

- [ ] Scripts run without errors
- [ ] No hardcoded personal paths
- [ ] Portable paths using `$HOME` and `$env:APPDATA`
- [ ] Logging works correctly
- [ ] Error handling covers edge cases
- [ ] Scheduled task integration works
- [ ] No breaking changes to existing functionality
- [ ] Documentation updated
- [ ] CHANGELOG.md updated

## Questions?

Feel free to:
- Open an issue for discussion
- Ask questions in pull request comments
- Reach out to maintainers

## Code of Conduct

Be respectful, constructive, and collaborative. We're all here to make this project better! 🚀

---

**Thank you for contributing!** ❤️
