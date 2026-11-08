# Offline integration tests. No credentials or public uploads.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'mod-manager.ps1')
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    $caught = $false
    try { & $Action } catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $caught = $true
    }
    Assert $caught "Expected error matching $Pattern"
}
function New-TestJar([string]$Path, [string]$Manifest = 'fabric.mod.json', [string]$Version = '2.1.0', [string]$Extra = '') {
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $writer = [IO.StreamWriter]::new($zip.CreateEntry($Manifest).Open())
        try { $writer.Write('{"schemaVersion":1,"id":"omniwheel","environment":"client","depends":{"java":">=21","fabricloader":">=0.16"},"version":"' + $Version + '","custom":"' + $Extra + '"}') } finally { $writer.Dispose() }
        $stream = $zip.CreateEntry('example/Mod.class').Open()
        try { $stream.Write([byte[]]@(202,254,186,190,0,0,0,65), 0, 8) } finally { $stream.Dispose() }
    } finally { $zip.Dispose() }
}
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('mods-manager-test-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path (Join-Path $tempRoot 'config') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'config/mods.psd1') -Destination (Join-Path $tempRoot 'config/mods.psd1')
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'config/minecraft-java.json') -Destination (Join-Path $tempRoot 'config/minecraft-java.json')
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'config/dependency-projects.psd1') -Destination (Join-Path $tempRoot 'config/dependency-projects.psd1')
    $w = Get-Workspace $tempRoot
    New-Item -ItemType Directory -Path $w.IncomingRoot -Force | Out-Null
    $jar = Join-Path $w.IncomingRoot 'omniwheel-2.1.0-fabric-mc26.3.jar'
    New-TestJar $jar
    $parsed = Read-ModJar $jar
    Assert ($parsed.Mod -eq 'omniwheel' -and $parsed.Release -eq '2.1.0' -and $parsed.Minecraft -eq '26.3') 'Example filename parsing'
    $items = @(Get-ModItems $w)
    Assert ($items.Count -eq 1 -and $items[0].Path -eq $jar) 'Release discovered directly in incoming'
    $sourcesJar = Join-Path $w.IncomingRoot 'omniwheel-2.1.0-forge-mc26.3-sources.jar'
    [IO.File]::WriteAllText($sourcesJar, 'not a release jar')
    Assert (@(Get-ModItems $w).Count -eq 1) 'Sources JAR ignored without an import step'
    Remove-Item -LiteralPath $sourcesJar
    Assert (Test-Path -LiteralPath $jar) 'Original JAR retained'
    Assert (@(Get-ModItems $w -Version @('26.2..26.3')).Count -eq 1) 'Inclusive range'
    Assert (@(Get-ModItems $w -Loader @('forge')).Count -eq 0) 'Loader selection'
    Assert ((Compare-GameVersion '1.21.11' '1.21.9') -gt 0) 'Numeric ordering'
    Assert-Throws { Test-GameSelection '26.3' @('26.3..26.2') } 'Reversed range'
    Assert-Throws { @(Get-UploadPlan $w $items 'Modrinth') } 'Set Modrinth.Project'
    Assert (Test-Path -LiteralPath (Join-Path $w.ModsRoot 'omniwheel/mod.publish.psd1')) 'Publishing automatically creates missing mod settings'
    $plan = @(Get-UploadPlan $w $items 'Modrinth' @{ omniwheel = 'https://modrinth.com/mod/omniwheel' })[0]
    Assert ($plan.Data.project_id -eq 'omniwheel') 'Project URL normalization'
    Assert ($plan.Data.version_number -eq '2.1.0-fabric-mc26.3') 'Loader-specific version number'
    Assert ($plan.Data.name -eq 'omniwheel 2.1.0') 'Version subtitle contains only display name and mod release'
    Assert ($plan.Data.loaders[0] -eq 'fabric' -and $plan.Data.game_versions[0] -eq '26.3') 'Modrinth compatibility metadata'
    Assert ($plan.Data.dependencies.Count -eq 0) 'Empty dependency array'
    $cf = @(Get-UploadPlan $w $items 'CurseForge' @{ omniwheel = '123456' } '' $true)[0]
    Assert ($cf.Data.gameVersionNames -contains 'Fabric') 'CurseForge loader tag'
    Assert ($cf.Data.gameVersionNames -contains '26.3') 'CurseForge game tag'
    Assert ($cf.Data.changelog -eq '') 'Explicit empty changelog'
    Assert ($cf.Data.displayName -eq 'omniwheel-2.1.0-fabric-mc26.3') 'CurseForge display name uses the artifact filename without its extension'
    Assert (-not $cf.Data.Contains('relations')) 'CurseForge omits optional relations when dependencies are empty'
    . (Join-Path $PSScriptRoot 'test-minecraft-java.ps1')
    . (Join-Path $PSScriptRoot 'test-mod-runtime.ps1')
    . (Join-Path $PSScriptRoot 'test-mod-changelog.ps1')
    . (Join-Path $PSScriptRoot 'test-add-changelog.ps1')
    . (Join-Path $PSScriptRoot 'test-remove-changelog.ps1')
    . (Join-Path $PSScriptRoot 'test-publish-setup.ps1')
    . (Join-Path $PSScriptRoot 'test-shared-environment.ps1')
    $settings = @{ Dependencies = @(
        @{ ProjectId = 'P7dR8mSH'; Type = 'required'; Loaders = @('fabric'); Versions = @('26.3') }
        @{ ProjectId = 'P7dR8mSH'; Type = 'required'; MinVersion = '26.2' }
        @{ ProjectId = 'Abcd1234'; Type = 'optional'; ExcludeVersions = @('26.3') }
        @{ ProjectId = 'Abcd5678'; Type = 'optional'; Loaders = @('forge') }
    ) }
    $deps = @(Get-Dependencies $settings $items[0] 'Modrinth')
    Assert ($deps.Count -eq 1 -and $deps[0].dependency_type -eq 'required') 'Dependency filters and deduplication'
    $settings.Dependencies += @{ ProjectId = 'P7dR8mSH'; Type = 'optional' }
    Assert-Throws { Get-Dependencies $settings $items[0] 'Modrinth' } 'Conflicting dependency'
    Assert-Throws { Get-Dependencies @{ Dependencies = @(@{ ProjectId = '123'; Type = 'required' }) } $items[0] 'Modrinth' } '8-character ID'
    $deps = @(Get-Dependencies @{ Dependencies = @(@{ Slug = 'fabric-api'; ProjectId = '306612'; Type = 'requiredDependency' }) } $items[0] 'CurseForge')
    Assert ($deps[0].projectID -is [int] -and $deps[0].type -eq 'requiredDependency') 'CurseForge relations'
    # Exercise the real multipart builder against an in-memory HTTP handler.
    Add-Type -TypeDefinition @'
using System;
using System.Net;
using System.Net.Http;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
public class ModsTestHandler : HttpMessageHandler {
    public string Body;
    public string Url;
    public bool Fail;
    public int PostCount;
    public int LookupStatus = 200;
    public string LookupBody = "{\"id\":\"AbCd1234\",\"project_type\":\"mod\"}";
    public string MissingProject = "";
    public string VersionBody = "[]";
    public string FailPostHost = "";
    public List<string> GetUrls = new List<string>();
    public List<string> PostBodies = new List<string>();
    public List<string> PostUrls = new List<string>();
    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
        Url = request.RequestUri.ToString();
        if (request.Method == HttpMethod.Get) {
            GetUrls.Add(Url);
            if (MissingProject.Length > 0 && Url.EndsWith("/project/" + MissingProject)) {
                return new HttpResponseMessage(HttpStatusCode.NotFound) { Content = new StringContent("{}") };
            }
            return new HttpResponseMessage((HttpStatusCode)LookupStatus) {
                Content = new StringContent(Url.EndsWith("/version") ? VersionBody : LookupBody)
            };
        }
        PostCount++;
        PostUrls.Add(Url);
        Body = await request.Content.ReadAsStringAsync();
        PostBodies.Add(Body);
        bool failUpload = Fail || (FailPostHost.Length > 0 && request.RequestUri.Host == FailPostHost);
        return new HttpResponseMessage(failUpload ? HttpStatusCode.BadRequest : HttpStatusCode.OK) {
            Content = new StringContent(failUpload ? "invalid upload" : "{\"id\":\"test-id\"}")
        };
    }
}
'@ -ReferencedAssemblies 'System.Net.Http'
    $handler = [ModsTestHandler]::new()
    $http = [Net.Http.HttpClient]::new($handler)
    try {
        $rMR.Project = 'omni-wheel'
        $rMR.Data.project_id = 'omni-wheel'
        Assert-Throws { Send-ModUpload $http $rMR } 'requires a resolved internal project ID'
        Assert ($handler.PostCount -eq 0) 'Unresolved slug rejected before sending an upload'
        Resolve-ModrinthUploadProjects $http @($rMR)
        Assert ($rMR.Project -ceq 'AbCd1234' -and $rMR.Data.project_id -ceq 'AbCd1234') 'Hyphenated slug resolved to canonical base62 project ID'
        Assert ($handler.GetUrls[0] -eq 'https://api.modrinth.com/v2/project/omni-wheel') 'Slug lookup uses Get Project endpoint'
        $formattedNotes = "**Added:**`n- New Clipboard entry type.`n- Global/local chat toggle.`n`n**Changed:**`n- Unified highlight fade animations across editor controls."
        $rMR.Data.changelog = $formattedNotes
        $rCF.Data.changelog = $formattedNotes
        Assert ((Send-ModUpload $http $rMR) -eq 'test-id') 'Modrinth upload response'
        Assert ($handler.Url -eq 'https://api.modrinth.com/v2/version') 'Modrinth endpoint'
        Assert ($handler.Body -match 'name="?data"?' -and $handler.Body -match 'omniwheel-2.1.0-fabric-mc26.3.jar' -and $handler.Body -match 'application/java-archive') 'Modrinth multipart JSON and JAR'
        Assert ($handler.Body -match '"environment":"client_only"' -and $handler.Body -notmatch 'java_versions') 'Modrinth multipart includes environment without invented Java field'
        Assert ($handler.Body -match '"project_id":"AbCd1234"' -and $handler.Body -notmatch '"project_id":"omni-wheel"') 'Multipart project_id contains the resolved ID, never the slug'
        Assert ($handler.Body.Contains(($formattedNotes | ConvertTo-Json -Compress))) 'Modrinth multipart metadata preserves complete Markdown content'
        Assert ((Send-ModUpload $http $rCF) -eq 'test-id') 'CurseForge upload response'
        Assert ($handler.Url -eq 'https://minecraft.curseforge.com/api/projects/123456/upload-file' -and $handler.Body -match 'name="?metadata"?') 'CurseForge multipart endpoint and metadata'
        Assert ($handler.Body -match 'Java 25' -and $handler.Body -match 'Client') 'CurseForge multipart includes Java and side tags'
        Assert ($handler.Body.Contains(($formattedNotes | ConvertTo-Json -Compress)) -and $handler.Body -match '"changelogType":"markdown"') 'CurseForge multipart preserves Markdown and declares Markdown rendering'
        Assert ($handler.Body -notmatch '"relations"') 'CurseForge multipart never sends an empty relations.projects array'
        $dependencyConfig = @{ Runtime = @{ Environment = 'client_only' }; CurseForge = @{ Dependencies = @(@{ Slug = 'fabric-api'; ProjectId = '306612'; Type = 'requiredDependency' }) } }
        $cfWithDependencies = @(Get-UploadPlan $w @($items[0]) 'CurseForge' @{ omniwheel = '123456' } -SettingsOverrides @{ omniwheel = $dependencyConfig })[0]
        Assert ($cfWithDependencies.Data.relations.projects.Count -eq 1) 'Configured CurseForge dependencies retain the relations field'
        $null = Send-ModUpload $http $cfWithDependencies
        Assert ($handler.Body -match '"relations"' -and $handler.Body -match '"slug":"fabric-api"' -and $handler.Body -match '"projectID":306612' -and $handler.Body -match '"type":"requiredDependency"') 'Populated CurseForge relations serialize correctly in the upload request'
        $handler.Fail = $true
        Assert-Throws { Send-ModUpload $http $cf } 'HTTP 400'
    } finally { $http.Dispose() }
    . (Join-Path $PSScriptRoot 'test-modrinth-projects.ps1')
    . (Join-Path $PSScriptRoot 'test-publish-batch.ps1')
    . (Join-Path $PSScriptRoot 'test-publish-both.ps1')
    . (Join-Path $PSScriptRoot 'test-minecraft-ranges.ps1')
    . (Join-Path $PSScriptRoot 'test-mod-dependencies.ps1')
    . (Join-Path $PSScriptRoot 'test-release-types.ps1')
    # Check local settings protection in a real temporary git repository.
    & git -C $tempRoot init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize test git repository.' }
    Assert ((Read-LocalSettings $w 'Modrinth').Count -eq 0) 'Missing local settings accepted'
    $localPath = Join-Path $tempRoot 'config/modrinth.local.psd1'
    [IO.File]::WriteAllText($localPath, "@{ Projects = @{ omniwheel = 'private-slug' } }")
    Assert ((Read-LocalSettings $w 'Modrinth').Projects.omniwheel -eq 'private-slug') 'Local project settings loaded'
    $testScripts = Join-Path $tempRoot 'scripts'
    New-Item -ItemType Directory -Path $testScripts | Out-Null
    foreach ($scriptName in @('mod-manager.ps1', 'mod-runtime.ps1', 'jar-metadata.ps1', 'mod-changelog.ps1', 'mod-dependencies.ps1', 'publish-setup.ps1', 'publish-mods.ps1', 'scan-dependencies.ps1', 'changelog-setup.ps1', 'changelog-editor.ps1', 'add-changelog.ps1', 'remove-changelog.ps1')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $scriptName) -Destination (Join-Path $testScripts $scriptName)
    }
    Remove-Item -LiteralPath (Join-Path $w.ModsRoot 'omniwheel/mod.publish.psd1')
    $preview = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testScripts 'publish-mods.ps1') -Platform Modrinth -Mod omniwheel -Version 26.3 -Loader fabric -NonInteractive)
    Assert ($LASTEXITCODE -eq 0 -and ($preview -join "`n") -match 'Dry run complete') 'Command-line dry run works without token'
    Assert (($preview -join "`n") -match 'private-slug') 'Command-line applies local project overrides'
    $changelogPath = Join-Path $tempRoot 'notes with spaces.md'
    $fileMarkdown = "**Added:**`r`n- New Clipboard entry type.`r`n`r`n**Changed:**`r`n- Updated the default profile.`r`n"
    [IO.File]::WriteAllText($changelogPath, $fileMarkdown, [Text.UTF8Encoding]::new($false))
    $filePreview = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testScripts 'publish-mods.ps1') -Platform Modrinth -Mod omniwheel -NonInteractive -ChangelogFile $changelogPath)
    Assert ($LASTEXITCODE -eq 0 -and ($filePreview -join "`n").Contains(($fileMarkdown | ConvertTo-Json -Compress))) 'CLI Markdown file override preserves line breaks without prompting'
    $changelogAction = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testScripts 'add-changelog.ps1') -Mod omniwheel -ReleaseVersion '2.3.0' -ChangelogFile $changelogPath)
    Assert ($LASTEXITCODE -eq 0 -and ($changelogAction -join "`n") -match 'Saved omniwheel 2.3.0 changelog') 'Add Changelog command runs from its script entry point'
    Assert ((Read-ModReleaseChangelog $w 'omniwheel' '2.3.0') -ceq $fileMarkdown.Trim([char[]]"`r`n")) 'Add Changelog CLI saves the complete Markdown file under the requested release'
    $removeAction = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testScripts 'remove-changelog.ps1') -Mod omniwheel -ReleaseVersion '2.3.0' -Yes)
    Assert ($LASTEXITCODE -eq 0 -and ($removeAction -join "`n") -match 'Removed omniwheel 2.3.0 changelog section') 'Remove Changelog command runs from its script entry point'
    Assert-Throws { Read-ModReleaseChangelog $w 'omniwheel' '2.3.0' } 'Changelog: add a ## 2.3.0'
    $fixtureConfigPath = Join-Path $w.ModsRoot 'omniwheel/mod.publish.psd1'
    $originalFixtureConfig = [IO.File]::ReadAllText($fixtureConfigPath)
    try {
        [IO.File]::WriteAllText($fixtureConfigPath, "@{ Runtime = @{ Environment = 'client_only' }; Modrinth = @{ Project = 'private-slug' }; CurseForge = @{ Project = '123456' } }")
        $bothPreview = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $testScripts 'publish-mods.ps1') -Platform Both -Mod omniwheel -NonInteractive)
        Assert ($LASTEXITCODE -eq 0 -and @($bothPreview | Where-Object { $_ -match '^Modrinth / ' }).Count -eq 1 -and @($bothPreview | Where-Object { $_ -match '^CurseForge / ' }).Count -eq 1) 'One CLI command previews both platforms from the same JAR selection without tokens'
    } finally { [IO.File]::WriteAllText($fixtureConfigPath, $originalFixtureConfig) }
    Assert (Test-Path -LiteralPath (Join-Path $w.ModsRoot 'omniwheel/mod.publish.psd1')) 'First command-line preview generates settings automatically'
    Assert (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'config/publish-state.local.json'))) 'Dry run leaves no publish receipt'
    Assert (-not (Test-Path -LiteralPath (Join-Path (Join-Path $w.ModsRoot 'omniwheel') 'fabric'))) 'Dry run creates no published loader folders'
    Assert (Test-Path -LiteralPath $jar) 'Dry run leaves incoming JAR intact'
    . (Join-Path $PSScriptRoot 'test-local-publish-settings.ps1')
    & git -C $tempRoot add -f config/modrinth.local.psd1
    Assert-Throws { Read-LocalSettings $w 'Modrinth' } 'must not be tracked'
    $bad = Join-Path $w.IncomingRoot 'bad-2.1.0-forge-mc26.3.jar'
    New-TestJar $bad
    Assert-Throws { Read-ModJar $bad } 'missing META-INF/mods.toml'
    Remove-Item -LiteralPath $bad
    $bad = Join-Path $w.IncomingRoot 'bad-9.0.0-fabric-mc26.3.jar'
    New-TestJar $bad
    Assert-Throws { Read-ModJar $bad } 'differs from manifest'
    Remove-Item -LiteralPath $bad
    $bad = Join-Path $w.IncomingRoot 'bad.jar'
    [IO.File]::WriteAllText($bad, 'not a jar')
    Assert-Throws { Get-ModItems $w } 'Unrecognized JAR'
    Remove-Item -LiteralPath $bad
    # Mock the transport, retaining real planning, state and published storage.
    $script:UploadCount = 0
    function Send-ModUpload($Client, $Plan) { $script:UploadCount++; return '12345' }
    $cfPlans = @(Get-UploadPlan $w @(Get-ModItems $w) 'CurseForge' @{ omniwheel = '123456' })
    Invoke-PublishPlans $w $cfPlans 'offline-test'
    $publishedJar = Join-Path $w.ModsRoot 'omniwheel/fabric/2.1.0/omniwheel-2.1.0-fabric-mc26.3.jar'
    Assert (Test-Path -LiteralPath $publishedJar) 'Published release stored under mod/loader/mod-version'
    Assert (-not (Test-Path -LiteralPath $jar)) 'Matching incoming JAR removed after successful publishing'
    Assert ((Get-FileHash -LiteralPath $publishedJar -Algorithm SHA512).Hash.ToLowerInvariant() -eq $parsed.Hash) 'Stored published JAR is byte-identical'
    Copy-Item -LiteralPath $publishedJar -Destination $jar
    Invoke-PublishPlans $w $cfPlans 'offline-test'
    Assert ($script:UploadCount -eq 1) 'Successful publishing recorded and duplicate skipped'
    Assert (-not (Test-Path -LiteralPath $jar)) 'Already-published receipt also clears a matching re-added incoming copy'
    $state = @(Get-Content (Join-Path $tempRoot 'config/publish-state.local.json') -Raw | ConvertFrom-Json)
    Assert ($state.Count -eq 1 -and $state[0].Id -eq '12345') 'Persistent platform receipt'
    $secondPlatform = @(Get-UploadPlan $w @(Get-ModItems $w) 'Modrinth' @{ omniwheel = 'omniwheel' })
    Assert ($secondPlatform.Count -eq 1 -and $secondPlatform[0].Item.Path -eq $publishedJar) 'Second platform reuses the retained published JAR'
    . (Join-Path $PSScriptRoot 'test-publish-layout.ps1')
    # A failed upload must leave its incoming source intact and not record success.
    Copy-Item -LiteralPath $publishedJar -Destination $jar
    $incomingItem = Read-ModJar $jar
    function Send-ModUpload($Client, $Plan) { throw 'simulated upload failure' }
    $failPlans = @(Get-UploadPlan $w @($incomingItem) 'CurseForge' @{ omniwheel = '654321' })
    Assert-Throws { Invoke-PublishPlans $w $failPlans 'offline-test' } 'simulated upload failure'
    Assert (Test-Path -LiteralPath $jar) 'Failed upload leaves incoming JAR intact'
    Remove-Item -LiteralPath $jar
    New-TestJar $jar 'fabric.mod.json' '2.1.0' 'changed'
    Assert-Throws { Get-ModItems $w } 'Conflicting incoming/published'
    Assert-Throws { Copy-IdenticalOrNew $jar $publishedJar } 'refusing to overwrite'
    Assert (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'build'))) 'No build directory created'
    Assert (-not (Test-Path -LiteralPath (Join-Path $tempRoot 'archive'))) 'No archive directory created'
    Write-Host 'All mod manager tests passed.' -ForegroundColor Green
} finally {
    $resolved = [IO.Path]::GetFullPath($tempRoot)
    $expected = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolved.StartsWith($expected, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -like 'mods-manager-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
