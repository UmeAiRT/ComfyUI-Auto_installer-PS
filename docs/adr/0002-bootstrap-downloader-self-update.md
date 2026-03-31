# ADR-0002: Bootstrap-Downloader.ps1 Self-Update

**Date**: 2026-03-23
**Status**: accepted
**Deciders**: airoku, Claude

## Context

`Bootstrap-Downloader.ps1` is responsible for downloading all installer scripts
from the configured fork/branch. However, it was never included in its own
`$filesToDownload` list. The bat launcher only downloads `Bootstrap-Downloader.ps1`
when the file is completely absent (broken install). For any existing install with a
working but stale copy, bug fixes pushed to the repo would never be delivered — the
old version would run indefinitely. This was discovered when a permissions-handling
fix needed to reach existing installs and could not.

## Decision

Add `Bootstrap-Downloader.ps1` as the last entry in its own `$filesToDownload`
list. The entry is intentionally last so the current run completes with the existing
version; the downloaded replacement takes effect on the next bootstrap run.

## Alternatives Considered

### Alternative 1: Manual update instructions
- **Pros**: No code change required
- **Cons**: Not discoverable; requires users to read release notes; error-prone
- **Why not**: Contradicts the script's own purpose of being self-healing

### Alternative 2: Version check + conditional re-download
- **Pros**: Could skip the download if already current, saving a network round-trip
- **Cons**: Requires embedding and maintaining a version string in the script
- **Why not**: The download is cheap; adding versioning is disproportionate complexity

### Alternative 3: Bat re-downloads Bootstrap-Downloader.ps1 on every run
- **Pros**: Ensures even the very first bootstrap invocation gets the latest version
- **Cons**: Requires restructuring the bat's "download if missing" guard; introduces a
  mid-run version switch risk (bat starts old version, downloads new, which version
  continues?)
- **Why not**: The one-run lag of the self-update approach is acceptable and avoids
  the mid-run version mismatch hazard

## Consequences

### Positive
- Self-healing: fixes propagate to all existing installs on the next bootstrap run
- Minimal change: one list entry added
- Natural next-run update cycle eliminates mid-run version switch risk

### Negative
- One bootstrap run lag before a fix reaches an existing install

### Risks
- A broken `Bootstrap-Downloader.ps1` pushed to the repo could break subsequent
  bootstraps — mitigated by the same review process that governs all other script
  changes, and by the bat's fallback behaviour if the download itself fails
