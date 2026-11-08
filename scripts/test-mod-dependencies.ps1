# Real ZIPs, manifest parsing, guided setup and multipart bodies; no network.
function Test-AutomaticDependencyPublishing($ParentWorkspace) {
    . (Join-Path $PSScriptRoot 'publish-setup.ps1')
    $root = Join-Path $ParentWorkspace.Root 'auto-dependencies'
    $workspace = @{ Root = $root; IncomingRoot = (Join-Path $root 'incoming'); ModsRoot = (Join-Path $root 'mods') }
    New-Item -ItemType Directory -Path $workspace.IncomingRoot -Force | Out-Null
    function New-DependencyJar([string]$FileName, [string]$Text, [string]$Manifest = 'fabric.mod.json', [string]$NestedPath = '') {
        $path = Join-Path $workspace.IncomingRoot $FileName
        $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $writer = [IO.StreamWriter]::new($zip.CreateEntry($Manifest).Open())
            try { $writer.Write($Text) } finally { $writer.Dispose() }
            if ($NestedPath) {
                $stream = $zip.CreateEntry('META-INF/jars/bundled.jar').Open()
                $source = [IO.File]::OpenRead($NestedPath)
                try { $source.CopyTo($stream) } finally { $source.Dispose(); $stream.Dispose() }
            }
        } finally { $zip.Dispose() }
        return Read-ModJar $path
    }
    $first = New-DependencyJar 'dependencyfixture-1.0-fabric-mc26.1.x.jar' '{"id":"dependencyfixture","name":"Dependency Fixture","version":"1.0","environment":"*","depends":{"fabricloader":">=0.19","minecraft":">=26.1 <26.2","java":">=25","fabric-api":">=0.145.0","fusion":">=1.3.5"},"suggests":{"modmenu":">=18.0.2","jei":"*"}}'
    $second = New-DependencyJar 'dependencyfixture-1.0-fabric-mc1.21.1.jar' '{"id":"dependencyfixture","name":"Dependency Fixture","version":"1.0","environment":"*","depends":{"minecraft":"1.21.1","fusion":">=1.2.12"},"recommends":{"modmenu":">=11.0.4"}}'
    $answers = [Collections.Generic.Queue[string]]::new()
    foreach ($answer in @('example-project', '', 'client_and_server', '', 'no')) { $answers.Enqueue($answer) }
    function Read-Host([string]$Prompt) {
        if (-not $answers.Count) { throw "Unexpected automatic dependency prompt: $Prompt" }
        return $answers.Dequeue()
    }
    Invoke-ModPublishSetup $workspace @($first, $second) Modrinth @{}
    Assert ($answers.Count -eq 0) 'New mod defaults to automatic dependencies without entering project IDs for libraries'
    $mr = @(Get-UploadPlan $workspace @($first, $second) Modrinth)
    $cf = @(Get-UploadPlan $workspace @($first, $second) CurseForge @{ dependencyfixture = '123456' })
    Assert ($mr[0].Data.dependencies.Count -eq 4 -and $mr[1].Data.dependencies.Count -eq 2) 'Shared setup retains a different dependency list for every binary'
    Assert (@($mr[0].Data.dependencies | Where-Object dependency_type -eq 'required').Count -eq 2 -and @($mr[0].Data.dependencies | Where-Object dependency_type -eq 'optional').Count -eq 2) 'Fabric required and suggested dependencies retain their relations'
    Assert ($cf[0].Data.relations.projects.Count -eq 4 -and $cf[1].Data.relations.projects.Count -eq 2) 'CurseForge automatic dependency lists also remain artifact-specific'
    Assert (@($cf[0].Data.relations.projects | Where-Object { $_.slug -eq 'fusion-connected-textures' -and $_.projectID -eq 854949 -and $_.type -eq 'requiredDependency' }).Count -eq 1) 'Manifest mod ID fusion maps to the verified hosting project rather than a guessed slug'
    $scan = @(Get-DependencyScan $first Modrinth)
    Assert (@($scan | Where-Object Status -eq 'ignored').Count -eq 3) 'Minecraft, Java and the loader are runtime declarations, not uploaded mod relations'
    Assert (@($scan | Where-Object ModId -eq 'fusion')[0].Constraint -ceq '>=1.3.5') 'Original mod-version requirement is preserved in the scan'
    Assert (@($mr[0].Data.dependencies | Where-Object { $_.Contains('version_id') }).Count -eq 0) 'Manifest lower bounds never become invented or incompatible pinned version IDs'
    $handler = [ModsTestHandler]::new()
    $client = [Net.Http.HttpClient]::new($handler)
    try {
        Resolve-ModrinthUploadProjects $client $mr
        $null = Send-ModUpload $client $mr[0]
        Assert ($handler.Body -match '"project_id":"p19vrgc2"' -and $handler.Body -match '"dependency_type":"optional"') 'Modrinth multipart includes automatic required and optional relations'
        $null = Send-ModUpload $client $cf[0]
        Assert ($handler.Body -match '"slug":"fusion-connected-textures"' -and $handler.Body -match '"type":"requiredDependency"') 'CurseForge multipart includes automatic relations'
    } finally { $client.Dispose() }
    foreach ($loader in @('forge', 'neoforge')) {
        $manifest = if ($loader -eq 'forge') { 'META-INF/mods.toml' } else { 'META-INF/neoforge.mods.toml' }
        $required = if ($loader -eq 'forge') { 'mandatory=true' } else { 'type="required"' }
        $optional = if ($loader -eq 'forge') { 'mandatory=false' } else { 'type="optional"' }
        $text = "[[mods]]`nmodId=`"dependencyfixture`"`nversion=`"1.0`"`n[[dependencies.dependencyfixture]]`nmodId=`"fusion`"`n$required`nversionRange=`"[1.3.5,)`"`n[[dependencies.dependencyfixture]]`nmodId=`"jei`"`n$optional`nversionRange=`"*`""
        $item = New-DependencyJar "dependencyfixture-1.0-$loader-mc26.1.x.jar" $text $manifest
        $deps = @(Get-Dependencies @{ DependencyMode = 'auto' } $item Modrinth)
        Assert ($deps.Count -eq 2 -and @($deps | Where-Object dependency_type -eq 'required').Count -eq 1) "$loader manifest dependency relations detected"
    }
    $quilt = New-DependencyJar 'dependencyfixture-1.0-quilt-mc26.1.x.jar' '{"quilt_loader":{"id":"dependencyfixture","version":"1.0","depends":[{"id":"quilt_loader","versions":">=0.20"},{"id":"fusion","versions":">=1.3.5"},{"id":"modmenu","versions":"*","optional":true}]}}' 'quilt.mod.json'
    Assert (@(Get-Dependencies @{ DependencyMode = 'auto' } $quilt CurseForge).Count -eq 2) 'Quilt required and optional entries detected with loader excluded'
    $unknown = New-DependencyJar 'unknownfixture-1.0-fabric-mc26.3.jar' '{"id":"unknownfixture","version":"1.0","depends":{"unmapped-library":"*"}}'
    Assert (@(Get-DependencyScan $unknown Modrinth)[0].Status -eq 'unmapped') 'Unfamiliar mod IDs are reported rather than guessed'
    Assert-Throws { Get-Dependencies @{ DependencyMode = 'auto' } $unknown Modrinth } 'Automatic dependencies:.*unmapped'
    Assert (@(Get-Dependencies @{ DependencyMode = 'manual' } $unknown Modrinth).Count -eq 0) 'Explicit manual or none mode remains available'
    $conditional = New-DependencyJar 'conditionalfixture-1.0-fabric-mc26.3.jar' '{"id":"conditionalfixture","version":"1.0","breaks":{"jei":"<1.0"}}'
    Assert-Throws { Get-Dependencies @{ DependencyMode = 'auto' } $conditional Modrinth } 'needs review'
    $conflicts = New-DependencyJar 'conflictfixture-1.0-fabric-mc26.3.jar' '{"id":"conflictfixture","version":"1.0","conflicts":{"jei":"*"}}'
    Assert-Throws { Get-Dependencies @{ DependencyMode = 'auto' } $conflicts Modrinth } 'needs review'
    $duplicate = New-DependencyJar 'duplicatefixture-1.0-fabric-mc26.3.jar' '{"id":"duplicatefixture","version":"1.0","depends":{"fusion":"*"},"suggests":{"fusion":"*"}}'
    $deps = @(Get-Dependencies @{ DependencyMode = 'auto' } $duplicate Modrinth)
    Assert ($deps.Count -eq 1 -and $deps[0].dependency_type -eq 'required') 'A required relation takes precedence over duplicate suggestions'
    $nested = New-DependencyJar 'bundledlib-1.0-fabric-mc26.3.jar' '{"id":"bundledlib","version":"1.0"}'
    $outer = New-DependencyJar 'bundlefixture-1.0-fabric-mc26.3.jar' '{"id":"bundlefixture","version":"1.0","depends":{"bundledlib":"*"},"jars":[{"file":"META-INF/jars/bundled.jar"}]}' 'fabric.mod.json' $nested.Path
    Assert (@(Get-DependencyScan $outer Modrinth)[0].Ignored -eq 'bundled inside this JAR') 'Nested library identity read from its real manifest'
    Assert (@(Get-Dependencies @{ DependencyMode = 'auto' } $outer Modrinth).Count -eq 0) 'Bundled libraries are not incorrectly required as separate downloads'
    $settings = @{ DependencyMode = 'auto'; Dependencies = @() }
    $answers.Enqueue('none')
    $result = Read-SetupDependencies $settings $first Modrinth
    Assert ($settings.DependencyMode -eq 'manual' -and $result.Count -eq 0) 'Wizard none choice disables automatic dependencies explicitly'
    $answers.Enqueue('auto')
    $null = Read-SetupDependencies $settings $first Modrinth
    Assert ($settings.DependencyMode -eq 'auto') 'Wizard can enable automatic scanning for an existing configuration'
    Write-Host 'All automatic per-JAR dependency tests passed.' -ForegroundColor Green
}
Test-AutomaticDependencyPublishing $w
