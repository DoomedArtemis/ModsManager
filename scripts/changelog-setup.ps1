. (Join-Path $PSScriptRoot 'changelog-editor.ps1')

function Read-ChangelogNotes([string]$Release) {
    Write-Host 'Paste Markdown notes, including headings, bullets and blank lines.'
    Write-Host "The ## $Release heading is added automatically."
    Write-Host 'Finish with :end on its own line, or :cancel to leave the file unchanged.'
    while ($true) {
        $lines = [Collections.Generic.List[string]]::new()
        while ($true) {
            $line = Read-Host
            if ($line -ceq ':cancel') { return $null }
            if ($line -ceq ':end') { break }
            $lines.Add($line)
        }
        try { return ConvertTo-ModChangelogNotes ($lines -join "`n") $Release }
        catch { Write-Host $_.Exception.Message; Write-Host 'Paste the notes again, then :end (or :cancel).' }
    }
}

function Invoke-AddModChangelog($Workspace, [string]$Mod = '', [string]$Release = '', [string]$ChangelogFile = '') {
    $items = @(Get-ModItems $Workspace)
    $names = @(@($items | Select-Object -ExpandProperty Mod) + @(Get-ChildItem -LiteralPath $Workspace.ModsRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) | Sort-Object -Unique)
    Write-Host 'Available mods:'
    foreach ($name in $names) { Write-Host "  $name" }
    if (-not $Mod) {
        $defaultMod = if ($names.Count -eq 1) { $names[0] } else { '' }
        $Mod = Read-SetupText 'Mod folder name (e.g. laboratoryblocks)' $defaultMod '^[a-z0-9][a-z0-9_-]*$' -Required
    }
    if ($Mod -cnotmatch '^[a-z0-9][a-z0-9_-]*$') { throw 'Changelog: use a lowercase mod folder name.' }
    $path = Join-Path (Join-Path $Workspace.ModsRoot $Mod) 'changelog.md'
    $text = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) } else { '' }
    $sections = @(Get-ModChangelogSections $text $path)
    $known = @(@($items | Where-Object Mod -CEQ $Mod | Select-Object -ExpandProperty Release) + @($sections | Where-Object Release -INE 'Unreleased' | Select-Object -ExpandProperty Release) | Sort-Object -Unique)
    Write-Host "Known mod releases for ${Mod}: $($known -join ', ')"
    if (-not $Release) {
        $defaultRelease = if ($known.Count -eq 1) { $known[0] } else { '' }
        $Release = Read-SetupText 'Mod release version (not Minecraft version; e.g. 1.0)' $defaultRelease '^[0-9][a-zA-Z0-9.+_-]*$' -Required
    }
    if ($Release -cnotmatch '^[0-9][a-zA-Z0-9.+_-]*$') { throw 'Changelog: invalid mod release version.' }
    $mode = 'add'
    $entry = @($sections | Where-Object Release -CEQ $Release)
    if ($entry.Count) {
        $previous = Read-ModReleaseChangelog $Workspace $Mod $Release
        if ($previous) {
            Write-Host "Existing notes for $Mod ${Release}:`n$previous"
            $mode = Read-SetupChoice 'This release already has notes' @('cancel', 'append', 'replace') @('Leave the existing entry unchanged', 'Add the new notes after the existing notes', 'Replace only this release, preserving other versions') 'cancel'
            if ($mode -eq 'cancel') { Write-Host 'Cancelled. Changelog unchanged.'; return }
        }
    }
    if ($ChangelogFile) { $notes = ConvertTo-ModChangelogNotes (Read-ChangelogFile $ChangelogFile) $Release }
    else {
        $inputMode = Read-SetupChoice 'Changelog input' @('paste', 'file', 'terminal') @('Open a multiline paste window; paste Markdown and click Save', 'Read Markdown from a UTF-8 file', 'Enter notes in this terminal; finish with :end') 'paste'
        if ($inputMode -eq 'file') {
            while ($true) {
                $filePath = Read-SetupText 'Markdown file path (:cancel to cancel)' '' '' -Required
                if ($filePath -ceq ':cancel') { Write-Host 'Cancelled. Changelog unchanged.'; return }
                try { $notes = ConvertTo-ModChangelogNotes (Read-ChangelogFile $filePath.Trim('"')) $Release; break }
                catch { Write-Host $_.Exception.Message }
            }
        } elseif ($inputMode -eq 'terminal') { $notes = Read-ChangelogNotes $Release }
        else { $notes = Show-ChangelogNotesEditor $Mod $Release }
    }
    if ($null -eq $notes) { Write-Host 'Cancelled. Changelog unchanged.'; return }
    $displayName = $Mod
    $matchingItems = @($items | Where-Object Mod -CEQ $Mod)
    if ($matchingItems.Count -and $matchingItems[0].Metadata.DisplayName) { $displayName = $matchingItems[0].Metadata.DisplayName }
    $configPath = Join-Path (Join-Path $Workspace.ModsRoot $Mod) 'mod.publish.psd1'
    if (Test-Path -LiteralPath $configPath) { $displayName = Get-Setting (Import-PowerShellDataFile $configPath) 'DisplayName' $displayName }
    $saved = Set-ModReleaseChangelog $Workspace $Mod $Release $notes $mode $displayName
    Write-Host "Saved $Mod $Release changelog: $saved"
    Write-Host 'Both Modrinth and CurseForge will use these notes for this mod release.'
}

function Invoke-RemoveModChangelog($Workspace, [string]$Mod = '', [string]$Release = '', [switch]$Yes) {
    $names = @(Get-ChildItem -LiteralPath $Workspace.ModsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'changelog.md') } | Select-Object -ExpandProperty Name | Sort-Object)
    if (-not $Mod) {
        if (-not $names.Count) { Write-Host 'No mod changelog files found.'; return }
        $Mod = Read-SetupChoice 'Mod changelog to edit (folder name or number)' $names @() $names[0]
    }
    if ($Mod -cnotmatch '^[a-z0-9][a-z0-9_-]*$') { throw 'Changelog: use a lowercase mod folder name.' }
    $path = Join-Path (Join-Path $Workspace.ModsRoot $Mod) 'changelog.md'
    if (-not (Test-Path -LiteralPath $path)) { throw "Changelog: missing $path." }
    $original = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $releases = @(Get-ModChangelogSections $original $path | Where-Object Release -INE 'Unreleased' | Select-Object -ExpandProperty Release)
    if (-not $Release) {
        if (-not $releases.Count) { Write-Host "No version changelogs to remove for $Mod."; return }
        $Release = Read-SetupChoice 'Mod release changelog to remove (version or number)' $releases @() $releases[0]
    }
    if ($Release -cnotin $releases) { throw "Changelog: no entry for $Mod $Release. Nothing was removed." }
    $notes = Read-ModReleaseChangelog $Workspace $Mod $Release
    Write-Host "Changelog selected for removal: $Mod $Release -> $path"
    if ($notes) { Write-Host $notes } else { Write-Host '(Empty release section)' }
    if (-not $Yes -and -not (Read-SetupBool "Remove the $Mod $Release section from the local changelog?")) { Write-Host 'Cancelled. Changelog unchanged.'; return }
    $saved = Remove-ModReleaseChangelog $Workspace $Mod $Release -ExpectedText $original
    Write-Host "Removed $Mod $Release changelog section: $saved"
    Write-Host 'Other releases are preserved. Already published platform changelogs are unchanged.'
}
