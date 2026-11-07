# Called from the integration suite; use separate filenames and preserve its fixtures.
$layoutCases = @(
    @{ File = 'omniwheel-2.0.1-fabric-mc26.3.jar'; Manifest = 'fabric.mod.json'; Release = '2.0.1'; Loader = 'fabric' }
    @{ File = 'omniwheel-2.0.1-neoforge-mc26.3.jar'; Manifest = 'META-INF/neoforge.mods.toml'; Release = '2.0.1'; Loader = 'neoforge' }
    @{ File = 'omniwheel-2.0.2-fabric-mc26.3.jar'; Manifest = 'fabric.mod.json'; Release = '2.0.2'; Loader = 'fabric' }
)
$layoutPaths = @()
try {
    foreach ($case in $layoutCases) {
        $layoutIncoming = Join-Path $w.IncomingRoot $case.File
        New-TestJar $layoutIncoming $case.Manifest $case.Release
        $layoutItem = Read-ModJar $layoutIncoming
        $expectedPath = Join-Path $w.ModsRoot "omniwheel/$($case.Loader)/$($case.Release)/$($case.File)"
        $layoutPaths += $expectedPath
        Complete-ModPublish $w $layoutItem
        Assert ($layoutItem.Path -eq $expectedPath -and (Test-Path -LiteralPath $expectedPath)) 'Loader and mod release get independent directories'
        Assert (-not (Test-Path -LiteralPath $layoutIncoming)) 'Direct incoming source moved after publish completion'
        Complete-ModPublish $w $layoutItem
        Assert (Test-Path -LiteralPath $expectedPath) 'Repeated completion preserves retained release'
    }
    $layoutCase = $layoutCases[0]
    $layoutIncoming = Join-Path $w.IncomingRoot $layoutCase.File
    New-TestJar $layoutIncoming $layoutCase.Manifest $layoutCase.Release 'different'
    $changedItem = Read-ModJar $layoutIncoming
    Assert-Throws { Assert-PublishedModDestination $w $changedItem } 'refusing to overwrite'
    $layoutUploadCount = $script:UploadCount
    Assert-Throws { Invoke-PublishPlans $w @([pscustomobject]@{ Item = $changedItem }) 'offline-test' } 'refusing to overwrite'
    Assert ($script:UploadCount -eq $layoutUploadCount) 'Destination conflict detected before uploading'
    Assert (Test-Path -LiteralPath $layoutIncoming) 'Destination conflict preserves incoming source'
    # An incoming file replaced after the upload plan was built is not removed.
    $retainedItem = Read-ModJar $layoutPaths[0]
    Complete-ModPublish $w $retainedItem
    Assert (Test-Path -LiteralPath $layoutIncoming) 'Changed incoming file preserved when completing an older published release'
    Remove-Item -LiteralPath $layoutIncoming
} finally {
    foreach ($layoutPath in $layoutPaths) {
        if (Test-Path -LiteralPath $layoutPath) { Remove-Item -LiteralPath $layoutPath }
    }
}
Write-Host 'All published layout tests passed.' -ForegroundColor Green
