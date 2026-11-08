function Test-AddChangelogWorkflow($ParentWorkspace) {
    . (Join-Path $PSScriptRoot 'publish-setup.ps1')
    . (Join-Path $PSScriptRoot 'changelog-setup.ps1')
    $root = Join-Path $ParentWorkspace.Root 'add-changelog'
    $workspace = @{ Root = $root; IncomingRoot = (Join-Path $root 'incoming'); ModsRoot = (Join-Path $root 'mods') }
    New-Item -ItemType Directory -Path $workspace.ModsRoot -Force | Out-Null
    $notes = "## Added`n`n- **Dark blocks** and music discs.`n`n## Fixed`n`n- Inventory checks."
    $path = Set-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0' $notes -DisplayName 'Laboratory Blocks'
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0') -ceq $notes) 'Creates the per-mod changelog with an exact release section and complete Markdown'
    Assert ([IO.File]::ReadAllText($path).StartsWith("# Laboratory Blocks changelog`n`n## 1.0`n")) 'Creates the correct document and release headings'
    $first = [IO.File]::ReadAllText($path)
    Assert-Throws { Set-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0' 'Accidental overwrite.' } 'already has notes'
    Assert ([IO.File]::ReadAllText($path) -ceq $first) 'Existing notes cannot be silently overwritten'
    $null = Set-ModReleaseChangelog $workspace 'laboratoryblocks' '1.1' "## 1.1`n`n## Changed`n- New notes."
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.1') -ceq "## Changed`n- New notes.") 'A matching pasted version heading is accepted without duplication'
    Assert ([IO.File]::ReadAllText($path).EndsWith($first.Substring($first.IndexOf('## 1.0')))) 'Adding a release preserves the previous release verbatim'
    $null = Set-ModReleaseChangelog $workspace 'laboratoryblocks' '1.1' 'Appended notes.' 'append'
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.1') -ceq "## Changed`n- New notes.`n`nAppended notes.") 'Append adds notes within the correct release'
    $null = Set-ModReleaseChangelog $workspace 'laboratoryblocks' '1.1' 'Replacement notes.' 'replace'
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.1') -ceq 'Replacement notes.') 'Explicit replacement changes only the chosen release'
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0') -ceq $notes) 'Older release remains unchanged after append and replace'
    $before = [IO.File]::ReadAllText($path)
    foreach ($invalid in @('', "## 9.9`nWrong release.", "## Added`n- Notes.`n## Unreleased`nFuture notes.", "``````md`nUnclosed code.")) {
        Assert-Throws { Set-ModReleaseChangelog $workspace 'laboratoryblocks' '1.2' $invalid } 'Changelog:'
        Assert ([IO.File]::ReadAllText($path) -ceq $before) 'Invalid pasted notes leave the file unchanged'
    }
    Assert-Throws { Set-ModReleaseChangelog $workspace '../outside' '1.2' $notes } 'lowercase mod folder'
    Assert-Throws { Set-ModReleaseChangelog $workspace 'laboratoryblocks' '../1.2' $notes } 'mod release'
    $crlf = "# Existing changelog`r`n`r`n## Unreleased`r`n`r`nWork in progress.`r`n`r`n## [1.0] - 2026-11-08`r`n`r`nOld notes.`r`n"
    [IO.File]::WriteAllText($path, $crlf)
    $null = Set-ModReleaseChangelog $workspace 'laboratoryblocks' '1.1' 'New notes.'
    $saved = [IO.File]::ReadAllText($path)
    Assert ($saved.StartsWith($crlf.Substring(0, $crlf.IndexOf('## [1.0]')))) 'Unreleased section remains above the new release'
    Assert ($saved.Contains("## 1.1`r`n`r`nNew notes.`r`n`r`n## [1.0]")) 'Existing CRLF separators and dated headings survive insertion'
    $null = Set-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0' 'Updated old notes.' 'replace'
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.1') -ceq 'New notes.') 'Replacing a dated older release preserves newer notes'
    $answers = [Collections.Generic.Queue[string]]::new()
    function Read-Host([string]$Prompt) {
        if (-not $answers.Count) { throw "Unexpected Add Changelog prompt: $Prompt" }
        return $answers.Dequeue()
    }
    foreach ($answer in @('', '1.2', 'terminal', '## Added', '', '- **Pasted** notes.', '', '## Fixed', '- Fixed behavior.', ':end')) { $answers.Enqueue($answer) }
    Invoke-AddModChangelog $workspace
    Assert ($answers.Count -eq 0) 'Run action asks for mod and version, and accepts multiline Markdown until :end'
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.2') -ceq "## Added`n`n- **Pasted** notes.`n`n## Fixed`n- Fixed behavior.") 'Interactive paste preserves headings, emphasis, bullets and blank lines'
    $before = [IO.File]::ReadAllText($path)
    $answers.Enqueue('')
    Invoke-AddModChangelog $workspace 'laboratoryblocks' '1.2'
    Assert ([IO.File]::ReadAllText($path) -ceq $before) 'Existing release defaults to cancel'
    foreach ($answer in @('terminal', ':cancel')) { $answers.Enqueue($answer) }
    Invoke-AddModChangelog $workspace 'laboratoryblocks' '1.3'
    Assert ([IO.File]::ReadAllText($path) -ceq $before) 'Cancelling a paste does not create a release'
    foreach ($answer in @('terminal', ':end', '## 9.9', 'Wrong version.', ':end', '## Added', '- Corrected notes.', ':end')) { $answers.Enqueue($answer) }
    Invoke-AddModChangelog $workspace 'laboratoryblocks' '1.3'
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.3') -ceq "## Added`n- Corrected notes.") 'Empty and wrong-version pastes are retried without corrupting the document'
    $file = Join-Path $root 'notes with spaces.md'
    [IO.File]::WriteAllText($file, $notes)
    foreach ($answer in @('file', ('"' + $file + '"'))) { $answers.Enqueue($answer) }
    Invoke-AddModChangelog $workspace 'laboratoryblocks' '1.4'
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.4') -ceq $notes) 'File input handles quoted paths with spaces and preserves the Markdown'
    $dialogNotes = @'
## Added

- Complete dark laboratory blockset with a dedicated creative tab.
- **Exploration** by Cleyton Kauffman and **Pondering the Cosmos** by Ruskerdax music discs.
- Exploration can be found in abandoned mineshaft chests; Pondering the Cosmos in End City treasure chests, each with a 10% chance. Both also drop from creepers killed by skeletons.
- **Laboratory Soundtrack** advancement for playing either disc.

## Changed

- Existing laboratory advancements now accept dark variants.
- Renamed gray laboratory pillars to dark laboratory pillars, preserving existing blocks and items in saved worlds.

## Fixed

- Fixed inventory-based advancements failing when holding stacks larger than one item.
'@
    # Exercise real Windows controls and the Save handler without displaying a
    # dialog or touching the clipboard. The default workflow is tested below.
    $previousContext = [Threading.SynchronizationContext]::Current
    $editor = New-ChangelogEditor 'laboratoryblocks' '1.5'
    try {
        Assert ($editor.TextBox.Multiline -and $editor.TextBox.AcceptsReturn -and $editor.TextBox.AcceptsTab -and $null -eq $editor.Form.AcceptButton) 'Paste editor accepts multiline Markdown and ordinary Enter cannot submit it'
        $saveClick = $editor.SaveButton.GetType().GetMethod('OnClick', [Reflection.BindingFlags]'Instance,NonPublic')
        $null = $saveClick.Invoke($editor.SaveButton, @([EventArgs]::Empty))
        Assert ($null -eq $editor.Notes -and $editor.ErrorLabel.Text -match 'cannot be empty' -and $editor.Form.DialogResult -eq [Windows.Forms.DialogResult]::None) 'Empty Save keeps the editor open with an inline error'
        $editor.TextBox.Text = "## 9.9`r`nWrong release."
        $null = $saveClick.Invoke($editor.SaveButton, @([EventArgs]::Empty))
        Assert ($null -eq $editor.Notes -and $editor.ErrorLabel.Text -match 'paste only the notes' -and $editor.Form.DialogResult -eq [Windows.Forms.DialogResult]::None) 'Wrong release heading cannot close or submit the editor'
        $editor.TextBox.Text = $dialogNotes
        $null = $saveClick.Invoke($editor.SaveButton, @([EventArgs]::Empty))
        Assert ($editor.Notes.Replace("`r`n", "`n") -ceq $dialogNotes.Replace("`r`n", "`n") -and $editor.Form.DialogResult -eq [Windows.Forms.DialogResult]::OK) 'Real Save handler preserves the complete user-provided Laboratory Blocks Markdown without an end marker'
    } finally {
        $editor.Form.Dispose()
        [Threading.SynchronizationContext]::SetSynchronizationContext($previousContext)
    }
    $shown = @{}
    function Show-ChangelogNotesEditor([string]$Mod, [string]$Release) { $shown.Mod = $Mod; $shown.Release = $Release; return $dialogNotes }
    $answers.Enqueue('')
    Invoke-AddModChangelog $workspace 'laboratoryblocks' '1.5'
    Assert ($shown.Mod -ceq 'laboratoryblocks' -and $shown.Release -ceq '1.5' -and $answers.Count -eq 0) 'Default paste choice opens the editor for the selected mod and release without terminal line prompts'
    $expectedDialogNotes = $dialogNotes
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.5') -ceq $expectedDialogNotes) 'Entire pasted changelog is saved beneath one automatically generated release heading'
    $beforeCancel = [IO.File]::ReadAllText($path)
    $dialogNotes = $null
    $answers.Enqueue('paste')
    Invoke-AddModChangelog $workspace 'laboratoryblocks' '1.6'
    Assert ([IO.File]::ReadAllText($path) -ceq $beforeCancel) 'Cancelling the paste window leaves the changelog file unchanged'
    Assert ($answers.Count -eq 0 -and -not (Test-Path -LiteralPath ($path + '.tmp'))) 'Run workflow consumes expected answers and leaves no temporary files'
    $fixture = Read-ModJar (Join-Path $ParentWorkspace.IncomingRoot 'omniwheel-2.1.0-fabric-mc26.3.jar')
    $fixture.Mod = 'laboratoryblocks'; $fixture.Release = '1.5'
    $config = @{ Runtime = @{ Environment = 'client_only' }; Modrinth = @{ Project = 'preview-project' }; CurseForge = @{ Project = '123456' } }
    foreach ($platform in @('Modrinth', 'CurseForge')) {
        $plan = @(Get-UploadPlan $workspace @($fixture) $platform -SettingsOverrides @{ laboratoryblocks = $config })[0]
        Assert ($plan.Data.changelog -ceq $expectedDialogNotes) "$platform upload consumes the complete Markdown saved by the paste-window workflow"
    }
    Write-Host 'All Add Changelog workflow tests passed.' -ForegroundColor Green
}
Test-AddChangelogWorkflow $w
