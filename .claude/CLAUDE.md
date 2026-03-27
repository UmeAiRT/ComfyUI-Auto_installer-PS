# ComfyUI Auto-Installer - Claude Code Configuration

> **Read `/AGENTS.md` first** - it contains all project conventions, architecture patterns,
> and coding standards. This file only adds Claude-specific configuration.

## Architecture Reference

- **Architecture**: `/docs/codemaps/architecture.md`
- **Backend Scripts**: `/docs/codemaps/backend.md`
- **Data Models**: `/docs/codemaps/data.md`
- **UI Patterns**: `/docs/codemaps/frontend.md`

## Recommended Skills

- **security-review, security-scan**: Critical for installer security
- **python-patterns, python-testing**: ComfyUI custom nodes ecosystem
- **deployment-patterns**: Release process, versioning
- **verification-loop**: Pre-commit quality checks

## Codemap Regeneration

```
# Requires: ECC plugin
/plugin marketplace add affaan-m/everything-claude-code
/plugin install everything-claude-code@everything-claude-code

# Regenerate after structural changes
/everything-claude-code:update-codemaps
```

## Tooling

This project's Claude Code configuration is built on [Everything Claude Code (ECC)](https://github.com/affaan-m/everything-claude-code).
