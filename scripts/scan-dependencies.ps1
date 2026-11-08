[CmdletBinding()]
param(
    [ValidateSet('Modrinth', 'CurseForge', 'Both')][string]$Platform = 'Both',
    [string[]]$Mod = @('all'),
    [ValidateSet('auto', 'incoming', 'published', 'all')][string]$Source = 'incoming',
    [switch]$Json
)
. (Join-Path $PSScriptRoot 'mod-manager.ps1')
$items = @(Get-PublishItems (Get-Workspace) -Mod $Mod -Source $Source)
if (-not $items.Count) { throw 'No matching JARs to scan.' }
$platforms = @($Platform)
if ($Platform -eq 'Both') { $platforms = @('Modrinth', 'CurseForge') }
$rows = @(foreach ($item in $items) { foreach ($target in $platforms) { Get-DependencyScan $item $target } })
if ($Json) { ConvertTo-Json -InputObject $rows -Depth 12; return }
foreach ($group in @($rows | Group-Object FileName)) {
    Write-Host "`n$($group.Name)"
    $group.Group | Select-Object Platform, ModId, Type, @{ Name = 'Constraint'; Expression = { if ($_.Constraint -is [string]) { $_.Constraint } else { ConvertTo-Json -InputObject $_.Constraint -Compress -Depth 8 } } }, Status, @{ Name = 'Project'; Expression = { if ($_.Platform -eq 'Modrinth') { Get-Setting $_.Project 'ProjectId' '' } else { Get-Setting $_.Project 'Slug' '' } } }, Ignored | Format-Table -AutoSize -Wrap | Out-Host
}
$unresolved = @($rows | Where-Object { $_.Status -notin @('resolved', 'ignored') })
Write-Host "Scanned $($items.Count) JAR(s). $($unresolved.Count) unresolved dependency declaration(s). No uploads, file moves or configuration changes."
if ($unresolved.Count) { throw 'Some dependency declarations need a verified mapping or manual review before automatic publishing.' }
