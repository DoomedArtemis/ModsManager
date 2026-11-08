function Test-SharedModEnvironment($ParentWorkspace, $SourceItem) {
    . (Join-Path $PSScriptRoot 'publish-setup.ps1')
    $root = Join-Path $ParentWorkspace.Root 'shared-environment'
    $workspace = @{ Root = $root; ModsRoot = (Join-Path $root 'mods'); IncomingRoot = (Join-Path $root 'incoming') }
    $item = Read-ModJar $SourceItem.Path
    $item.Mod = 'environmentfixture'
    $item.RuntimeEvidence.ManifestEnvironment = '*'
    $answers = [Collections.Generic.Queue[string]]::new()
    $counts = @{ Environment = 0 }
    $choiceImplementation = ${function:Read-SetupChoice}
    function Read-SetupChoice([string]$Label, [string[]]$Values, [string[]]$Descriptions, [string]$Default = '') {
        if ($Label.StartsWith('Where must players install')) { $counts.Environment++ }
        return & $choiceImplementation $Label $Values $Descriptions $Default
    }
    function Read-Host([string]$Prompt) {
        if (-not $answers.Count) { throw "Unexpected shared environment prompt: $Prompt" }
        return $answers.Dequeue()
    }
    $projects = @{ environmentfixture = 'example-project' }
    foreach ($answer in @('', 'client_and_server', 'keep', 'no')) { $answers.Enqueue($answer) }
    Invoke-ModPublishSetup $workspace @($item) Modrinth $projects
    $path = Join-Path $workspace.ModsRoot 'environmentfixture/mod.publish.psd1'
    $saved = Import-PowerShellDataFile $path
    Assert ($counts.Environment -eq 1 -and $saved.Runtime.Environment -eq 'client_and_server') 'First setup asks once and stores client/server at mod level'
    Assert (@([regex]::Matches([IO.File]::ReadAllText($path), "'Environment'\s*=")).Count -eq 1) 'Saved mod contains exactly one environment declaration'
    $future = Read-ModJar $SourceItem.Path
    $future.Mod = $item.Mod; $future.Release = '2.2.0'; $future.Minecraft = '1.21.1'
    $future.RuntimeEvidence.ManifestEnvironment = '*'
    $forge = Read-ModJar $SourceItem.Path
    $forge.Mod = $item.Mod; $forge.Release = $future.Release; $forge.Loader = 'forge'
    $forge.RuntimeEvidence.ManifestEnvironment = '*'
    $null = Set-ModReleaseChangelog $workspace $item.Mod $future.Release 'Next release notes.'
    foreach ($answer in @('keep', 'no')) { $answers.Enqueue($answer) }
    Invoke-ModPublishSetup $workspace @($future, $forge) Modrinth $projects
    foreach ($answer in @('keep', 'no', 'keep', 'no')) { $answers.Enqueue($answer) }
    $cfProjects = @{ environmentfixture = '123456' }
    Invoke-ModPublishSetup $workspace @($item, $future, $forge) CurseForge $cfProjects
    # The second release needs its platform choices, but never another side choice.
    Assert ($counts.Environment -eq 1) 'New releases, Minecraft targets, loaders and second platform never repeat the environment question'
    foreach ($platform in @('Modrinth', 'CurseForge')) {
        $projectOverrides = if ($platform -eq 'Modrinth') { $projects } else { $cfProjects }
        foreach ($plan in @(Get-UploadPlan $workspace @($item, $future, $forge) $platform $projectOverrides)) {
            Assert ($plan.Runtime.Environment -eq 'client_and_server') 'Every platform and binary uses the shared mod installation requirement'
        }
    }
    # Configure can change the shared choice, once even for a mixed-release batch.
    foreach ($answer in @('', '', 'client_only', 'keep', 'no', '', '', 'keep', 'no')) { $answers.Enqueue($answer) }
    Invoke-ModPublishSetup $workspace @($item, $future, $forge) Modrinth $projects -Configure
    Assert ($counts.Environment -eq 2 -and $answers.Count -eq 0) 'Explicit review asks once per mod across multiple releases'
    foreach ($plan in @(Get-UploadPlan $workspace @($item, $future, $forge) Modrinth $projects)) { Assert ($plan.Data.environment -eq 'client_only') 'A reviewed mod-wide setting updates every variant immediately' }
    $legacy = @{
        Runtime = @{ Environment = 'auto'; AllowPreviewFeatures = $false }
        Overrides = @(
            @{ Versions = @('26.3'); Settings = @{ Runtime = @{ Environment = 'client_only'; AllowPreviewFeatures = $true }; Modrinth = @{ Status = 'unlisted' } } }
            @{ Loaders = @('forge'); Settings = @{ Runtime = @{ Environment = 'client_only' } } }
        )
    }
    Assert ((Get-EffectiveModSettings $legacy $future).Runtime.Environment -eq 'client_only') 'Legacy answer is reusable on an unconfigured future variant before the config is rewritten'
    $legacyPath = Join-Path $root 'legacy.psd1'
    Save-ModSettings $legacyPath $legacy
    $migrated = Import-PowerShellDataFile $legacyPath
    Assert ($migrated.Runtime.Environment -eq 'client_only' -and @([regex]::Matches([IO.File]::ReadAllText($legacyPath), "'Environment'\s*=")).Count -eq 1) 'Existing identical answers migrate automatically into one root setting'
    Assert ($migrated.Overrides[0].Settings.Runtime.AllowPreviewFeatures -and $migrated.Overrides[0].Settings.Modrinth.Status -eq 'unlisted') 'Migration preserves preview permissions and platform metadata'
    $migrated.Runtime.Environment = 'client_and_server'
    $migrated.Overrides[0].Settings.Runtime.Environment = 'server_only'
    Assert ((Get-EffectiveModSettings $migrated $item).Runtime.Environment -eq 'client_and_server') 'Stale variant answers cannot override the shared mod setting'
    $other = Read-ModJar $SourceItem.Path
    $other.Mod = 'otherenvironmentmod'
    foreach ($answer in @('', 'client_only', 'keep', 'no')) { $answers.Enqueue($answer) }
    Invoke-ModPublishSetup $workspace @($other) Modrinth @{ otherenvironmentmod = 'other-project' }
    Assert ($counts.Environment -eq 3 -and $answers.Count -eq 0) 'A different mod has its own independently saved environment choice'
    Write-Host 'All shared mod environment tests passed.' -ForegroundColor Green
}
Test-SharedModEnvironment $w $items[0]
