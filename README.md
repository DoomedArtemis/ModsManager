# Mods Manager

Mods Manager is a PowerShell publishing workspace for Minecraft Java mods. Drop compiled JARs into `incoming/`, add release notes, and publish to Modrinth, CurseForge, or both in one run. Successful uploads retain the original JARs under `mods/<mod>/<loader>/<mod-version>/`.

The project follows the workspace and configuration style of [Resource Packs Manager](https://github.com/DoomedArtemis/ResourcePacksManager). Build your mods in their source projects; this manager publishes the finished files without rewriting them.

## Getting Started

Use Windows PowerShell 5.1 (`powershell.exe`) and run commands from the repository root. IntelliJ is optional; its shared run configurations invoke the same scripts. The changelog paste window uses Windows Forms and runs in STA mode automatically through **Add Changelog**.

Create your mod's hosting project on each platform before uploading. Modrinth accepts its project ID, slug, or mod URL; CurseForge needs its numeric project ID or authors-dashboard project URL.

1. Copy your compiled release JARs into `incoming/`. Fabric, Quilt, Forge and NeoForge files can be mixed in the same batch.
2. Run **Add Changelog**. Choose the mod folder and mod release, select **paste**, paste your Markdown, and click **Save**. The file and release heading are created automatically.
3. Run **Scan Incoming Dependencies** to inspect detected required and optional dependencies and check their project mappings.
4. Run **Dry Run Selected Mods to Both Platforms**. Answer the setup prompts, then review each file's upload metadata. Settings are saved automatically; you do not need to fill in `mod.publish.psd1` yourself.
5. Run **Publish Selected Mods to Both Platforms**. Enter each platform's token once if it has not been saved yet. Later runs reuse those tokens for all mods.
6. Commit and push the retained JARs, settings and changelogs through Git or IntelliJ as usual. Publishing does not commit or push automatically.

For one platform, use the matching **Dry Run** / **Publish** action ending in **Modrinth** or **CurseForge**. **All Mods** actions use the same source-selection rules as **Selected Mods**, but skip the mod-selection prompt.

Dry runs perform no network requests, require no token, and leave JARs in place. Interactive dry runs can create settings and changelog scaffolds and save your setup answers. They validate locally; the hosting services can still reject an upload.

## What Is Automatic

| Setting | How it is determined |
| --- | --- |
| Mod folder, release and loader | JAR filename; release is checked against manifest metadata where available |
| Minecraft compatibility | Filename target, expanded against the shared release list for wildcards/ranges |
| Java requirement | Shared Minecraft-to-Java mapping, checked against compiled class headers |
| Release / beta / alpha | Each JAR's mod release version |
| Required / optional dependencies | Each JAR's manifest, translated through the shared dependency-project lookup |
| Client/server mode | Chosen once and saved for the whole mod |
| Release notes | Matching mod-version section in that mod's `changelog.md` |
| Credentials | Separate ignored token file for each platform, reused across mods |

Project references, display name, dependency mode and optional platform settings are configured through the setup prompts. Client/server mode is shared across every loader, Minecraft target, release and both platforms. Other setup choices are reused within a mod-release batch; configured variants keep their settings unless explicitly reviewed with **Configure Mod Publishing**.

## Repository Layout

```text
incoming/                         compiled JARs waiting to publish
mods/
  laboratoryblocks/
    mod.publish.psd1              publishing settings maintained by setup
    changelog.md                  one Markdown file for this mod's releases
    fabric/
      1.0/
        laboratoryblocks-1.0-fabric-mc26.1.x.jar
config/
  mods.psd1                       incoming/mods folder locations
  minecraft-java.json             shared Minecraft-to-Java mapping
  dependency-projects.psd1         shared mod-ID-to-hosting-project mappings
  modrinth.local.psd1             private Modrinth token and optional overrides
  curseforge.local.psd1           private CurseForge token and optional overrides
  publish-state.local.json        local upload receipts
scripts/                          publishing, changelog tools and offline tests
.idea/runConfigurations/           shared IntelliJ actions
```

JARs, mod settings, changelogs and shared mappings are tracked by Git. Private token files and upload receipts are ignored. This repository includes mod-specific settings and binaries; the manager's MIT license does not replace the licenses or credits embedded in those mods.

## Mod JARs

Name release files as:

```text
<mod>-<mod-version>-<loader>-mc<minecraft-target>.jar
```

Mod folder names use lowercase letters, numbers, hyphens or underscores. Loaders are `fabric`, `quilt`, `forge` and `neoforge`. Examples:

```text
laboratoryblocks-1.0-fabric-mc1.21.1.jar
laboratoryblocks-1.0-fabric-mc26.1.x.jar
examplemod-1.0b-neoforge-mc1.21.1-1.21.3.jar
examplemod-1.0a-forge-mc1.20.1.jar
```

Only top-level JARs in `incoming/` are pending inputs. Sources, javadoc and dev artifacts are skipped. Files must open as ZIPs and contain the matching loader manifest: `fabric.mod.json`, `quilt.mod.json`, `META-INF/mods.toml`, or `META-INF/neoforge.mods.toml`. Older NeoForge files may use `META-INF/mods.toml`.

The filename's mod release must match a concrete manifest release. Forge/NeoForge exact Minecraft requirements and simple numeric interval bounds are checked too. Other manifest constraints remain visible in previews; this is not a Minecraft runtime test.

### Minecraft Targets

| Filename target | Minecraft upload tags |
| --- | --- |
| `mc1.21.1` | `1.21.1` |
| `mc26.1.x` | `26.1`, `26.1.1`, `26.1.2` with the current shared mapping |
| `mc1.21.1-1.21.3` | `1.21.1`, `1.21.2`, `1.21.3` |

Wildcards and inclusive ranges expand to known stable releases in `config/minecraft-java.json`. Sync the mapping when new Minecraft versions arrive. Reversed ranges, unknown range endpoints and wildcards with no matches stop publishing. Snapshots and pre-releases need exact Minecraft targets.

Each JAR uploads once per platform with all its expanded game tags. Selecting a covered version, such as `-Version 26.1.1`, selects the entire `mc26.1.x` JAR and keeps all its tags. Filenames, retained paths and upload names preserve the original wildcard or range expression.

Forge JARs targeting exactly Minecraft `1.20.1` also receive the NeoForge loader tag on both platforms. This changes only compatibility tags, not filenames, version numbers, subtitles, dependency selection or storage paths.

### Release Channels and Names

| Mod version | Channel |
| --- | --- |
| `1.0`, `2.1.0` | release |
| `1.0b`, `2.1.0b` | beta |
| `1.0a`, `2.1.0a` | alpha |

Uppercase `A`/`B`, numbered suffixes such as `1.0b2`, and explicit forms such as `1.0-alpha.1` / `1.0-beta.1` also work. Build metadata after `+` does not change the channel. Unknown release labels stop publishing rather than guessing. No channel question is asked, and old `VersionType` / `ReleaseType` settings are ignored and removed on save.

For `omniwheel-2.1.0-forge-mc1.16.5.jar` with display name `Omni Wheel`:

| Upload field | Value |
| --- | --- |
| Modrinth version number | `2.1.0-forge-mc1.16.5` |
| Modrinth subtitle | `Omni Wheel 2.1.0` |
| CurseForge display name | `omniwheel-2.1.0-forge-mc1.16.5` |

## Markdown Changelogs

Use **Add Changelog** to select a mod and its mod release version, then paste the complete Markdown into the multiline window with Ctrl+V. Click **Save** or press Ctrl+Enter. Ordinary Enter inserts a newline; no `:end` marker is needed. Cancel, Escape or closing the window leaves the file unchanged.

The tool manages one `mods/<mod>/changelog.md` file and adds the version heading for you. Existing entries offer **append**, **replace**, or **cancel** (the default). Other releases are preserved. It also accepts a UTF-8 file; the optional **terminal** mode uses `:end` to finish and `:cancel` to cancel.

For example, paste only these notes after choosing version `1.0`:

```markdown
## Added

- **New blocks** and a dedicated creative tab.

## Changed

- Updated existing advancements.

## Fixed

- Fixed inventory checks.
```

The saved document has a title and `## 1.0` above that text. Publishing selects the exact mod-version section. `1.0` and `1.1` are separate entries even when their notes are identical. All loaders and Minecraft targets of the same mod release receive those notes on both platforms.

Bold text, bullets, headings and internal blank lines are preserved. The document title, version heading, other releases and `Unreleased` notes are not uploaded. Version headings inside fenced code blocks are ignored. Bracketed or dated headings such as `## [1.0] - 2026-11-08`, an optional `v` prefix and prerelease versions are supported.

Use **Remove Changelog** to choose an existing mod and release, preview its notes and confirm removal. Enter cancels. It removes that complete release section while keeping the file, other releases and `Unreleased` notes. This changes local notes only; previously published platform notes are unchanged.

A missing or duplicate version section stops publishing; another version's notes are never substituted. An intentionally empty existing section sends no notes. Setup scaffolds missing files, but you should add your notes before publishing. Unclosed code fences and pasted headings for another release are rejected.

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/add-changelog.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/remove-changelog.ps1
```

For a one-run override, `publish-mods.ps1 -ChangelogFile <path>` reads an entire UTF-8 file, while `-Changelog <text>` supplies notes directly. They cannot be combined and do not edit the saved changelog. Automatic sections use Markdown on CurseForge; `ChangelogType` applies only to explicit overrides.

## Dependencies

New mod configurations default to `DependencyMode = 'auto'` on both platforms. Every JAR is scanned independently, so one batch can contain different required and optional dependencies for different Minecraft versions or loaders.

| Manifest declaration | Automatic relation |
| --- | --- |
| Fabric `depends` | required |
| Fabric `recommends` / `suggests` | optional |
| Forge `mandatory = true` / `false` | required / optional |
| NeoForge `type = "required"` / `"optional"` | required / optional |
| Simple Quilt `depends` entries | required, or optional when declared optional |

Minecraft, Java and loader requirements are runtime metadata, not downloadable mod relations. Mods supplied by the same JAR and mod libraries found inside nested JARs are excluded from separate-download requirements.

`config/dependency-projects.psd1` translates manifest mod IDs into verified hosting project IDs and slugs. It currently includes Fabric API, Fusion, Mod Menu and JEI. A new mod ID needs a verified mapping added once to this shared file; similar names and search rankings are not treated as proof of identity.

Unknown projects, conditional Quilt dependencies and relationships that cannot be represented accurately are reported before automatic uploads. For example, a version-specific incompatibility is not converted into an unconditional ban on the entire dependency project. Use a verified mapping or manual mode for those cases.

The scan preserves each JAR's dependency version constraints for inspection. Automatic uploads link dependency projects, not specific files: a requirement such as Fusion `>=1.3.5` remains enforced by the loader manifest. The manager does not automatically select a dependency file or check whether a compatible release currently exists.

Run **Scan Incoming Dependencies**, or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/scan-dependencies.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/scan-dependencies.ps1 -Json
```

The scan needs no token or network and does not edit files. JSON output includes each declaration's constraint, source, mapping and resolution status.

### Manual Dependencies

Setup offers **auto**, **keep**, **replace**, and **none**. Keep preserves the current mode and list; replace and none select manual mode. Older configurations without `DependencyMode` keep their manual behavior until you choose auto through **Configure Mod Publishing**.

| Platform | Identifier | Relationships |
| --- | --- | --- |
| Modrinth | Case-sensitive 8-character project ID, optionally a version ID; external filenames are also supported | required, optional, incompatible, embedded |
| CurseForge | Project slug, optionally its numeric project ID | requiredDependency, optionalDependency, incompatible, embeddedLibrary, tool |

Modrinth version IDs can pin a dependency release. CurseForge upload relations cannot pin dependency files. The prompts default newly entered relations to required; declarations written manually without a `Type` default to optional.

Additional manual entries in auto mode are merged with detected relations. Identical entries collapse; conflicting relations for the same project stop publishing. Loader/version filters are supported in the configuration, although the dependency-entry prompts do not create those filters:

```powershell
Dependencies = @(
    @{ ProjectId = 'P7dR8mSH'; Type = 'required'; Loaders = @('fabric'); Versions = @('26.1.x') }
)
```

`Versions`, `ExcludeVersions`, `Loaders`, inclusive `MinVersion` / `MaxVersion`, exclusive `AfterVersion` / `BeforeVersion`, and `Enabled` are supported. For multi-version JARs, a declaration matches if at least one concrete target satisfies all its conditions. These filters select your JARs; they are not dependency mod-version constraints.

## Runtime Compatibility

Client/server installation mode is saved once in the mod's top-level `Runtime.Environment`. It is reused for all releases, loaders, Minecraft targets and both platforms. Old repeated answers migrate automatically when they agree; variant overrides cannot replace the shared setting. **Configure Mod Publishing** lets you change it deliberately.

| Setting | Installation requirement |
| --- | --- |
| `client_and_server` | Required on client and server |
| `client_only` | Client only; works with vanilla servers |
| `server_only` | Server required; also works in singleplayer |
| `dedicated_server_only` | Dedicated server only; no singleplayer |
| `server_only_client_optional` | Server required, client optional |
| `client_only_server_optional` | Client required, server optional |
| `client_or_server` | Works independently on either side |
| `client_or_server_prefers_both` | Works on either side; extra features with both |
| `singleplayer_only` | Singleplayer only |

Explicit client/server restrictions in loader manifests must agree with your choice. A Fabric/Quilt `*` environment cannot establish whether installation is required on both sides; setup asks you. Forge/NeoForge `clientSideOnly` is recognized, but a dependency's `side="CLIENT"` is not a mod-wide client-only declaration.

Modrinth receives the detailed environment value. CurseForge receives `Client`, `Server`, or both; those tags cannot express every required/optional distinction.

### Automatic Java Versions

`config/minecraft-java.json` supplies exact Minecraft-to-Java mappings shared by all mods. The main release transitions are:

| Minecraft release | Java major |
| --- | --- |
| Through 1.16.5 | 8 |
| 1.17 / 1.17.1 | 16 |
| 1.18 through 1.20.4 | 17 |
| 1.20.5 through 1.21.11 | 21 |
| 26.1 through 26.3 | 25 |

Snapshots use exact mapping entries, not numeric comparisons against this table. Unknown versions stop with instructions to sync the mapping. No Java question is asked, and old manual Java/Minecraft runtime selections cannot override the detected targets.

The manager checks baseline class headers against every selected Minecraft runtime. A JAR compiled for a newer Java version stops publishing. Multi-release class alternatives are excluded from the baseline check. Nested-library bytecode and complex loader predicates are not fully validated; test the JAR in Minecraft separately.

Java preview bytecode needs explicit `AllowPreviewFeatures = $true` and its matching Java major. Users must launch with `--enable-preview`; this manager does not install Java or change launch arguments. Preview permissions can remain variant-specific.

CurseForge receives the matching Java compatibility tags. Modrinth has no Java upload field; the requirement is validated locally and remains in the loader metadata.

Run **Sync Minecraft Java Versions** when new Minecraft versions arrive:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-minecraft-java.ps1
```

Sync requires internet, reads Mojang's version manifest and verifies each version metadata checksum. Older entries without Java metadata use an unambiguous major from Prism Launcher metadata. Provenance is saved in the mapping; replacement happens only after the download validates. Normal previews and Java resolution use the saved mapping offline.

## Publishing Tokens and State

The first hidden token prompt saves credentials separately for each platform:

| Platform | Ignored token file | Environment override |
| --- | --- | --- |
| Modrinth | `config/modrinth.local.psd1` | `MODRINTH_TOKEN` |
| CurseForge | `config/curseforge.local.psd1` | `CURSEFORGE_TOKEN` |

The token is reused for every mod project that account can publish to. Environment variables take precedence over saved tokens. `-PromptForToken` replaces the saved token. Modrinth needs version-creation permission; CurseForge needs an author upload token, separate from a CurseForge Core API key.

The ignored files can also contain private `Projects` overrides; examples are provided as `config/*.local.example.psd1`. Tokens and upload receipts must remain ignored and untracked. Keep local receipts when moving the workspace.

Successful uploads are recorded in `config/publish-state.local.json` by platform, project, version number, JAR hash and remote ID. Modrinth also checks existing remote version numbers and hashes. CurseForge duplicate detection relies on local receipts; losing them can cause duplicate uploads.

After intentionally deleting a remote file, reset its matching local receipt before republishing. Use the project ID recorded in the receipt. Preview the reset with `-WhatIf`, then omit that flag to apply it:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/reset-publish-state.ps1 -Platform Modrinth -Project isSnF43I -VersionNumber 2.1.0-forge-mc1.16.5 -WhatIf
```

This resets one local record; it does not delete remote releases, retained JARs, credentials or mod settings. Clearing the entire state file also forgets every CurseForge upload receipt.

## Publishing and Recovery

Default source selection prefers matching `incoming/` JARs. If none match, it uses retained JARs in `mods/`. Select `-Source incoming`, `-Source published`, or `-Source all` explicitly when needed.

Both-platform publishing selects files once, validates both sets of local metadata and obtains both tokens before uploading. Modrinth then CurseForge run sequentially. Successful JARs are retained unchanged; matching incoming copies are removed. The second platform reuses the retained path. A failed upload does not move its JAR, although an earlier platform may already have retained it.

If one platform fails, the command still attempts the other. Successful uploads keep their receipts. When a failed batch has files split between `incoming/` and `mods/`, retry that mod release with `-Source all` so neither group is missed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform Both -Mod laboratoryblocks -ReleaseVersion 1.0 -Source all -Publish
```

Matching recorded successes are skipped. Files with the same name/version but different contents fail instead of overwriting a published release. Already-published versions are not edited when you change names, settings or changelogs locally.

An upload can reach a server before a connection error or failed receipt write is reported. Check the platform before retrying an uncertain result, especially on CurseForge. Run one publishing command at a time in a workspace.

## Commands

All publish commands are previews unless `-Publish` is supplied:

```powershell
# List incoming and retained releases
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/list-mods.ps1

# Preview one mod on both platforms
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform Both -Mod laboratoryblocks

# Publish all selected source files, across mods and loaders
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform Both -Publish

# Filter by mod release, Minecraft target and loader
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform Modrinth -Mod laboratoryblocks -ReleaseVersion 1.0 -Version '26.1.x' -Loader fabric

# Review saved configuration; this finishes with a preview
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform CurseForge -Mod laboratoryblocks -Configure

# Preview preconfigured values without prompts
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform Both -Mod laboratoryblocks -NonInteractive

# Scaffold settings before having a JAR
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/new-mod.ps1 -Name examplemod

# Run the offline suite
powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/test-mod-manager.ps1
```

Selections default to `all`. `-ReleaseVersion` means the mod's version; `-Version` means Minecraft compatibility. Comma-separated version selections, wildcards, hyphen ranges, `..` ranges and `to` ranges are supported. Filters select artifacts without relabeling them.

`-NonInteractive` requires valid existing configuration and cannot be combined with prompt switches or `-Configure`. Noninteractive uploads also require a saved token or environment variable.

## IntelliJ Run Configurations

| Action | Purpose |
| --- | --- |
| **Add Changelog** / **Remove Changelog** | Maintain a mod's versioned Markdown notes |
| **Scan Incoming Dependencies** | Inspect manifest dependencies and mappings |
| **List Mod Releases** | Inspect incoming and retained artifacts |
| **Dry Run Selected Mods to Both Platforms** | Preview a chosen mod or mods |
| **Publish Selected Mods to Both Platforms** | Publish the same selection to both services |
| **Dry Run All Mods to Both Platforms** / **Publish All Mods to Both Platforms** | Use the default source selection without a mod prompt |
| **Configure Mod Publishing for Modrinth** / **Configure Mod Publishing for CurseForge** | Review saved settings without uploading |
| **Create New Mod** | Scaffold per-mod settings and notes |
| **Sync Minecraft Java Versions** | Refresh the shared runtime mapping |
| **Test Mods Manager** | Run offline tests with temporary fixtures and fake HTTP |

Single-platform dry-run/publish equivalents are included. These actions use IntelliJ's Shell Script support and run in a terminal. Publish actions offer the saved project reference for review; Enter keeps it.

## Configuration Reference

Setup maintains `mods/<mod>/mod.publish.psd1`; normal publishing does not require manual edits. Repository folder locations live in `config/mods.psd1` and must stay inside the repository.

| Scope | Settings |
| --- | --- |
| Mod | `DisplayName`, shared `Runtime.Environment` |
| Modrinth | `Project`, `Enabled`, `DependencyMode`, `Dependencies`, `Status`, `Featured`, optional `RequestedStatus` |
| CurseForge | `Project`, `Enabled`, `DependencyMode`, `Dependencies`, `ManualRelease`, optional `GameVersionNames` / `GameVersions`; `ChangelogType` for explicit notes overrides |
| Runtime | `AllowPreviewFeatures`, subject to each JAR's Java checks |

Advanced `Overrides` use dependency-style version/loader selectors plus optional `ReleaseVersions`. Later matches take precedence; nested dictionaries merge and arrays replace. Client/server mode, detected Minecraft/Java targets and release channels remain governed by the automatic/shared rules above.

Project descriptions, categories, licenses and links belong on the hosting project or in mod source metadata, not file-upload settings. The upload structures follow the [Modrinth API](https://docs.modrinth.com/api/operations/createversion/) and [CurseForge Upload API](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api).

## Licensing

The manager uses the MIT License; see [LICENSE](LICENSE). It is copied from Resource Packs Manager with its original DoomedArtemis copyright notice. Individual mods and third-party content retain their own license and credit requirements.
