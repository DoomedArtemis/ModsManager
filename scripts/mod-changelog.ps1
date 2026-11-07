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

function Read-ModReleaseChangelog($Workspace, [string]$Mod, [string]$Release) {
    $path = Join-Path (Join-Path $Workspace.ModsRoot $Mod) 'changelog.md'
    if (-not (Test-Path -LiteralPath $path)) { throw "Changelog: missing $path. Add a ## $Release section." }
    $text = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
    $sections = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $current = $null; $start = 0; $fenceCharacter = ''; $fenceLength = 0
    foreach ($lineMatch in [regex]::Matches($text, '[^\r\n]+(?:\r\n|\n|\r|$)|\r\n|\n|\r')) {
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
        if ($current) { $sections[$current] = $text.Substring($start, $lineMatch.Index - $start).Trim([char[]]"`r`n") }
        $current = $null
        if ($label.StartsWith('v', [StringComparison]::Ordinal)) { $label = $label.Substring(1) }
        if ($label -match '^[0-9][a-zA-Z0-9.+_-]*$') {
            if ($sections.ContainsKey($label)) { throw "Changelog: duplicate ## $label section in $path." }
            $current = $label
            # Reserve the section immediately, including empty release sections.
            $sections[$current] = ''
            $start = $lineMatch.Index + $lineMatch.Length
        }
    }
    if ($current) { $sections[$current] = $text.Substring($start).Trim([char[]]"`r`n") }
    if (-not $sections.ContainsKey($Release)) { throw "Changelog: add a ## $Release section to $path. Another release's notes will not be used." }
    return $sections[$Release]
}
