# ADR-0003: Use `git config --global` for long paths, with idempotent pre-check

**Date**: 2026-03-26
**Status**: accepted
**Deciders**: shinseiko

## Context

Windows imposes a 260-character MAX_PATH limit by default. Git repos with deep
directory structures (common in ComfyUI custom nodes) can fail to clone or
checkout without `core.longpaths = true`. Phase 2 of the installer attempts to
set this configuration before cloning ComfyUI.

The original code used `git config --system core.longpaths true`, which writes
to the system-wide git config. That requires administrator privileges, which
contradicts the project goal of running without elevation. When the command
failed with "Permission denied", the surrounding code printed a success message
unconditionally (the `Write-Log "Configuring Git..."` line ran before the
command, and `Invoke-AndLog -IgnoreErrors` silently swallowed the non-zero exit
code, making the dead outer `catch` block unreachable).

## Decision

Use `git config --global core.longpaths true` (user-level config, no admin
required). Check whether the setting is already `true` before attempting to
write it, and log the actual outcome — skip at verbosity Level 3 if already
set, log success or an actionable warning otherwise.

## Alternatives Considered

### Alternative 1: `git config --system` (original approach)
- **Pros**: Applies to all users on the machine; only needs to be set once
- **Cons**: Requires administrator privileges; fails silently in non-admin
  context; mutates system-wide state, which is inappropriate for a
  self-contained installer
- **Why not**: Contradicts the no-elevation goal and produced a misleading
  success message on failure

### Alternative 2: `git config --local` per cloned repo
- **Pros**: Fully self-contained — affects only the specific repo
- **Cons**: Cannot be set before the repo exists; long-path failures can occur
  during the `git clone` itself, before a local config is writable
- **Why not**: Too late in the lifecycle to prevent the clone from failing

### Alternative 3: Set via Windows Registry (`HKLM\SYSTEM\...LongPathsEnabled`)
- **Pros**: OS-level fix; persistent; covers all tools, not just git
- **Cons**: Requires admin; well outside the scope of a ComfyUI installer
- **Why not**: Excessive blast radius and elevation requirement

## Consequences

### Positive
- Installer runs without requiring elevation, consistent with project goals
- Setting is idempotent: already-configured systems see a quiet `[INFO]` note
  at `-v` verbosity rather than a redundant write
- Outcome is reported accurately: success logs green, failure logs a yellow
  warning with a copy-pasteable remediation command

### Negative
- `--global` writes to `~/.gitconfig`, which is user-scoped rather than
  machine-scoped; other user accounts on the same machine are unaffected

### Risks
- If the user's `~/.gitconfig` is read-only for some reason the warning will
  fire; the user's remediation command (`git config --global core.longpaths
  true`) covers that case explicitly
