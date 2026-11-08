[CmdletBinding()]
param([string]$Mod, [string]$ReleaseVersion, [switch]$Yes)
. (Join-Path $PSScriptRoot 'mod-manager.ps1')
. (Join-Path $PSScriptRoot 'publish-setup.ps1')
. (Join-Path $PSScriptRoot 'changelog-setup.ps1')
Invoke-RemoveModChangelog (Get-Workspace) $Mod $ReleaseVersion -Yes:$Yes
