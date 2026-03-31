# ADR-0004: Use DazzleML v0.8.6 (pinned, uv-patched fork) for Triton/SageAttention

**Date**: 2026-03-26
**Status**: accepted
**Deciders**: airoku

## Context

Installing Triton and SageAttention on Windows requires knowing which `triton-windows`
version constraint is compatible with the installed PyTorch build (e.g.
`torch 2.10 → triton-windows>=3.6,<4`) and which pre-built SageAttention wheel URL
matches the CUDA version and PyTorch ABI (e.g.
`sageattention-2.2.0+cu130torch2.9.0andhigher.post4-cp39-abi3-win_amd64.whl`).
This constraint knowledge is not exposed in PyPI metadata — it is embedded in
DazzleML's `comfyui_triton_sageattention.py` installer logic.

DazzleML v0.8.6 also handles VS Build Tools detection (check-only; Phase 1 already
installs them, so this check is redundant but harmless) and falls back gracefully
when packages are already at the correct version.

However, DazzleML internally invokes pip via `python -m pip install`, which conflicts
with the project's uv-first policy. The fix is applied in a fork of the DazzleML
repo; `dependencies.json` points to the fork's tagged release and its SHA-256.

Confirmed in venv test (torch 2.10.0+cu130):
- triton-windows 3.6.0.post26 selected correctly
- sageattention 2.2.0+cu130torch2.9.0andhigher.post4 wheel selected correctly

## Decision

Point `dependencies.json → files.installer_script` at a fork of
`comfyui_triton_sageattention.py` (v0.8.6 base) that replaces all internal
`python -m pip` calls with `uv pip --python <path>`. The download URL and
SHA-256 in `dependencies.json` pin to a specific commit/tag in the fork.
Conda mode continues to bypass DazzleML entirely (it crashes there) and uses
direct `uv pip install` instead.

## Alternatives Considered

### Alternative 1: Direct uv install without DazzleML
- **Pros**: Simpler pipeline, no external script dependency
- **Cons**: Cannot encode PyTorch→Triton constraint mapping or CUDA-specific
  SageAttention wheel URLs without duplicating DazzleML's embedded knowledge
- **Why not**: Would require maintaining a parallel version-constraint table that
  DazzleML already curates and updates

### Alternative 2: Post-download text patch inside Phase 2
- **Pros**: No fork to maintain; patch lives entirely in this repo
- **Cons**: SHA-256 verification runs before the patch, so the stored hash must
  match the unpatched upstream file, making it easy to accidentally verify the
  wrong thing; patching logic in PowerShell is fragile if DazzleML's pip call
  patterns change
- **Why not**: Harder to audit and more brittle than a versioned fork commit

### Alternative 3: Use DazzleML unpatched
- **Pros**: Zero modification required
- **Cons**: Three internal `python -m pip install` calls bypass uv, producing an
  inconsistent and harder-to-audit install environment
- **Why not**: Violates the project's uv-first policy established to ensure
  reproducible, fast, and auditable package operations

## Consequences

### Positive
- Retains DazzleML's curated PyTorch↔Triton constraint knowledge and pre-built
  wheel selection without maintaining it ourselves
- All pip operations (including those inside DazzleML) go through uv, satisfying
  the project-wide uv-first requirement
- SHA-256 pin in `dependencies.json` covers the already-patched fork file —
  no ambiguity about which version is verified

### Negative
- The fork must be kept in sync when DazzleML publishes a new version with new
  PyTorch/CUDA pairings

### Risks
- **DazzleML upstream divergence**: New constraint mappings won't land automatically.
  Mitigation: treat DazzleML version bumps as explicit upgrade tasks; the SHA-256
  pin will fail loudly if the upstream file changes unexpectedly.
- **Conda fallback gaps**: Conda mode skips DazzleML entirely and uses unconstrained
  `uv pip install triton-windows`. If a new PyTorch version requires a specific
  triton-windows pin, Conda mode may install an incompatible version.
  Mitigation: document Conda as best-effort; venv is the recommended install type.
