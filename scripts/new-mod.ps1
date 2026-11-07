[CmdletBinding()]
param([string]$Name)
. (Join-Path $PSScriptRoot 'mod-manager.ps1')
if (-not $Name) { $Name = Read-Host 'Mod folder name (e.g. omniwheel)' }
New-ModSettings (Get-Workspace) $Name
$workspace = Get-Workspace
$config = Import-PowerShellDataFile (Join-Path (Join-Path $workspace.ModsRoot $Name) 'mod.publish.psd1')
Initialize-ModChangelog $workspace @([pscustomobject]@{ Mod = $Name; Release = 'Unreleased'; Minecraft = ''; Loader = '' }) $config
