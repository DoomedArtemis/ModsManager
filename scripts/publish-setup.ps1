$script:ReviewedModEnvironments = @{}

function ConvertTo-ModDataLiteral($Value, [int]$Indent = 0) {
    if ($null -eq $Value) { return '$null' }
    if ($Value -is [bool]) { if ($Value) { return '$true' }; return '$false' }
    if ($Value -is [string]) { return "'$($Value.Replace("'", "''"))'" }
    if ($Value -is [Collections.IDictionary]) {
        $lines = @('@{')
        foreach ($key in @($Value.Keys | Sort-Object)) {
            $lines += (' ' * ($Indent + 4)) + (ConvertTo-ModDataLiteral ([string]$key)) + ' = ' + (ConvertTo-ModDataLiteral $Value[$key] ($Indent + 4))
        }
        return ($lines -join "`n") + "`n" + (' ' * $Indent) + '}'
    }
    if ($Value -is [Collections.IEnumerable]) {
        $entries = @($Value | ForEach-Object { ConvertTo-ModDataLiteral $_ ($Indent + 4) })
        if (-not $entries.Count) { return '@()' }
        return "@(`n" + (' ' * ($Indent + 4)) + ($entries -join (",`n" + (' ' * ($Indent + 4)))) + "`n" + (' ' * $Indent) + ')'
    }
    if ($Value -is [ValueType]) { return [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture) }
    throw "Cannot save configuration value of type $($Value.GetType().Name)."
}

function Remove-ManualJavaSettings($Settings) {
    if ($Settings -is [Collections.IDictionary]) {
        foreach ($key in @($Settings.Keys)) {
            if ($key -eq 'Runtime' -and $Settings[$key] -is [Collections.IDictionary]) { $Settings[$key].Remove('JavaVersions'); $Settings[$key].Remove('MinecraftVersions') }
            if ($key -in @('Modrinth', 'CurseForge') -and $Settings[$key] -is [Collections.IDictionary]) {
                $Settings[$key].Remove('Changelog')
                $Settings[$key].Remove('VersionType'); $Settings[$key].Remove('ReleaseType')
            }
            Remove-ManualJavaSettings $Settings[$key]
        }
    } elseif ($Settings -is [Collections.IEnumerable] -and $Settings -isnot [string]) {
        foreach ($entry in $Settings) { Remove-ManualJavaSettings $entry }
    }
}

function Save-ModSettings([string]$Path, [hashtable]$Settings) {
    Move-ModEnvironmentToRoot $Settings
    Remove-ManualJavaSettings $Settings
    $temporary = $Path + '.tmp.psd1'
    $text = "# Saved by the interactive publishing setup. Tokens are never saved here.`n" + (ConvertTo-ModDataLiteral $Settings) + "`n"
    [IO.File]::WriteAllText($temporary, $text, [Text.UTF8Encoding]::new($false))
    $null = Import-PowerShellDataFile -LiteralPath $temporary
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Save-PlatformToken($Workspace, [ValidateSet('Modrinth', 'CurseForge')][string]$Platform, [string]$Token) {
    if ([string]::IsNullOrWhiteSpace($Token)) { throw 'Cannot save an empty platform token.' }
    $settings = Read-LocalSettings $Workspace $Platform
    $relative = "config/$($Platform.ToLowerInvariant()).local.psd1"
    foreach ($candidate in @($relative, ($relative + '.tmp.psd1'))) {
        & git -C $Workspace.Root check-ignore --quiet --no-index -- $candidate
        if ($LASTEXITCODE -ne 0) { throw "Refusing to save a token: $candidate must be ignored by git." }
    }
    $settings.Token = $Token
    $path = Join-Path $Workspace.Root $relative
    $temporary = $path + '.tmp.psd1'
    $text = "# Private $Platform credentials, shared by all mods. Keep this file out of git.`n" + (ConvertTo-ModDataLiteral $settings) + "`n"
    [IO.File]::WriteAllText($temporary, $text, [Text.UTF8Encoding]::new($false))
    $null = Import-PowerShellDataFile -LiteralPath $temporary
    Move-Item -LiteralPath $temporary -Destination $path -Force
    Write-Host "Saved $Platform token to $relative for all mods."
}

function Get-PublishingToken($Workspace, [ValidateSet('Modrinth', 'CurseForge')][string]$Platform, [switch]$PromptForToken, [switch]$NonInteractive) {
    $localSettings = Read-LocalSettings $Workspace $Platform
    $token = [Environment]::GetEnvironmentVariable($Platform.ToUpperInvariant() + '_TOKEN')
    if ([string]::IsNullOrWhiteSpace($token)) { $token = [string](Get-Setting $localSettings 'Token' '') }
    if ($PromptForToken -or ([string]::IsNullOrWhiteSpace($token) -and -not $NonInteractive)) {
        do { $token = Read-Token $Platform } while ([string]::IsNullOrWhiteSpace($token))
        Save-PlatformToken $Workspace $Platform $token
    }
    if ([string]::IsNullOrWhiteSpace($token)) { throw "A $Platform token is required. Run publishing interactively once to save it, or set $($Platform.ToUpperInvariant())_TOKEN." }
    return $token
}

function Read-SetupText([string]$Label, [string]$Default = '', [string]$Pattern = '', [switch]$Required) {
    while ($true) {
        $suffix = ''
        if ($Default) { $suffix = " [$Default]" }
        $answer = Read-Host ($Label + $suffix)
        if ([string]::IsNullOrWhiteSpace($answer)) { $answer = $Default }
        if ($Required -and [string]::IsNullOrWhiteSpace($answer)) { Write-Host 'A value is required.'; continue }
        if ($Pattern -and $answer -and $answer -notmatch $Pattern) { Write-Host 'That value is not in the displayed format. Please try again.'; continue }
        return $answer
    }
}

function Read-ChangelogFile([string]$Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Changelog file not found: $fullPath" }
    return [IO.File]::ReadAllText($fullPath, [Text.Encoding]::UTF8)
}

function Read-SetupChangelog([AllowEmptyString()][string]$Default = '') {
    if ($Default) { Write-Host "Current release notes:`n$Default" }
    Write-Host 'Markdown is preserved. Enter keeps saved notes; - clears them.'
    Write-Host 'Use :paste for multiple lines, or :file <path> to read a UTF-8 Markdown file.'
    while ($true) {
        $answer = Read-Host 'Release notes / :paste / :file <path>'
        if ($answer -ceq '') { return $Default }
        if ($answer -ceq '-') { return '' }
        if ($answer -ceq ':paste') {
            Write-Host 'Paste Markdown, including blank lines. Finish with :end on a line by itself.'
            $lines = [Collections.Generic.List[string]]::new()
            while ($true) {
                $line = Read-Host '>'
                if ($line -ceq ':end') { break }
                $lines.Add($line)
            }
            return $lines -join "`n"
        }
        if ($answer -match '^:file\s+(.+)$') {
            $path = $Matches[1].Trim()
            if (($path.StartsWith('"') -and $path.EndsWith('"')) -or ($path.StartsWith("'") -and $path.EndsWith("'"))) { $path = $path.Substring(1, $path.Length - 2) }
            try { return Read-ChangelogFile $path } catch { Write-Host $_.Exception.Message; continue }
        }
        return $answer
    }
}

function Read-SetupChoice([string]$Label, [string[]]$Values, [string[]]$Descriptions, [string]$Default = '') {
    Write-Host $Label
    for ($i = 0; $i -lt $Values.Count; $i++) {
        $help = ''
        if ($Descriptions -and $i -lt $Descriptions.Count) { $help = ' - ' + $Descriptions[$i] }
        Write-Host "  $($i + 1). $($Values[$i])$help"
    }
    while ($true) {
        $answer = Read-SetupText 'Enter a number or the displayed value' $Default
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Values.Count) { return $Values[$number - 1] }
        if ($answer -in $Values) { return $Values | Where-Object { $_ -eq $answer } | Select-Object -First 1 }
        Write-Host 'Choose one of the listed options.'
    }
}

function Read-SetupBool([string]$Label, [bool]$Default = $false) {
    $selected = 'no'
    if ($Default) { $selected = 'yes' }
    return (Read-SetupChoice $Label @('no', 'yes') @() $selected) -eq 'yes'
}

function Read-SetupDependencies($Settings, $Item, [string]$Platform) {
    $existing = @(Get-Setting $Settings 'Dependencies' @())
    Write-Host "Current $Platform dependencies: $(ConvertTo-Json -InputObject $existing -Depth 15 -Compress)"
    $defaultAction = if ((Get-Setting $Settings 'DependencyMode' 'manual') -eq 'auto') { 'auto' } else { 'keep' }
    $action = Read-SetupChoice 'Dependencies for this release' @('keep', 'replace', 'none', 'auto') @('Keep the saved dependency mode and list', 'Enter a manual dependency list', 'Publish without dependencies', 'Scan each JAR separately and use its declared dependencies') $defaultAction
    if ($action -eq 'keep') { return ,$existing }
    if ($action -eq 'auto') { $Settings.DependencyMode = 'auto'; return ,@() }
    $Settings.DependencyMode = 'manual'
    if ($action -eq 'none') { return ,@() }
    $result = @()
    while ($true) {
        $dep = @{}
        if ($Platform -eq 'Modrinth') {
            $kind = Read-SetupChoice 'Dependency identifier' @('project', 'version', 'external-file') @('8-character Modrinth project ID', '8-character Modrinth version ID (pins a release)', 'External filename shown to users') 'project'
            if ($kind -eq 'external-file') { $dep.FileName = Read-SetupText 'External filename (e.g. library.jar)' '' '' -Required }
            elseif ($kind -eq 'version') { $dep.VersionId = Read-SetupText 'Modrinth version ID (e.g. AbCd1234)' '' '^[a-zA-Z0-9]{8}$' -Required }
            else {
                $dep.ProjectId = Read-SetupText 'Modrinth project ID (8 characters, e.g. P7dR8mSH; not a CurseForge ID)' '' '^[a-zA-Z0-9]{8}$' -Required
                $pin = Read-SetupText 'Optional exact Modrinth version ID (8 characters; blank = any release)' '' '^[a-zA-Z0-9]{8}$'
                if ($pin) { $dep.VersionId = $pin }
            }
            $dep.Type = Read-SetupChoice 'Dependency relation' @('required', 'optional', 'incompatible', 'embedded') @('Must be installed', 'Adds optional features', 'Cannot be used together', 'Already bundled inside this JAR') 'required'
        } else {
            $dep.Slug = Read-SetupText 'CurseForge dependency slug (e.g. fabric-api)' '' '^[a-z0-9][a-z0-9-]*$' -Required
            $projectId = Read-SetupText 'Optional numeric dependency project ID (e.g. 306612; blank = slug only)' '' '^[1-9][0-9]{0,8}$'
            if ($projectId) { $dep.ProjectId = $projectId }
            $dep.Type = Read-SetupChoice 'Dependency relation' @('requiredDependency', 'optionalDependency', 'incompatible', 'embeddedLibrary', 'tool') @('Must be installed', 'Adds optional features', 'Cannot be used together', 'Bundled inside this JAR', 'Related development tool') 'requiredDependency'
        }
        try {
            $candidate = @($result) + @($dep)
            $null = @(Get-Dependencies @{ Dependencies = $candidate } $Item $Platform)
            $result = $candidate
        } catch { Write-Host $_.Exception.Message; continue }
        if (-not (Read-SetupBool 'Add another dependency?')) { break }
    }
    return ,$result
}

function Read-SetupRuntime($Effective, $Item, [switch]$SkipEnvironmentPrompt) {
    $runtime = Merge-ModSettings @{} (Get-Setting $Effective 'Runtime' @{})
    $runtime.Remove('JavaVersions')
    $runtime.Remove('MinecraftVersions')
    $environments = @(Get-ModEnvironments)
    $help = @('Required on both client and server', 'Client only; works with vanilla servers', 'Server only; also works in singleplayer', 'Dedicated server only; no singleplayer', 'Server required, client optional', 'Client required, server optional', 'Works independently on either side', 'Works on either side; extra features with both', 'Only works in singleplayer')
    $defaultEnvironment = [string](Get-Setting $runtime 'Environment' '')
    if ($defaultEnvironment -notin $environments) {
        $defaultEnvironment = switch ($Item.RuntimeEvidence.ManifestEnvironment) { client { 'client_only' }; server { 'dedicated_server_only' }; default { '' } }
    }
    while ($true) {
        if ($SkipEnvironmentPrompt) { $runtime.Environment = $defaultEnvironment }
        else { $runtime.Environment = Read-SetupChoice 'Where must players install this mod? (saved once for the entire mod)' $environments $help $defaultEnvironment }
        Write-Host "Compiled Java target: $($Item.RuntimeEvidence.BytecodeMinimumJava). Java is selected automatically from Minecraft's runtime metadata."
        if ($Item.RuntimeEvidence.ManifestConstraints.Count) { Write-Host "Manifest requirements: $($Item.RuntimeEvidence.ManifestConstraints | ConvertTo-Json -Depth 10 -Compress)" }
        Write-Host "Minecraft $($Item.Minecraft), loader $($Item.Loader) and mod version $($Item.Release) are read from the JAR."
        if ($Item.RuntimeEvidence.PreviewJavaVersions.Count) {
            $runtime.AllowPreviewFeatures = Read-SetupBool 'This JAR uses Java preview features. Will users launch with --enable-preview?' ([bool](Get-Setting $runtime 'AllowPreviewFeatures' $false))
        }
        try {
            $resolved = Get-ModRuntime @{ Runtime = $runtime } $Item
            foreach ($requirement in $resolved.JavaRequirements) { Write-Host "Minecraft $($requirement.Minecraft): automatically using Java $($requirement.JavaMajor)." }
            return $runtime
        } catch {
            if ($SkipEnvironmentPrompt -or $_.Exception.Message.StartsWith('Automatic Java:')) { throw }
            Write-Host $_.Exception.Message; $defaultEnvironment = $runtime.Environment
        }
    }
}

function Invoke-ModVariantSetup($Workspace, $Items, [string]$Platform, [hashtable]$Projects, [switch]$Configure, [switch]$PromptForProject, [switch]$PromptForChangelog, [hashtable]$ChangelogInput = @{}) {
    $projectPrompts = @{}
    foreach ($item in $Items) {
        New-ModSettings $Workspace $item.Mod
        $path = Join-Path (Join-Path $Workspace.ModsRoot $item.Mod) 'mod.publish.psd1'
        $config = Import-PowerShellDataFile -LiteralPath $path
        Move-ModEnvironmentToRoot $config
        $effective = Get-EffectiveModSettings $config $item
        $platformSettings = Get-Setting $effective $Platform @{}
        if (-not (Get-Setting $platformSettings 'Enabled' $true)) { continue }
        $setup = Get-Setting $effective 'InteractiveSetup' @{}
        $environmentNeeded = (Get-SharedModEnvironment $config) -notin @(Get-ModEnvironments) -or ($Configure -and -not $script:ReviewedModEnvironments.ContainsKey($path))
        $runtimeNeeded = $environmentNeeded -or $Configure -or -not (Get-Setting $setup 'RuntimeComplete' $false)
        $platformNeeded = $Configure -or -not (Get-Setting $setup ($Platform + 'Complete') $false)
        Write-Host "Release: $($item.Mod) $($item.Release), $($item.Loader), Minecraft $($item.Minecraft)"
        while ($true) {
            if (-not $config.ContainsKey($Platform)) { $config[$Platform] = @{} }
            $project = [string](Get-Setting $platformSettings 'Project' '')
            if ($Projects.ContainsKey($item.Mod)) { $project = $Projects[$item.Mod] }
            if (-not $projectPrompts.ContainsKey($item.Mod) -and ($Configure -or $PromptForProject -or -not $project)) {
                if ($Platform -eq 'Modrinth') {
                    $project = Read-SetupText 'Modrinth project slug, ID, or https://modrinth.com/mod/<slug>' $project '^(?:[a-zA-Z0-9_-]+|https://modrinth\.com/mod/[^/?#]+/?(?:[?#].*)?)$' -Required
                } else {
                    $project = Read-SetupText 'CurseForge numeric project ID or https://authors.curseforge.com/dashboard/projects/<id>' $project '^(?:[1-9][0-9]*|https://authors\.curseforge\.com/dashboard/projects/[1-9][0-9]*(?:[/?#].*)?)$' -Required
                }
                $config[$Platform].Project = $project
                $Projects[$item.Mod] = $project
                $projectPrompts[$item.Mod] = $true
            }
            if ($runtimeNeeded -or $platformNeeded) {
                if (-not (Get-Setting $config 'DisplayName' '') -or $Configure -or -not $config.ContainsKey('InteractiveSetup')) {
                    $defaultName = [string](Get-Setting $config 'DisplayName' $item.Mod)
                    if ($defaultName -eq $item.Mod -and $item.Metadata.DisplayName) { $defaultName = $item.Metadata.DisplayName }
                    $config.DisplayName = Read-SetupText 'Mod display name (e.g. Omniwheel)' $defaultName '' -Required
                    $baseSetup = Get-Setting $config 'InteractiveSetup' @{}
                    $baseSetup.DisplayNameComplete = $true
                    $config.InteractiveSetup = $baseSetup
                }
                $saved = @{ InteractiveSetup = @{} }
                if ($runtimeNeeded) {
                    $saved.Runtime = Read-SetupRuntime $effective $item -SkipEnvironmentPrompt:(-not $environmentNeeded)
                    $config.Runtime = Merge-ModSettings (Get-Setting $config 'Runtime' @{}) @{ Environment = $saved.Runtime.Environment }
                    $saved.Runtime.Remove('Environment')
                    if ($environmentNeeded -and $Configure) { $script:ReviewedModEnvironments[$path] = $true }
                    $environmentNeeded = $false
                    $saved.InteractiveSetup.RuntimeComplete = $true
                }
                if ($platformNeeded) {
                    $settings = Merge-ModSettings @{} $platformSettings
                    # Project references are shared at mod level, not pinned to a release.
                    $settings.Remove('Project')
                    $settings.Remove('VersionType'); $settings.Remove('ReleaseType')
                    Write-Host "Automatic release channel for $($item.Release): $(Get-ModReleaseType $item.Release)"
                    $settings.Remove('Changelog')
                    $settings.Dependencies = Read-SetupDependencies $settings $item $Platform
                    if (Read-SetupBool 'Configure advanced publishing settings (visibility, featured/manual release, extra tags)?') {
                        if ($Platform -eq 'Modrinth') {
                            $settings.Status = Read-SetupChoice 'Version visibility' @('listed', 'unlisted', 'draft', 'archived') @('Publicly listed', 'Accessible by link', 'Draft release', 'Archived release') ([string](Get-Setting $settings 'Status' 'listed'))
                            $settings.Featured = Read-SetupBool 'Feature this release?' ([bool](Get-Setting $settings 'Featured' $false))
                            $requested = Read-SetupChoice 'Requested status' @('default', 'listed', 'unlisted', 'draft', 'archived') @() ([string](Get-Setting $settings 'RequestedStatus' 'default'))
                            if ($requested -eq 'default') { $settings.Remove('RequestedStatus') } else { $settings.RequestedStatus = $requested }
                        } else {
                            $settings.ChangelogType = Read-SetupChoice 'Release notes format' @('markdown', 'text', 'html') @() ([string](Get-Setting $settings 'ChangelogType' 'markdown'))
                            $settings.ManualRelease = Read-SetupBool 'Hold for manual release after approval?' ([bool](Get-Setting $settings 'ManualRelease' $false))
                        $tags = Read-SetupText 'Extra non-Java CurseForge compatibility names, comma-separated (- clears; Java tags are automatic)' (@((Get-Setting $settings 'GameVersionNames' @()) | Where-Object { $_ -notmatch '^Java(?:\s|$)' }) -join ',')
                            $settings.GameVersionNames = @()
                            if ($tags -and $tags -ne '-') { $settings.GameVersionNames = @($tags.Split(',') | ForEach-Object { $_.Trim() }) }
                            $ids = Read-SetupText 'Extra CurseForge compatibility IDs, comma-separated (blank = none; - clears)' (@(Get-Setting $settings 'GameVersions' @()) -join ',') '^(?:-|[1-9][0-9]{0,8}(\s*,\s*[1-9][0-9]{0,8})*)$'
                            $settings.GameVersions = @()
                            if ($ids -and $ids -ne '-') { $settings.GameVersions = @($ids.Split(',') | ForEach-Object { [int]$_.Trim() }) }
                        }
                    }
                    $saved[$Platform] = $settings
                    $saved.InteractiveSetup[$Platform + 'Complete'] = $true
                }
                # Platform and preview options remain variant-specific; the
                # client/server answer above is stored only at mod level.
                $rule = @{ Versions = @($item.Minecraft); Loaders = @($item.Loader); ReleaseVersions = @($item.Release); Settings = $saved }
                $config.Overrides = @(Get-Setting $config 'Overrides' @()) + @($rule)
            }
            try {
                $candidateConfigs = @{ $item.Mod = $config }
                $null = @(Get-UploadPlan $Workspace @($item) $Platform $Projects -SettingsOverrides $candidateConfigs -Changelog ([string](Get-Setting $ChangelogInput 'Value' '')) -OverrideChangelog:$ChangelogInput.ContainsKey('Value'))
            } catch {
                if ($_.Exception.Message.StartsWith('Automatic Java:') -or $_.Exception.Message.StartsWith('Changelog:')) { throw }
                Write-Host "Please review the settings: $($_.Exception.Message)"
                $runtimeNeeded = $true
                $platformNeeded = $true
                continue
            }
            Save-ModSettings $path $config
            Write-Host "Saved settings: $path"
            break
        }
    }
}

function Invoke-ModPublishSetup($Workspace, $Items, [string]$Platform, [hashtable]$Projects, [switch]$Configure, [switch]$PromptForProject, [switch]$PromptForChangelog, [hashtable]$ChangelogInput = @{}) {
    foreach ($group in @($Items | Group-Object Mod, Release)) {
        $members = @($group.Group)
        $modName = $members[0].Mod
        New-ModSettings $Workspace $modName
        $path = Join-Path (Join-Path $Workspace.ModsRoot $modName) 'mod.publish.psd1'
        $before = Import-PowerShellDataFile -LiteralPath $path
        Initialize-ModChangelog $Workspace $members $before
        if (-not $ChangelogInput.ContainsKey('Value')) { $null = Read-ModReleaseChangelog $Workspace $modName $members[0].Release }
        Write-Host "Changelog: $($Workspace.ModsRoot)/$modName/changelog.md -> ## $($members[0].Release)"
        # Prefer an already configured variant so existing release choices are
        # offered once as defaults for the rest of this batch.
        $ranked = @($members | Sort-Object -Property @{ Expression = {
            $effective = Get-EffectiveModSettings $before $_
            $setup = Get-Setting $effective 'InteractiveSetup' @{}
            [int](Get-Setting $setup 'RuntimeComplete' $false) + [int](Get-Setting $setup ($Platform + 'Complete') $false)
        }; Descending = $true })
        $representative = $ranked[0]
        Write-Host "Publishing batch: $modName $($representative.Release), $($members.Count) JAR(s). Shared settings are asked once."
        $members | Select-Object FileName, Loader, @{ Name = 'Minecraft'; Expression = { (Resolve-MinecraftVersions $_.Minecraft) -join ', ' } }, @{ Name = 'Java'; Expression = { (@(Resolve-MinecraftVersions $_.Minecraft) | ForEach-Object { (Get-MinecraftJavaRequirement $_).JavaMajor } | Sort-Object -Unique) -join ', ' } } | Format-Table -AutoSize | Out-Host
        Invoke-ModVariantSetup $Workspace @($representative) $Platform $Projects -Configure:$Configure -PromptForProject:$PromptForProject -PromptForChangelog:$PromptForChangelog -ChangelogInput $ChangelogInput
        $config = Import-PowerShellDataFile -LiteralPath $path
        $shared = Get-EffectiveModSettings $config $representative
        foreach ($member in $members) {
            if ($member -eq $representative) { continue }
            $previous = Get-EffectiveModSettings $before $member
            $previousSetup = Get-Setting $previous 'InteractiveSetup' @{}
            $saved = @{ InteractiveSetup = @{} }
            if ($Configure -or -not (Get-Setting $previousSetup 'RuntimeComplete' $false)) {
                $runtime = Merge-ModSettings @{} (Get-Setting $shared 'Runtime' @{})
                $runtime.Remove('Environment')
                $saved.Runtime = $runtime
                $saved.InteractiveSetup.RuntimeComplete = $true
            }
            if ($Configure -or -not (Get-Setting $previousSetup ($Platform + 'Complete') $false)) {
                $saved[$Platform] = Merge-ModSettings @{} (Get-Setting $shared $Platform @{})
                $saved[$Platform].Remove('Project')
                $saved.InteractiveSetup[$Platform + 'Complete'] = $true
            }
            $config.Overrides = @(Get-Setting $config 'Overrides' @()) + @(@{ Versions = @($member.Minecraft); Loaders = @($member.Loader); ReleaseVersions = @($member.Release); Settings = $saved })
        }
        # Validate all targets before saving the propagated choices or uploading.
        $null = @(Get-UploadPlan $Workspace $members $Platform $Projects -SettingsOverrides @{ $modName = $config } -Changelog ([string](Get-Setting $ChangelogInput 'Value' '')) -OverrideChangelog:$ChangelogInput.ContainsKey('Value'))
        Save-ModSettings $path $config
    }
}
