# ComfyUI Auto-Installer - TODO / Roadmap

> **Context:** This TODO was assembled during an infrastructure review of the installer codebase.
> It captures security findings, reliability improvements, and feature opportunities.
> Intended as a contributor roadmap - not a critique of existing work.

---

## 1. Security

### 1.1 Network Exposure - `--listen` binds 0.0.0.0
- **Files:** `UmeAiRT-Start-ComfyUI.bat:63`, `UmeAiRT-Start-ComfyUI_LowVRAM.bat:63`
- **Issue:** `--listen` with no address defaults to `0.0.0.0:8188`, exposing ComfyUI to the entire network.
- **Fix:** Default to `127.0.0.1`. Let users override via `local-config.json`.

### 1.2 Supply Chain - No Checksum Verification
- **Files:** `Bootstrap-Downloader.ps1` (20 files), `Install-ComfyUI-Phase1.ps1` (multiple downloads), `dependencies.json` (all URLs)
- **Issue:** Every downloaded binary and script is trusted blindly - no SHA256, no GPG.
- **Fix:**
  - Add SHA256 checksums to `dependencies.json` for every download URL.
  - Verify checksums after download, before execution.
  - Investigate GPG signing for releases.
  - Sign commits (contributor-level).

### 1.3 Raw `pip` Usage - 15 Unverified Installs
- **Files:** `Install-ComfyUI-Phase2.ps1` (12 calls), `Update-ComfyUI.ps1` (2 calls), `UmeAiRTUtils.psm1`
- **Issue:** Raw `pip install` with no `--require-hashes`, no constraints file, no lockfile.
- **Fix:**
  - Migrate all pip calls to `uv pip` (see section 2).
  - Support user-supplied `constraints.txt` for pinning.
  - Add hash verification where feasible.

### 1.4 DazzleML Script - Downloaded and Executed Unverified
- **Files:** `Install-ComfyUI-Phase2.ps1:385`, `Update-ComfyUI.ps1:152-156`
- **Issue:** Third-party script downloaded fresh every run and executed without verification. Sources wheels from woct0rdho (4th-party relative to us).
- **Fix:** Replace entirely (see section 3).

### 1.5 `Invoke-Expression` with Dynamic Strings
- **File:** `UmeAiRTUtils.psm1:106, 174-176`
- **Issue:** `Invoke-Expression` with constructed strings is a code injection vector.
- **Fix:** Replace with `&` operator or `Start-Process` with explicit argument arrays.

### 1.6 Bootstrap Overwrites User Config
- **File:** `Bootstrap-Downloader.ps1`
- **Issue:** Every install/update overwrites `dependencies.json`, `custom_nodes.csv`, `snapshot.json`, and all scripts from git. User customizations are destroyed.
- **Fix:** Introduce `local-config.json` (see section 5) that is never overwritten. Merge strategy for dependencies.

### 1.7 `repo-config.json` - Undocumented, Not Bootstrapped
- **File:** `repo-config.json.example`
- **Issue:** `.example` file exists in repo but is not downloaded by bootstrapper. Not mentioned in README. Users who discover it (e.g., fork users) get no guidance.
- **Fix:** Document in README. Bootstrap the `.example` file. Fold into `local-config.json`.

### 1.8 Pickle/Tensor Model Scanner
- **Issue:** Downloaded model files (`.safetensors`, `.ckpt`, `.pt`) could contain malicious payloads, especially pickle-based formats.
- **Fix:** Integrate a lightweight scanner that detects unsafe methods without loading tensors. Evaluate open-source options.

### 1.9 Admin Privilege Audit - Principle of Least Privilege
- **File:** `Install-ComfyUI-Phase1.ps1:57-174`
- **Current admin operations:**
  1. **Long Paths registry key** (lines 82-91)
  2. **VS Build Tools installation** (lines 94-120)
  3. **`git config --system`** in `Install-ComfyUI-Phase2.ps1:108` (should be `--global`)
- **Fix:**
  - **Long Paths:** Do not elevate. Provide user-facing copy-pasteable command or a small signed batch file the user runs themselves.
  - **VS Build Tools:** May be unnecessary (see section 3.2). If kept, detect existing VS installations (Pro/Enterprise/Community), not just hardcoded BuildTools path.
  - **git config --system to --global:** `--system` is logically wrong for per-user installer config. (See Phase2 line 108)
  - **Goal:** Zero admin elevation required for standard install path.

---

## 2. Package Management - Migrate to UV

### 2.1 UV as Default Package Manager
- **Issue:** pip is slower, less secure, worse dependency resolution.
- **Fix:**
  - Default to `uv` for all package operations.
  - No pip fallback option - UV is the path forward.
  - Create venv with `uv venv` in both Light and Full modes.
  - Note: `uv pip` is not 100% flag-compatible with pip - audit each call for incompatible switches.

### 2.2 Legacy Migration Path
- **Issue:** Existing users upgrading from pip-based installs.
- **Fix:**
  - Detect existing pip venv during upgrade.
  - Offer migration to UV-managed environment.
  - Document migration path clearly.

### 2.3 Constraints File Support
- **Fix:** Allow users to place a `constraints.txt` that gets applied to all `uv pip install` calls. Enables pinning without forking config.

---

## 3. DazzleML Replacement

### 3.1 Current Usage is Minimal
- **Files:** `Install-ComfyUI-Phase2.ps1:385,398`, `Update-ComfyUI.ps1:156`
- **Finding:** We only use two flags: `--install --non-interactive` and `--upgrade --non-interactive`.
- **Not using:** Custom nodes, backup, dry-run, build tools management, venv management, PyTorch management.
- **Fix:** Replace with direct installation:
  1. Maintain a version mapping (PyTorch version to SageAttention wheel URL + triton-windows version).
  2. `uv pip install` SageAttention from woct0rdho GitHub Releases.
  3. `uv pip install triton-windows` from PyPI (bundles own CUDA toolchain + TinyCC).

### 3.2 VS Build Tools May Be Unnecessary
- **Finding:** woct0rdho SageAttention README states pre-built wheels need NO VS/CUDA toolkit. `triton-windows` on PyPI bundles its own CUDA toolchain and TinyCC compiler.
- **Fix:** If DazzleML is replaced with direct wheel installs, VS Build Tools may be eliminable entirely. Validate with testing.

### 3.3 Compiler Toolchain Support (If Needed)
- **If** compilation is still required for any dependency:
  - Detect existing toolchains: VS Pro/Enterprise/Community, VS Build Tools, clang-cl (MSVC-compatible drop-in), MinGW/GCC.
  - Let users specify preferred toolchain in `local-config.json`.
  - clang-cl is a drop-in replacement for MSVC cl.exe - support it.
  - Only prompt for VS Build Tools install as last resort.

### 3.4 Track astral-sh Pyx
- **Context:** woct0rdho is tracking astral-sh Pyx project for future PyPI variant support. When Pyx lands, SageAttention wheels may become installable directly from PyPI with platform variants.
- **Action:** Monitor and adapt when available.

---

## 4. Dependency Conflicts and Deprecation

### 4.1 `pynvml` vs `nvidia-ml-py` Conflict
- **File:** `dependencies.json` - line 42: `nvidia-ml-py`, line 51: `pynvml`
- **Issue:** Both packages occupy the same namespace. `pynvml` causes import conflicts. Crystools (which installs `pynvml` as a dependency) works fine with `nvidia-ml-py`.
- **Fix:** Remove `pynvml` from dependencies. Pre-emptively uninstall it after Crystools installation, or use constraints to prevent it.

### 4.2 Deprecation Warnings Audit
- **Issue:** Startup shows warnings about deprecated code/imports. Possible cruft from old package versions persisting through updates.
- **Fix:** Thorough audit of all deprecation warnings. Identify source packages, update or replace as needed.

### 4.3 `custom_nodes.csv` - Effectively Dead Code
- **File:** `custom_nodes.csv`
- **Issue:** Overwritten every update by bootstrap. Only used as fallback when `snapshot.json` is missing - which never happens in practice since snapshot.json is always present.
- **Fix:** Either remove the CSV fallback path or make it genuinely useful (e.g., user-extensible additions that merge rather than overwrite).

---

## 5. Configuration Architecture - `local-config.json`

### 5.1 Unified Local Config
- **Issue:** Settings are scattered across `repo-config.json`, hardcoded values in scripts, and batch file arguments.
- **Fix:** Introduce `local-config.json` as the single user-local config file:
  - listen_address (default: 127.0.0.1)
  - listen_port (default: 8188)
  - package_manager (default: uv)
  - compiler_toolchain (default: auto)
  - gh_user, gh_reponame, gh_branch
  - long_paths_enabled
- **Critical:** This file must NEVER be overwritten by bootstrap/update. Add to `.gitignore`. Bootstrap creates it only if missing (from a `.example` template).

### 5.2 Deprecate `repo-config.json`
- Migrate its 3 fields (`gh_user`, `gh_reponame`, `gh_branch`) into `local-config.json`.
- Keep backward compatibility during transition (read old file if new one missing).

---

## 6. Reliability and Error Handling

### 6.1 Junction Creation - Unchecked
- **File:** `Install-ComfyUI-Phase2.ps1:166`
- **Issue:** Junction creation does not verify success.
- **Fix:** Check return value; fail loudly if junction was not created.

### 6.2 `SilentlyContinue` Hiding Failures
- **File:** `Install-ComfyUI-Phase2.ps1:148-156`
- **Issue:** `-ErrorAction SilentlyContinue` may hide real problems.
- **Fix:** Replace with explicit error handling. Log errors even if continuing.

### 6.3 Git Pull - No Conflict Handling
- **File:** `Update-ComfyUI.ps1:90`
- **Issue:** `git pull` with no conflict resolution strategy.
- **Fix:** Detect conflicts, notify user, offer resolution options.

### 6.4 `Save-File` Assumes Existing Files Valid
- **File:** `UmeAiRTUtils.psm1:149-152`
- **Issue:** If a file already exists at the target path, it is assumed valid/complete.
- **Fix:** Verify file integrity (size, checksum) before skipping download.

---

## 7. Code Quality

### 7.1 `git config --system` to `--global`
- **File:** `Install-ComfyUI-Phase2.ps1:108`
- **Issue:** `--system` modifies machine-wide git config, requiring admin. The installer is per-user - `--global` is correct.

### 7.2 VS Build Tools Detection - Hardcoded Path
- **File:** `Install-ComfyUI-Phase1.ps1`, `dependencies.json:12`
- **Issue:** Only checks `C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools`. Misses VS Professional, Enterprise, Community editions.
- **Fix:** Use `vswhere.exe` to detect any VS installation with C++ workload.

### 7.3 URL Construction Without Validation
- **File:** `Bootstrap-Downloader.ps1:33`
- **Issue:** URL built from user parameters without sanitization.
- **Fix:** Validate parameters before URL construction.

---

## 8. Documentation

- [ ] Document `repo-config.json` (and eventual `local-config.json`) in README
- [ ] Document listen address configuration and security implications
- [ ] Document UV migration for existing users
- [ ] Document compiler toolchain options
- [ ] Add security policy (SECURITY.md) for reporting vulnerabilities
- [ ] Document the junction architecture for contributors

---

## 9. Testing

- [ ] Establish Pester test suite for PowerShell scripts
- [ ] Test matrix: Light mode, Full mode, existing Python, different drives, upgrade paths
- [ ] Test UV migration from existing pip installs
- [ ] Test DazzleML replacement with direct wheel installs
- [ ] Test with/without VS Build Tools installed
- [ ] Test long paths prompt flow (user-facing, no elevation)
- [ ] Validate all checksums in CI

---

## 10. Future Features

### 10.1 Container Support
- **Issue:** No Docker/container support. Limits deployment to bare-metal Windows. Cloud, production, and multi-GPU setups benefit enormously from containerization.
- **Fix:**
  - Provide `Dockerfile` and `docker-compose.yml`.
  - Support NVIDIA Container Toolkit for GPU passthrough.
  - Map volumes for models, outputs, custom nodes (preserving junction architecture concept).
  - Environment variables for all `local-config.json` settings.
  - Document container deployment alongside bare-metal.

### 10.2 CI/CD Pipeline
- [ ] GitHub Actions for release signing
- [ ] Automated checksum generation for release artifacts
- [ ] Automated testing on fresh Windows VMs

### 10.3 Release Signing
- [ ] GPG-sign releases
- [ ] Commit signing for contributors
- [ ] Publish public keys in repo

---

## Priority Order (Suggested)

1. **Security blockers:** `--listen 0.0.0.0`, raw pip, `Invoke-Expression`, DazzleML unverified execution
2. **Package management:** UV migration, constraints support
3. **DazzleML replacement:** Direct wheel installs, eliminate middleman
4. **Config architecture:** `local-config.json`, stop overwriting user config
5. **Least privilege:** Eliminate admin elevation, long paths user-facing command
6. **Dependency cleanup:** pynvml conflict, deprecation audit, dead code
7. **Reliability:** Junction checks, error handling, git conflict handling
8. **Documentation and testing:** README updates, Pester suite, test matrix
9. **Future features:** Container support, CI/CD, release signing
