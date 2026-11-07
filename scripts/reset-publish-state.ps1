[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Modrinth', 'CurseForge')][string]$Platform,
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$VersionNumber
)
. (Join-Path $PSScriptRoot 'mod-manager.ps1')
if ($PSCmdlet.ShouldProcess("$Platform / $Project / $VersionNumber", 'Reset local publishing receipt')) {
    $count = Reset-LocalPublishReceipt (Get-Workspace) $Platform $Project $VersionNumber
    Write-Host "Reset $count local publishing receipt(s). The JAR can be published again; no remote files or mod settings were changed."
}
