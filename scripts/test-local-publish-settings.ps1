function Test-LocalPublishPersistence($Workspace) {
    . (Join-Path $PSScriptRoot 'publish-setup.ps1')
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) '.gitignore') -Destination (Join-Path $Workspace.Root '.gitignore')
    $modPath = Join-Path $Workspace.Root 'config/modrinth.local.psd1'
    $cfPath = Join-Path $Workspace.Root 'config/curseforge.local.psd1'
    $statePath = Join-Path $Workspace.Root 'config/publish-state.local.json'
    $originalModSettings = [IO.File]::ReadAllText($modPath)
    $oldModToken = [Environment]::GetEnvironmentVariable('MODRINTH_TOKEN')
    $oldCFToken = [Environment]::GetEnvironmentVariable('CURSEFORGE_TOKEN')
    $answers = [Collections.Generic.Queue[string]]::new()
    foreach ($answer in @("fake-mod-token-with'quote", 'fake-cf-token', 'replacement-mod-token')) { $answers.Enqueue($answer) }
    function Read-Token([string]$Platform) {
        if (-not $answers.Count) { throw 'A saved global token unexpectedly prompted again.' }
        return $answers.Dequeue()
    }
    try {
        [Environment]::SetEnvironmentVariable('MODRINTH_TOKEN', $null)
        [Environment]::SetEnvironmentVariable('CURSEFORGE_TOKEN', $null)
        Assert-Throws { Get-PublishingToken $Workspace 'CurseForge' -NonInteractive } 'token is required'
        $modToken = Get-PublishingToken $Workspace 'Modrinth'
        Assert ($modToken -eq "fake-mod-token-with'quote") 'First Modrinth prompt returns entered token'
        Assert ((Read-LocalSettings $Workspace 'Modrinth').Token -eq $modToken) 'Prompted token saved in separate Modrinth file'
        Assert ((Read-LocalSettings $Workspace 'Modrinth').Projects.omniwheel -eq 'private-slug') 'Saving token preserves local project settings'
        Assert ((Get-PublishingToken $Workspace 'Modrinth' -NonInteractive) -eq $modToken) 'Saved token reused without interaction for any Modrinth operation'
        $cfToken = Get-PublishingToken $Workspace 'CurseForge'
        Assert ($cfToken -eq 'fake-cf-token' -and (Read-LocalSettings $Workspace 'CurseForge').Token -eq $cfToken) 'CurseForge uses its own global token file'
        Assert ((Get-PublishingToken $Workspace 'Modrinth') -eq $modToken) 'CurseForge credentials do not overwrite Modrinth credentials'
        $replacement = Get-PublishingToken $Workspace 'Modrinth' -PromptForToken
        Assert ($replacement -eq 'replacement-mod-token' -and (Get-PublishingToken $Workspace 'Modrinth') -eq $replacement) 'Forced token entry replaces the saved global token'
        Assert ($answers.Count -eq 0) 'Only first-time or explicitly forced token prompts are used'
        [Environment]::SetEnvironmentVariable('MODRINTH_TOKEN', 'environment-mod-token')
        Assert ((Get-PublishingToken $Workspace 'Modrinth' -NonInteractive) -eq 'environment-mod-token') 'Explicit environment token retains precedence'
        $records = @(
            @{ Platform = 'Modrinth'; Project = 'AbCd1234'; Number = '2.1.0-forge-mc1.16.5'; Hash = 'hash1'; Id = 'file1' }
            @{ Platform = 'Modrinth'; Project = 'AbCd1234'; Number = '2.1.0-forge-mc1.21.1'; Hash = 'hash2'; Id = 'file2' }
            @{ Platform = 'CurseForge'; Project = '123456'; Number = '2.1.0-forge-mc1.16.5'; Hash = 'hash3'; Id = 'file3' }
        )
        Write-PublishRecords $Workspace $records
        Assert ((Reset-LocalPublishReceipt $Workspace 'Modrinth' 'AbCd1234' '2.1.0-forge-mc1.16.5') -eq 1) 'Reset removes exactly the requested platform/project/version receipt'
        $remaining = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        Assert (@($remaining).Count -eq 2 -and @($remaining | Where-Object Platform -eq 'CurseForge').Count -eq 1) 'Other platforms and versions retain their receipts'
        Assert ((Reset-LocalPublishReceipt $Workspace 'Modrinth' 'AbCd1234' '2.1.0-forge-mc1.16.5') -eq 0) 'Repeated reset is harmless'
        Assert ([IO.File]::ReadAllText($statePath) -notmatch 'fake-mod-token|replacement-mod-token|fake-cf-token') 'Credentials never enter publishing receipts'
        $modConfig = Join-Path $Workspace.ModsRoot 'omniwheel/mod.publish.psd1'
        Assert ([IO.File]::ReadAllText($modConfig) -notmatch 'fake-mod-token|replacement-mod-token|fake-cf-token') 'Credentials never enter tracked per-mod settings'
    } finally {
        [Environment]::SetEnvironmentVariable('MODRINTH_TOKEN', $oldModToken)
        [Environment]::SetEnvironmentVariable('CURSEFORGE_TOKEN', $oldCFToken)
        [IO.File]::WriteAllText($modPath, $originalModSettings)
        foreach ($temporaryFile in @($cfPath, $statePath)) { if (Test-Path -LiteralPath $temporaryFile) { Remove-Item -LiteralPath $temporaryFile } }
    }
    Write-Host 'All global token and publishing reset tests passed.' -ForegroundColor Green
}
Test-LocalPublishPersistence $w
