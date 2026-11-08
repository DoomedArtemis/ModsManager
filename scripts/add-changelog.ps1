[CmdletBinding()]
param([string]$Mod, [string]$ReleaseVersion, [string]$ChangelogFile)
. (Join-Path $PSScriptRoot 'mod-manager.ps1')
. (Join-Path $PSScriptRoot 'publish-setup.ps1')
. (Join-Path $PSScriptRoot 'changelog-setup.ps1')
Invoke-AddModChangelog (Get-Workspace) $Mod $ReleaseVersion $ChangelogFile
