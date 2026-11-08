# Exercises real prompts with queued terminal answers, saving only temporary fixtures.
function Test-PublishSetupWorkflow($Workspace, $FixtureItem) {
    . (Join-Path $PSScriptRoot 'publish-setup.ps1')
    $setupPath = Join-Path $Workspace.ModsRoot 'omniwheel/mod.publish.psd1'
    $originalSettings = [IO.File]::ReadAllText($setupPath)
    $modNotesPath = Join-Path $Workspace.ModsRoot 'omniwheel/changelog.md'
    $originalNotes = [IO.File]::ReadAllText($modNotesPath)
    $fixtureNotes = "**Added:**`n- Release-specific notes."
    $answers = [Collections.Generic.Queue[string]]::new()
    $allowManualNotes = $false
    function Read-Host([string]$Prompt) {
        if ($Prompt -match '^Supported Java') { throw 'Java must never be requested interactively.' }
        if (-not $allowManualNotes -and $Prompt -match '^Release notes') { throw 'Changelog must be selected automatically from the mod Markdown file.' }
        if (-not $answers.Count) { throw "Unexpected prompt: $Prompt" }
        return $answers.Dequeue()
    }
    try {
        [IO.File]::WriteAllText($modNotesPath, "# Omniwheel changelog`n`n## 2.1.0`n`n$fixtureNotes`n")
        foreach ($answer in @(
            'not-a-numeric-id', '123456', "Omniwheel's mod",
            'invalid-environment', '2',
            'replace', 'INVALID SLUG', 'fabric-api', 'bad-id', '306612', '1', 'no',
            'yes', 'markdown', 'yes', 'Java 25', '12345'
        )) { $answers.Enqueue($answer) }
        $projects = @{}
        Invoke-ModPublishSetup $Workspace @($FixtureItem) 'CurseForge' $projects
        Assert ($answers.Count -eq 0) 'CurseForge wizard consumed all expected answers'
        $savedConfig = Import-PowerShellDataFile -LiteralPath $setupPath
        $savedEffective = Get-EffectiveModSettings $savedConfig $FixtureItem
        Assert ($savedConfig.DisplayName -eq "Omniwheel's mod") 'PSD1 serializer escapes apostrophes'
        Assert ($savedConfig.CurseForge.Project -eq '123456') 'Project ID saved for later runs'
        Assert ($savedEffective.Runtime.Environment -eq 'client_only' -and -not $savedEffective.Runtime.ContainsKey('JavaVersions')) 'Environment saved without a per-mod Java declaration'
        Assert ($savedEffective.CurseForge.Dependencies.Count -eq 1 -and $savedEffective.CurseForge.Dependencies[0].Slug -eq 'fabric-api') 'Dependency wizard persists relations'
        $savedPlan = @(Get-UploadPlan $Workspace @($FixtureItem) 'CurseForge')[0]
        Assert ($savedPlan.Data.releaseType -eq 'release' -and $savedPlan.Data.isMarkedForManualRelease) 'Automatic channel and advanced choices reach upload plan'
        Assert ($savedPlan.Data.gameVersions[0] -eq 12345 -and $savedPlan.Data.gameVersionNames -contains 'Java 25') 'Advanced compatibility choices reach upload plan'
        Assert ($savedPlan.Data.changelog -ceq $fixtureNotes) 'Release notes are selected from the per-mod Markdown file without prompting'
        Invoke-ModPublishSetup $Workspace @($FixtureItem) 'CurseForge' @{}
        Assert ($answers.Count -eq 0) 'Configured release reused without prompting'
        # Only platform settings are needed on the second platform; runtime is shared.
        foreach ($answer in @('omniwheel', 'replace', 'project', 'bad', 'P7dR8mSH', '', 'required', 'no', 'yes', 'unlisted', 'yes', 'default')) { $answers.Enqueue($answer) }
        Invoke-ModPublishSetup $Workspace @($FixtureItem) 'Modrinth' @{}
        Assert ($answers.Count -eq 0) 'Second platform reuses runtime answers'
        $savedMR = @(Get-UploadPlan $Workspace @($FixtureItem) 'Modrinth')[0]
        Assert ($savedMR.Data.dependencies.Count -eq 1 -and $savedMR.Data.dependencies[0].project_id -eq 'P7dR8mSH') 'Modrinth dependencies reach upload payload'
        Assert ($savedMR.Data.status -eq 'unlisted' -and $savedMR.Data.featured) 'Modrinth visibility and featured prompts work'
        $otherItem = Read-ModJar $FixtureItem.Path
        $otherItem.Minecraft = '26.2'
        $otherEffective = Get-EffectiveModSettings (Import-PowerShellDataFile -LiteralPath $setupPath) $otherItem
        Assert ($otherEffective.Runtime.Environment -eq 'client_only') 'Client/server setting is shared with different Minecraft targets'
        # Force review, accept existing defaults, and clear dependencies interactively.
        foreach ($answer in @('', '', '', 'none', 'no')) { $answers.Enqueue($answer) }
        Invoke-ModPublishSetup $Workspace @($FixtureItem) 'Modrinth' @{} -Configure
        Assert ($answers.Count -eq 0) 'Configure supports reviewing saved settings'
        $reviewed = @(Get-UploadPlan $Workspace @($FixtureItem) 'Modrinth')[0]
        Assert ($reviewed.Data.dependencies.Count -eq 0) 'Dependencies can be cleared without editing the PSD1'
        # Metadata errors detected by the real planner reopen setup instead of
        # persisting a completed but unusable configuration.
        foreach ($answer in @(
            '', '', 'keep', 'yes', '', '', 'Server', '',
            '', 'keep', 'no'
        )) { $answers.Enqueue($answer) }
        Invoke-ModPublishSetup $Workspace @($FixtureItem) 'CurseForge' @{} -Configure
        Assert ($answers.Count -eq 0) 'Invalid advanced compatibility tag reopens setup for correction'
        $corrected = @(Get-UploadPlan $Workspace @($FixtureItem) 'CurseForge')[0]
        Assert ($corrected.Data.gameVersionNames -notcontains 'Server') 'Invalid side tag not saved as completed setup'
        # Exercise a genuine Forge fixture, whose manifest cannot choose an environment.
        $forgePath = Join-Path $Workspace.IncomingRoot 'omniwheel-2.1.0-forge-mc26.3.jar'
        New-TestJar $forgePath 'META-INF/mods.toml'
        try {
            $forgeItem = Read-ModJar $forgePath
            foreach ($answer in @('keep', 'no')) { $answers.Enqueue($answer) }
            Invoke-ModPublishSetup $Workspace @($forgeItem) 'CurseForge' @{}
            Assert ($answers.Count -eq 0) 'A new loader reuses the mod-wide client/server setting without asking again'
            $forgePlan = @(Get-UploadPlan $Workspace @($forgeItem) 'CurseForge')[0]
            Assert ($forgePlan.Runtime.Environment -eq 'client_only' -and $forgePlan.Data.gameVersionNames -notcontains 'Server') 'Forge publishes with the same client/server setting already chosen for the mod'
        } finally { Remove-Item -LiteralPath $forgePath }
        $markdown = @(
            '**Added:**'
            '- New Clipboard entry type.'
            '- Global/local chat toggle.'
            ''
            '**Changed:**'
            '- Unified highlight fade animations across editor controls.'
            '- Updated the default profile to use the new entry type and local messaging toggle instead of custom logic.'
        ) -join "`n"
        $allowManualNotes = $true
        $answers.Enqueue(':paste')
        foreach ($line in $markdown.Split([char]10)) { $answers.Enqueue($line) }
        $answers.Enqueue(':end')
        Assert ((Read-SetupChangelog) -ceq $markdown) 'Optional manual multiline input still preserves Markdown'
        Assert ($answers.Count -eq 0) 'Multiline Markdown input stops only at the explicit end marker'
        [IO.File]::WriteAllText($modNotesPath, "## 2.1.0`n`n$markdown`n")
        Invoke-ModPublishSetup $Workspace @($FixtureItem) 'Modrinth' @{} -PromptForChangelog
        $markdownPlan = @(Get-UploadPlan $Workspace @($FixtureItem) 'Modrinth')[0]
        Assert ($markdownPlan.Data.changelog -ceq $markdown) 'Headings, list markers and blank lines survive setup, saving and upload planning'
        $notesPath = Join-Path $Workspace.Root 'release notes.md'
        $fileNotes = $markdown.Replace("`n", "`r`n") + "`r`n`r`n"
        [IO.File]::WriteAllText($notesPath, $fileNotes, [Text.UTF8Encoding]::new($false))
        $answers.Enqueue(':file "' + $notesPath + '"')
        Assert ((Read-SetupChangelog) -ceq $fileNotes) 'Quoted Markdown file paths preserve original line endings and trailing blank lines'
        Invoke-ModPublishSetup $Workspace @($FixtureItem) 'Modrinth' @{} -ChangelogInput @{ Value = (Read-ChangelogFile $notesPath) }
        Assert (@(Get-UploadPlan $Workspace @($FixtureItem) 'Modrinth' @{} $fileNotes $true)[0].Data.changelog -ceq $fileNotes) 'Explicit file override remains available for a single invocation'
        $roundtrip = @{ Example = @(@{ Enabled = $true; Note = "Multiline`nwith 'quotes'" }); Empty = @(); Count = 123; Disabled = $false }
        $roundtripPath = Join-Path $Workspace.Root 'config/roundtrip.psd1'
        Save-ModSettings $roundtripPath $roundtrip
        $loaded = Import-PowerShellDataFile -LiteralPath $roundtripPath
        Assert ($loaded.Example[0].Note -eq $roundtrip.Example[0].Note -and $loaded.Empty.Count -eq 0 -and $loaded.Disabled -eq $false -and $loaded.Count -eq 123) 'Serializer preserves nested arrays, booleans, numbers and multiline strings'
        Assert ([IO.File]::ReadAllText($setupPath) -notmatch 'MODRINTH_TOKEN|CURSEFORGE_TOKEN') 'Setup saves metadata without tokens'
        $legacyJava = Import-PowerShellDataFile -LiteralPath $setupPath
        $legacyJava.Runtime.JavaVersions = @(8)
        $legacyJava.Overrides += @{ Versions = @('26.3'); Settings = @{ Runtime = @{ JavaVersions = @(17) } } }
        Save-ModSettings $setupPath $legacyJava
        Assert ([IO.File]::ReadAllText($setupPath) -notmatch 'JavaVersions') 'Saving settings removes legacy Java overrides at every level'
    } finally { [IO.File]::WriteAllText($setupPath, $originalSettings); [IO.File]::WriteAllText($modNotesPath, $originalNotes) }
    Write-Host 'All interactive setup tests passed.' -ForegroundColor Green
}
Test-PublishSetupWorkflow $w $items[0]
