# PDF Expert Patcher
A patcher that makes PDF Expert feel more at home on macOS.

- Move tab close buttons to the left
- Hide AI & Translator
- Hide sidebar close buttons

![Showcase](./images/Showcase.png)

---

Current version: **1.4.2**, as recorded in [VERSION](VERSION). Four independent
runtime patches for the official DMG edition of PDF Expert on macOS, with
**3.13.4 build 1177** as the known compatibility baseline.

| Module | Effect |
|---|---|
| TabPatch | Moves tab close buttons to the left |
| SidebarPatch | Hides close buttons in recognized editing-tool right sidebars |
| ToolbarPatch | Hides AI and translation toolbar entries and four AI/translation context-menu items |
| KeychainFix | Preserves the restored, working keychain routing for login persistence |

For adaptation after major app changes or handoff to another LLM, read
[AGENTS.md](AGENTS.md), then the [handoff guide](docs/handoff.md).
See the [documentation index](docs/index.md) for all documentation and the
[update guide](docs/update-guide.md) for steps after official app updates.

## Everyday use

Requires Xcode or Command Line Tools and Python 3. Hopper is only needed for
fresh reverse engineering. Run from the project directory:

```bash
./patch.sh                              # Build and install all modules after an official in-place update
./patch.sh --check                      # Read-only checks of load commands, signatures, architectures, versions, and hashes
./patch.sh --build SidebarPatch         # Build one module; omit the name to build all four
./patch.sh --update SidebarPatch        # Build/update only this already-injected module
./patch.sh --test                       # Run all automated tests and temporary-app deployment exercises
./patch.sh --status-json                # Machine-readable identity report; excludes full signature checks
./patch.sh --record-compatibility       # Capture observations; leave manual validation fields pending
./patch.sh --restore                    # Restore a complete official app matching the version/build
```

Valid module names are `TabPatch`, `SidebarPatch`, `ToolbarPatch`, and `KeychainFix`.
`--update` does not modify or re-sign the main executable or update other modules.
If the target has not been injected or its paths do not match, a full installation
is required. App updates usually remove the injection, so **run `./patch.sh` after
an official in-place update**. A single-module update is insufficient in that case.
If internal implementation details have changed, follow the handoff guide to adapt
the patches; rerunning the installer alone does not guarantee compatibility.

Builds and tests do not change the actual app, installed dylibs, or user keychain;
tests operate only on temporary stand-in apps. Installation and updates quit PDF
Expert normally, respect unsaved-document prompts, and never force-terminate it.
Deployment proceeds only after exit is confirmed. If process-query permission is
unavailable, deployment stops instead of treating a failed query as proof of exit.

## Version identification

Build artifacts default to `build/`; installed files reside in `~/Library/PEPatch/`.
Each new dylib has a companion `NAME.json` recording the project version and hashes
of the module source, build recipe, and binary. Installation records also associate
the module with the app version.

`--check` separately reports the installed version, actual SHA256, and whether the
module matches the current build, source, and recipe. JSON observations also record
the main executable's SHA256, actual app path, and patch reference paths for each
architecture. These are static observations; manual validation remains separate.
Older modules without metadata appear as `unknown (untracked)`; this does not mean
they are broken, and no version is guessed. A metadata/binary mismatch is an error.
Source or recipe differences indicate a difference, not proof of incompatibility.
Re-signing can change binary bytes, so build and installation hashes are retained
separately. See the [architecture guide](docs/architecture.md) for technical details.

## Backup and recovery

A full installation commits the app copy after injection, signing, and verification
succeed; failures within the running installer trigger an attempted rollback.
Only the outer bundle is re-signed; nested code is not recursively re-signed.
Single-module updates commit the dylib and metadata together, preserving the old
module and recovery record in `backup/updates/NAME/<timestamp>-<hash>/` first.

Complete official snapshots are stored in `backup/<version>-<build>-<hash>/`.
Restoration checks the version/build, SHA256, Readdle Team ID, and full signature.
Backups are not cleaned up automatically. Legacy `PDF Expert.orig.*` backups contain
only the main executable and cannot restore the entire bundle's official signature.
Module-update backups are also distinct from complete official app snapshots.

If you already have a complete official copy, save it first:

```bash
PDF_EXPERT_APP="/path/to/official/PDF Expert.app" ./patch.sh --backup-original
./patch.sh --restore
```

Without a complete snapshot, restore the app using an official installer before
installing the patches again. Do not combine executables or remove signatures to
present an app as an official original. Full installation rejects apps that fail
full signature verification; single-module updates do not repair existing signature
problems.

The app, external dylibs, and metadata do not form one atomic transaction. Automatic
rollback is not guaranteed after a power failure or SIGKILL. If rollback itself
fails, retain the `.pepatch-*` directories identified in the error. Insufficient
permissions stop the operation; sudo is never invoked automatically. Check the
target's parent directory, installation directory, and backup directory permissions
first to avoid making all artifacts root-owned.

## Confirmed login baseline

Narrowing KeychainFix query matching in v1.3.1 caused a regression requiring login
after each restart. v1.3.2 reverted that restriction, and the user confirmed recovery.
v1.4.x **preserves uniform query routing and only improves diagnostic logging**;
reads and writes are no longer restricted to queries simultaneously matching
service/class/DP/group. See the [compatibility record](docs/compatibility.md) for
detailed evidence.

Ad-hoc signing changes the app's identity and may affect the keychain, iCloud,
extensions, and other features. Automated tests cannot replace real UI, document
saving, and login/restart validation. A successful arm64 build does not establish
arm64 runtime compatibility.

## Debugging and configuration

ToolbarPatch also hides Summarize, Explain, Translate to, and Translate PDF from
context menus, matching actions and language-submenu types. The Translate PDF
closure item additionally requires an exact match against the app's localized
title. Main-menu entries and underlying AI/translation functionality remain
available; SwiftUI panel close buttons are unchanged. `TOOLBARPATCH_DISABLE`
disables both toolbar and menu filtering. Automated regression tests cover menu
filtering. On 2026-10-15, the user confirmed that v1.4.2 hid all four context-menu
items. That confirmation applies only to 3.13.4 build 1177 on Intel; future versions
require fresh validation.

Set environment variables when executing the main binary directly; `open -a` does
not pass these variables through:

| Variable | Purpose |
|---|---|
| `TABPATCH_DEBUG=1` | Tab constraint logging |
| `SIDEBARPATCH_DEBUG=1` / `TOOLBARPATCH_DEBUG=1` | Button identifier diagnostics |
| `KEYCHAINFIX_DEBUG=1` | Operations, status codes/error descriptions, class, and field presence; no account or field values |
| `SIDEBARPATCH_DISABLE=1` / `TOOLBARPATCH_DISABLE=1` | Disable the corresponding UI changes while preserving original method calls |
| `KEYCHAINFIX_DISABLE=1` | Skip fishhook installation at startup without deleting or migrating existing credentials |

Switches are enabled whenever the variable exists, including when its value is
`0`; unset the variable to turn the switch off. Individual keychain calls are not
logged by default; patch installation results are still logged at startup.

| Configuration variable | Default |
|---|---|
| `PDF_EXPERT_APP` | `/Applications/PDF Expert.app` |
| `PEPATCH_BUILD_DIR` | Project `build/` directory |
| `PEPATCH_BACKUP_DIR` | Project `backup/` directory |
| `PEPATCH_INSTALL_DIR` | `~/Library/PEPatch` |

Use `DEVELOPER_DIR`, `CLANG`, `SDKROOT`, and `PYTHON` to override tool paths.
Injection uses absolute dylib paths; moving the installation directory requires a
full patch reinstallation, and long paths may exhaust Mach-O header space.
See the [vendor notes](src/vendor/README.md) for fishhook's source and license.
