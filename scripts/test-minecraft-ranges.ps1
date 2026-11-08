# Offline end-to-end coverage for one binary advertising several Minecraft releases.
function Test-MinecraftRangePublishing($ParentWorkspace) {
    . (Join-Path $PSScriptRoot 'publish-setup.ps1')
    Assert ((@(Resolve-MinecraftVersions '26.1.x') -join ',') -ceq '26.1,26.1.1,26.1.2') 'Wildcard includes the base release and its known patches'
    Assert ((@(Resolve-MinecraftVersions '1.21.1-1.21.3') -join ',') -ceq '1.21.1,1.21.2,1.21.3') 'Filename range includes both endpoints'
    Assert ((@(Resolve-MinecraftVersions '1.21.9-1.21.11') -join ',') -ceq '1.21.9,1.21.10,1.21.11') 'Ranges use numeric ordering'
    Assert ((@(Resolve-MinecraftVersions '26.1..26.1.2') -join ',') -ceq '26.1,26.1.1,26.1.2') 'Existing double-dot range syntax also expands'
    Assert ((@(Resolve-MinecraftVersions '26.4-snapshot-7') -join ',') -ceq '26.4-snapshot-7') 'Exact snapshot identifiers stay intact'
    Assert-Throws { Resolve-MinecraftVersions '1.21.3-1.21.1' } 'Reversed range'
    Assert-Throws { Resolve-MinecraftVersions '99.1.x' } 'matches no known releases'
    Assert-Throws { Resolve-MinecraftVersions '26.1-99.1' } 'unknown endpoint'
    Assert (Test-GameSelection '26.1.x' @('26.1.1')) 'A concrete version selects its multi-version JAR'
    Assert (Test-GameSelection '1.21.1-1.21.3' @('1.21.2..1.21.11')) 'Overlapping ranges select a JAR once'
    Assert (Test-GameSelection '26.1.2' @('26.1.x')) 'Wildcard selection matches exact-version JARs'
    Assert (-not (Test-GameSelection '1.21.11' @('1.21.1-1.21.3'))) 'Unrelated numeric patches do not match'
    Assert (-not (Test-GameSelection '26.4-snapshot-7' @('26.1-26.3'))) 'Numeric selection skips snapshots'
    $root = Join-Path $ParentWorkspace.Root 'minecraft-ranges'
    $workspace = @{ Root = $root; IncomingRoot = (Join-Path $root 'incoming'); ModsRoot = (Join-Path $root 'mods') }
    foreach ($directory in @((Join-Path $root 'config'), $workspace.IncomingRoot, $workspace.ModsRoot)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    foreach ($loader in @('fabric', 'quilt', 'forge', 'neoforge')) {
        foreach ($target in @('26.1.x', '1.21.1-1.21.3')) {
            $path = Join-Path $workspace.IncomingRoot "rangefixture-1.0-$loader-mc$target.jar"
            $manifest = @{ fabric = 'fabric.mod.json'; quilt = 'quilt.mod.json'; forge = 'META-INF/mods.toml'; neoforge = 'META-INF/neoforge.mods.toml' }[$loader]
            $constraint = if ($target -eq '26.1.x') { '[26.1,26.2)' } else { '[1.21.1,1.21.3]' }
            $text = switch ($loader) {
                fabric { '{"id":"rangefixture","name":"Range Mod","version":"1.0","environment":"*"}' }
                quilt { '{"quilt_loader":{"id":"rangefixture","metadata":{"name":"Range Mod"},"version":"1.0"},"minecraft:environment":"*"}' }
                default { "[[mods]]`nmodId=`"rangefixture`"`nversion=`"1.0`"`ndisplayName=`"Range Mod`"`n[[dependencies.rangefixture]]`nmodId=`"minecraft`"`nversionRange=`"$constraint`"" }
            }
            $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
            try {
                $writer = [IO.StreamWriter]::new($zip.CreateEntry($manifest).Open())
                try { $writer.Write($text) } finally { $writer.Dispose() }
                $stream = $zip.CreateEntry('example/Mod.class').Open()
                try { $stream.Write([byte[]]@(202,254,186,190,0,0,0,65), 0, 8) } finally { $stream.Dispose() }
            } finally { $zip.Dispose() }
        }
    }
    $items = @(Get-PublishItems $workspace)
    Assert ($items.Count -eq 8) 'All loaders accept wildcard and range filenames'
    Assert (@(Get-PublishItems $workspace -Version @('26.1.1')).Count -eq 4) 'Concrete selection discovers wildcard artifacts for all loaders'
    $answers = [Collections.Generic.Queue[string]]::new()
    foreach ($answer in @('example-mod', '', 'client_and_server', 'keep', 'no')) { $answers.Enqueue($answer) }
    function Read-Host([string]$Prompt) {
        if (-not $answers.Count) { throw "Unexpected repeated range setup prompt: $Prompt" }
        return $answers.Dequeue()
    }
    Invoke-ModPublishSetup $workspace $items 'Modrinth' @{}
    Assert ($answers.Count -eq 0) 'Guided setup handles all eight multi-version JARs with one set of answers'
    $mr = @(Get-UploadPlan $workspace $items 'Modrinth')
    $cf = @(Get-UploadPlan $workspace $items 'CurseForge' @{ rangefixture = '123456' })
    foreach ($plan in @($mr) + @($cf)) {
        $expected = if ($plan.Item.Minecraft -eq '26.1.x') { '26.1,26.1.1,26.1.2' } else { '1.21.1,1.21.2,1.21.3' }
        Assert (($plan.Runtime.MinecraftVersions -join ',') -ceq $expected) 'Each upload contains exactly the concrete release targets'
        Assert ($plan.Runtime.JavaVersions.Count -eq 1 -and $plan.Runtime.JavaVersions[0] -eq $(if ($plan.Item.Minecraft -eq '26.1.x') { 25 } else { 21 })) 'Java resolved for every advertised Minecraft release'
        Assert ($plan.Number -ceq "1.0-$($plan.Item.Loader)-mc$($plan.Item.Minecraft)") 'Version number preserves the filename expression'
        if ($plan.Platform -eq 'Modrinth') {
            Assert (($plan.Data.game_versions -join ',') -ceq $expected -and $plan.Data.name -ceq 'Range Mod 1.0') 'Modrinth receives expanded tags and the clean subtitle'
        } else {
            foreach ($game in $plan.Runtime.MinecraftVersions) { Assert ($plan.Data.gameVersionNames -contains $game) 'CurseForge receives each concrete release tag' }
            Assert ($plan.Data.gameVersionNames -notcontains $plan.Item.Minecraft) 'CurseForge never receives a wildcard or range tag'
            Assert ($plan.Data.displayName -ceq [IO.Path]::GetFileNameWithoutExtension($plan.Item.FileName)) 'CurseForge preserves the original display-name scheme'
        }
    }
    $rangeItem = @($items | Where-Object Minecraft -eq '1.21.1-1.21.3')[0]
    Assert (Test-Dependency @{ Versions = @('1.21.2'); MinVersion = '1.21.2'; BeforeVersion = '1.21.3' } $rangeItem) 'Dependency selectors evaluate concrete targets'
    Assert (-not (Test-Dependency @{ Versions = @('1.21.1'); MinVersion = '1.21.2' } $rangeItem)) 'All dependency conditions must match the same target'
    Assert (-not (Test-Dependency @{ ExcludeVersions = @('1.21.x') } $rangeItem)) 'Excluded targets cannot activate a dependency'
    $javaItem = Read-ModJar $rangeItem.Path
    $javaItem.Minecraft = '1.20.4-1.20.5'
    Assert-Throws { Get-ModRuntime @{ Runtime = @{ Environment = 'client_and_server' } } $javaItem } 'Minecraft 1.20.4.*bytecode minimum'
    $javaItem.RuntimeEvidence.BytecodeMinimumJava = 17
    Assert (((Get-ModRuntime @{ Runtime = @{ Environment = 'client_and_server' } } $javaItem).JavaVersions -join ',') -ceq '17,21') 'Ranges crossing Java requirements retain every required Java tag'
    $badForge = Join-Path $workspace.IncomingRoot 'rangefixture-1.0-forge-mc1.21.1-1.21.4.jar'
    Copy-Item -LiteralPath (Join-Path $workspace.IncomingRoot 'rangefixture-1.0-forge-mc1.21.1-1.21.3.jar') -Destination $badForge
    try { Assert-Throws { Read-ModJar $badForge } 'outside the JAR manifest range' } finally { Remove-Item -LiteralPath $badForge }
    $handler = [ModsTestHandler]::new()
    function New-PublishClient([string]$Platform, [string]$Token) { return [Net.Http.HttpClient]::new($handler, $false) }
    try {
        $batches = [ordered]@{ Modrinth = $mr; CurseForge = $cf }
        $tokens = @{ Modrinth = 'fake-token'; CurseForge = 'fake-token' }
        Invoke-PlatformPublishBatches $workspace $batches $tokens
        Assert ($handler.PostCount -eq 16) 'Eight JARs upload once each to both platforms, rather than once per Minecraft version'
        Assert (@(Get-ChildItem -LiteralPath $workspace.IncomingRoot -Filter '*.jar').Count -eq 0) 'Successful publishing organizes every fixture JAR'
        foreach ($item in $items) {
            $retained = Get-PublishedModPath $workspace $item
            Assert ((Test-Path -LiteralPath $retained) -and (Get-FileHash -LiteralPath $retained -Algorithm SHA512).Hash.ToLowerInvariant() -ceq $item.Hash) 'Wildcard/range filenames and bytes survive retention'
        }
        Invoke-PlatformPublishBatches $workspace $batches $tokens
        Assert ($handler.PostCount -eq 16) 'Wildcard and range receipts prevent duplicate uploads on retry'
    } finally { $handler.Dispose() }
    Write-Host 'All Minecraft wildcard and range publishing tests passed.' -ForegroundColor Green
}
Test-MinecraftRangePublishing $w
