# Runtime declarations describe the existing binary; they never rewrite the JAR.
$script:MinecraftJavaCache = $null
function Get-MinecraftJavaMapping {
    $path = Join-Path (Split-Path $PSScriptRoot -Parent) 'config/minecraft-java.json'
    if (-not (Test-Path -LiteralPath $path)) { throw 'Automatic Java: shared mapping is missing. Run scripts/sync-minecraft-java.ps1.' }
    $file = Get-Item -LiteralPath $path
    if ($null -eq $script:MinecraftJavaCache -or $script:MinecraftJavaCache.Timestamp -ne $file.LastWriteTimeUtc.Ticks) {
        $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($data.SchemaVersion -ne 1) { throw 'Automatic Java: unsupported shared mapping schema.' }
        $lookup = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach ($property in $data.Versions.PSObject.Properties) { $lookup[$property.Name] = $property.Value }
        $script:MinecraftJavaCache = @{ Timestamp = $file.LastWriteTimeUtc.Ticks; Lookup = $lookup }
        $script:MinecraftVersionExpansionCache = @{}
    }
    return $script:MinecraftJavaCache.Lookup
}

function Get-MinecraftJavaRequirement([string]$Version) {
    $null = Get-MinecraftJavaMapping
    if (-not $script:MinecraftJavaCache.Lookup.ContainsKey($Version)) { throw "Automatic Java: Minecraft '$Version' is not in the shared mapping. Run scripts/sync-minecraft-java.ps1; no Java version will be guessed." }
    $entry = $script:MinecraftJavaCache.Lookup[$Version]
    if ($null -eq $entry.JavaMajor -or [int]$entry.JavaMajor -le 0) { throw "Automatic Java: Mojang provides no Java runtime metadata for '$Version'; this historical version cannot be assigned automatically." }
    $source = $entry.MetadataUrl
    if ($entry.FallbackMetadataUrl) { $source = $entry.FallbackMetadataUrl }
    return [pscustomobject]@{ Minecraft = $Version; JavaMajor = [int]$entry.JavaMajor; Component = $entry.Component; Source = $source }
}

function Get-JsonProperty($Object, [string]$Name, $Default = $null) {
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}

function Get-JarRuntimeEvidence($Zip, [string]$Loader, $Manifest) {
    $environment = ''
    $constraints = @{}
    if ($Loader -eq 'fabric') {
        $environment = [string](Get-JsonProperty $Manifest 'environment' '*')
        $depends = Get-JsonProperty $Manifest 'depends'
        foreach ($key in @('java', 'minecraft', 'fabricloader')) {
            $value = Get-JsonProperty $depends $key
            if ($null -ne $value) { $constraints[$key] = $value }
        }
    } elseif ($Loader -eq 'quilt') {
        # Quilt's environment lives at the JSON root, outside quilt_loader.
        $environment = [string](Get-JsonProperty $Manifest 'minecraft:environment' '*')
        $quilt = Get-JsonProperty $Manifest 'quilt_loader'
        foreach ($dep in @(Get-JsonProperty $quilt 'depends' @())) {
            $id = [string](Get-JsonProperty $dep 'id' '')
            if ($id -in @('java', 'minecraft', 'quilt_loader')) {
                $constraints[$id] = Get-JsonProperty $dep 'versions' '*'
            }
        }
    } elseif ($null -ne $Manifest) {
        if (Get-Setting $Manifest.Root 'clientSideOnly' $false) { $environment = 'client' }
        foreach ($dep in $Manifest.Dependencies) {
            $id = [string](Get-Setting $dep 'modId' '')
            if ($id -in @('minecraft', 'forge', 'neoforge')) { $constraints[$id] = Get-Setting $dep 'versionRange' '' }
        }
    }
    $minimum = 0
    $preview = @()
    $versionedClasses = 0
    $nestedJars = 0
    foreach ($entry in $Zip.Entries) {
        if ($entry.FullName -like '*.jar') { $nestedJars++; continue }
        if ($entry.FullName -notlike '*.class') { continue }
        # Multi-release classes are alternatives, not baseline requirements.
        if ($entry.FullName -cmatch '^META-INF/versions/') { $versionedClasses++; continue }
        $stream = $entry.Open()
        try {
            $header = New-Object byte[] 8
            $offset = 0
            while ($offset -lt 8) {
                $read = $stream.Read($header, $offset, 8 - $offset)
                if ($read -eq 0) { throw "Truncated class header: $($entry.FullName)" }
                $offset += $read
            }
            if ($header[0] -ne 202 -or $header[1] -ne 254 -or $header[2] -ne 186 -or $header[3] -ne 190) { throw "Invalid class header: $($entry.FullName)" }
            $major = [int]$header[6] * 256 + [int]$header[7]
            if ($major -lt 45) { throw "Invalid class version: $($entry.FullName)" }
            $java = $major - 44
            $minimum = [Math]::Max($minimum, $java)
            if ($header[4] -eq 255 -and $header[5] -eq 255) { $preview += $java }
        } finally { $stream.Dispose() }
    }
    return [pscustomobject]@{
        ManifestEnvironment = $environment; ManifestConstraints = $constraints
        BytecodeMinimumJava = $minimum; PreviewJavaVersions = @($preview | Sort-Object -Unique)
        MultiReleaseClassCount = $versionedClasses; NestedJarCount = $nestedJars
    }
}

function Merge-ModSettings([hashtable]$Base, [hashtable]$Override) {
    $result = @{}
    foreach ($key in $Base.Keys) { $result[$key] = $Base[$key] }
    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and $result[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            $result[$key] = Merge-ModSettings $result[$key] $Override[$key]
        } else { $result[$key] = $Override[$key] }
    }
    return $result
}

function Get-ModEnvironments {
    return @('client_and_server', 'client_only', 'server_only', 'dedicated_server_only', 'server_only_client_optional', 'client_only_server_optional', 'client_or_server', 'client_or_server_prefers_both', 'singleplayer_only')
}

function Get-SharedModEnvironment([hashtable]$Config) {
    $environment = [string](Get-Setting (Get-Setting $Config 'Runtime' @{}) 'Environment' 'auto')
    if ($environment -and $environment -ne 'auto') { return $environment }
    # Existing workspaces stored the same answer in many variant overrides.
    $legacy = @(@(Get-Setting $Config 'Overrides' @()) | ForEach-Object {
        $runtime = Get-Setting (Get-Setting $_ 'Settings' @{}) 'Runtime' @{}
        [string](Get-Setting $runtime 'Environment' '')
    } | Where-Object { $_ -and $_ -ne 'auto' } | Sort-Object -Unique)
    if ($legacy.Count -eq 1) { return $legacy[0] }
    return 'auto'
}

function Move-ModEnvironmentToRoot([hashtable]$Config) {
    $environment = Get-SharedModEnvironment $Config
    # Conflicting legacy answers need one explicit mod-wide choice in setup.
    if ($environment -eq 'auto') { return }
    $Config.Runtime = Merge-ModSettings (Get-Setting $Config 'Runtime' @{}) @{ Environment = $environment }
    foreach ($rule in @(Get-Setting $Config 'Overrides' @())) {
        $settings = Get-Setting $rule 'Settings' @{}
        if ($settings.ContainsKey('Runtime')) { $settings.Runtime.Remove('Environment') }
    }
}

function Get-EffectiveModSettings([hashtable]$Config, $Item) {
    $result = Merge-ModSettings @{} $Config
    foreach ($rule in @(Get-Setting $Config 'Overrides' @())) {
        if (-not (Test-Dependency $rule $Item)) { continue }
        if ($rule.ContainsKey('ReleaseVersions') -and $Item.Release -notin $rule.ReleaseVersions) { continue }
        $settings = Get-Setting $rule 'Settings' @{}
        if ($settings -isnot [hashtable]) { throw 'Override Settings must be a hashtable.' }
        $result = Merge-ModSettings $result $settings
    }
    # Installation requirements belong to the mod, never a loader/game/release.
    $result.Runtime = Merge-ModSettings (Get-Setting $result 'Runtime' @{}) @{ Environment = (Get-SharedModEnvironment $Config) }
    return $result
}

function Get-ModRuntime($Config, $Item) {
    $settings = Get-Setting $Config 'Runtime' @{}
    foreach ($key in $settings.Keys) {
        if ($key -notin @('Environment', 'JavaVersions', 'MinecraftVersions', 'AllowPreviewFeatures')) { throw "Unknown Runtime setting: $key" }
    }
    $evidence = $Item.RuntimeEvidence
    $environment = [string](Get-Setting $settings 'Environment' 'auto')
    if ($environment -eq 'auto') {
        # A physical loader restriction can establish these two environments.
        # '*' cannot establish whether installation is required on both sides.
        $environment = switch ($evidence.ManifestEnvironment) {
            client { 'client_only' }
            server { 'dedicated_server_only' }
            default { '' }
        }
    }
    $allowed = @(Get-ModEnvironments)
    if ($environment -notin $allowed) { throw "Set Runtime.Environment for $($Item.FileName): the manifest cannot establish client/server installation requirements. Use a documented Modrinth environment value." }
    if ($evidence.ManifestEnvironment -eq 'client' -and $environment -notin @('client_only', 'singleplayer_only')) { throw 'Runtime.Environment conflicts with a client-only loader manifest.' }
    if ($evidence.ManifestEnvironment -eq 'server' -and $environment -ne 'dedicated_server_only') { throw 'Runtime.Environment conflicts with a dedicated-server-only loader manifest.' }
    # Each compiled artifact advertises its own Minecraft target, never the
    # target saved during setup for a different JAR in the same release.
    $gameVersions = @(Resolve-MinecraftVersions $Item.Minecraft)
    foreach ($game in $gameVersions) {
        if ($game -isnot [string] -or $game -notmatch '^[0-9][a-zA-Z0-9.+_-]*$') { throw 'Invalid Runtime.MinecraftVersions entry.' }
    }
    $javaRequirements = @($gameVersions | ForEach-Object { Get-MinecraftJavaRequirement $_ })
    # Legacy per-mod JavaVersions values are ignored; the shared table always wins.
    $javaVersions = @($javaRequirements.JavaMajor | Sort-Object -Unique)
    foreach ($requirement in $javaRequirements) {
        $version = $requirement.JavaMajor
        if ($version -lt $evidence.BytecodeMinimumJava) { throw "Automatic Java: Minecraft $($requirement.Minecraft) uses Java $version but the JAR bytecode minimum is Java $($evidence.BytecodeMinimumJava). Recompile the mod for this Minecraft runtime." }
        # Enforce a simple declared lower bound as well as the compiled target.
        # Keep complex loader predicates visible; do not pretend to solve them.
        if ($evidence.ManifestConstraints.ContainsKey('java') -and $evidence.ManifestConstraints.java -is [string] -and $evidence.ManifestConstraints.java -match '^>=\s*(\d+)(?:\.\d+)*$') {
            $manifestMinimum = [int]$Matches[1]
            if ($manifestMinimum -gt 1 -and $version -lt $manifestMinimum) { throw "Automatic Java: Minecraft $($requirement.Minecraft) uses Java $version, below manifest Java requirement $($evidence.ManifestConstraints.java)." }
        }
    }
    if ($evidence.PreviewJavaVersions.Count) {
        if (-not (Get-Setting $settings 'AllowPreviewFeatures' $false)) { throw 'JAR uses Java preview features. Set Runtime.AllowPreviewFeatures only if users will launch Java with --enable-preview.' }
        if ($evidence.PreviewJavaVersions.Count -ne 1 -or $javaVersions.Count -ne 1 -or $javaVersions[0] -ne $evidence.PreviewJavaVersions[0]) { throw 'Automatic Java: preview bytecode requires its matching Java major, but the Minecraft runtime mapping differs.' }
    }
    $tags = switch ($environment) {
        client_only { @('Client') }
        singleplayer_only { @('Client') }
        dedicated_server_only { @('Server') }
        default { @('Client', 'Server') }
    }
    return [pscustomobject]@{
        Environment = $environment; JavaVersions = $javaVersions; JavaRequirements = $javaRequirements
        MinecraftVersions = @($gameVersions | Select-Object -Unique); SideTags = @($tags)
        Evidence = $evidence
    }
}

function Write-RuntimePreview($Plan) {
    $runtime = $Plan.Runtime
    Write-Host "  Environment: $($runtime.Environment)"
    $declared = $runtime.JavaVersions -join ', '
    Write-Host "  Automatic Java: $declared (shared Minecraft runtime mapping); bytecode minimum: $($runtime.Evidence.BytecodeMinimumJava) (0 = no baseline classes)"
    foreach ($requirement in $runtime.JavaRequirements) { Write-Host "    Minecraft $($requirement.Minecraft) -> Java $($requirement.JavaMajor)" }
    if ($runtime.Evidence.ManifestConstraints.Count) { Write-Host "  Manifest constraints: $($runtime.Evidence.ManifestConstraints | ConvertTo-Json -Depth 10 -Compress)" }
    if ($runtime.Evidence.NestedJarCount) { Write-Host '  Nested libraries need their own runtime review; their bytecode is not inspected.' }
    if ($runtime.Evidence.PreviewJavaVersions.Count) { Write-Host '  Java preview features require --enable-preview at launch.' }
    if ($Plan.Platform -eq 'Modrinth') { Write-Host '  Java compatibility is enforced by the JAR/loader; the Modrinth upload API has no Java version field.' }
}
