[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Modrinth', 'CurseForge', 'Both')][string]$Platform,
    [string[]]$Mod = @('all'),
    [string[]]$Version = @('all'),
    [ValidateSet('all', 'fabric', 'quilt', 'forge', 'neoforge')][string[]]$Loader = @('all'),
    [string]$ReleaseVersion,
    [ValidateSet('auto', 'incoming', 'published', 'all')][string]$Source = 'auto',
    [switch]$PromptForMod,
    [switch]$PromptForVersion,
    [switch]$PromptForProject,
    [switch]$PromptForChangelog,
    [switch]$PromptForToken,
    [switch]$Configure,
    [switch]$NonInteractive,
    [AllowEmptyString()][string]$Changelog,
    [string]$ChangelogFile,
    [switch]$Publish
)
. (Join-Path $PSScriptRoot 'mod-manager.ps1')
. (Join-Path $PSScriptRoot 'publish-setup.ps1')
$workspace = Get-Workspace
# Validate local state even in previews. Dry runs never need a token or network.
$platforms = @($Platform)
if ($Platform -eq 'Both') { $platforms = @('Modrinth', 'CurseForge') }
$localSettings = @{}
foreach ($targetPlatform in $platforms) { $localSettings[$targetPlatform] = Read-LocalSettings $workspace $targetPlatform }
if ($PSBoundParameters.ContainsKey('Changelog') -and $PSBoundParameters.ContainsKey('ChangelogFile')) { throw 'Use either -Changelog or -ChangelogFile, not both.' }
$overrideChangelog = $PSBoundParameters.ContainsKey('Changelog') -or $PSBoundParameters.ContainsKey('ChangelogFile')
$changelogInput = @{}
if ($PSBoundParameters.ContainsKey('ChangelogFile')) { $Changelog = Read-ChangelogFile $ChangelogFile }
if ($overrideChangelog) { $changelogInput.Value = $Changelog }
if ($NonInteractive -and ($Configure -or $PromptForMod -or $PromptForVersion -or $PromptForProject -or $PromptForChangelog -or $PromptForToken)) { throw '-NonInteractive cannot be combined with prompt switches or -Configure.' }
if ($PromptForMod -or $PromptForVersion) {
    Get-PublishItems $workspace -Source $Source | Select-Object Mod, Release, Loader, Minecraft | Format-Table -AutoSize | Out-Host
}
if ($PromptForMod) {
    $availableMods = @(Get-PublishItems $workspace -Source $Source | Select-Object -ExpandProperty Mod -Unique)
    if ($availableMods.Count -eq 1) { $Mod = @($availableMods[0]); Write-Host "Selected $($availableMods[0]) (the only available mod)." }
    else {
        $answer = Read-Host 'Mods (comma-separated folder names, or all) [all]'
        if ($answer) { $Mod = @($answer.Split(',') | ForEach-Object { $_.Trim() }) }
    }
}
if ($PromptForVersion) {
    $answer = Read-Host 'Minecraft versions (e.g. 26.1.x,1.21.1-1.21.3, or all) [all]'
    if ($answer) { $Version = @($answer) }
}
$items = @(Get-PublishItems $workspace $Mod $Version $Loader $ReleaseVersion $Source)
if (-not $items.Count) { throw 'No matching JARs. Drop release JARs into incoming/ or select a retained release from mods/.' }
$batches = [ordered]@{}
foreach ($targetPlatform in $platforms) {
    $projects = Get-Setting $localSettings[$targetPlatform] 'Projects' @{}
    if (-not $NonInteractive) {
        Invoke-ModPublishSetup $workspace $items $targetPlatform $projects -Configure:$Configure -PromptForProject:$PromptForProject -PromptForChangelog:$PromptForChangelog -ChangelogInput $changelogInput
    }
    # Validate both platforms before uploading to either. All plans share the
    # same Item objects, so a retained path from the first upload is reused.
    $plans = @(Get-UploadPlan $workspace $items $targetPlatform $projects $Changelog $overrideChangelog)
    foreach ($plan in $plans) {
        Write-Host "$targetPlatform / $($plan.Project) / $($plan.Item.FileName)"
        Write-RuntimePreview $plan
        if ($targetPlatform -eq 'Modrinth') { Write-Host '  Offline preview: the project reference will be resolved to its internal Modrinth ID before publishing.' }
        Write-Host ($plan.Data | ConvertTo-Json -Depth 20)
    }
    if ($plans.Count) { $batches[$targetPlatform] = $plans }
}
if (-not $batches.Count) { Write-Host 'All matching mods are disabled for the selected platforms.'; return }
if (-not $Publish) { Write-Host 'Dry run complete. Add -Publish to upload these JARs.'; return }
$tokens = @{}
foreach ($targetPlatform in $batches.Keys) {
    $tokens[$targetPlatform] = Get-PublishingToken $workspace $targetPlatform -PromptForToken:$PromptForToken -NonInteractive:$NonInteractive
}
Invoke-PlatformPublishBatches $workspace $batches $tokens
