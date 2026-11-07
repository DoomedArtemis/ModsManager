[CmdletBinding()]
param(
    [string]$OutputPath,
    [ValidateRange(1, 32)][int]$Concurrency = 16
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $OutputPath) { $OutputPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config/minecraft-java.json' }
Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::DefaultConnectionLimit = 32
$manifestUrl = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'
$client = [Net.Http.HttpClient]::new()
$client.Timeout = [TimeSpan]::FromSeconds(90)
$client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', 'DoomedArtemis/ModsManager Java metadata sync') | Out-Null
try {
    $manifest = $client.GetStringAsync($manifestUrl).GetAwaiter().GetResult() | ConvertFrom-Json
    $entries = @($manifest.versions)
    $versions = [ordered]@{}
    $missingJavaCount = 0
    for ($offset = 0; $offset -lt $entries.Count; $offset += $Concurrency) {
        $batch = @()
        for ($i = $offset; $i -lt [Math]::Min($offset + $Concurrency, $entries.Count); $i++) {
            $entry = $entries[$i]
            if ($entry.url -notmatch '^https://piston-meta\.mojang\.com/') { throw "Unexpected metadata host for $($entry.id)." }
            $batch += @{ Entry = $entry; Task = $client.GetByteArrayAsync([string]$entry.url) }
        }
        foreach ($request in $batch) {
            $entry = $request.Entry
            $bytes = $request.Task.GetAwaiter().GetResult()
            $sha1 = [Security.Cryptography.SHA1]::Create()
            try { $hash = [BitConverter]::ToString($sha1.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() } finally { $sha1.Dispose() }
            if ($hash -ne $entry.sha1) { throw "Metadata checksum mismatch for $($entry.id)." }
            $metadata = [Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
            if ($metadata.id -cne $entry.id) { throw "Metadata ID mismatch for $($entry.id)." }
            $javaMajor = $null
            $component = $null
            $resolution = 'mojang-javaVersion'
            $fallbackUrl = $null
            $fallbackHash = $null
            if ($metadata.PSObject.Properties['javaVersion']) {
                $javaMajor = [int]$metadata.javaVersion.majorVersion
                $component = [string]$metadata.javaVersion.component
                if ($javaMajor -le 0) { throw "Invalid official Java metadata for $($entry.id)." }
            } else {
                # Some 2013 entries lack javaVersion. Use the launcher-maintained
                # compatibility data only when it declares exactly one major.
                $fallbackUrl = 'https://meta.prismlauncher.org/v1/net.minecraft/' + [Uri]::EscapeDataString([string]$entry.id) + '.json'
                $fallbackBytes = $client.GetByteArrayAsync($fallbackUrl).GetAwaiter().GetResult()
                $fallback = [Text.Encoding]::UTF8.GetString($fallbackBytes) | ConvertFrom-Json
                $majors = @($fallback.compatibleJavaMajors)
                if ($fallback.version -cne $entry.id -or $majors.Count -ne 1 -or [int]$majors[0] -le 0) { throw "No unambiguous launcher Java metadata for $($entry.id)." }
                $javaMajor = [int]$majors[0]
                $resolution = 'prism-compatibleJavaMajors'
                $sha256 = [Security.Cryptography.SHA256]::Create()
                try { $fallbackHash = [BitConverter]::ToString($sha256.ComputeHash($fallbackBytes)).Replace('-', '').ToLowerInvariant() } finally { $sha256.Dispose() }
                $missingJavaCount++
            }
            $versions[[string]$entry.id] = [ordered]@{
                JavaMajor = $javaMajor
                Component = $component
                Type = [string]$entry.type
                MetadataUrl = [string]$entry.url
                MetadataSha1 = $hash
                Resolution = $resolution
                FallbackMetadataUrl = $fallbackUrl
                FallbackMetadataSha256 = $fallbackHash
            }
        }
        if ($versions.Count % 128 -eq 0 -or $versions.Count -eq $entries.Count) { Write-Host "Read $($versions.Count)/$($entries.Count) Minecraft metadata documents." }
    }
    $data = [ordered]@{
        SchemaVersion = 1
        Source = $manifestUrl
        UpdatedAtUtc = [DateTime]::UtcNow.ToString('o')
        Versions = $versions
    }
    # Only replace the shared mapping after every metadata document validates.
    $temporary = $OutputPath + '.tmp'
    [IO.File]::WriteAllText($temporary, ($data | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $OutputPath -Force
    Write-Host "Saved $($versions.Count) exact Minecraft-to-Java mappings to $OutputPath"
    if ($missingJavaCount) { Write-Host "$missingJavaCount legacy entries without Mojang's Java field use explicit Prism Launcher compatibility metadata; provenance is saved per entry." }
} finally { $client.Dispose() }
