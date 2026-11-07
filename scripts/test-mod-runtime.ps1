# Called by test-mod-manager.ps1 with its temporary workspace and real JAR fixture.
$rItem = $items[0]
Assert ($rItem.RuntimeEvidence.BytecodeMinimumJava -eq 21) 'Java 21 class header detected'
Assert ($rItem.RuntimeEvidence.ManifestConstraints.java -eq '>=21') 'Fabric Java constraint read'
Assert ($plan.Data.environment -eq 'client_only') 'Physical client manifest maps to client-only release'
Assert ($cf.Data.gameVersionNames -contains 'Client' -and $cf.Data.gameVersionNames -notcontains 'Server') 'Client-only CurseForge side tags'
Assert-Throws { Get-ModRuntime @{ Runtime = @{ Environment = 'client_and_server' } } $rItem } 'conflicts with a client-only'
$rOlderGame = Read-ModJar $rItem.Path
$rOlderGame.Minecraft = '1.20.1'
Assert-Throws { Get-ModRuntime @{} $rOlderGame } 'bytecode minimum'
$rLowerTarget = Read-ModJar $rItem.Path
$rLowerTarget.RuntimeEvidence.BytecodeMinimumJava = 17
$rLowerTarget.Minecraft = '1.20.1'
Assert-Throws { Get-ModRuntime @{} $rLowerTarget } 'manifest Java requirement'
Assert ((Get-ModRuntime @{ Runtime = @{ JavaVersions = @('invalid-old-manual-value') } } $rItem).JavaVersions[0] -eq 25) 'Legacy per-mod Java setting cannot override the shared mapping'
Assert-Throws { Get-ModRuntime @{ Runtime = @{ JavaVersion = 21 } } $rItem } 'Unknown Runtime setting'
Assert ((Get-ModRuntime @{ Runtime = @{ MinecraftVersions = @('1.21.1') } } $rItem).MinecraftVersions[0] -eq '26.3') 'Minecraft version comes from the artifact rather than a previous setup answer'
$rBoth = Read-ModJar $rItem.Path
$rBoth.RuntimeEvidence.ManifestEnvironment = '*'
Assert-Throws { Get-ModRuntime @{} $rBoth } 'Set Runtime.Environment'
foreach ($rEnvironment in @('client_and_server', 'client_only', 'client_only_server_optional', 'singleplayer_only', 'server_only', 'server_only_client_optional', 'dedicated_server_only', 'client_or_server', 'client_or_server_prefers_both')) {
    $rRuntime = Get-ModRuntime @{ Runtime = @{ Environment = $rEnvironment; JavaVersions = @(21,25); MinecraftVersions = @('26.2','26.3') } } $rBoth
    Assert ($rRuntime.Environment -eq $rEnvironment -and $rRuntime.JavaVersions.Count -eq 1 -and $rRuntime.JavaVersions[0] -eq 25) "Supported environment $rEnvironment"
}
$rServer = Read-ModJar $rItem.Path
$rServer.RuntimeEvidence.ManifestEnvironment = 'server'
Assert ((Get-ModRuntime @{} $rServer).Environment -eq 'dedicated_server_only') 'Physical server restriction mapping'
$rPreview = Read-ModJar $rItem.Path
$rPreview.RuntimeEvidence.PreviewJavaVersions = @(21)
Assert-Throws { Get-ModRuntime @{} $rPreview } 'preview features'
Assert-Throws { Get-ModRuntime @{ Runtime = @{ AllowPreviewFeatures = $true } } $rPreview } 'matching Java major'
$rPreview.RuntimeEvidence.PreviewJavaVersions = @(25)
Assert ((Get-ModRuntime @{ Runtime = @{ AllowPreviewFeatures = $true } } $rPreview).JavaVersions[0] -eq 25) 'Preview features require the automatically selected Java runtime'
$rConfig = @{
    Runtime = @{ Environment = 'client_and_server'; AllowPreviewFeatures = $false }
    Modrinth = @{ Project = 'example'; Dependencies = @(@{ ProjectId = 'P7dR8mSH' }) }
    Overrides = @(
        @{ MaxVersion = '26.3'; Loaders = @('fabric'); Settings = @{ Runtime = @{ AllowPreviewFeatures = $true } } }
        @{ Versions = @('26.3'); ReleaseVersions = @('2.1.0'); Settings = @{ Runtime = @{ MinecraftVersions = @('26.2', '26.3') } } }
        @{ Loaders = @('forge'); Settings = @{ Runtime = @{ Environment = 'server_only' } } }
    )
}
$rEffective = Get-EffectiveModSettings $rConfig $rBoth
Assert ($rEffective.Runtime.AllowPreviewFeatures -and $rEffective.Runtime.Environment -eq 'client_and_server') 'Overrides merge runtime dictionaries'
Assert ($rEffective.Runtime.MinecraftVersions.Count -eq 2 -and $rEffective.Modrinth.Dependencies.Count -eq 1) 'Override filters preserve unrelated settings'
Assert (-not $rConfig.Runtime.AllowPreviewFeatures) 'Overrides do not mutate base configuration'
$rPath = Join-Path (Join-Path $w.ModsRoot 'omniwheel') 'mod.publish.psd1'
$rOriginal = [IO.File]::ReadAllText($rPath)
try {
    [IO.File]::WriteAllText($rPath, @'
@{
    Runtime = @{ Environment = 'client_only'; JavaVersions = @(21,25); MinecraftVersions = @('26.2','26.3') }
    Modrinth = @{ Project = 'example'; RequestedStatus = 'unlisted' }
    CurseForge = @{ Project = '123456'; GameVersionNames = @('Java 21'); GameVersions = @(12345) }
}
'@)
    $rMR = @(Get-UploadPlan $w @($rItem) 'Modrinth')[0]
    $rCF = @(Get-UploadPlan $w @($rItem) 'CurseForge')[0]
    Assert ($rMR.Data.game_versions.Count -eq 1 -and $rMR.Data.game_versions[0] -eq '26.3' -and $rMR.Data.requested_status -eq 'unlisted') 'Modrinth artifact-specific Minecraft metadata and requested status'
    Assert (-not $rMR.Data.Contains('java_versions')) 'No unsupported Java field on Modrinth'
    Assert ($rCF.Data.gameVersionNames -contains 'Java 25' -and $rCF.Data.gameVersionNames -notcontains 'Java 21') 'Automatic Java tags replace obsolete manual Java tags'
    Assert ($rCF.Data.gameVersions[0] -is [int] -and $rCF.Data.gameVersions[0] -eq 12345) 'CurseForge extra version IDs'
    [IO.File]::WriteAllText($rPath, @'
@{
    Runtime = @{ Environment = 'client_only'; MinecraftVersions = @('26.2','26.3') }
    Modrinth = @{ Project = 'example'; Dependencies = @(@{ ProjectId = 'P7dR8mSH'; Versions = @('26.3') }) }
}
'@)
    Assert (@(Get-UploadPlan $w @($rItem) 'Modrinth')[0].Data.dependencies.Count -eq 1) 'Dependencies resolve against the artifact Minecraft version'
} finally { [IO.File]::WriteAllText($rPath, $rOriginal) }
# Valid manifests for each loader with a baseline class and a higher multi-release alternative.
foreach ($rLoader in @('fabric', 'quilt', 'forge', 'neoforge')) {
    $rJarPath = Join-Path $w.IncomingRoot "runtimefixture-1.0.0-$rLoader-mc26.3.jar"
    $rZip = [IO.Compression.ZipFile]::Open($rJarPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $rManifest = @{ fabric = 'fabric.mod.json'; quilt = 'quilt.mod.json'; forge = 'META-INF/mods.toml'; neoforge = 'META-INF/neoforge.mods.toml' }[$rLoader]
        $rText = switch ($rLoader) {
            fabric { '{"version":"1.0.0","environment":"*"}' }
            quilt { '{"quilt_loader":{"version":"1.0.0","depends":[{"id":"java","versions":">=21"}]},"minecraft:environment":"client"}' }
            default { 'modLoader="javafml"' }
        }
        $rWriter = [IO.StreamWriter]::new($rZip.CreateEntry($rManifest).Open())
        try { $rWriter.Write($rText) } finally { $rWriter.Dispose() }
        foreach ($rClass in @(@('example/Mod.class', 65), @('META-INF/versions/25/example/Mod.class', 69))) {
            $rStream = $rZip.CreateEntry($rClass[0]).Open()
            try { $rStream.Write([byte[]]@(202,254,186,190,0,0,0,$rClass[1]), 0, 8) } finally { $rStream.Dispose() }
        }
    } finally { $rZip.Dispose() }
    try {
        $rParsed = Read-ModJar $rJarPath
        Assert ($rParsed.RuntimeEvidence.BytecodeMinimumJava -eq 21 -and $rParsed.RuntimeEvidence.MultiReleaseClassCount -eq 1) "$rLoader baseline bytecode detection ignores multi-release alternatives"
        if ($rLoader -eq 'quilt') { Assert ((Get-ModRuntime @{} $rParsed).Environment -eq 'client_only') 'Quilt root environment metadata' }
        else { Assert ((Get-ModRuntime @{ Runtime = @{ Environment = 'client_and_server' } } $rParsed).JavaVersions[0] -eq 25) "$rLoader uses shared automatic Java mapping" }
    } finally { Remove-Item -LiteralPath $rJarPath }
}
Write-Host 'All mod runtime tests passed.' -ForegroundColor Green
