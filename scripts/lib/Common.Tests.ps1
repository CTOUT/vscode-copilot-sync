Describe 'Invoke-LegacyUserCustomizationMigration' {
    BeforeAll {
        . "$PSScriptRoot/Common.ps1"
    }

    BeforeEach {
        $testRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $legacyDirectory = Join-Path $testRoot 'legacy-prompts'
        New-Item -ItemType Directory -Path $legacyDirectory -Force | Out-Null
    }

    It 'moves legacy agents and instructions and leaves unrelated prompts alone' {
        $agentsDirectory = Join-Path $testRoot 'copilot/agents'
        $instructionsDirectory = Join-Path $testRoot 'copilot/instructions'
        Set-Content -Path (Join-Path $legacyDirectory 'sample.agent.md') -Value 'agent content'
        Set-Content -Path (Join-Path $legacyDirectory 'sample.instructions.md') -Value 'instruction content'
        Set-Content -Path (Join-Path $legacyDirectory 'sample.prompt.md') -Value 'prompt content'

        $result = Invoke-LegacyUserCustomizationMigration `
            -LegacyDirectory $legacyDirectory `
            -AgentsDirectory $agentsDirectory `
            -InstructionsDirectory $instructionsDirectory

        if ($result.FilesMoved -ne 2) { throw 'Expected two migrated files.' }
        if (-not (Test-Path (Join-Path $agentsDirectory 'sample.agent.md'))) { throw 'Agent was not migrated.' }
        if (-not (Test-Path (Join-Path $instructionsDirectory 'sample.instructions.md'))) { throw 'Instruction was not migrated.' }
        if (Test-Path (Join-Path $legacyDirectory 'sample.agent.md')) { throw 'Legacy agent was not removed.' }
        if (Test-Path (Join-Path $legacyDirectory 'sample.instructions.md')) { throw 'Legacy instruction was not removed.' }
        if (-not (Test-Path (Join-Path $legacyDirectory 'sample.prompt.md'))) { throw 'Unrelated prompt was changed.' }
    }

    It 'removes the legacy copy when the destination is identical' {
        $agentsDirectory = Join-Path $testRoot 'copilot/agents'
        $instructionsDirectory = Join-Path $testRoot 'copilot/instructions'
        $legacyFile = Join-Path $legacyDirectory 'sample.agent.md'
        $destinationFile = Join-Path $agentsDirectory 'sample.agent.md'
        New-Item -ItemType Directory -Path $agentsDirectory -Force | Out-Null
        Set-Content -Path $legacyFile -Value 'same content'
        Set-Content -Path $destinationFile -Value 'same content'

        $result = Invoke-LegacyUserCustomizationMigration `
            -LegacyDirectory $legacyDirectory `
            -AgentsDirectory $agentsDirectory `
            -InstructionsDirectory $instructionsDirectory

        if ($result.DuplicateFilesRemoved -ne 1) { throw 'Expected one identical duplicate to be removed.' }
        if (Test-Path $legacyFile) { throw 'Identical legacy duplicate was not removed.' }
        if (-not (Test-Path $destinationFile)) { throw 'Current destination file was removed.' }
    }

    It 'preserves both files when the destination differs' {
        $agentsDirectory = Join-Path $testRoot 'copilot/agents'
        $instructionsDirectory = Join-Path $testRoot 'copilot/instructions'
        $legacyFile = Join-Path $legacyDirectory 'sample.agent.md'
        $destinationFile = Join-Path $agentsDirectory 'sample.agent.md'
        New-Item -ItemType Directory -Path $agentsDirectory -Force | Out-Null
        Set-Content -Path $legacyFile -Value 'legacy content'
        Set-Content -Path $destinationFile -Value 'destination content'

        $result = Invoke-LegacyUserCustomizationMigration `
            -LegacyDirectory $legacyDirectory `
            -AgentsDirectory $agentsDirectory `
            -InstructionsDirectory $instructionsDirectory

        if ($result.Conflicts -notcontains 'sample.agent.md') { throw 'Expected a destination conflict.' }
        if ((Get-Content -Path $legacyFile -Raw).Trim() -ne 'legacy content') { throw 'Legacy content was changed.' }
        if ((Get-Content -Path $destinationFile -Raw).Trim() -ne 'destination content') { throw 'Destination content was changed.' }
    }

    It 'previews moves without creating destination files' {
        $agentsDirectory = Join-Path $testRoot 'copilot/agents'
        $instructionsDirectory = Join-Path $testRoot 'copilot/instructions'
        $legacyFile = Join-Path $legacyDirectory 'sample.agent.md'
        Set-Content -Path $legacyFile -Value 'agent content'

        $result = Invoke-LegacyUserCustomizationMigration `
            -LegacyDirectory $legacyDirectory `
            -AgentsDirectory $agentsDirectory `
            -InstructionsDirectory $instructionsDirectory `
            -DryRun

        if ($result.FilesWouldMove -ne 1) { throw 'Expected one planned migration.' }
        if (-not (Test-Path $legacyFile)) { throw 'Dry run removed the legacy file.' }
        if (Test-Path (Join-Path $agentsDirectory 'sample.agent.md')) { throw 'Dry run created a destination file.' }
    }
}

Describe 'Assert-PathWithin' {
    BeforeAll {
        . "$PSScriptRoot/Common.ps1"
    }

    BeforeEach {
        $testRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    }

    It 'rejects the authorized root unless equality is explicitly allowed' {
        { Assert-PathWithin -Path $testRoot -ParentDirectory $testRoot } | Should -Throw
        { Assert-PathWithin -Path $testRoot -ParentDirectory $testRoot -AllowEqual } | Should -Not -Throw
    }

    It 'rejects a path outside the authorized root' {
        $outsidePath = "$testRoot-sibling/file.txt"

        { Assert-PathWithin -Path $outsidePath -ParentDirectory $testRoot } | Should -Throw
    }

    It 'rejects destination paths that traverse a symbolic link' {
        $linkPath = Join-Path $testRoot 'link'
        $outsideRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $outsideRoot -Force | Out-Null

        try {
            if ($IsWindows) {
                New-Item -ItemType Junction -Path $linkPath -Target $outsideRoot | Out-Null
            }
            else {
                [System.IO.Directory]::CreateSymbolicLink($linkPath, $outsideRoot) | Out-Null
            }
        }
        catch {
            Set-ItResult -Skipped -Because 'The current platform or account cannot create symbolic links.'
        }

        { Assert-PathWithin -Path (Join-Path $linkPath 'file.txt') -ParentDirectory $testRoot } | Should -Throw '*symbolic link*'
    }
}
