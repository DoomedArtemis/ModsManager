function Initialize-ModChangelog($Workspace, $Items, [hashtable]$Config) {
    $members = @($Items)
    if (-not $members.Count) { return }
    $directory = Join-Path $Workspace.ModsRoot $members[0].Mod
    $path = Join-Path $directory 'changelog.md'
    if (Test-Path -LiteralPath $path) { return }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $text = '# ' + [string](Get-Setting $Config 'DisplayName' $members[0].Mod) + " changelog`n"
    foreach ($release in @($members.Release | Sort-Object -Unique -Descending)) {
        $notes = ''
        foreach ($item in @($members | Where-Object Release -CEQ $release)) {
            $effective = Get-EffectiveModSettings $Config $item
            foreach ($platform in @('Modrinth', 'CurseForge')) {
                $candidate = [string](Get-Setting (Get-Setting $effective $platform @{}) 'Changelog' '')
                if ($candidate -and -not $notes) { $notes = $candidate }
            }
        }
        $text += "`n## $release`n`n$notes`n"
    }
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
    Write-Host "Created $path. Add release notes beneath each ## <mod-version> heading."
}

function Get-ModChangelogSections([string]$Text, [string]$Path = 'changelog.md') {
    $sections = @()
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $current = $null; $fenceCharacter = ''; $fenceLength = 0
    foreach ($lineMatch in [regex]::Matches($Text, '[^\r\n]+(?:\r\n|\n|\r|$)|\r\n|\n|\r')) {
        $line = $lineMatch.Value.TrimEnd([char[]]"`r`n")
        if ($fenceCharacter) {
            if ($line -match ('^[ ]{0,3}' + [regex]::Escape($fenceCharacter) + '{' + $fenceLength + ',}[ \t]*$')) { $fenceCharacter = '' }
            continue
        }
        if ($line -match '^[ ]{0,3}(`{3,}|~{3,})') {
            $fenceCharacter = $Matches[1].Substring(0, 1); $fenceLength = $Matches[1].Length
            continue
        }
        if ($line -notmatch '^[ ]{0,3}##[ \t]+(?<label>\[[^\]]+\]|[^ \t]+)(?:[ \t]+.*)?$') { continue }
        $label = $Matches.label.Trim([char[]]'[]')
        if ($label.StartsWith('v', [StringComparison]::Ordinal)) { $label = $label.Substring(1) }
        # Content headings such as ## Added belong to the selected release.
        # Only another release or Unreleased ends its notes.
        if ($label -notmatch '^[0-9][a-zA-Z0-9.+_-]*$' -and $label -ine 'Unreleased') { continue }
        if ($current) { $current.End = $lineMatch.Index }
        if ($label -ine 'Unreleased' -and -not $seen.Add($label)) { throw "Changelog: duplicate ## $label section in $Path." }
        $current = [pscustomobject]@{ Release = $label; HeadingStart = $lineMatch.Index; BodyStart = $lineMatch.Index + $lineMatch.Length; End = $Text.Length }
        $sections += $current
    }
    if ($fenceCharacter) { throw "Changelog: close the fenced code block in $Path before saving or publishing." }
    return $sections
}

function Read-ModReleaseChangelog($Workspace, [string]$Mod, [string]$Release) {
    $path = Join-Path (Join-Path $Workspace.ModsRoot $Mod) 'changelog.md'
    if (-not (Test-Path -LiteralPath $path)) { throw "Changelog: missing $path. Add a ## $Release section." }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $section = @(Get-ModChangelogSections $text $path | Where-Object Release -CEQ $Release)
    if (-not $section.Count) { throw "Changelog: add a ## $Release section to $path. Another release's notes will not be used." }
    return $text.Substring($section[0].BodyStart, $section[0].End - $section[0].BodyStart).Trim([char[]]"`r`n")
}

function ConvertTo-ModChangelogNotes([string]$Notes, [string]$Release) {
    $notesText = $Notes.Trim([char[]]"`r`n")
    if ([string]::IsNullOrWhiteSpace($notesText)) { throw 'Changelog: notes cannot be empty.' }
    $sections = @(Get-ModChangelogSections $notesText 'pasted notes')
    # Accept a pasted matching release heading without nesting it or duplicating it.
    if ($sections.Count -eq 1 -and $sections[0].Release -ceq $Release -and $sections[0].HeadingStart -eq 0) {
        $notesText = $notesText.Substring($sections[0].BodyStart).Trim([char[]]"`r`n")
    } elseif ($sections.Count) {
        throw "Changelog: paste only the notes for $Release. Other version headings and Unreleased belong in separate entries."
    }
    if ([string]::IsNullOrWhiteSpace($notesText)) { throw 'Changelog: notes cannot be empty.' }
    return $notesText
}

function Set-ModReleaseChangelog($Workspace, [string]$Mod, [string]$Release, [string]$Notes, [ValidateSet('add', 'append', 'replace')][string]$Mode = 'add', [string]$DisplayName = '') {
    if ($Mod -cnotmatch '^[a-z0-9][a-z0-9_-]*$') { throw 'Changelog: use a lowercase mod folder name, such as laboratoryblocks.' }
    if ($Release -cnotmatch '^[0-9][a-zA-Z0-9.+_-]*$') { throw 'Changelog: enter the mod release, such as 1.0 or 2.1.0-beta.1.' }
    $notesText = ConvertTo-ModChangelogNotes $Notes $Release
    $directory = Join-Path $Workspace.ModsRoot $Mod
    $path = Join-Path $directory 'changelog.md'
    $existed = Test-Path -LiteralPath $path
    $original = if ($existed) { [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) } else { '' }
    $sections = @(Get-ModChangelogSections $original $path)
    $section = @($sections | Where-Object Release -CEQ $Release)
    $newline = "`n"
    if ($original.Contains("`r`n")) { $newline = "`r`n" }
    if ($section.Count) {
        $entry = $section[0]
        $previous = $original.Substring($entry.BodyStart, $entry.End - $entry.BodyStart).Trim([char[]]"`r`n")
        if ($previous -and $Mode -eq 'add') { throw "Changelog: $Mod $Release already has notes. Choose append or replace." }
        if ($previous -and $Mode -eq 'append') { $notesText = $previous + $newline + $newline + $notesText }
        $prefix = $original.Substring(0, $entry.BodyStart)
        if (-not $prefix.EndsWith("`n")) { $prefix += $newline }
        $text = $prefix + $newline + $notesText + $newline
        if ($entry.End -lt $original.Length) { $text += $newline + $original.Substring($entry.End) }
    } else {
        $releases = @($sections | Where-Object Release -INE 'Unreleased')
        $offset = $original.Length
        if ($releases.Count) { $offset = $releases[0].HeadingStart }
        $prefix = $original.Substring(0, $offset)
        if (-not $original.Trim()) {
            if (-not $DisplayName) { $DisplayName = $Mod }
            $prefix = '# ' + $DisplayName.Replace("`r", '').Replace("`n", '') + ' changelog'
        }
        $text = $prefix.TrimEnd([char[]]"`r`n") + $newline + $newline + "## $Release" + $newline + $newline + $notesText + $newline
        if ($offset -lt $original.Length) { $text += $newline + $original.Substring($offset) }
    }
    $writtenSections = @(Get-ModChangelogSections $text $path | Where-Object Release -CEQ $Release)
    if ($writtenSections.Count -ne 1 -or $text.Substring($writtenSections[0].BodyStart, $writtenSections[0].End - $writtenSections[0].BodyStart).Trim([char[]]"`r`n") -cne $notesText) {
        throw 'Changelog: could not preserve the complete release notes. No file was changed.'
    }
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $temporary = $path + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $text, [Text.UTF8Encoding]::new($false))
        if ((Test-Path -LiteralPath $path) -ne $existed -or ($existed -and [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) -cne $original)) { throw 'Changelog: the file changed while editing. Run Add Changelog again.' }
        Move-Item -LiteralPath $temporary -Destination $path -Force
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
    return $path
}

function Remove-ModReleaseChangelog($Workspace, [string]$Mod, [string]$Release, [string]$ExpectedText) {
    if ($Mod -cnotmatch '^[a-z0-9][a-z0-9_-]*$') { throw 'Changelog: use a lowercase mod folder name.' }
    if ($Release -cnotmatch '^[0-9][a-zA-Z0-9.+_-]*$') { throw 'Changelog: enter a specific mod release version.' }
    $path = Join-Path (Join-Path $Workspace.ModsRoot $Mod) 'changelog.md'
    if (-not (Test-Path -LiteralPath $path)) { throw "Changelog: missing $path." }
    $original = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    if ($PSBoundParameters.ContainsKey('ExpectedText') -and $original -cne $ExpectedText) { throw 'Changelog: the file changed while reviewing. Run Remove Changelog again.' }
    $sections = @(Get-ModChangelogSections $original $path)
    $selected = @($sections | Where-Object Release -CEQ $Release)
    if (-not $selected.Count) { throw "Changelog: no ## $Release section in $path. Nothing was removed." }
    $entry = $selected[0]
    $text = $original.Remove($entry.HeadingStart, $entry.End - $entry.HeadingStart)
    $remaining = @(Get-ModChangelogSections $text $path)
    if ($remaining.Count -ne $sections.Count - 1 -or @($remaining | Where-Object Release -CEQ $Release).Count) { throw 'Changelog: could not remove exactly one release section. No file was changed.' }
    $temporary = $path + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $text, [Text.UTF8Encoding]::new($false))
        if (-not (Test-Path -LiteralPath $path) -or [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) -cne $original) { throw 'Changelog: the file changed while editing. Run Remove Changelog again.' }
        Move-Item -LiteralPath $temporary -Destination $path -Force
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
    return $path
}
