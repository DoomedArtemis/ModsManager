# Shared mapping tests are offline; sync itself verifies each Mojang metadata hash.
$javaCases = @{
    '1.0' = 8; '1.6.4' = 8; '1.12.2' = 8; '1.16.5' = 8
    '1.17' = 16; '1.17.1' = 16
    '1.18' = 17; '1.20.1' = 17; '1.20.4' = 17
    '1.20.5' = 21; '1.21.1' = 21; '1.21.11' = 21
    '26.1' = 25; '26.2' = 25; '26.3' = 25
}
foreach ($javaCase in $javaCases.GetEnumerator()) {
    Assert ((Get-MinecraftJavaRequirement $javaCase.Key).JavaMajor -eq $javaCase.Value) "Minecraft $($javaCase.Key) automatically selects Java $($javaCase.Value)"
}
$mapping = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'config/minecraft-java.json') -Raw | ConvertFrom-Json
foreach ($entry in $mapping.Versions.PSObject.Properties) {
    Assert ([int]$entry.Value.JavaMajor -gt 0 -and $entry.Value.MetadataSha1 -match '^[0-9a-f]{40}$') "Shared runtime mapping and metadata checksum for $($entry.Name)"
    if ($entry.Value.Resolution -eq 'prism-compatibleJavaMajors') {
        Assert ($entry.Value.FallbackMetadataUrl -like 'https://meta.prismlauncher.org/*' -and $entry.Value.FallbackMetadataSha256 -match '^[0-9a-f]{64}$') 'Legacy fallback preserves source and checksum'
    }
}
Assert-Throws { Get-MinecraftJavaRequirement '99.99.99' } 'Automatic Java:.*not in the shared mapping'
$mixedRuntime = Get-ModRuntime @{ Runtime = @{ MinecraftVersions = @('1.21.1', '26.3') } } $items[0]
Assert ($mixedRuntime.JavaVersions.Count -eq 1 -and $mixedRuntime.JavaVersions[0] -eq 25 -and $mixedRuntime.MinecraftVersions[0] -eq '26.3') 'Stale multi-version settings cannot change the compiled artifact target or Java tags'
$tooNew = Read-ModJar $items[0].Path
$tooNew.RuntimeEvidence.BytecodeMinimumJava = 26
Assert-Throws { Get-ModRuntime @{} $tooNew } 'Automatic Java:.*Recompile'
Write-Host 'All shared Minecraft Java mapping tests passed.' -ForegroundColor Green
