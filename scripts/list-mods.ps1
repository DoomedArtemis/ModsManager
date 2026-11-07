[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'mod-manager.ps1')
Get-ModItems (Get-Workspace) | Select-Object Mod, Release, Loader, Minecraft, @{ Name = 'BytecodeJava'; Expression = { $_.RuntimeEvidence.BytecodeMinimumJava } }, @{ Name = 'ManifestEnvironment'; Expression = { $_.RuntimeEvidence.ManifestEnvironment } }, FileName | Format-Table -AutoSize
