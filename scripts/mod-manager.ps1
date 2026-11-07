Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.Net.Http
. (Join-Path $PSScriptRoot 'mod-runtime.ps1')
. (Join-Path $PSScriptRoot 'jar-metadata.ps1')
. (Join-Path $PSScriptRoot 'mod-changelog.ps1')

function Get-Setting($Table, [string]$Key, $Default = $null) {
    if ($Table.ContainsKey($Key)) { return $Table[$Key] }
    return $Default
}

function Get-Workspace([string]$Root = (Split-Path $PSScriptRoot -Parent)) {
    $rootPath = [IO.Path]::GetFullPath($Root)
    $config = Import-PowerShellDataFile (Join-Path $rootPath 'config/mods.psd1')
    $result = @{ Root = $rootPath }
    foreach ($key in @('IncomingRoot', 'ModsRoot')) {
        $path = [IO.Path]::GetFullPath((Join-Path $rootPath $config[$key]))
        if (-not $path.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw "$key must be inside the repository."
        }
        $result[$key] = $path
    }
    return $result
}

function Read-ModJar([string]$Path) {
    $file = Get-Item -LiteralPath $Path
    if ($file.Name -notmatch '^(?<mod>[a-z0-9][a-z0-9_-]*?)-(?<release>[0-9][a-zA-Z0-9.+_-]*)-(?<loader>fabric|quilt|neoforge|forge)-mc(?<game>[0-9][a-zA-Z0-9.+_-]*)\.jar$') {
        throw "Unrecognized JAR name '$($file.Name)'. Expected <mod>-<release>-<loader>-mc<version>.jar."
    }
    $item = [pscustomobject]@{
        Mod = $Matches.mod; Release = $Matches.release; Loader = $Matches.loader
        Minecraft = $Matches.game; Path = $file.FullName; FileName = $file.Name
        Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA512).Hash.ToLowerInvariant()
    }
    $zip = [IO.Compression.ZipFile]::OpenRead($file.FullName)
    try {
        $manifest = switch ($item.Loader) {
            fabric { 'fabric.mod.json' }
            quilt { 'quilt.mod.json' }
            forge { 'META-INF/mods.toml' }
            neoforge { 'META-INF/neoforge.mods.toml' }
        }
        $entry = $zip.GetEntry($manifest)
        if (-not $entry -and $item.Loader -eq 'neoforge') { $entry = $zip.GetEntry('META-INF/mods.toml') }
        if (-not $entry) { throw "'$($file.Name)' is missing $manifest for loader $($item.Loader)." }
        $rootMetadata = $null
        $displayName = ''; $modId = ''; $declaredVersion = ''; $minecraftConstraint = ''
        if ($item.Loader -in @('fabric', 'quilt')) {
            $reader = [IO.StreamReader]::new($entry.Open())
            try { $metadata = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
            $rootMetadata = $metadata
            if ($item.Loader -eq 'quilt') { $metadata = $metadata.quilt_loader }
            $modId = [string](Get-JsonProperty $metadata 'id' '')
            $displayName = [string](Get-JsonProperty $metadata 'name' '')
            if ($item.Loader -eq 'quilt') { $displayName = [string](Get-JsonProperty (Get-JsonProperty $metadata 'metadata') 'name' '') }
            $declaredVersion = [string]$metadata.version
            if ([string]$metadata.version -ne $item.Release) {
                throw "Filename release $($item.Release) differs from manifest version $($metadata.version)."
            }
        } else {
            $reader = [IO.StreamReader]::new($entry.Open())
            try { $rootMetadata = Read-ForgeModMetadata $reader.ReadToEnd() } finally { $reader.Dispose() }
            $matching = @($rootMetadata.Mods | Where-Object { (Get-Setting $_ 'modId' '') -eq $item.Mod -or (Get-Setting $_ 'modId' '') -eq $item.Mod.Replace('-', '_') })
            if (-not $matching.Count -and $rootMetadata.Mods.Count -eq 1) { $matching = @($rootMetadata.Mods[0]) }
            if ($matching.Count -eq 1) {
                $modId = [string](Get-Setting $matching[0] 'modId' '')
                $displayName = [string](Get-Setting $matching[0] 'displayName' '')
                $declaredVersion = [string](Get-Setting $matching[0] 'version' '')
                if ($declaredVersion -match '^\d' -and $declaredVersion -cne $item.Release) { throw "Filename release $($item.Release) differs from manifest version $declaredVersion." }
            }
            foreach ($dep in $rootMetadata.Dependencies) {
                if ((Get-Setting $dep 'modId' '') -eq 'minecraft') {
                    $minecraftConstraint = [string](Get-Setting $dep 'versionRange' '')
                    Assert-JarMinecraftConstraint $minecraftConstraint $item.Minecraft
                }
            }
        }
        $item | Add-Member -NotePropertyName Metadata -NotePropertyValue ([pscustomobject]@{ ModId = $modId; DisplayName = $displayName; Release = $declaredVersion; MinecraftConstraint = $minecraftConstraint })
        $item | Add-Member -NotePropertyName RuntimeEvidence -NotePropertyValue (Get-JarRuntimeEvidence $zip $item.Loader $rootMetadata)
    } finally { $zip.Dispose() }
    return $item
}

function New-ModSettings($Workspace, [string]$Name) {
    if ($Name -notmatch '^[a-z0-9][a-z0-9_-]*$') { throw 'Use a lowercase mod folder name.' }
    $directory = Join-Path $Workspace.ModsRoot $Name
    $path = Join-Path $directory 'mod.publish.psd1'
    if (Test-Path -LiteralPath $path) { return }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $template = @'
@{
    DisplayName = '__NAME__'
    Runtime = @{
        # auto works for explicit environment restrictions in the manifest.
        # For '*' or Forge/NeoForge choose an environment explicitly; e.g.
        # client_and_server, client_only, server_only, client_or_server.
        Environment = 'auto'
        # Java is selected automatically from config/minecraft-java.json.
        # Minecraft version, loader and mod version are read from each JAR.
        AllowPreviewFeatures = $false
    }
    Overrides = @(
        # Later matching rules win; dictionaries merge, arrays replace.
        # @{ Versions = @('1.20.1'); Loaders = @('fabric'); Settings = @{
        #     Runtime = @{ Environment = 'client_and_server' }
        # } }
    )
    Modrinth = @{
        Enabled = $true
        Project = '' # Project ID, slug, or https://modrinth.com/mod/<slug>
        VersionType = 'release' # release, beta, alpha
        Status = 'listed'
        Featured = $false
        # Release notes are selected from changelog.md by mod version.
        # RequestedStatus = 'listed' # Optional requested visibility
        Dependencies = @(
            # @{ ProjectId = 'P7dR8mSH'; Type = 'required'; Loaders = @('fabric') }
            # Optional selectors: Versions, ExcludeVersions, MinVersion, MaxVersion,
            # AfterVersion, BeforeVersion, Loaders. VersionId pins a dependency release.
        )
    }
    CurseForge = @{
        Enabled = $true
        Project = '' # Numeric project ID or authors dashboard project URL
        ReleaseType = 'release'
        ChangelogType = 'markdown'
        ManualRelease = $false
        # Release notes are selected from changelog.md by mod version.
        # GameVersionNames = @() # Extra non-Java compatibility tags
        # GameVersions = @(12345) # Extra CurseForge game-version IDs
        Dependencies = @(
            # @{ Slug = 'fabric-api'; Type = 'requiredDependency'; Loaders = @('fabric') }
        )
    }
}
'@
    [IO.File]::WriteAllText($path, $template.Replace('__NAME__', $Name), [Text.UTF8Encoding]::new($false))
    Write-Host "Created mods/$Name/mod.publish.psd1"
}

function Copy-IdenticalOrNew([string]$Source, [string]$Destination) {
    if (Test-Path -LiteralPath $Destination) {
        if ((Get-FileHash -LiteralPath $Source -Algorithm SHA512).Hash -ne (Get-FileHash -LiteralPath $Destination -Algorithm SHA512).Hash) {
            throw "Different JAR already exists at '$Destination'; refusing to overwrite a release."
        }
        return
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination
}

function Get-ModItems($Workspace, [string[]]$Mod = @('all'), [string[]]$Version = @('all'), [string[]]$Loader = @('all'), [string]$ReleaseVersion) {
    $found = @{}
    # Retained releases remain available for publishing to the second platform.
    foreach ($root in @($Workspace.ModsRoot, $Workspace.IncomingRoot)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $files = if ($root -eq $Workspace.IncomingRoot) {
            Get-ChildItem -LiteralPath $root -File -Filter '*.jar'
        } else {
            Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.jar'
        }
        foreach ($file in $files) {
            if ($file.Name -match '-(sources|javadoc|dev)(-|\.)') { continue }
            $item = Read-ModJar $file.FullName
            if ('all' -notin $Mod -and $item.Mod -notin $Mod) { continue }
            if ('all' -notin $Loader -and $item.Loader -notin $Loader) { continue }
            if ($ReleaseVersion -and $item.Release -ne $ReleaseVersion) { continue }
            if (-not (Test-GameSelection $item.Minecraft $Version)) { continue }
            if ($found.ContainsKey($item.FileName) -and $found[$item.FileName].Hash -ne $item.Hash) { throw "Conflicting incoming/published contents for $($item.FileName)." }
            if (-not $found.ContainsKey($item.FileName)) { $found[$item.FileName] = $item }
        }
    }
    return @($found.Values | Sort-Object Mod, Release, Minecraft, Loader)
}

function Compare-GameVersion([string]$A, [string]$B) {
    if ($A -notmatch '^\d+(\.\d+){1,3}$' -or $B -notmatch '^\d+(\.\d+){1,3}$') { throw 'Version bounds/ranges require numeric Minecraft versions; use exact Versions for snapshots.' }
    $left = @($A.Split('.') | ForEach-Object { [int]$_ })
    $right = @($B.Split('.') | ForEach-Object { [int]$_ })
    for ($i = 0; $i -lt [Math]::Max($left.Count, $right.Count); $i++) {
        $l = 0; $r = 0
        if ($i -lt $left.Count) { $l = $left[$i] }
        if ($i -lt $right.Count) { $r = $right[$i] }
        if ($l -ne $r) { return $l.CompareTo($r) }
    }
    return 0
}

function Test-GameSelection([string]$Game, [string[]]$Selection) {
    foreach ($part in ($Selection -join ',').Split(',')) {
        $part = $part.Trim()
        if ($part -eq 'all' -or $part -eq $Game) { return $true }
        if ($part -match '^(.+?)(?:\.\.|\s+to\s+)(.+)$') {
            $low = $Matches[1].Trim(); $high = $Matches[2].Trim()
            if ((Compare-GameVersion $low $high) -gt 0) { throw "Reversed range: $part" }
            if ((Compare-GameVersion $Game $low) -ge 0 -and (Compare-GameVersion $Game $high) -le 0) { return $true }
        }
    }
    return $false
}

function Test-Dependency($Dependency, $Item) {
    if (-not (Get-Setting $Dependency 'Enabled' $true)) { return $false }
    if ($Dependency.ContainsKey('Loaders') -and $Item.Loader -notin $Dependency.Loaders) { return $false }
    if ($Dependency.ContainsKey('Versions') -and -not (Test-GameSelection $Item.Minecraft $Dependency.Versions)) { return $false }
    if ($Dependency.ContainsKey('ExcludeVersions') -and (Test-GameSelection $Item.Minecraft $Dependency.ExcludeVersions)) { return $false }
    foreach ($key in @('MinVersion', 'MaxVersion', 'AfterVersion', 'BeforeVersion')) {
        if (-not $Dependency.ContainsKey($key)) { continue }
        $cmp = Compare-GameVersion $Item.Minecraft $Dependency[$key]
        if (($key -eq 'MinVersion' -and $cmp -lt 0) -or ($key -eq 'MaxVersion' -and $cmp -gt 0) -or ($key -eq 'AfterVersion' -and $cmp -le 0) -or ($key -eq 'BeforeVersion' -and $cmp -ge 0)) { return $false }
    }
    return $true
}

function Get-Dependencies($Settings, $Item, [string]$Platform) {
    $selected = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($dep in (Get-Setting $Settings 'Dependencies' @())) {
        if (-not (Test-Dependency $dep $Item)) { continue }
        if ($Platform -eq 'Modrinth') {
            $relation = [ordered]@{ dependency_type = (Get-Setting $dep 'Type' 'optional') }
            if ($relation.dependency_type -notin @('required', 'optional', 'incompatible', 'embedded')) { throw 'Invalid Modrinth dependency type.' }
            foreach ($pair in @(@('ProjectId','project_id'), @('VersionId','version_id'), @('FileName','file_name'))) {
                if ($dep.ContainsKey($pair[0])) { $relation[$pair[1]] = [string]$dep[$pair[0]] }
            }
            if ($relation.Count -eq 1) { throw 'A Modrinth dependency needs ProjectId, VersionId or FileName.' }
            foreach ($key in @('project_id', 'version_id')) {
                if ($relation.Contains($key) -and $relation[$key] -cnotmatch '^[a-zA-Z0-9]{8}$') { throw "Modrinth $key must be a case-sensitive 8-character ID." }
            }
            $id = [string](Get-Setting $dep 'ProjectId' (Get-Setting $dep 'VersionId' (Get-Setting $dep 'FileName' '')))
        } else {
            $slug = [string](Get-Setting $dep 'Slug' '')
            if ($slug -notmatch '^[a-z0-9][a-z0-9-]*$') { throw 'A CurseForge dependency needs a project Slug.' }
            $relation = [ordered]@{ slug = $slug; type = (Get-Setting $dep 'Type' 'optionalDependency') }
            if ($relation.type -notin @('requiredDependency', 'optionalDependency', 'incompatible', 'embeddedLibrary', 'tool')) { throw 'Invalid CurseForge dependency type.' }
            if ($dep.ContainsKey('ProjectId')) {
                if ([string]$dep.ProjectId -notmatch '^[1-9][0-9]*$') { throw 'CurseForge ProjectId must be positive.' }
                $relation.projectID = [int]$dep.ProjectId
            }
            $id = $slug
        }
        # Case-sensitive IDs on Modrinth.
        $identity = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($id))
        $json = $relation | ConvertTo-Json -Compress
        if ($selected.ContainsKey($identity) -and $selected[$identity].Json -ne $json) { throw "Conflicting dependency declarations for $id." }
        $selected[$identity] = @{ Json = $json; Relation = $relation }
    }
    return @($selected.Values | Sort-Object Json | ForEach-Object { $_.Relation })
}

function Get-UploadPlan($Workspace, $Items, [string]$Platform, [hashtable]$ProjectOverrides = @{}, [AllowNull()][string]$Changelog, [bool]$OverrideChangelog = $false, [hashtable]$SettingsOverrides = @{}) {
    foreach ($group in @($Items | Group-Object Mod)) {
        $modName = $group.Group[0].Mod
        New-ModSettings $Workspace $modName
        $sourceConfig = Import-PowerShellDataFile (Join-Path (Join-Path $Workspace.ModsRoot $modName) 'mod.publish.psd1')
        if ($SettingsOverrides.ContainsKey($modName)) { $sourceConfig = $SettingsOverrides[$modName] }
        Initialize-ModChangelog $Workspace @($group.Group) $sourceConfig
    }
    foreach ($item in $Items) {
        $path = Join-Path (Join-Path $Workspace.ModsRoot $item.Mod) 'mod.publish.psd1'
        if (-not (Test-Path -LiteralPath $path)) { New-ModSettings $Workspace $item.Mod }
        $sourceConfig = Import-PowerShellDataFile $path
        if ($SettingsOverrides.ContainsKey($item.Mod)) { $sourceConfig = $SettingsOverrides[$item.Mod] }
        $config = Get-EffectiveModSettings $sourceConfig $item
        $settings = Get-Setting $config $Platform @{}
        if (-not (Get-Setting $settings 'Enabled' $true)) { continue }
        $runtime = Get-ModRuntime $config $item
        $project = [string](Get-Setting $settings 'Project' '')
        if ($ProjectOverrides.ContainsKey($item.Mod)) { $project = $ProjectOverrides[$item.Mod] }
        if ($Platform -eq 'Modrinth') {
            $project = $project -replace '^https://modrinth.com/mod/([^/?#]+).*$','$1'
            if ($project -notmatch '^[a-zA-Z0-9_-]+$') { throw "Set Modrinth.Project for $($item.Mod), or use -PromptForProject." }
        } else {
            $project = $project -replace '^https://authors.curseforge.com/dashboard/projects/([0-9]+).*$','$1'
            if ($project -notmatch '^[1-9][0-9]*$') { throw "Set CurseForge.Project to a numeric ID for $($item.Mod)." }
        }
        $name = "$(Get-Setting $config 'DisplayName' $item.Mod) $($item.Release)"
        $number = "$($item.Release)-$($item.Loader)-mc$($item.Minecraft)"
        if ($OverrideChangelog) { $log = $Changelog }
        else { $log = Read-ModReleaseChangelog $Workspace $item.Mod $item.Release }
        $dependencies = @(Get-Dependencies $settings $item $Platform)
        $uploadLoaders = @($item.Loader)
        if ($item.Loader -eq 'forge' -and $item.Minecraft -eq '1.20.1') { $uploadLoaders += 'neoforge' }
        if ($Platform -eq 'Modrinth') {
            $type = Get-Setting $settings 'VersionType' 'release'
            $status = Get-Setting $settings 'Status' 'listed'
            if ($status -notin @('listed', 'archived', 'draft', 'unlisted')) { throw 'Invalid Modrinth status.' }
            $data = [ordered]@{
                project_id = $project; name = $name; version_number = $number; changelog = $log
                game_versions = $runtime.MinecraftVersions; loaders = $uploadLoaders; version_type = $type
                environment = $runtime.Environment
                status = $status; featured = [bool](Get-Setting $settings 'Featured' $false)
                dependencies = $dependencies; file_parts = @('file'); primary_file = 'file'
            }
            if ($settings.ContainsKey('RequestedStatus')) {
                if ($settings.RequestedStatus -notin @('listed', 'archived', 'draft', 'unlisted')) { throw 'Invalid Modrinth RequestedStatus.' }
                $data.requested_status = $settings.RequestedStatus
            }
        } else {
            $type = Get-Setting $settings 'ReleaseType' 'release'
            $format = 'markdown'
            if ($OverrideChangelog) { $format = Get-Setting $settings 'ChangelogType' 'markdown' }
            if ($format -notin @('markdown', 'text', 'html')) { throw 'Invalid CurseForge changelog type.' }
            $loaderNames = @($uploadLoaders | ForEach-Object { @{ fabric = 'Fabric'; quilt = 'Quilt'; forge = 'Forge'; neoforge = 'NeoForge' }[$_] })
            $data = [ordered]@{
                displayName = [IO.Path]::GetFileNameWithoutExtension($item.FileName); changelog = $log; changelogType = $format; releaseType = $type
                gameVersionNames = @(@($runtime.MinecraftVersions) + $loaderNames + @($runtime.SideTags) + @($runtime.JavaVersions | ForEach-Object { "Java $_" }) + @((Get-Setting $settings 'GameVersionNames' @()) | Where-Object { $_ -notmatch '^Java(?:\s|$)' }) | Select-Object -Unique)
                isMarkedForManualRelease = [bool](Get-Setting $settings 'ManualRelease' $false)
            }
            # CurseForge rejects relations.projects = []; the optional field
            # must be omitted entirely when no dependencies apply to this JAR.
            if ($dependencies.Count -gt 0) { $data.relations = @{ projects = $dependencies } }
            foreach ($tag in $data.gameVersionNames) {
                if ($tag -isnot [string] -or [string]::IsNullOrWhiteSpace($tag)) { throw 'CurseForge GameVersionNames must contain nonempty strings.' }
                if ($tag -in @('Client', 'Server') -and $tag -notin $runtime.SideTags) { throw "CurseForge tag $tag conflicts with Runtime.Environment." }
                if ($tag -match '^Java (\d+)$' -and [int]$Matches[1] -lt $runtime.Evidence.BytecodeMinimumJava) { throw 'CurseForge Java tag is below the JAR bytecode minimum.' }
            }
            if ($settings.ContainsKey('GameVersions')) {
                $ids = @()
                foreach ($id in @($settings.GameVersions)) {
                    if ([string]$id -notmatch '^[1-9][0-9]*$') { throw 'CurseForge GameVersions must be positive numeric IDs.' }
                    $ids += [int]$id
                }
                $data.gameVersions = @($ids | Select-Object -Unique)
            }
        }
        if ($type -notin @('release', 'beta', 'alpha')) { throw "Invalid release type: $type" }
        [pscustomobject]@{ Item = $item; Platform = $Platform; Project = $project; Number = $number; Data = $data; Runtime = $runtime }
    }
}

function Get-PublishedModPath($Workspace, $Item) {
    $directory = Join-Path (Join-Path (Join-Path $Workspace.ModsRoot $Item.Mod) $Item.Loader) $Item.Release
    return Join-Path $directory $Item.FileName
}

function Assert-PublishedModDestination($Workspace, $Item) {
    $destination = Get-PublishedModPath $Workspace $Item
    if (Test-Path -LiteralPath $destination) {
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA512).Hash.ToLowerInvariant() -ne $Item.Hash) {
            throw "Different JAR already exists at '$destination'; refusing to overwrite a published release."
        }
    }
}

function Complete-ModPublish($Workspace, $Item) {
    $destination = Get-PublishedModPath $Workspace $Item
    Assert-PublishedModDestination $Workspace $Item
    # Save and verify the retained copy before removing any matching working files.
    Copy-IdenticalOrNew $Item.Path $destination
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA512).Hash.ToLowerInvariant() -ne $Item.Hash) {
        throw "JAR changed during publishing; retained copies need review: $destination"
    }
    $Item.Path = $destination
    foreach ($source in @((Join-Path $Workspace.IncomingRoot $Item.FileName))) {
        if (-not (Test-Path -LiteralPath $source) -or $source -eq $destination) { continue }
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA512).Hash.ToLowerInvariant() -eq $Item.Hash) {
            Remove-Item -LiteralPath $source
        } else {
            Write-Host "Preserved changed working JAR: $source"
        }
    }
    Write-Host "Stored published JAR: $destination"
}

function Read-LocalSettings($Workspace, [string]$Platform) {
    $relative = "config/$($Platform.ToLowerInvariant()).local.psd1"
    $tracked = @(& git -C $Workspace.Root ls-files -- $relative ($relative + '.tmp.psd1') 'config/publish-state.local.json')
    if ($LASTEXITCODE -ne 0) { throw 'Cannot check whether local publishing settings are tracked.' }
    if ($tracked.Count) { throw 'Local publishing settings/state must not be tracked by git.' }
    $path = Join-Path $Workspace.Root $relative
    if (Test-Path -LiteralPath $path) { return Import-PowerShellDataFile $path }
    return @{}
}

function Read-Token([string]$Platform) {
    $secret = Read-Host "$Platform token (saved in its ignored platform token file for all mods)" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function New-PublishClient([string]$Platform, [string]$Token) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $client = [Net.Http.HttpClient]::new()
    $client.Timeout = [TimeSpan]::FromMinutes(10)
    $client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', 'DoomedArtemis/ModsManager (github.com/DoomedArtemis/ModsManager)') | Out-Null
    $header = 'Authorization'
    if ($Platform -eq 'CurseForge') { $header = 'X-Api-Token' }
    $client.DefaultRequestHeaders.TryAddWithoutValidation($header, $Token) | Out-Null
    return $client
}

function Resolve-ModrinthUploadProjects($Client, $Plans) {
    $resolved = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($plan in $Plans) {
        if ($plan.Platform -ne 'Modrinth') { continue }
        $reference = [string]$plan.Project
        # Even an eight-character reference can be a slug. Always ask the API.
        if (-not $resolved.ContainsKey($reference)) {
            $uri = 'https://api.modrinth.com/v2/project/' + [Uri]::EscapeDataString($reference)
            $response = $Client.GetAsync($uri).GetAwaiter().GetResult()
            try {
                $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                if (-not $response.IsSuccessStatusCode) { throw "Cannot resolve Modrinth project '$reference' (HTTP $([int]$response.StatusCode)). Check the project reference and token access. No files were uploaded." }
                $project = $body | ConvertFrom-Json
                if (-not $project.PSObject.Properties['id'] -or [string]$project.id -cnotmatch '^[a-zA-Z0-9]{8}$') { throw "Modrinth returned an invalid internal project ID for '$reference'. No files were uploaded." }
                if ($project.PSObject.Properties['project_type'] -and $project.project_type -ne 'mod') { throw "Modrinth project '$reference' is not a mod project. No files were uploaded." }
                $resolved[$reference] = [string]$project.id
                $resolved[[string]$project.id] = [string]$project.id
            } finally { $response.Dispose() }
        }
        $plan | Add-Member -NotePropertyName ProjectReference -NotePropertyValue $reference -Force
        $plan.Project = $resolved[$reference]
        $plan.Data.project_id = $resolved[$reference]
        Write-Host "Resolved Modrinth project '$reference' -> $($plan.Project)"
    }
}

function Send-ModUpload($Client, $Plan) {
    if ($Plan.Platform -eq 'Modrinth' -and ([string]$Plan.Data.project_id -cnotmatch '^[a-zA-Z0-9]{8}$' -or $Plan.Data.project_id -cne $Plan.Project)) {
        throw 'Modrinth upload requires a resolved internal project ID. Project slugs/URLs must be resolved before uploading.'
    }
    $multipart = [Net.Http.MultipartFormDataContent]::new()
    $response = $null
    try {
        $field = 'data'; $url = 'https://api.modrinth.com/v2/version'
        if ($Plan.Platform -eq 'CurseForge') { $field = 'metadata'; $url = "https://minecraft.curseforge.com/api/projects/$($Plan.Project)/upload-file" }
        $multipart.Add([Net.Http.StringContent]::new(($Plan.Data | ConvertTo-Json -Depth 20 -Compress), [Text.Encoding]::UTF8, 'application/json'), $field)
        $content = [Net.Http.StreamContent]::new([IO.File]::OpenRead($Plan.Item.Path))
        $content.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('application/java-archive')
        $multipart.Add($content, 'file', $Plan.Item.FileName)
        $response = $Client.PostAsync($url, $multipart).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) { throw "Upload failed (HTTP $([int]$response.StatusCode)): $body" }
        $result = $body | ConvertFrom-Json
        if (-not $result.id) { throw 'Upload response did not contain an ID. Check the platform before retrying.' }
        return [string]$result.id
    } finally {
        if ($response) { $response.Dispose() }
        $multipart.Dispose()
    }
}

function Write-PublishRecords($Workspace, $Records) {
    $path = Join-Path $Workspace.Root 'config/publish-state.local.json'
    $temporary = $path + '.tmp'
    [IO.File]::WriteAllText($temporary, (ConvertTo-Json -InputObject @($Records) -Depth 10), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $path -Force
}

function Reset-LocalPublishReceipt($Workspace, [ValidateSet('Modrinth', 'CurseForge')][string]$Platform, [string]$Project, [string]$VersionNumber) {
    $null = Read-LocalSettings $Workspace $Platform
    $path = Join-Path $Workspace.Root 'config/publish-state.local.json'
    if (-not (Test-Path -LiteralPath $path)) { return 0 }
    $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $records = @($saved | ForEach-Object { $_ })
    $remaining = @($records | Where-Object { -not ($_.Platform -eq $Platform -and $_.Project -ceq $Project -and $_.Number -ceq $VersionNumber) })
    $count = $records.Count - $remaining.Count
    if ($count) { Write-PublishRecords $Workspace $remaining }
    return $count
}

function Invoke-PlatformPublishBatches($Workspace, [Collections.IDictionary]$Batches, [hashtable]$Tokens) {
    foreach ($platform in $Batches.Keys) {
        if (-not $Tokens.ContainsKey($platform) -or [string]::IsNullOrWhiteSpace([string]$Tokens[$platform])) { throw "A $platform token is required before starting the publishing batch." }
        foreach ($plan in $Batches[$platform]) { Assert-PublishedModDestination $Workspace $plan.Item }
    }
    $failures = @()
    foreach ($platform in $Batches.Keys) {
        try {
            Write-Host "Publishing $($Batches[$platform].Count) selected artifact(s) to $platform."
            Invoke-PublishPlans $Workspace $Batches[$platform] $Tokens[$platform]
            Write-Host "$platform processing completed."
        } catch {
            $failures += $platform
            Write-Host "$platform publishing did not complete: $($_.Exception.Message)"
        }
    }
    if ($failures.Count) { throw "Publishing incomplete for: $($failures -join ', '). Successful uploads remain recorded; retry this command to skip successes and finish the remaining uploads." }
}

function Invoke-PublishPlans($Workspace, $Plans, [string]$Token) {
    $statePath = Join-Path $Workspace.Root 'config/publish-state.local.json'
    $records = @()
    if (Test-Path -LiteralPath $statePath) {
        $storedRecords = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $records = @($storedRecords | ForEach-Object { $_ })
    }
    # Check every retained destination before the first network request.
    foreach ($plan in $Plans) { Assert-PublishedModDestination $Workspace $plan.Item }
    $client = New-PublishClient $Plans[0].Platform $Token
    try {
        # Resolve every target before any upload; slugs work in GET paths but
        # Create Version's project_id must contain the canonical base62 ID.
        Resolve-ModrinthUploadProjects $client $Plans
        foreach ($plan in $Plans) {
            $item = $plan.Item
            $projectKeys = @($plan.Project)
            if ($plan.PSObject.Properties['ProjectReference']) { $projectKeys += $plan.ProjectReference }
            $existing = @($records | Where-Object { $_.Platform -eq $plan.Platform -and $_.Project -cin $projectKeys -and $_.Number -ceq $plan.Number })
            if ($existing.Count) {
                if ($existing[0].Hash -ne $item.Hash) { throw "Published release has different contents: $($plan.Number)" }
                Write-Host "Already published: $($item.FileName)"
                Complete-ModPublish $Workspace $item
                continue
            }
            if ($plan.Platform -eq 'Modrinth') {
                $uri = 'https://api.modrinth.com/v2/project/' + [Uri]::EscapeDataString($plan.Project) + '/version'
                $response = $client.GetAsync($uri).GetAwaiter().GetResult()
                try {
                    if (-not $response.IsSuccessStatusCode) { throw "Cannot check existing Modrinth versions (HTTP $([int]$response.StatusCode))." }
                    # Preserve the JSON array itself: wrapping ConvertFrom-Json
                    # in @() on PowerShell 5.1 nests even an empty versions list.
                    $remote = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
                } finally { $response.Dispose() }
                $matching = @($remote | Where-Object { $_.version_number -ceq $plan.Number })
                if ($matching.Count) {
                    $hashes = @($matching | ForEach-Object { $_.files } | ForEach-Object { $_.hashes.sha512 })
                    if ($item.Hash -notin $hashes) { throw "Modrinth already has $($plan.Number) with different contents." }
                    Write-Host "Already on Modrinth: $($item.FileName)"
                    Complete-ModPublish $Workspace $item
                    continue
                }
            }
            # Recheck just before sending; never retry an ambiguous upload automatically.
            if ((Get-FileHash -LiteralPath $item.Path -Algorithm SHA512).Hash.ToLowerInvariant() -ne $item.Hash) { throw "JAR changed after validation: $($item.Path)" }
            $id = Send-ModUpload $client $plan
            $records += [pscustomobject]@{ Platform = $plan.Platform; Project = $plan.Project; Number = $plan.Number; Hash = $item.Hash; Id = $id }
            Write-PublishRecords $Workspace $records
            Complete-ModPublish $Workspace $item
            Write-Host "Published $($item.FileName): $id"
        }
    } finally { $client.Dispose() }
}
