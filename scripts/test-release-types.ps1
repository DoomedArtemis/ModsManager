function Test-AutomaticReleaseTypes($ParentWorkspace) {
    . (Join-Path $PSScriptRoot 'publish-setup.ps1')
    foreach ($case in @(
        @('1.0', 'release'), @('2.1.0', 'release'), @('1.0b', 'beta'), @('1.0a', 'alpha'),
        @('1.0B', 'beta'), @('1.0A', 'alpha'), @('1.0b2', 'beta'), @('1.0a.2', 'alpha'),
        @('1.0-beta.1', 'beta'), @('1.0-alpha.2', 'alpha'), @('1.0+build.alpha', 'release')
    )) { Assert ((Get-ModReleaseType $case[0]) -ceq $case[1]) "Automatic channel for $($case[0]) is $($case[1])" }
    Assert-Throws { Get-ModReleaseType '1.0banana' } 'Automatic release channel: cannot classify'
    $root = Join-Path $ParentWorkspace.Root 'release-types'
    $workspace = @{ Root = $root; ModsRoot = (Join-Path $root 'mods'); IncomingRoot = (Join-Path $root 'incoming') }
    New-Item -ItemType Directory -Path $workspace.IncomingRoot -Force | Out-Null
    foreach ($loader in @('fabric', 'quilt', 'forge', 'neoforge')) {
        foreach ($release in @('1.0', '1.0a', '1.0b')) {
            $path = Join-Path $workspace.IncomingRoot "releasefixture-$release-$loader-mc26.1.x.jar"
            $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
            try {
                $manifest = @{ fabric = 'fabric.mod.json'; quilt = 'quilt.mod.json'; forge = 'META-INF/mods.toml'; neoforge = 'META-INF/neoforge.mods.toml' }[$loader]
                $text = switch ($loader) {
                    fabric { '{"id":"releasefixture","version":"' + $release + '","environment":"*"}' }
                    quilt { '{"quilt_loader":{"id":"releasefixture","version":"' + $release + '"},"minecraft:environment":"*"}' }
                    default { "[[mods]]`nmodId=`"releasefixture`"`nversion=`"$release`"" }
                }
                $writer = [IO.StreamWriter]::new($zip.CreateEntry($manifest).Open())
                try { $writer.Write($text) } finally { $writer.Dispose() }
            } finally { $zip.Dispose() }
        }
    }
    New-ModSettings $workspace 'releasefixture'
    $configPath = Join-Path $workspace.ModsRoot 'releasefixture/mod.publish.psd1'
    $config = Import-PowerShellDataFile $configPath
    $config.DisplayName = 'Release Fixture'
    $config.Runtime.Environment = 'client_and_server'
    $config.Modrinth.Project = 'example-project'; $config.CurseForge.Project = '123456'
    $config.Modrinth.VersionType = 'alpha'; $config.CurseForge.ReleaseType = 'alpha'
    $config.Overrides = @(@{ Settings = @{ Modrinth = @{ VersionType = 'beta' }; CurseForge = @{ ReleaseType = 'beta' } } })
    [IO.File]::WriteAllText($configPath, (ConvertTo-ModDataLiteral $config))
    $items = @(Get-PublishItems $workspace -Source incoming)
    Assert ($items.Count -eq 12) 'Release, short-alpha and short-beta JARs are accepted across all four loaders'
    $handler = [ModsTestHandler]::new()
    $client = [Net.Http.HttpClient]::new($handler)
    try {
        foreach ($platform in @('Modrinth', 'CurseForge')) {
            $plans = @(Get-UploadPlan $workspace $items $platform)
            Assert ($plans.Count -eq 12) 'Mixed release-channel batch retains one plan per artifact'
            foreach ($plan in $plans) {
                $expected = @{ '1.0' = 'release'; '1.0a' = 'alpha'; '1.0b' = 'beta' }[$plan.Item.Release]
                $field = if ($platform -eq 'Modrinth') { 'version_type' } else { 'releaseType' }
                Assert ($plan.Data[$field] -ceq $expected) 'Legacy root and variant channel settings cannot change the automatic per-JAR channel'
                Assert ($plan.Number -ceq "$($plan.Item.Release)-$($plan.Item.Loader)-mc26.1.x") 'Channel detection does not rewrite version numbers or artifact naming'
                if ($platform -eq 'Modrinth') { Resolve-ModrinthUploadProjects $client @($plan) }
                $null = Send-ModUpload $client $plan
                Assert ($handler.Body.Contains(('"' + $field + '":"' + $expected + '"'))) 'Actual multipart metadata contains the per-JAR automatic channel'
            }
        }
    } finally { $client.Dispose() }
    $answers = [Collections.Generic.Queue[string]]::new()
    foreach ($answer in @('', 'keep', 'no', 'keep', 'no', 'keep', 'no')) { $answers.Enqueue($answer) }
    $choiceImplementation = ${function:Read-SetupChoice}
    function Read-SetupChoice([string]$Label, [string[]]$Values, [string[]]$Descriptions, [string]$Default = '') {
        if ($Label -eq 'Release channel') { throw 'The release channel must never be requested interactively.' }
        return & $choiceImplementation $Label $Values $Descriptions $Default
    }
    function Read-Host([string]$Prompt) {
        if (-not $answers.Count) { throw "Unexpected automatic channel prompt: $Prompt" }
        return $answers.Dequeue()
    }
    Invoke-ModPublishSetup $workspace $items Modrinth @{}
    Assert ($answers.Count -eq 0) 'Guided mixed-channel batch asks no channel question'
    foreach ($answer in @('keep', 'no', 'keep', 'no', 'keep', 'no')) { $answers.Enqueue($answer) }
    Invoke-ModPublishSetup $workspace $items CurseForge @{}
    Assert ($answers.Count -eq 0) 'Second platform also requires no channel answer'
    Assert ([IO.File]::ReadAllText($configPath) -notmatch "'(VersionType|ReleaseType)'\s*=") 'Saving removes obsolete channel fields from base settings and overrides'
    Write-Host 'All automatic per-JAR release channel tests passed.' -ForegroundColor Green
}
Test-AutomaticReleaseTypes $w
