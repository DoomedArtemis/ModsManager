# Mods Manager

Mods Manager is a PowerShell-based publishing workspace for Minecraft Java mods. It publishes compiled release JARs directly from `incoming/` to Modrinth or CurseForge, keeps per-mod configuration in `mods/`, and organizes successfully published JARs by mod, loader and mod version.

The project follows the configuration and publishing style of [Resource Packs Manager](https://github.com/DoomedArtemis/ResourcePacksManager), adapted for maintaining multiple mods across Minecraft releases and loaders. JAR contents and filenames are preserved. Compile your mods in their own source projects and drop the finished JARs here.

## Getting Started

Use Windows PowerShell 5.1 (`powershell.exe`). IntelliJ's shared run
configurations use the same scripts and terminal prompts as the commands below.

1. Copy your compiled JARs to `incoming/`, for example
   all five `omniwheel-2.1.0-forge-mc<version>.jar` variants for your release.
2. Run **Dry Run Selected Mods to Modrinth** or its CurseForge equivalent.
   The publisher reads the JAR directly and automatically creates a missing
   `mods/omniwheel/mod.publish.psd1`. Existing settings are preserved.
3. Answer the setup questions. Numbered menus explain client/server modes,
   release channels and dependency relations. Prompts show accepted project
   formats. Minecraft version, loader and mod version come from each JAR;
   Java is selected automatically. Shared questions are asked once per mod release. Saved
   answers are offered as defaults; invalid answers are retried.
   Changelogs are read from the mod's `changelog.md` automatically.
   Preview the loader, Minecraft version, release number and dependency JSON.
   Dry runs require no token and make no network requests. Setup automatically
   saves your answers to `mod.publish.psd1`; no manual editing is required.
4. Run **Publish Selected Mods to Modrinth** or **Publish Selected Mods to
   CurseForge**. Enter your token at the hidden prompt if no token is configured.
   Successful uploads retain the JAR in `mods/<mod>/<loader>/<mod-version>/`
   and remove the matching copy from `incoming/`. The retained JAR
   remains available for publishing to the other platform.

To publish to both in one run, choose **Publish Selected Mods to Both Platforms**.
It selects the JARs once, prepares both platforms, then publishes to Modrinth and
CurseForge using their separate saved tokens. The uploads run in sequence within
the same command; you do not need to start a second run or move JARs back.
Shared runtime questions are answered once, while each platform retains its own
project and dependency settings. **Dry Run Selected Mods to Both Platforms**
previews both without uploading or requesting tokens.

Both sets of upload metadata and required tokens are checked before the first
upload. If one platform fails, the command still attempts the other and reports
which did not finish. Successful uploads retain their receipts and JARs. Rerun
the combined command to finish the remaining platform; matching successes are
skipped rather than uploaded again.

For example, publishing `incoming/omniwheel-2.0.1-fabric-mc26.3.jar` produces:

```text
mods/
  omniwheel/
    mod.publish.psd1
    fabric/
      2.0.1/
        omniwheel-2.0.1-fabric-mc26.3.jar
```

The release folder is the mod's own version (`2.0.1`), and each loader gets its
own branch. The full JAR filename distinguishes Minecraft targets within that
release. Dry runs and failed uploads leave incoming files in place. Matching
already-published releases complete this organization too, without uploading
again. A changed incoming file is preserved rather than removed.

One **Publish Selected Mods to Modrinth** run handles every incoming variant of
the selected mod. For example, the five Forge builds for Minecraft 1.16.5,
1.18.2, 1.19.2, 1.20.1 and 1.21.1 become five separate uploads with Java 8, 17,
17, 17 and 21 respectively. They share your project, release notes and other
release choices. Each upload uses its own Minecraft version and loader. Forge
JARs targeting exactly Minecraft 1.20.1 additionally advertise NeoForge on both
platforms. This changes only the loader tags; the filename, version number,
display name, dependency selection and storage path still identify the Forge JAR.
The token is requested once for the entire command. Matching existing remote
uploads are skipped and organized along with the newly uploaded files.

When incoming files are available, default selection excludes unrelated older
releases stored in `mods/`. With no matching incoming files, retained releases
are available again for publishing to the other platform. Use `-Source incoming`,
`-Source published` or `-Source all` to select a source explicitly.

Publishing targets existing projects. Create the mod's project on each platform
first. No real project IDs, tokens or mod binaries are bundled in this repo.

## Repository Layout

```text
incoming/                 compiled release JARs waiting to publish (tracked by git)
mods/<mod>/               tracked mod.publish.psd1 settings
mods/<mod>/changelog.md    Markdown release notes, one file per mod
mods/<mod>/<loader>/<mod-version>/  retained published JARs (tracked by git)
scripts/                  list, scaffold, publish, tests
config/mods.psd1          repository folder layout
config/minecraft-java.json shared Minecraft-to-Java runtime mapping
config/*.local.psd1      optional private token/project overrides (git-ignored)
.idea/runConfigurations/ shared IntelliJ actions
```

## Mod JARs

Release filenames must follow `<mod>-<release>-<loader>-mc<version>.jar`.
Mod names use lowercase letters, numbers, hyphens or underscores. Supported
loaders are `fabric`, `quilt`, `forge` and `neoforge`. For example:

```text
omniwheel-2.1.0-fabric-mc26.3.jar
omniwheel-2.1.0-neoforge-mc26.3.jar
another_mod-1.0.0-beta.1-forge-mc1.20.1.jar
```

Only top-level JARs in `incoming/` are selected. Sources, javadoc and dev JARs
are skipped. Other unrecognized names fail with an actionable error. Each JAR
must open as a ZIP and contain the corresponding root loader manifest:
`fabric.mod.json`, `quilt.mod.json`, `META-INF/mods.toml`, or
`META-INF/neoforge.mods.toml`. Fabric/Quilt manifest versions must match the
filename's release. Older NeoForge builds may use `META-INF/mods.toml`.
The publisher also reads Forge/NeoForge mod IDs, display names, release versions,
Minecraft dependency ranges and explicit `clientSideOnly` declarations. A
concrete manifest release must match the filename, as must an exact Minecraft
dependency; numeric interval bounds are checked where supplied. Complex loader
constraints remain visible for review. Embedded
manifest dependencies are not automatically mapped to hosting project IDs.

JARs are never rewritten. A same-named JAR with different contents fails rather
than overwriting an existing release. JARs in `incoming/` and published JARs
under `mods/` are included in normal Git commits and pushes, together with
per-mod settings and changelogs. Publishing a tracked incoming JAR appears as
a move into its retained release directory in the next commit. Tokens and local
publishing receipts remain ignored. Publishing itself does not run Git commits
or pushes; commit and push the files through IntelliJ or Git as usual.
Publishing scans `incoming/` and retained releases in `mods/`, so files can be
reused on either platform.

## Publishing Configuration

Repository folder settings live in `config/mods.psd1`:

```powershell
@{
    IncomingRoot = 'incoming'
    ModsRoot = 'mods'
}
```

Paths are relative to the repository root and must stay inside it. JARs stay in
`incoming/` until a successful upload places them in `mods/<mod>/<loader>/<mod-version>/`.

## Per-Mod Configuration

The publishing setup creates and maintains `mod.publish.psd1` automatically.
On the first run for a release it asks for:

- Project reference and the mod's display name.
- Client/server installation mode, with all nine choices explained.
- Minecraft version, loader and mod release are detected rather than asked;
  Java is looked up automatically.
- Release channel (`release`, `beta`, `alpha`); release notes are selected automatically.
- Dependencies: keep, replace or clear the list; adding dependencies prompts
  for the platform identifier and required/optional/incompatible/embedded relation.
- Optional advanced fields: Modrinth visibility, featured and requested status;
  CurseForge notes format, manual release and extra compatibility names/IDs.

JARs are grouped by mod and mod release. Setup chooses an already configured
variant as the starting point when available, so adding older Minecraft targets
to an existing release does not repeat the same compatibility questions. Shared
answers apply to the new variants in that batch. Already configured variants
retain their specific settings unless `-Configure` explicitly reviews the batch;
the matching changelog section is used for all variants of that mod release. Dependency
version/loader filters still resolve independently for each file.

Project references are saved for the mod. Runtime and platform answers are saved
with exact mod-version, Minecraft-version and loader selectors, preserving older
release settings. The second platform reuses the saved runtime answers and asks
for its own project and dependencies. A new release gets a compatibility review.
Subsequent runs reuse completed setup. The IntelliJ publish actions still offer
the saved project for review; Enter keeps the displayed value. Maintain release
notes in the mod's Markdown file. Enter `-` to clear extra compatibility lists. Tokens are asked securely
only when publishing and saved in their separate ignored platform settings file,
never in the mod's configuration.

### Markdown Changelogs

Keep one `mods/<mod>/changelog.md` file per mod, beside `mod.publish.psd1`.
Each level-two heading identifies a mod release:

```markdown
# Omni Wheel changelog

## 2.1.1

**Fixed:**
- Changes for the next release.

## 2.1.0

**Added:**
- New Clipboard entry type.
- Global/local chat toggle.

**Changed:**
- Unified highlight fade animations across editor controls.
```

For `omniwheel-2.1.0-forge-mc1.21.1.jar`, publishing selects only the body beneath
`## 2.1.0`. Its mod release (`2.1.0`), not its Minecraft version, selects the
section. All loaders and game targets of that release receive the same notes
on Modrinth and CurseForge. Mixed-release batches select each release's own
section automatically. No changelog prompt or filename argument is needed.

The file title, release heading, other releases and `Unreleased` notes are not
uploaded. Formatting and internal blank lines are preserved; blank separator
lines surrounding a section are omitted. Use bold labels or level-three headings
for subsections. Version headings inside fenced code blocks are ignored.
Bracketed headings such as `## [2.1.0] - 2026-11-07`, an optional `v` prefix,
and exact prerelease versions such as `## 2.2.0-beta.1` are also supported.

Add a new `## <mod-version>` section before publishing a new release. A missing
or duplicate section stops the run before uploading; the newest or nearest
version is never substituted. An empty matching section intentionally publishes
no release notes. Initial setup creates the file if missing and migrates existing
inline release notes once when available. Subsequent edits belong only in this
Markdown file, and saved per-platform changelog text is removed.

Advanced command-line overrides remain available: `-ChangelogFile <path>` reads
an entire UTF-8 file for that invocation, or `-Changelog <text>` supplies text
directly. These override automatic section selection without changing the mod's
Markdown file. They cannot be combined. Automatic file sections are always sent
to CurseForge with `changelogType = 'markdown'`; the configured format applies
only to explicit overrides. Already-published
versions skipped by duplicate detection retain their existing changelogs.

Use **Configure Mod Publishing for Modrinth** / **Configure Mod Publishing for
CurseForge**, or add `-Configure`, to review and change all saved answers through
the same menus. These configure actions finish with a dry-run preview.

The following configuration syntax is provided for reference. This shortened example
illustrates dependencies for Omniwheel; replace the project placeholders:

```powershell
@{
    DisplayName = 'Omniwheel'
    Runtime = @{
        Environment = 'client_and_server' # Choose the actual installation requirements
    }
    Modrinth = @{
        Project = 'your-modrinth-slug'
        VersionType = 'release'
        Dependencies = @(
            @{ ProjectId = 'P7dR8mSH'; Type = 'required'; Loaders = @('fabric') }
        )
    }
    CurseForge = @{
        Project = 'YOUR_NUMERIC_PROJECT_ID'
        ReleaseType = 'release'
        Dependencies = @(
            @{ Slug = 'fabric-api'; Type = 'requiredDependency'; Loaders = @('fabric') }
        )
    }
}
```

Modrinth accepts a project ID, slug, or `https://modrinth.com/mod/<slug>` URL.
CurseForge accepts a positive numeric project ID or an author dashboard URL
containing that ID. Dependencies use platform-specific identifiers:

| Platform | Dependency identifiers | Relation types |
| --- | --- | --- |
| Modrinth | `ProjectId`, `VersionId`, and/or `FileName` | `required`, `optional` (default), `incompatible`, `embedded` |
| CurseForge | Required `Slug`, optional numeric `ProjectId` | `requiredDependency`, `optionalDependency` (default), `incompatible`, `embeddedLibrary`, `tool` |

Modrinth project/version dependency IDs must be case-sensitive 8-character IDs;
they cannot be CurseForge numeric IDs. `VersionId` pins a dependency release.
Both platforms support these dependency filters:

- `Enabled = $false` disables an entry.
- `Loaders = @('fabric', 'quilt')` restricts loaders.
- `Versions = @('1.21.1', '26.2..26.3')` includes Minecraft versions.
- `ExcludeVersions` excludes versions even if included elsewhere.
- `MinVersion` / `MaxVersion` are inclusive numeric bounds.
- `AfterVersion` / `BeforeVersion` are exclusive numeric bounds.

Without filters, an enabled dependency applies to every selected JAR. Numeric
comparisons order `1.21.11` after `1.21.9`; snapshots can use exact version
selectors. Matching identical declarations collapse; conflicting declarations
for the same project fail before uploads begin. Use a consistent project
identifier in each declaration. Filters select your JAR's Minecraft version;
they do not express dependency mod-version constraints. CurseForge upload
relations cannot pin a dependency file.

## Runtime Compatibility

The setup stores compatibility in `Runtime` settings. It also handles files
created before interactive setup was available. These settings apply to both platforms:

```powershell
Runtime = @{
    Environment = 'client_and_server'
    AllowPreviewFeatures = $false
}
```

Choose the environment based on how your mod actually works:

| `Runtime.Environment` | Installation requirements |
| --- | --- |
| `client_only` | Client only, works with vanilla servers |
| `server_only` | Server only, also works in singleplayer |
| `dedicated_server_only` | Dedicated server only, no singleplayer |
| `client_and_server` | Required on both client and server |
| `server_only_client_optional` | Required on server, optional client features |
| `client_only_server_optional` | Required on client, optional server features |
| `client_or_server` | Works independently on either side |
| `client_or_server_prefers_both` | Works on either side, extra features with both |
| `singleplayer_only` | Singleplayer only |

These are the [current Modrinth environment values](https://modrinth.com/news/article/new-environments/).
The publisher sends the selected `environment` on each new Modrinth version.
It does not edit the project's page settings. CurseForge receives `Client`
and/or `Server` compatibility tags: client-only and singleplayer map to
`Client`, dedicated-server-only maps to `Server`, and other environments map
to both. Those tags cannot express Modrinth's full required/optional distinction.

The generated default `Environment = 'auto'` works when a Fabric/Quilt
manifest explicitly restricts the physical environment to `client` or `server`.
The latter means a dedicated server; an integrated singleplayer server runs
inside a physical client. A manifest with `*` does not reveal whether your mod
needs installation on both sides. Interactive setup asks you to choose explicitly,
including for Forge/NeoForge builds without an explicit `clientSideOnly` flag.
That flag is recognized as a client restriction; a dependency's `side="CLIENT"`
alone is not treated as a mod-wide restriction. A configured environment contradicting
an explicit loader restriction is rejected.

Java is always selected from the shared `config/minecraft-java.json` mapping
using each supported Minecraft version. Setup never asks for Java, including
when reviewing settings with `-Configure`. Existing per-mod `JavaVersions`
values are ignored and removed when settings are saved. Old `MinecraftVersions`
answers are likewise ignored and removed, so settings saved for one artifact
cannot advertise the wrong Minecraft version for another. Older manual `Java N`
compatibility names are replaced by the automatically generated tags.

CurseForge receives the mapped `Java 8`, `Java 17`, `Java 21`, etc. tag for each
artifact's own Minecraft version.
The [Modrinth create-version API](https://docs.modrinth.com/api/operations/createversion/)
has no Java compatibility field; its preview shows the same automatic selection
and the publisher validates it locally. The manager does not install Java or
rewrite the JAR's loader requirements.

Every selected/listed JAR is inspected for baseline `.class` headers. Previews
show the highest compiled Java target and Fabric/Quilt Java, Minecraft and
loader constraints. A compiled Java target above any selected Minecraft runtime
stops publishing with a recompile message; the mapping is never silently raised.
A simple Fabric/Quilt `java >=N` lower bound is checked too. Full loader version
predicates and nested library bytecode are not solved; review the displayed
constraints and test your mod. Forge/NeoForge essential TOML scalar metadata
and simple Minecraft bounds are read, rather than evaluating all TOML predicates.
Multi-release class
alternatives under `META-INF/versions/` are excluded from the baseline check.

Java preview bytecode is rejected unless `AllowPreviewFeatures = $true` and
the automatically selected runtime is exactly the matching Java major. Users must launch with
`--enable-preview`; setting this option does not add launch arguments for them.

For different requirements on older game versions or different loaders, add
top-level `Overrides`. Rules use the same version/loader selectors as
dependencies, plus an optional exact `ReleaseVersions` list:

```powershell
Overrides = @(
    @{
        Versions = @('1.20.1')
        Loaders = @('fabric')
        Settings = @{
            Runtime = @{ Environment = 'client_and_server' }
            Modrinth = @{ VersionType = 'beta' }
        }
    }
    @{
        MinVersion = '26.1'
        Settings = @{ Modrinth = @{ VersionType = 'release' } }
    }
)
```

Later matching rules take precedence. Nested dictionaries merge; arrays such
as dependencies replace the earlier array. Version filters
match the filename's Minecraft version. Existing base settings are not changed.
Every JAR gets a separate upload with its own detected target. Compatibility
settings do not relabel a compiled JAR as a build for a different game or loader.

Additional platform options are supported in their respective blocks:

- `Modrinth.RequestedStatus`: `listed`, `unlisted`, `draft`, or `archived`.
- `CurseForge.GameVersionNames`: extra compatibility tag names added to the
  generated Minecraft, loader, environment and automatic Java tags. Tag names
  must exist on CurseForge. Conflicting side tags are rejected locally; manual
  Java names are ignored in favor of the shared mapping.
- `CurseForge.GameVersions`: extra positive numeric game-version/tag IDs for
  tags you prefer to identify by ID. These are sent as JSON integers; the
  platform validates their meaning.

The existing release channel, changelog format, visibility, featured status,
manual release and dependency settings continue to work with runtime overrides.
Changelogs come from the mod's versioned Markdown file rather than these overrides.
Project descriptions, licenses, categories and links belong on the hosting
project page or in your mod's source metadata. They are not file-upload fields.
Already-published releases skipped by duplicate detection are not edited when
you change these settings.

## Minecraft Java Mapping

`config/minecraft-java.json` is checked into the repository and shared by every
mod and both platforms. It contains exact entries for 922 releases, snapshots,
alpha and beta versions from the current launcher manifest. The normal release
transitions are:

| Minecraft release | Automatically selected Java major |
| --- | --- |
| Through 1.16.5 | 8 |
| 1.17 / 1.17.1 | 16 |
| 1.18 through 1.20.4 | 17 |
| 1.20.5 through 1.21.11 | 21 |
| 26.1 through 26.3 | 25 |

These describe the launcher-selected runtime, rather than every Java version a
particular mod might happen to support. Snapshots use their exact entries,
not a comparison against these release ranges. An unknown future version stops
with instructions to refresh the mapping instead of asking for a Java version.

The sync script reads [Mojang's version manifest](https://piston-meta.mojang.com/mc/game/version_manifest_v2.json)
and each version's `javaVersion.majorVersion`, verifying the version JSON against
its manifest SHA1. Eighteen older entries lack that field; their Java 8 mapping
comes from the single supported major in [Prism Launcher's version metadata](https://meta.prismlauncher.org/v1/net.minecraft/1.6.4.json).
The source URL, resolution method and metadata checksums are stored per entry.
No Java major is inferred from an arbitrary future version number.

Run **Sync Minecraft Java Versions** in IntelliJ, or:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-minecraft-java.ps1
```

The sync needs internet access and replaces the shared file only after the
whole download validates. Normal publishing and previews use the saved file
offline for Java resolution.

## Publishing Tokens and State

Tokens can come from `MODRINTH_TOKEN` / `CURSEFORGE_TOKEN`, an optional ignored
`config/modrinth.local.psd1` / `config/curseforge.local.psd1`, or the hidden
interactive prompt. The first prompted token is saved automatically for all mods
on that platform. Later publishing runs reuse it without asking.
`-PromptForToken` asks for a replacement and updates the saved token.
Modrinth needs version-creation permission. CurseForge
needs an author upload token, separate from a Core API key.

`config/modrinth.local.psd1` stores the global Modrinth `Token`, and
`config/curseforge.local.psd1` stores the global CurseForge `Token`. Each token
works for every mod project on its platform that the account can publish to.
Files are created automatically when saving a token and can also contain private
project overrides (`Projects = @{ omniwheel = 'project-reference' }`). Existing
overrides are preserved when a token changes.

These are plain-text credential files, kept separate from tracked mod settings,
examples and publish receipts. Both the final and temporary credential files
must be git-ignored and untracked before a token can be saved. Environment
variables override saved file tokens when explicitly set. Never place tokens
in tracked mod configs. Publishing refuses tracked local settings or receipts.

All selected JARs and upload plans are validated before the first upload.
Success receipts are written immediately to ignored
`config/publish-state.local.json`, before organizing the published JAR. Subsequent uploads to the
same platform/project/version skip matching contents and reject changed JARs.
Modrinth also checks existing remote versions and SHA512 hashes. CurseForge
duplicate detection uses local receipts because its upload API has no documented
remote listing endpoint; keep this state file when moving your workspace.
Network errors are not automatically retried. If a response or local receipt
write fails after an upload reaches the server, check the platform before retrying.
Run one publishing command at a time in a workspace.

After deleting a remote release, reset its local receipt before retrying:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/reset-publish-state.ps1 -Platform Modrinth -Project isSnF43I -VersionNumber 2.1.0-forge-mc1.16.5
```

`-Project` matches the project ID saved in the receipt. This resets only that
platform/project/version record; it does not delete remote files, JARs, tokens,
or mod settings. Put the JAR in `incoming/` to retry it specifically, or publish
the retained copy using `-Source published` if it is still present in `mods/`.

## Commands

```powershell
# Inspect incoming and published releases
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/list-mods.ps1

# Preview one release; add -Publish when ready to upload
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform Modrinth -Mod omniwheel -Version 26.3 -Loader fabric -ReleaseVersion 2.1.0

# Preview several Minecraft versions / ranges
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform CurseForge -Mod omniwheel -Version '1.21.1,26.2..26.3'

# Publish all incoming variants of one mod in a single run
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform Modrinth -Mod omniwheel -Publish

# Publish the same JAR selection to both services in one command
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform Both -Mod omniwheel -Publish

# Review or change saved answers using the interactive menus
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform CurseForge -Mod omniwheel -Configure

# Refresh Java requirements for every project
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/sync-minecraft-java.ps1

# Automation: use preconfigured values and never prompt
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-mods.ps1 -Platform Modrinth -Mod omniwheel -NonInteractive

# Create a settings file before you have a JAR
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/new-mod.ps1 -Name omniwheel

# Run offline tests
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-mod-manager.ps1
```

Selections default to `all`. `-ReleaseVersion` filters existing releases; it
does not relabel a compiled JAR. Use `-Changelog ''` for an empty release-note
override on one invocation, or leave the matching Markdown section empty.
Publishing never happens without `-Publish`.
`-NonInteractive` skips the setup and requires existing valid configuration.
It cannot be combined with prompt switches or `-Configure`. For noninteractive
publishing, supply the token through the environment or ignored local settings.

## IntelliJ Run Configurations

IntelliJ configurations include **List Mod Releases**,
**Create New Mod**, **Sync Minecraft Java Versions**, **Test Mods Manager**, and dry-run / publish
actions for all or selected mods on each platform. Publishing actions prompt
for the shared project once per release, with changelogs, loader and Minecraft
targets detected from the JARs. Selected-mod actions offer mod selection when
several mods are available; a single mod is selected automatically. Missing
tokens prompt securely once for the whole command. These use
IntelliJ's Shell Script support and execute in a terminal for interactive input.
Combined actions are **Publish Selected Mods to Both Platforms**, **Publish All
Mods to Both Platforms**, and their matching **Dry Run** configurations. Each
platform reuses its own token, prompting once only when that token is missing.
The **Configure Mod Publishing for Modrinth** and **Configure Mod Publishing for
CurseForge** actions reopen the full setup for the selected releases.

## Modrinth Publishing

`scripts/publish-mods.ps1 -Platform Modrinth` prepares Modrinth versions from
incoming and retained published release JARs. It performs a dry run unless
`-Publish` is provided. Retained releases are reused, allowing the same JAR to
be uploaded to both platforms.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-mods.ps1 -Platform Modrinth -Mod omniwheel -Version 26.3 -Loader fabric
```

Per-mod settings live in the `Modrinth` block of `mod.publish.psd1`. Configure
`Project`, `VersionType`, `Status`, `Featured`, `Dependencies`, and
optionally `RequestedStatus`. `changelog.md` supplies the matching release notes.
The shared `Runtime` block supplies the release's
environment and compatible Minecraft versions. Java requirements are displayed
and validated locally; the upload API has no Java compatibility field.

Project references can be Modrinth mod URLs, project IDs, or slugs. Dependencies
use case-sensitive project/version IDs, as described in Per-Mod Configuration.
Publishing requires a personal access token with version-creation permission.
Before uploading, the publisher resolves every project reference through
Modrinth's Get Project endpoint and sends the returned internal base62 ID as
`project_id`. Even eight-character slugs are looked up. A failed lookup stops
the batch before any uploads. Offline previews display the configured reference;
the authenticated lookup happens only when publishing.

The publisher checks remote version numbers and SHA512 file hashes. Matching
releases are skipped; a matching number with different contents fails. Successful
uploads are recorded locally and their JARs are retained under
`mods/<mod>/<loader>/<mod-version>/`, with matching incoming copies removed.

Modrinth version numbers include loader and Minecraft version, for example
`2.1.0-fabric-mc26.3`. Each JAR gets its own upload; Forge and Fabric releases
do not collide. The release subtitle contains only `DisplayName` and the mod
release: for example, version number `2.0.1-neoforge-mc1.21.1` has subtitle
`Omni Wheel 2.0.1` when `DisplayName = 'Omni Wheel'`. CurseForge's file display
name uses the JAR filename without `.jar`, for example
`omniwheel-2.1.0-forge-mc1.16.5`. Existing published versions skipped by
duplicate detection retain their current titles.

CurseForge receives the Minecraft version and loader name as
`gameVersionNames`. Preview JSON uses the documented
[Modrinth version API](https://docs.modrinth.com/api/operations/createversion/)
and [CurseForge Upload API](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api).

## CurseForge Publishing

`scripts/publish-mods.ps1 -Platform CurseForge` prepares CurseForge files using
the same JAR selection, dry-run, publishing and release storage workflow:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\publish-mods.ps1 -Platform CurseForge -Mod omniwheel -Version 26.3 -Loader fabric
```

Per-mod settings live in the `CurseForge` block of `mod.publish.psd1`. Configure
`Project`, `ReleaseType`, `ChangelogType`, `ManualRelease`,
`Dependencies`, and optionally `GameVersionNames` / `GameVersions`. `changelog.md`
supplies the matching release notes. The shared
`Runtime` block supplies compatible Minecraft versions, client/server tags and
automatic Java tags.

Project references must be positive numeric CurseForge project IDs or author
dashboard URLs containing that ID. Public project slugs are insufficient for
upload calls. Dependency relations use project slugs and optional numeric IDs.
Publishing requires a CurseForge author upload token, separate from a Core API key.

CurseForge receives compatibility names in `gameVersionNames`. Its upload API
cannot represent all Modrinth environment distinctions or pin dependency files.
Duplicate detection uses the local publishing receipts; retain those receipts
when moving the workspace. Successful uploads retain their JARs under
`mods/<mod>/<loader>/<mod-version>/` and remove matching incoming copies.

The metadata follows the [CurseForge Upload API](https://support.curseforge.com/support/solutions/articles/9000197321-curseforge-upload-api).

## Licensing

The repository is licensed under the MIT License; see `LICENSE`. The license
is copied from Resource Packs Manager, including its DoomedArtemis copyright
notice. Individual mods may include third-party work with separate credits and
license notices. Preserve those notices when building and publishing mods; the
manager keeps compiled JARs and their embedded metadata unchanged.
