function Test-VersionedModChangelog($Workspace, $FixtureItem) {
    $path = Join-Path $Workspace.ModsRoot 'omniwheel/changelog.md'
    $original = [IO.File]::ReadAllText($path)
    $notes = "## Added`r`n- New Clipboard entry type.`r`n- Global/local chat toggle.`r`n`r`n## Changed`r`n- Preserve **formatting**.`r`n`r`n## Fixed`r`n- Keep all release sections.`r`n`r`n``````md`r`n## 9.9.9`r`nThis is a code example.`r`n``````"
    try {
        $document = "# Omni Wheel changelog`r`n`r`n## Unreleased`r`n`r`nUnreleased notes.`r`n`r`n## 2.1.0`r`n`r`n$notes`r`n`r`n## [2.0.0] - 2026-11-07`r`n`r`nPrevious release.`r`n`r`n## v2.2.0-beta.1`r`n`r`nBeta notes.`r`n"
        [IO.File]::WriteAllText($path, $document, [Text.UTF8Encoding]::new($false))
        Assert ((Read-ModReleaseChangelog $Workspace 'omniwheel' '2.1.0') -ceq $notes) 'Release section preserves Markdown, blank lines, original line endings and fenced headings'
        Assert ((Read-ModReleaseChangelog $Workspace 'omniwheel' '2.0.0') -ceq 'Previous release.') 'Bracketed dated release heading selects exact older notes'
        Assert ((Read-ModReleaseChangelog $Workspace 'omniwheel' '2.2.0-beta.1') -ceq 'Beta notes.') 'Prerelease heading is an exact independent release'
        Assert-Throws { Read-ModReleaseChangelog $Workspace 'omniwheel' '9.9.9' } 'Changelog: add a ## 9.9.9'
        Assert-Throws { Read-ModReleaseChangelog $Workspace 'omniwheel' '2.1' } 'Changelog: add a ## 2.1'
        $mr = @(Get-UploadPlan $Workspace @($FixtureItem) 'Modrinth' @{ omniwheel = 'omni-wheel' })[0]
        $cf = @(Get-UploadPlan $Workspace @($FixtureItem) 'CurseForge' @{ omniwheel = '123456' })[0]
        Assert ($mr.Data.changelog -ceq $notes -and $cf.Data.changelog -ceq $notes) 'Both platforms select the same release-specific Markdown automatically'
        $cfPlainConfig = @{ CurseForge = @{ Project = '123456'; ChangelogType = 'text' }; Runtime = @{ Environment = 'client_only' } }
        $cfMarkdown = @(Get-UploadPlan $Workspace @($FixtureItem) 'CurseForge' -SettingsOverrides @{ omniwheel = $cfPlainConfig })[0]
        Assert ($cfMarkdown.Data.changelogType -eq 'markdown') 'Automatic Markdown files render as Markdown despite an obsolete plain-text platform setting'
        $older = Read-ModJar $FixtureItem.Path
        $older.Release = '2.0.0'
        $batch = @(Get-UploadPlan $Workspace @($FixtureItem, $older) 'Modrinth' @{ omniwheel = 'omni-wheel' })
        Assert ($batch[0].Data.changelog -ceq $notes -and $batch[1].Data.changelog -ceq 'Previous release.') 'Mixed mod-version batch selects different sections from one mod file'
        [IO.File]::WriteAllText($path, $document + "`r`n## 2.1.0`r`nDuplicate notes.")
        Assert-Throws { Read-ModReleaseChangelog $Workspace 'omniwheel' '2.1.0' } 'duplicate ## 2.1.0'
        [IO.File]::WriteAllText($path, "## 2.1.0`n`n## 2.0.0`nOld notes.")
        Assert ((Read-ModReleaseChangelog $Workspace 'omniwheel' '2.1.0') -ceq '') 'An intentionally empty matching release never uses another version notes'
        [IO.File]::WriteAllText($path, "## 2.1.0`n`n## Added`n- Released.`n`n## Unreleased`n`n## Fixed`n- Not released yet.")
        Assert ((Read-ModReleaseChangelog $Workspace 'omniwheel' '2.1.0') -ceq "## Added`n- Released.") 'Unreleased still ends a release while content headings remain in its notes'
    } finally { [IO.File]::WriteAllText($path, $original) }
    Write-Host 'All versioned mod changelog tests passed.' -ForegroundColor Green
}
Test-VersionedModChangelog $w $items[0]
