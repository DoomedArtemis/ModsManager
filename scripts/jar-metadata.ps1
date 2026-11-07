# Read the scalar fields needed from Forge/NeoForge TOML without treating
# descriptions or dependency-side restrictions as a mod-wide environment.
function Read-ForgeModMetadata([string]$Text) {
    $root = @{}
    $mods = @()
    $dependencies = @()
    $current = $root
    $multiline = ''
    foreach ($rawLine in ($Text -split '\r?\n')) {
        $line = $rawLine.Trim()
        if ($multiline) {
            if ($line.Contains($multiline)) { $multiline = '' }
            continue
        }
        if ($line -match '^\[\[mods\]\]\s*(?:#.*)?$') {
            $current = @{}; $mods += ,$current; continue
        }
        if ($line -match '^\[\[dependencies\.(?:"[^"]+"|''[^'']+''|[A-Za-z0-9_-]+)\]\]\s*(?:#.*)?$') {
            $current = @{}; $dependencies += ,$current; continue
        }
        if ($line.StartsWith('[')) { $current = @{}; continue }
        if ($line -notmatch '^([A-Za-z][A-Za-z0-9_]*)\s*=\s*(.*)$') { continue }
        $key = $Matches[1]; $value = $Matches[2]
        if ($value.StartsWith('"""') -or $value.StartsWith("'''")) {
            $delimiter = $value.Substring(0, 3)
            if (-not $value.Substring(3).Contains($delimiter)) { $multiline = $delimiter }
            continue
        }
        if ($key -notin @('modId', 'version', 'displayName', 'versionRange', 'side', 'mandatory', 'type', 'clientSideOnly', 'loaderVersion')) { continue }
        if ($value -match '^"((?:\\.|[^"\\])*)"\s*(?:#.*)?$') {
            $current[$key] = ConvertFrom-Json -InputObject ('"' + $Matches[1] + '"')
        } elseif ($value -match "^'([^']*)'\s*(?:#.*)?$") {
            $current[$key] = $Matches[1]
        } elseif ($value -match '^(true|false)\s*(?:#.*)?$') {
            $current[$key] = $Matches[1] -eq 'true'
        }
    }
    return [pscustomobject]@{ Root = $root; Mods = $mods; Dependencies = $dependencies }
}

function Assert-JarMinecraftConstraint([string]$Constraint, [string]$Minecraft) {
    if ($Constraint -match '^\[([^,\[\]]+)\]$') {
        if ($Matches[1] -cne $Minecraft) { throw "JAR manifest targets Minecraft $($Matches[1]), but its filename targets $Minecraft." }
    } elseif ($Minecraft -match '^\d+(\.\d+){1,3}$' -and $Constraint -match '^([\[\(])([^,]*),([^\]\)]*)([\]\)])$') {
        $lowerInclusive = $Matches[1] -eq '['; $upperInclusive = $Matches[4] -eq ']'
        $lower = $Matches[2].Trim(); $upper = $Matches[3].Trim()
        if ($lower -match '^\d+(\.\d+){1,3}$') {
            $comparison = Compare-GameVersion $Minecraft $lower
            if ($comparison -lt 0 -or ($comparison -eq 0 -and -not $lowerInclusive)) { throw "Minecraft $Minecraft is outside the JAR manifest range $Constraint." }
        }
        if ($upper -match '^\d+(\.\d+){1,3}$') {
            $comparison = Compare-GameVersion $Minecraft $upper
            if ($comparison -gt 0 -or ($comparison -eq 0 -and -not $upperInclusive)) { throw "Minecraft $Minecraft is outside the JAR manifest range $Constraint." }
        }
    }
}

function Get-PublishItems($Workspace, [string[]]$Mod = @('all'), [string[]]$Version = @('all'), [string[]]$Loader = @('all'), [string]$ReleaseVersion, [ValidateSet('auto', 'incoming', 'published', 'all')][string]$Source = 'auto') {
    $items = @(Get-ModItems $Workspace $Mod $Version $Loader $ReleaseVersion)
    $incoming = @($items | Where-Object { Test-Path -LiteralPath (Join-Path $Workspace.IncomingRoot $_.FileName) })
    if ($Source -eq 'incoming' -or ($Source -eq 'auto' -and $incoming.Count)) { return $incoming }
    if ($Source -eq 'published') { return @($items | Where-Object { $_.Path.StartsWith($Workspace.ModsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) }) }
    return $items
}
