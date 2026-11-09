# Classroom recovery acceptance - 2026-11-09

## Completed

| Check | Result |
| --- | --- |
| Conversation retention after restart | User confirmed the saved Codex conversation remains accessible. |
| Node on the retained installation | Installed v24.22.2 from the official archive; pinned SHA-256 matched. npm and npx both report 11.19.1. |
| Retained installation persistence checks | 0 failures, 0 warnings. Console input, output and native pipeline all use code page 65001. |
| Isolated rebuild | Started from an empty workspace `.tmp` target; after correcting CLI invocation and preserving missing packages, Bootstrap completed with exit code 0. |
| Rebuilt runtime versions | VS Code 1.144.1, Git 2.56.0.windows.4, uv 0.13.7, Node 24.22.2, Python 3.14.10. |
| Rebuilt extensions | All 37 pinned extension IDs and versions passed verification. |
| Persistent VSIX inventory | All 37 pinned VSIX packages saved outside Git; package identity and locally recorded SHA-256 verified. |
| Deployed maintenance templates | Updated with backups; the next tool update preserves Node/uv PATH, portable root and existing UTF-8/CODEX_HOME repairs. No updater or editor shutdown was invoked during deployment. |
| Offline inventory | 4 PASS, 39 UNVERIFIED, 0 MISSING, 0 FAIL; UNVERIFIED covers 37 VSIX artifacts plus Python runtime/cache provenance. |

The test used separate user data, extensions, and CODEX_HOME. It did not import conversations or credentials into the test installation or this repository. Existing launchers were backed up before Node setup. The test installation remains disposable under the workspace `.tmp` for inspection; use the regular D-drive launcher for daily work.

## Problems found and addressed

- Product metadata lookup now checks VS Code's program directories instead of recursively scanning user data and tool backups.
- Extension restoration now calls the official `bin/code.cmd` CLI. Calling `Code.exe` directly during the initial test did not perform the required CLI installation.
- Marketplace could not supply `rooveterinaryinc.roo-cline@3.54.0`. An existing matching VSIX was preserved and successfully used in the rebuild. The persistent cache is required for this pinned artifact while Marketplace remains unavailable.
- Added a reusable VSIX preservation helper and an offline cache inventory that distinguish local integrity from independent publisher authenticity.

## Remaining boundaries

- A real classroom C-drive restore was not initiated or independently verified. Restarted conversation retention is confirmed, and is recorded separately.
- Full offline Bootstrap is not implemented: Git/uv metadata queries and Python provisioning still require network support. Dependency downloads performed when extensions are first activated are not covered by the 37 VSIX artifacts.
- VSIX identity and local hashes are known, but there is no independently trusted manifest checksum for each VSIX; the inventory correctly keeps their provenance UNVERIFIED.
- The retained daily-use installation has two newer extensions than the pinned snapshot: Claude Code 2.1.319 versus 2.1.301, and Python Environments 1.42.0 versus 1.40.0. The isolated rebuild uses the pinned versions. The daily-use extensions were not downgraded.
- First-time SQLite rollout-path repair and dual-store conversation merging remain manual. They are separate from the already successful conversation retention in the retained installation.
- GitHub, VS Code sync, Codex and MCP authentication may need renewal after a classroom reset.

## Evidence and continuation

Local reports under `output/` include `persistence-check.json`, `offline-cache-report.json`, `vsix-cache-report.json` and `clean-bootstrap.log`; they are ignored by Git. This sanitized acceptance summary is safe to version.

Use `Check-AfterReset.cmd` after the next classroom reset. Follow `docs/C-Drive-Restore.md` for recovery and `docs/Offline-Cache.md` for the remaining offline work. Reopen daily-use VS Code through its portable launcher to inherit the newly added Node PATH.
