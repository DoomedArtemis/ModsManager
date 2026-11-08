function Test-RemoveChangelogWorkflow($ParentWorkspace) {
    . (Join-Path $PSScriptRoot 'publish-setup.ps1')
    . (Join-Path $PSScriptRoot 'changelog-setup.ps1')
    $root = Join-Path $ParentWorkspace.Root 'remove-changelog'
    $workspace = @{ Root = $root; ModsRoot = (Join-Path $root 'mods') }
    $directory = Join-Path $workspace.ModsRoot 'laboratoryblocks'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $path = Join-Path $directory 'changelog.md'
    $preamble = "# Laboratory Blocks changelog`r`n`r`n## Unreleased`r`n`r`nUpcoming notes.`r`n`r`n"
    $newest = "## 2.0`r`n`r`n## Added`r`n- **Newest** release.`r`n`r`n"
    $middle = "## [1.1] - 2026-11-08`r`n`r`n## Fixed`r`n- Middle release.`r`n`r`n``````md`r`n## 1.0`r`nExample heading.`r`n```````r`n`r`n"
    $oldest = "## v1.0`r`n`r`n## Changed`r`n- Original release.`r`n"
    $original = $preamble + $newest + $middle + $oldest
    foreach ($case in @(
        @{ Release = '2.0'; Expected = ($preamble + $middle + $oldest) },
        @{ Release = '1.1'; Expected = ($preamble + $newest + $oldest) },
        @{ Release = '1.0'; Expected = ($preamble + $newest + $middle) }
    )) {
        [IO.File]::WriteAllText($path, $original)
        $null = Remove-ModReleaseChangelog $workspace 'laboratoryblocks' $case.Release
        Assert ([IO.File]::ReadAllText($path) -ceq $case.Expected) 'Removing first, middle or last release preserves every other section verbatim, including CRLF and fenced headings'
        Assert-Throws { Read-ModReleaseChangelog $workspace 'laboratoryblocks' $case.Release } 'Changelog: add a'
    }
    [IO.File]::WriteAllText($path, $original)
    Assert-Throws { Remove-ModReleaseChangelog $workspace 'laboratoryblocks' '1.01' } 'no ## 1.01 section'
    Assert-Throws { Remove-ModReleaseChangelog $workspace '../outside' '1.0' } 'lowercase mod folder'
    Assert-Throws { Remove-ModReleaseChangelog $workspace 'laboratoryblocks' 'Unreleased' } 'specific mod release'
    Assert-Throws { Remove-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0' -ExpectedText 'Outdated preview' } 'file changed while reviewing'
    Assert ([IO.File]::ReadAllText($path) -ceq $original) 'Invalid or stale removal requests leave the file unchanged'
    [IO.File]::WriteAllText($path, $original + "`r`n## 1.0`r`nDuplicate.")
    $duplicate = [IO.File]::ReadAllText($path)
    Assert-Throws { Remove-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0' } 'duplicate ## 1.0'
    Assert ([IO.File]::ReadAllText($path) -ceq $duplicate) 'Ambiguous duplicate releases cannot cause an unintended removal'
    [IO.File]::WriteAllText($path, $original)
    $answers = [Collections.Generic.Queue[string]]::new()
    function Read-Host([string]$Prompt) {
        if (-not $answers.Count) { throw "Unexpected Remove Changelog prompt: $Prompt" }
        return $answers.Dequeue()
    }
    foreach ($answer in @('laboratoryblocks', '1.1', '')) { $answers.Enqueue($answer) }
    Invoke-RemoveModChangelog $workspace
    Assert ([IO.File]::ReadAllText($path) -ceq $original -and $answers.Count -eq 0) 'Interactive mod/version selection defaults to cancellation at confirmation'
    foreach ($answer in @('1', '2', 'yes')) { $answers.Enqueue($answer) }
    Invoke-RemoveModChangelog $workspace
    Assert ([IO.File]::ReadAllText($path) -ceq ($preamble + $newest + $oldest)) 'Interactive numbered choices remove exactly the confirmed release'
    [IO.File]::WriteAllText($path, "# Laboratory Blocks changelog`n`n## 1.0`n`n## Added`n- Only release.`n")
    $null = Remove-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0'
    Assert ((Test-Path -LiteralPath $path) -and [IO.File]::ReadAllText($path) -ceq "# Laboratory Blocks changelog`n`n") 'Removing the only release retains the mod Markdown file and title'
    Invoke-RemoveModChangelog $workspace 'laboratoryblocks'
    [IO.File]::WriteAllText($path, "# Laboratory Blocks changelog`n`n## 1.0`n`n")
    $null = Remove-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0'
    Assert (@(Get-ModChangelogSections ([IO.File]::ReadAllText($path))).Count -eq 0) 'Empty release sections can also be removed'
    $null = Set-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0' 'Restored notes.'
    Assert ((Read-ModReleaseChangelog $workspace 'laboratoryblocks' '1.0') -ceq 'Restored notes.') 'Removed versions can be added again using the existing action'
    Assert (-not (Test-Path -LiteralPath ($path + '.tmp'))) 'Removal leaves no temporary files'
    Write-Host 'All Remove Changelog workflow tests passed.' -ForegroundColor Green
}
Test-RemoveChangelogWorkflow $w
