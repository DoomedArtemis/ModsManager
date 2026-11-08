function Test-MultiJarPublishBatch($ParentWorkspace) {
    . (Join-Path $PSScriptRoot 'publish-setup.ps1')
    $root = Join-Path $ParentWorkspace.Root 'publish-batch'
    $workspace = @{ Root = $root; IncomingRoot = (Join-Path $root 'incoming'); ModsRoot = (Join-Path $root 'mods') }
    foreach ($directory in @((Join-Path $root 'config'), $workspace.IncomingRoot, $workspace.ModsRoot)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    function New-BatchForgeJar([string]$Path, [string]$Minecraft, [int]$Java, [string]$Release = '2.1.0') {
        $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $writer = [IO.StreamWriter]::new($zip.CreateEntry('META-INF/mods.toml').Open())
            try {
                $writer.Write("modLoader=`"javafml`"`n[[mods]]`nmodId=`"omniwheel`"`nversion=`"$Release`"`ndisplayName=`"OmniWheel`"`ndescription='''`n[[mods]]`nThis is description text, not another mod section.`n'''`n[[dependencies.`"omniwheel`"]]`nmodId=`"minecraft`"`nversionRange=`"[$Minecraft]`"`nside=`"CLIENT`"`n")
            } finally { $writer.Dispose() }
            $stream = $zip.CreateEntry('example/Mod.class').Open()
            try { $stream.Write([byte[]]@(202,254,186,190,0,0,0,($Java + 44)), 0, 8) } finally { $stream.Dispose() }
        } finally { $zip.Dispose() }
    }
    $cases = @{ '1.16.5' = 8; '1.18.2' = 17; '1.19.2' = 17; '1.20.1' = 17; '1.21.1' = 21 }
    foreach ($case in $cases.GetEnumerator()) { New-BatchForgeJar (Join-Path $workspace.IncomingRoot "omniwheel-2.1.0-forge-mc$($case.Key).jar") $case.Key $case.Value }
    New-TestJar (Join-Path $workspace.IncomingRoot 'omniwheel-2.1.0-fabric-mc1.21.1.jar')
    New-ModSettings $workspace 'omniwheel'
    $settingsPath = Join-Path $workspace.ModsRoot 'omniwheel/mod.publish.psd1'
    $config = Import-PowerShellDataFile -LiteralPath $settingsPath
    $config.Modrinth.Dependencies = @(@{ ProjectId = 'P7dR8mSH'; Type = 'optional'; Versions = @('1.20.1'); Loaders = @('forge') })
    Save-ModSettings $settingsPath $config
    $oldDirectory = Join-Path $workspace.ModsRoot 'omniwheel/forge/2.0.0'
    New-Item -ItemType Directory -Path $oldDirectory -Force | Out-Null
    $oldJar = Join-Path $oldDirectory 'omniwheel-2.0.0-forge-mc1.20.1.jar'
    New-BatchForgeJar $oldJar '1.20.1' 17 '2.0.0'
    $items = @(Get-PublishItems $workspace)
    Assert ($items.Count -eq 6 -and @($items | Where-Object Release -ne '2.1.0').Count -eq 0) 'Default publishing targets incoming JARs without selecting older retained releases'
    Assert (@(Get-PublishItems $workspace -Source all).Count -eq 7) 'Explicit source selection can include retained releases'
    $answers = [Collections.Generic.Queue[string]]::new()
    $batchNotes = "**Added:**`n- New Clipboard entry type.`n`n**Changed:**`n- Updated the default profile."
    [IO.File]::WriteAllText((Join-Path $workspace.ModsRoot 'omniwheel/changelog.md'), "# OmniWheel changelog`n`n## 2.1.0`n`n$batchNotes`n`n## 2.0.0`n`nOlder release.`n")
    foreach ($answer in @('omni-wheel', '', 'client_only', 'keep', 'no')) { $answers.Enqueue($answer) }
    function Read-Host([string]$Prompt) {
        if ($Prompt -match 'Supported Java|Supported Minecraft') { throw 'Artifact targets must never be requested interactively.' }
        if (-not $answers.Count) { throw "Unexpected repeated batch prompt: $Prompt" }
        return $answers.Dequeue()
    }
    $projects = @{}
    Invoke-ModPublishSetup $workspace $items 'Modrinth' $projects
    Assert ($answers.Count -eq 0) 'Six variants require only one set of shared setup answers'
    $plans = @(Get-UploadPlan $workspace $items 'Modrinth' $projects)
    Assert ($plans.Count -eq 6) 'One independent upload plan per incoming artifact'
    foreach ($plan in $plans) {
        Assert ($plan.Data.game_versions.Count -eq 1 -and $plan.Data.game_versions[0] -eq $plan.Item.Minecraft) 'Each upload uses its own Minecraft target'
        if ($plan.Item.Loader -eq 'forge' -and $plan.Item.Minecraft -eq '1.20.1') {
            Assert ($plan.Data.loaders.Count -eq 2 -and $plan.Data.loaders -contains 'forge' -and $plan.Data.loaders -contains 'neoforge') 'Forge 1.20.1 advertises both compatible mod loaders'
            Assert ($plan.Data.version_number -eq '2.1.0-forge-mc1.20.1' -and $plan.Item.Loader -eq 'forge') 'Extra loader tag does not relabel the version number or artifact'
        } else {
            Assert ($plan.Data.loaders.Count -eq 1 -and $plan.Data.loaders[0] -eq $plan.Item.Loader) 'Other artifacts retain their original loader metadata'
        }
        Assert ($plan.Runtime.JavaVersions[0] -eq (Get-MinecraftJavaRequirement $plan.Item.Minecraft).JavaMajor) 'Each variant gets its own automatic Java version'
        Assert ($plan.Data.environment -eq 'client_only' -and $plan.Data.name -eq 'OmniWheel 2.1.0') 'All loader/Minecraft variants share the clean display-name-and-release subtitle'
        Assert ($plan.Data.changelog -ceq $batchNotes) 'Multiline release notes propagate unchanged to every JAR in the batch'
        $expectedDependencies = [int]($plan.Item.Minecraft -eq '1.20.1' -and $plan.Item.Loader -eq 'forge')
        Assert ($plan.Data.dependencies.Count -eq $expectedDependencies) 'Dependency selectors apply independently to each artifact'
    }
    $cfPlans = @(Get-UploadPlan $workspace $items 'CurseForge' @{ omniwheel = '123456' })
    foreach ($cfPlan in $cfPlans) {
        $shouldIncludeNeoForge = $cfPlan.Item.Loader -eq 'forge' -and $cfPlan.Item.Minecraft -eq '1.20.1'
        Assert (($cfPlan.Data.gameVersionNames -contains 'NeoForge') -eq $shouldIncludeNeoForge) 'CurseForge adds the NeoForge tag only for Forge 1.20.1'
        Assert ($cfPlan.Data.displayName -ceq [IO.Path]::GetFileNameWithoutExtension($cfPlan.Item.FileName)) 'Additional loader tags do not change CurseForge display names'
        Assert ($cfPlan.Data.changelog -ceq $batchNotes) 'Additional loader tags do not change release notes'
    }
    # Repeated setup preserves intentionally different saved per-variant options.
    $customConfig = Import-PowerShellDataFile -LiteralPath $settingsPath
    $customConfig.Overrides += @{ Versions = @('1.20.1'); Loaders = @('forge'); ReleaseVersions = @('2.1.0'); Settings = @{ Modrinth = @{ Status = 'unlisted' } } }
    Save-ModSettings $settingsPath $customConfig
    Invoke-ModPublishSetup $workspace $items 'Modrinth' @{}
    Assert ($answers.Count -eq 0) 'Saved batch configuration reuses all shared answers'
    $plans = @(Get-UploadPlan $workspace $items 'Modrinth' $projects)
    Assert (@($plans | Where-Object { $_.Item.Minecraft -eq '1.20.1' -and $_.Item.Loader -eq 'forge' })[0].Data.status -eq 'unlisted') 'Existing customized variant settings are preserved'
    Assert-Throws { Assert-JarMinecraftConstraint '[1.20.1]' '1.19.2' } 'manifest targets Minecraft'
    Assert-Throws { Assert-JarMinecraftConstraint '[1.18,1.20)' '1.20.1' } 'outside the JAR manifest range'
    $mismatched = Join-Path $workspace.IncomingRoot 'omniwheel-2.2.0-forge-mc1.16.5.jar'
    Copy-Item -LiteralPath (Join-Path $workspace.IncomingRoot 'omniwheel-2.1.0-forge-mc1.16.5.jar') -Destination $mismatched
    Assert-Throws { Read-ModJar $mismatched } 'differs from manifest version'
    Remove-Item -LiteralPath $mismatched
    # Simulate the newest Forge variant already being on Modrinth, then publish
    # the remaining five artifacts through the real multipart implementation.
    $handler = [ModsTestHandler]::new()
    $alreadyPublished = @($items | Where-Object { $_.Loader -eq 'forge' -and $_.Minecraft -eq '1.21.1' })[0]
    $handler.VersionBody = ConvertTo-Json -InputObject @(@{ version_number = '2.1.0-forge-mc1.21.1'; files = @(@{ hashes = @{ sha512 = $alreadyPublished.Hash } }) }) -Depth 10 -Compress
    function New-PublishClient([string]$Platform, [string]$Token) { return [Net.Http.HttpClient]::new($handler, $false) }
    try {
        Invoke-PublishPlans $workspace $plans 'offline-test'
        Assert ($handler.PostCount -eq 5) 'One batch uploads all remaining JARs and skips the existing matching remote variant'
        Assert (@(Get-ChildItem -LiteralPath $workspace.IncomingRoot -Filter '*.jar').Count -eq 0) 'Every successfully published or matched incoming JAR is organized'
        Assert (Test-Path -LiteralPath $oldJar) 'Unselected historical release preserved'
        foreach ($item in $items) { Assert (Test-Path -LiteralPath (Get-PublishedModPath $workspace $item)) 'Artifacts stored by mod, loader, release with original Minecraft-specific filenames' }
        $receipts = Get-Content (Join-Path $root 'config/publish-state.local.json') -Raw | ConvertFrom-Json
        Assert (@($receipts).Count -eq 5) 'Distinct upload receipts persist for the full batch'
        Invoke-PublishPlans $workspace @(Get-UploadPlan $workspace @(Get-ModItems $workspace -ReleaseVersion '2.1.0') 'Modrinth' $projects) 'offline-test'
        Assert ($handler.PostCount -eq 5) 'Repeating a completed batch creates no duplicate uploads'
    } finally { $handler.Dispose() }
    Write-Host 'All multi-JAR publishing batch tests passed.' -ForegroundColor Green
}
Test-MultiJarPublishBatch $w
