# Roadmap & Backlog

## Overview

This backlog tracks outstanding tasks for the project's evolution from a VS Code utility into a cross-platform, platform-agnostic AI agent and context manager.

> For completed features, bug fixes, and historical milestones (Phases 1–3), see [CHANGELOG.md](CHANGELOG.md).

### Architectural Strategy on Shell Environments

- **Full Bash Engine Rewrite:** Evaluated and rejected. Maintaining parallel ~2,500-line PowerShell and Bash engines creates a dual-maintenance trap. macOS ships with Bash 3.2 (2007, lacking associative arrays and modern features), Zsh is the default macOS shell, and external tools like `jq` are not installed by default.
- **Adopted Strategy:**
  1. _Near-Term (v1.x):_ Unified PowerShell 7 core engine with a thin POSIX `/bin/sh` wrapper (`run.sh`) for frictionless execution on macOS and Linux (completed).
  2. _Long-Term (v3.0):_ Leapfrog Bash entirely into a compiled native binary (Go/Rust) or TypeScript CLI (`npx`), providing true zero-dependency cross-platform execution (Phase 5).

---

## Phase 4: Platform-Agnostic Context & Target Adapters

> **Scope:** High difficulty · Target: v2.0

### 4.1 Translation Layer / Target Adapters

- **Status:** Planned
- **Difficulty:** High (1–2 days)
- **Dependencies:** Canonical Asset Schema (completed in `schemas/canonical-asset.schema.json` and `scripts/lib/AssetSchema.ps1`)
- **Objective:** Decouple upstream resource ingestion from specific editor installations via a canonical asset model and target adapter interface:
  - **Instruction / Rule:** Passive guidelines and repo standards
  - **Agent / Persona:** Subagents with explicit roles, identity, tools, and prompts
  - **Skill:** Executable capability bundles (`SKILL.md`, scripts, references)
  - **Tool / Provider:** MCP server definitions and environment configs
- **Target Adapters:**
  - **GitHub Copilot:** `.github/agents/`, `.github/instructions/`, `.github/skills/`, and user prompts
  - **Cursor:** `.cursor/rules/*.mdc` and `.cursorrules`
  - **Claude Code:** `CLAUDE.md` and user tool definitions
  - **Open Standards:** Canonical `AGENTS.md` and `llms.txt`
  - **Cline / Roo Code / Continue:** `.clinerules`, `mcp.json`, and custom modes

### 4.2 Decentralized Registries via `llms.txt`

- **Status:** Planned
- **Difficulty:** Medium-High (1–2 days)
- **Dependencies:** 4.1, `scripts/lib/Config.ps1`
- **Objective:** Treat `llms.txt` as a discovery manifest and registry entrypoint. Allow adding arbitrary upstream endpoints (public repositories, internal enterprise networks, or team URLs) serving an `llms.txt` file, enabling asset discovery and synchronization without full git clones or centralized package registries.

---

## Phase 5: Rebranding & Standalone Zero-Dependency CLI

> **Scope:** High difficulty · Target: v3.0

### 5.1 Rebranding & Universal CLI Architecture

- **Status:** Conceptual
- **Difficulty:** Medium (1 day)
- **Dependencies:** Phase 4
- **Objective:** Rebrand project (e.g. `agent-sync`, `ctxmgr`, or `ai-context-sync`) and align CLI verbs around universal actions (`install`, `sync`, `search`, `remove`).

### 5.2 Standalone Compiled Binary or Node CLI Distribution

- **Status:** Conceptual
- **Difficulty:** High (2–3 days)
- **Dependencies:** 5.1
- **Objective:** Completely remove the PowerShell and shell runtime dependency on user machines.
- **Implementation Options:**
  - **Option A (Node/TypeScript CLI):** Distribute via `npx agent-sync`. Instant zero-install usage for all developers with Node.js; rich terminal UI via `@inquirer/prompts`.
  - **Option B (Compiled Binary in Go/Rust):** Single portable executable for macOS (ARM64/x64), Linux (x64/ARM64), and Windows. Distribute via Homebrew (`brew install`), Winget, and direct GitHub Releases.

---

## Superseded / Deprecated Items

| Original Item                               | Status                | Reason                                                                                                                                                                                                 |
| :------------------------------------------ | :-------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **OGV opens behind other windows**          | Superseded            | Consolidated into terminal picker (`Show-FzfPicker` / console menu). A cross-platform terminal selector renders Windows UIPI focus workarounds obsolete.                                               |
| **Selection without `Out-GridView`**        | Merged                | Consolidated into terminal picker (`Show-FzfPicker` / console menu).                                                                                                                                   |
| **Full Bash/Zsh engine rewrite**            | Rejected / Deprecated | Dual-script maintenance trap, lack of native JSON/associative array support in macOS default Bash 3.2, and external `jq` requirements. Replaced by `run.sh` (thin wrapper) and **5.2** (compiled CLI). |
| **PowerShell module packaging (PSGallery)** | Superseded            | Replaced by **5.2 (Standalone CLI / npm / binary distribution)**. Distributing via native binary or `npx` provides broader cross-platform adoption than a PSGallery module on Unix systems.            |
