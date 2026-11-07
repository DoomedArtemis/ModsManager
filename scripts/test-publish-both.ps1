function Test-DualPlatformPublishing($ParentWorkspace, $SourceItem) {
    $handler = [ModsTestHandler]::new()
    function New-PublishClient([string]$Platform, [string]$Token) { return [Net.Http.HttpClient]::new($handler, $false) }
    $root = Join-Path $ParentWorkspace.Root 'publish-both'
    $workspace = @{ Root = $root; IncomingRoot = (Join-Path $root 'incoming'); ModsRoot = (Join-Path $root 'mods') }
    foreach ($directory in @((Join-Path $root 'config'), $workspace.IncomingRoot, $workspace.ModsRoot)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $jarPath = Join-Path $workspace.IncomingRoot $SourceItem.FileName
    Copy-Item -LiteralPath $SourceItem.Path -Destination $jarPath
    $item = Read-ModJar $jarPath
    $batches = [ordered]@{
        Modrinth = @(Get-UploadPlan $workspace @($item) 'Modrinth' @{ omniwheel = 'omni-wheel' })
        CurseForge = @(Get-UploadPlan $workspace @($item) 'CurseForge' @{ omniwheel = '123456' })
    }
    try {
        Assert-Throws { Invoke-PlatformPublishBatches $workspace $batches @{ Modrinth = 'fake-mod-token' } } 'CurseForge token is required'
        Assert ($handler.PostCount -eq 0 -and (Test-Path -LiteralPath $jarPath)) 'Both tokens checked before the first upload or file move'
        $tokens = @{ Modrinth = 'fake-mod-token'; CurseForge = 'fake-cf-token' }
        $handler.FailPostHost = 'minecraft.curseforge.com'
        Assert-Throws { Invoke-PlatformPublishBatches $workspace $batches $tokens } 'Publishing incomplete for: CurseForge'
        $retainedPath = Get-PublishedModPath $workspace $item
        Assert (Test-Path -LiteralPath $retainedPath) 'First platform retained the JAR for the second platform after incoming cleanup'
        Assert (-not (Test-Path -LiteralPath $jarPath)) 'Successful upload organizes the incoming JAR once'
        Assert ($handler.PostCount -eq 2) 'Both platforms attempted within one command even when one failed'
        $state = Get-Content (Join-Path $root 'config/publish-state.local.json') -Raw | ConvertFrom-Json
        Assert (@($state).Count -eq 1 -and $state[0].Platform -eq 'Modrinth') 'Only successful platform receipt recorded after partial failure'
        $handler.FailPostHost = ''
        Invoke-PlatformPublishBatches $workspace $batches $tokens
        Assert ($handler.PostCount -eq 3) 'Retry skips completed platform and sends only the failed platform upload'
        Assert (@($handler.PostUrls | Where-Object { $_ -like 'https://api.modrinth.com/*' }).Count -eq 1) 'Modrinth receives no duplicate POST on retry'
        $state = Get-Content (Join-Path $root 'config/publish-state.local.json') -Raw | ConvertFrom-Json
        Assert (@($state).Count -eq 2) 'Both platform receipts persist after the successful retry'
        Invoke-PlatformPublishBatches $workspace $batches $tokens
        Assert ($handler.PostCount -eq 3) 'Repeating a fully published combined batch creates no additional uploads'
    } finally { $handler.Dispose() }
    Write-Host 'All combined platform publishing tests passed.' -ForegroundColor Green
}
Test-DualPlatformPublishing $w $items[0]
