function Test-ModrinthProjectResolution($SourceWorkspace, $SourceItem) {
    $handler = [ModsTestHandler]::new()
    $client = [Net.Http.HttpClient]::new($handler, $false)
    function New-ProjectPlan([string]$Reference) {
        return [pscustomobject]@{ Platform = 'Modrinth'; Project = $Reference; Data = @{ project_id = $Reference } }
    }
    try {
        $plans = @((New-ProjectPlan 'eightchr'), (New-ProjectPlan 'eightchr'), (New-ProjectPlan 'AbCd1234'))
        Resolve-ModrinthUploadProjects $client $plans
        Assert ($handler.GetUrls.Count -eq 1) 'Repeated project references resolved once per batch, including canonical aliases'
        Assert ($plans[0].Data.project_id -ceq 'AbCd1234') 'Eight-character alphanumeric slug is looked up instead of assumed to be an ID'
        $handler.LookupStatus = 404
        Assert-Throws { Resolve-ModrinthUploadProjects $client @((New-ProjectPlan 'missing-project')) } 'Cannot resolve.*HTTP 404'
        $handler.LookupStatus = 200
        $handler.LookupBody = '{"id":"bad-id","project_type":"mod"}'
        Assert-Throws { Resolve-ModrinthUploadProjects $client @((New-ProjectPlan 'bad-response')) } 'invalid internal project ID'
        $handler.LookupBody = '{"id":"AbCd1234","project_type":"resourcepack"}'
        Assert-Throws { Resolve-ModrinthUploadProjects $client @((New-ProjectPlan 'wrong-type')) } 'not a mod project'
        Assert ($handler.PostCount -eq 0) 'Failed project resolution never sends uploads'
    } finally { $client.Dispose() }
    # Real publication orchestration and multipart content, in-memory HTTP only.
    $handler = [ModsTestHandler]::new()
    function New-PublishClient([string]$Platform, [string]$Token) { return [Net.Http.HttpClient]::new($handler, $false) }
    $fixtureRoot = Join-Path $SourceWorkspace.Root 'modrinth-project-resolution'
    $workspace = @{ Root = $fixtureRoot; IncomingRoot = (Join-Path $fixtureRoot 'incoming'); ModsRoot = (Join-Path $fixtureRoot 'mods') }
    foreach ($directory in @((Join-Path $fixtureRoot 'config'), $workspace.IncomingRoot, $workspace.ModsRoot)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $jarPath = Join-Path $workspace.IncomingRoot $SourceItem.FileName
    Copy-Item -LiteralPath $SourceItem.Path -Destination $jarPath
    try {
        $item = Read-ModJar $jarPath
        $plans = @(Get-UploadPlan $workspace @($item) 'Modrinth' @{ omniwheel = 'omni-wheel' })
        $badPlan = @(Get-UploadPlan $workspace @($item) 'Modrinth' @{ omniwheel = 'missing-project' })[0]
        $handler.MissingProject = 'missing-project'
        Assert-Throws { Invoke-PublishPlans $workspace @($plans[0], $badPlan) 'offline-test' } 'Cannot resolve.*HTTP 404'
        Assert ($handler.PostCount -eq 0 -and (Test-Path -LiteralPath $jarPath)) 'All target projects resolved before the first upload or file move'
        $plans = @(Get-UploadPlan $workspace @($item) 'Modrinth' @{ omniwheel = 'https://modrinth.com/mod/omni-wheel' })
        Invoke-PublishPlans $workspace $plans 'offline-test'
        Assert ($handler.PostCount -eq 1 -and $handler.Body -match '"project_id":"AbCd1234"') 'Full publishing workflow resolves a project URL before multipart upload'
        $records = @(Get-Content (Join-Path $fixtureRoot 'config/publish-state.local.json') -Raw | ConvertFrom-Json)
        Assert ($records[0].Project -ceq 'AbCd1234') 'Publishing receipts use canonical Modrinth project IDs'
        $repeatPlans = @(Get-UploadPlan $workspace @(Get-ModItems $workspace) 'Modrinth' @{ omniwheel = 'AbCd1234' })
        Invoke-PublishPlans $workspace $repeatPlans 'offline-test'
        Assert ($handler.PostCount -eq 1) 'Switching between a project slug and its ID does not upload a duplicate'
    } finally { $handler.Dispose() }
    Write-Host 'All Modrinth project resolution tests passed.' -ForegroundColor Green
}
Test-ModrinthProjectResolution $w $items[0]
