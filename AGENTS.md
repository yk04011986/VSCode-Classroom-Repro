# Project Instructions

## Scope and Sources of Truth

This repository preserves scripts, manifests, templates, and documentation for rebuilding the classroom's portable VS Code environment.

- Read `README.md` and `state.md` before changing installation, recovery, or maintenance behavior. Use `manifests/versions.json` for pinned versions, download endpoints, and checksums; use `manifests/extensions.json` for extension versions.
- For C-drive restore, persistence, or conversation recovery tasks, read `docs/C-Drive-Restore.md` before making changes.
- Follow applicable parent workspace instructions. When available, consult the workspace's `.agents/shared-skills.json` and matching skills or workflows; keep the project usable when copied without those workspace resources.

## Persistence and Recovery

- Treat `C:` as non-persistent: the classroom restores it. Keep required configuration, reusable downloads, and repair procedures on `D:` or another confirmed persistent location. Confirm that the destination survives classroom resets; do not assume every non-system drive does.
- Make repairs reproducible in this repository's scripts or templates. A change to the running installation alone is incomplete; record the corresponding recovery procedure and remaining limitations.
- When a retained D-drive installation exists, inspect it before rebuilding. Preserve its `data`, extensions, portable tools, and conversations. Use Bootstrap for a missing installation or an explicitly selected new target.
- Installation folder names may refer to an older release. Determine the actual version from the executable and product metadata, then compare it with the manifest; do not infer it from the directory name.
- Save reusable downloads in the configured persistent cache. Treat `C:\Users\<user>\Downloads` as an input location, not a recovery source. Keep large archives and installed binaries out of Git.

## Safe Changes and Updates

- Installation scripts create missing components by default. Stop and explain existing version mismatches; never silently replace an installation or delete user data.
- Keep deployed launchers and their generating templates consistent. Preserve `CODEX_HOME`, portable home and Git configuration paths, UTF-8 initialization, required tool PATH entries, environment isolation with `setlocal`, and underlying exit codes. A tool update must retain these settings.
- Keep repairs independent of C-drive profiles, permanent execution-policy changes, system PATH edits, and file associations. Use the project's CMD entry points and per-process PowerShell initialization. Report any enforced school policy that prevents execution.
- Support Windows PowerShell 5.1: save PowerShell scripts as UTF-8 with BOM when needed, avoid assigning automatic variables such as `$HOME`, and preserve encoding settings after initialization returns.
- Before replacing program files, retain the updater's staging, integrity checks, exclusive lock, backup, transaction state, and rollback behavior. Resolve interrupted transactions before retrying. Closing editor processes requires the updater's explicit confirmation after the user saves their work.
- Download only from the official endpoints or GitHub release APIs specified by the manifests. Verify versions, advertised sizes, available SHA-256 digests, and Microsoft Authenticode signatures where applicable.
- Keep offline VSIX files in the configurable download cache, outside Git. Install the exact extension versions in the manifest.
- Invoke the Fusion installer from Bootstrap only when the user explicitly requests it.

## Private Data

- Keep credentials, personal memories, conversation files and databases, VS Code sessions, machine identifiers, and personal cloud project IDs outside this repository. Store only generic templates and recovery procedures here.
- Preserve both source and destination when migrating conversations. Existing data on both sides requires a reviewed merge, not an overwrite. Account for SQLite WAL, consistent backups, and relocated rollout paths; validate old and new conversations before declaring recovery complete.
- Retained files do not guarantee retained authentication. Document when GitHub, VS Code sync, Codex, or MCP services may require login after C-drive restoration. Do not export Windows credentials to bypass this requirement.

## Verification and Handoff

- After changing scripts or manifests, run PowerShell syntax and JSON checks. Use isolated fixtures for deployment, idempotency, conflict rejection, and backup behavior; do not run downloads, installers, real updates, or editor shutdown as a substitute for these checks.
- For persistence changes, run `scripts/Test-ClassroomPersistence.ps1` with an explicit installation path. Keep its local report outside Git and report failures, warnings, and manual checks separately.
- Distinguish static checks, tests against the current installation, and acceptance after an actual C-drive restore. Claim restore success only after that restore and the required functional checks have occurred.
- Update `README.md` when usage changes and `state.md` when the phase, completed work, next steps, or blockers change. Record known gaps rather than describing an unimplemented recovery step as working.
- Keep documents in `docs/`, scripts in `scripts/`, templates in `config/`, and final reports or deliverables in `output/`. Use the workspace `.tmp/` for disposable intermediates and clean up only this task's files. Keep the folder structure compact.
- Before committing, inspect the diff for private data and verify the configured Git author identity. Do not assume that identity or authentication survived a reset.
