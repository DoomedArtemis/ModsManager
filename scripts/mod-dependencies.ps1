# Loader declarations are read per binary. Hosting project identities are shared.
function Get-JarDependencyDeclarations($Zip, [string]$Loader, $Manifest) {
    $declarations = @()
    $provided = @()
    if ($Loader -eq 'fabric') {
        $provided = @([string](Get-JsonProperty $Manifest 'id' '')) + @(Get-JsonProperty $Manifest 'provides' @())
        foreach ($section in @('depends', 'recommends', 'suggests', 'breaks', 'conflicts')) {
            $values = Get-JsonProperty $Manifest $section
            if ($null -eq $values) { continue }
            foreach ($property in $values.PSObject.Properties) {
                $type = switch ($section) { depends { 'required' }; breaks { 'incompatible' }; conflicts { 'review' }; default { 'optional' } }
                $declarations += [pscustomobject]@{ ModId = $property.Name; Type = $type; Constraint = $property.Value; Source = $section; Side = 'BOTH' }
            }
        }
    } elseif ($Loader -eq 'quilt') {
        $quilt = Get-JsonProperty $Manifest 'quilt_loader'
        $provided = @([string](Get-JsonProperty $quilt 'id' ''))
        foreach ($section in @('depends', 'breaks')) {
            foreach ($dep in @(Get-JsonProperty $quilt $section @())) {
                $id = [string](Get-JsonProperty $dep 'id' '')
                $type = if ($section -eq 'breaks') { 'incompatible' } elseif (Get-JsonProperty $dep 'optional' $false) { 'optional' } else { 'required' }
                # Conditional / alternative dependency expressions need review.
                if (-not $id -or $null -ne (Get-JsonProperty $dep 'unless')) { $type = 'review' }
                $declarations += [pscustomobject]@{ ModId = $id; Type = $type; Constraint = (Get-JsonProperty $dep 'versions' '*'); Source = "quilt_loader.$section"; Side = 'BOTH' }
            }
        }
    } else {
        $provided = @($Manifest.Mods | ForEach-Object { Get-Setting $_ 'modId' '' })
        foreach ($dep in $Manifest.Dependencies) {
            $type = [string](Get-Setting $dep 'type' '')
            if (-not $type) { $type = if (Get-Setting $dep 'mandatory' $true) { 'required' } else { 'optional' } }
            if ($type -notin @('required', 'optional', 'incompatible')) { $type = 'review' }
            $declarations += [pscustomobject]@{ ModId = [string](Get-Setting $dep 'modId' ''); Type = $type; Constraint = (Get-Setting $dep 'versionRange' '*'); Source = 'dependencies'; Side = (Get-Setting $dep 'side' 'BOTH') }
        }
    }
    # Nested mod IDs are already supplied by this binary. Do not require users
    # to download them separately. Read nested manifests without extracting files.
    $bundled = @()
    foreach ($entry in @($Zip.Entries | Where-Object { $_.FullName -like '*.jar' })) {
        $stream = $entry.Open()
        $nested = $null
        try {
            $nested = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
            foreach ($name in @('fabric.mod.json', 'quilt.mod.json', 'META-INF/mods.toml', 'META-INF/neoforge.mods.toml')) {
                $metadataEntry = $nested.GetEntry($name)
                if (-not $metadataEntry) { continue }
                $reader = [IO.StreamReader]::new($metadataEntry.Open())
                try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
                if ($name.EndsWith('.json')) {
                    $metadata = $text | ConvertFrom-Json
                    if ($name -eq 'quilt.mod.json') { $metadata = $metadata.quilt_loader }
                    $bundled += [string](Get-JsonProperty $metadata 'id' '')
                } else { $bundled += @( (Read-ForgeModMetadata $text).Mods | ForEach-Object { Get-Setting $_ 'modId' '' }) }
            }
        } finally { if ($nested) { $nested.Dispose() }; $stream.Dispose() }
    }
    foreach ($dep in $declarations) {
        $ignored = ''
        if ($dep.ModId -in @('minecraft', 'java', 'fabricloader', 'quilt_loader', 'forge', 'neoforge', 'fml')) { $ignored = 'runtime' }
        elseif ($dep.ModId -and $dep.ModId -in $provided) { $ignored = 'provided by this JAR' }
        elseif ($dep.ModId -and $dep.ModId -in $bundled -and $dep.Type -ne 'incompatible') { $ignored = 'bundled inside this JAR' }
        $dep | Add-Member -NotePropertyName Ignored -NotePropertyValue $ignored
        $dep
    }
}

function Get-DependencyProjectMappings {
    $path = Join-Path (Split-Path $PSScriptRoot -Parent) 'config/dependency-projects.psd1'
    if (-not (Test-Path -LiteralPath $path)) { throw 'Automatic dependencies: shared config/dependency-projects.psd1 is missing.' }
    return Import-PowerShellDataFile -LiteralPath $path
}

function Get-DependencyScan($Item, [ValidateSet('Modrinth', 'CurseForge')][string]$Platform, [hashtable]$Mappings = (Get-DependencyProjectMappings)) {
    if (-not $Item.PSObject.Properties['DeclaredDependencies']) { return }
    foreach ($dep in $Item.DeclaredDependencies) {
        $status = 'resolved'; $project = @{}
        if ($dep.Ignored) { $status = 'ignored' }
        elseif ($dep.Type -eq 'review' -or ($dep.Type -eq 'incompatible' -and [string]$dep.Constraint -notin @('*', '', '(,)'))) { $status = 'needs review' }
        elseif (-not $Mappings.ContainsKey($dep.ModId) -or -not $Mappings[$dep.ModId].ContainsKey($Platform)) { $status = 'unmapped' }
        else { $project = $Mappings[$dep.ModId][$Platform] }
        [pscustomobject]@{ FileName = $Item.FileName; ModId = $dep.ModId; Type = $dep.Type; Constraint = $dep.Constraint; Source = $dep.Source; Side = $dep.Side; Status = $status; Ignored = $dep.Ignored; Project = $project; Platform = $Platform }
    }
}

function Get-AutomaticDependencies($Item, [string]$Platform) {
    $selected = @{}
    foreach ($row in @(Get-DependencyScan $Item $Platform)) {
        if ($row.Status -eq 'ignored') { continue }
        if ($row.Status -ne 'resolved') {
            throw "Automatic dependencies: $($Item.FileName): '$($row.ModId)' ($($row.Source)) is $($row.Status). Add a verified project mapping in config/dependency-projects.psd1 or choose manual dependencies for this release."
        }
        $type = $row.Type
        if ($Platform -eq 'CurseForge') { $type = @{ required = 'requiredDependency'; optional = 'optionalDependency'; incompatible = 'incompatible' }[$type] }
        $dep = @{ Type = $type }
        foreach ($key in @('ProjectId', 'Slug')) { if ($row.Project.ContainsKey($key)) { $dep[$key] = $row.Project[$key] } }
        $identity = if ($Platform -eq 'Modrinth') { [string](Get-Setting $dep 'ProjectId' '') } else { [string](Get-Setting $dep 'Slug' '') }
        if (-not $identity) { throw "Automatic dependencies: invalid $Platform mapping for '$($row.ModId)'." }
        if ($selected.ContainsKey($identity)) {
            $previous = $selected[$identity].Type
            if (($previous -eq 'incompatible') -ne ($type -eq 'incompatible')) { throw "Automatic dependencies: contradictory declarations for '$($row.ModId)'." }
            if ($previous -in @('required', 'requiredDependency')) { continue }
        }
        $selected[$identity] = $dep
    }
    return @($selected.Values)
}
