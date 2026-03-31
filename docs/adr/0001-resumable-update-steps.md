# ADR-0001: Resumable Update Steps via --ResumeFromStep

**Date**: 2026-03-23
**Status**: accepted
**Deciders**: airoku, Claude

## Context

`Update-ComfyUI.ps1` runs 4 sequential steps. Steps 1 and 2 involve git pulls, a
custom-node snapshot save/restore, and a global `cm-cli update all` — collectively
taking several minutes. When a late-step failure occurs (e.g. step 3 Triton install
failing due to a uv flag bug), the user must re-run the entire script from the
beginning. Re-running steps 1 and 2 is wasteful and not risk-free: the snapshot
prompt runs again, `cm-cli update all` re-applies, and any side-effects compound.

## Decision

Add a `-ResumeFromStep [int]` parameter to `Update-ComfyUI.ps1` (and a
`--resume-step N` passthrough in `UmeAiRT-Update-ComfyUI.bat`). Steps numbered
below the given value are skipped with a visible `[SKIP]` notice. The global step
counter is pre-seeded so step banner numbers remain correct throughout the run.

## Alternatives Considered

### Alternative 1: Automatic checkpointing
- **Pros**: Transparent to the user; no manual step identification needed
- **Cons**: Requires persisting checkpoint state to disk; must handle stale state and partial-write edge cases
- **Why not**: Significant added complexity for a 4-step script with infrequent failures

### Alternative 2: Step-specific bat launchers
- **Pros**: Simple; no new parameters
- **Cons**: Clutters the launcher set; each bat duplicates environment setup logic; harder to keep in sync
- **Why not**: Maintenance burden outweighs benefit

### Alternative 3: Status quo (no resume)
- **Pros**: No code change
- **Cons**: Poor UX; long re-runs with compounding side-effects on late-step failures
- **Why not**: Directly observed real-world pain point

## Consequences

### Positive
- Zero new infrastructure; no persistent state files
- Explicit and user-visible: the step number is printed in the failure output, so the user always knows what to pass
- No risk of stale state from a previous run

### Negative
- User must identify the failed step number manually (though it is clearly printed)
- Does not retry automatically; user still needs to re-invoke the script

### Risks
- User passes wrong step number and skips work that should have been re-run — mitigated by clear `[SKIP]` output and documentation in the `--help` text
