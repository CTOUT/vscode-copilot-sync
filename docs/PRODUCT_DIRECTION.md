# Product Direction: Cross-Agent Asset Management

**Reviewed:** 2026-10-22

## Summary

Evolve this project from a VS Code- and Awesome Copilot-specific synchronization toolkit toward a cross-agent asset manager. It should help individuals and teams discover, select, install, track, and safely update reusable agent assets across supported IDEs, CLIs, and agent workspaces.

The project should manage the _materials agents use_—such as skills, instructions, agent definitions, and MCP server configurations. It should not become an agent runtime, model provider, or multi-agent orchestration platform.

This is a product direction, not a claim that the current scripts already support these targets. The first cross-target scope should be validated with users before committing to a broad rewrite.

## Why the scope is changing

The original product addressed a real gap: collecting resources from Awesome Copilot and putting selected resources into VS Code or a repository with recommendations and lifecycle management. That gap is narrowing as agent products add native discovery, plugin installation, and update workflows.

The landscape now spans products and surfaces such as VS Code and GitHub Copilot, Kiro, Google Antigravity, Cursor, Claude Code, Warp, and command-line agents. Agent work is also moving into persistent runtimes and orchestration environments, such as [KiroCrew](https://github.com/kirodotdev/KiroCrew). These are not all the same kind of product: an IDE, CLI, plugin catalog, and persistent agent runtime have different responsibilities and configuration models.

The opportunity is the layer between asset publishers and the tools that consume those assets: a useful, trustworthy way to manage assets across multiple sources and targets without pretending every target behaves identically.

## Product thesis

> A developer or team should be able to choose useful agent assets from trusted sources, apply them to the environments they use, and understand their provenance, compatibility, and update history.

### Intended users

- Developers who use more than one agent IDE or CLI.
- Teams that need a repeatable set of agent customizations across repositories and developer environments.
- Maintainers who publish agent assets and want to distribute portable components with target-specific additions.

### Core user outcomes

- Discover assets from more than one source, including Awesome Copilot, Git repositories, and team-managed registries.
- Understand what an asset does, where it came from, what it needs, and which targets can use it.
- Install at repository or user scope with predictable, reviewable changes.
- Track installed versions or source revisions, inspect updates, preserve local edits, and remove only managed assets.
- Share a consistent setup without copying secrets or silently changing target-specific behavior.

## Portability model

Portability is a spectrum. The product should report compatibility honestly and preserve the original asset when possible.

### Portable content

- **Agent Skills** are the strongest shared content format. Their directory and `SKILL.md` convention is supported by multiple agent products, although supported locations and optional metadata can differ.
- **MCP** is a shared protocol for exposing tools and context. It does not make server configuration, authentication, secrets, installation, or permissions identical across clients.
- **`AGENTS.md`** and similar instruction files can be read by multiple tools, but rule precedence, discovery paths, and additional vendor-specific instruction files vary.

### Portable packaging

[Agent Plugins v1](https://agent-plugins.org/specification) provides a useful packaging standard for Skills and MCP servers. Its portable core intentionally does not standardize custom agents, hooks, or rules. Clients can add those through namespaced extensions or their own package formats.

### Target-specific behavior

Custom agents, hooks, instruction activation rules, MCP configuration formats, credentials, and plugin marketplaces remain target-specific in important ways. A target adapter may place files, configure native package formats, or transform an asset, but it must not claim that a transformation is lossless unless it has been verified.

Use explicit compatibility outcomes:

- **Native:** Install the source asset in a format the target supports.
- **Adapted:** Generate or transform target-specific files and report any omitted or changed behavior.
- **Unsupported:** Explain why the asset cannot be safely installed for that target.

## Product boundaries

The project should:

- Manage asset sources, metadata, installation state, revisions, and target adapters.
- Treat Awesome Copilot as an important first-class source, not the only source.
- Prefer existing open standards and native package formats over a competing universal schema.
- Make changes reviewable and reversible, including explicit handling of locally modified files.
- Keep secrets and machine-specific credentials outside shared assets and manifests.

The project should not:

- Reimplement each vendor's marketplace or compete on catalog size alone.
- Build or host an agent execution runtime, model gateway, persistent memory system, or multi-agent orchestration layer.
- Automatically translate every agent definition, hook, permission model, or MCP configuration into every target.
- Replace standards such as Agent Skills, MCP, Agent Plugins, or target-native configuration with an all-encompassing canonical format.

Agent runtimes and orchestrators—including projects such as KiroCrew—may become consumers or integration targets. They are adjacent to the asset-management problem, not the same product category.

## Strategic principles

1. **Separate sources from targets.** Catalog discovery should not depend on a single editor, vendor, or repository.
2. **Use standards before inventing formats.** Preserve standard packages as packages; add adapters only where real compatibility gaps exist.
3. **Expose fidelity and provenance.** Show source revision, target, adaptation, setup requirements, and unsupported features before installation.
4. **Make installation safe.** Preview changes, preserve local edits, validate paths, avoid embedding secrets, and track exactly what the tool manages.
5. **Keep the first product slice narrow.** Prove multi-source, multi-target lifecycle management before adding more ecosystems or rewriting the implementation language.

## Initial validation hypothesis

A practical first slice to test with users is:

- Keep Awesome Copilot as a supported source while adding a generic Git-based source model.
- Manage standard Agent Plugin packages and standalone Agent Skills without converting their contents unnecessarily.
- Provide a small number of target adapters selected from actual user workflows, rather than attempting broad support for every named product at once.
- Record source, revision, target, installed files, and local modifications so updates can be reviewed and applied safely.
- Support both repository-scoped and user-scoped installations where the target provides those scopes.

This slice is a hypothesis, not a committed implementation plan. Select the first targets only after confirming that users regularly need to move the same assets between them and that native installers do not already cover their workflow.

## Validation questions

Before a major rewrite or broad adapter effort, answer these questions with developers and teams who use multiple agent environments:

1. Which combinations of IDEs, CLIs, and agent runtimes do they actually use in the same workflow?
2. What do they currently copy, duplicate, or manually update between those environments?
3. Is their main pain discovery, installation, team consistency, version pinning, safe updates, or compatibility conversion?
4. Which assets do they share, and which are inherently target-specific?
5. Would they use a shared repository manifest or registry, and who should approve its changes?
6. Which native marketplaces or importers already solve their problem adequately?

Evidence of demand should include repeated cross-target usage, reduced setup or maintenance effort, and user preference for this manager over native per-target workflows. If users only need one native marketplace, keep this project focused on its existing niche or retire the broader product thesis.

## Current implementation versus direction

The current repository is a PowerShell 7 toolkit that syncs Awesome Copilot and installs selected resources into Copilot-oriented repository and user locations. It already provides repository-aware recommendations, subscription tracking, safe update/removal workflows, and cross-platform execution through PowerShell 7.

The roadmap's canonical asset schema and registry ideas are exploratory foundations; they do not by themselves establish cross-target compatibility. The current source and target integrations should remain clearly described until additional adapters have been implemented and tested.

A rewrite from PowerShell to Node.js, Go, or Rust should be considered only if measured installation friction or distribution requirements justify it. Changing the runtime or project name is not a substitute for validating the product thesis.

## Ecosystem references

- [Awesome Copilot](https://awesome-copilot.github.com/) — community catalog of Copilot agents, skills, instructions, plugins, and related assets.
- [VS Code agent customizations](https://code.visualstudio.com/docs/agent-customization/overview) — native customization management and discovery.
- [VS Code agent plugins](https://code.visualstudio.com/docs/agent-customization/agent-plugins) — plugin installation, marketplaces, and supported components.
- [Agent Skills specification](https://agentskills.io/specification) — portable skill file format.
- [Agent Plugins specification](https://agent-plugins.org/specification) — portable plugin package contract.
- [Kiro Skills](https://kiro.dev/docs/skills/) and [Kiro Powers](https://kiro.dev/docs/powers/) — skills and plugin-style packaging in Kiro.
- [Antigravity plugins](https://antigravity.google/docs/plugins) — Antigravity's plugin layout and components.
- [Cursor plugins](https://cursor.com/docs/plugins) — Agent Plugins support and Cursor-specific packaging.
- [Claude Code plugins](https://code.claude.com/docs/en/plugins) — Claude Code plugin and marketplace workflows.
- [Warp agent skills](https://docs.warp.dev/agents/capabilities/skills/) — skill discovery across multiple skill-directory conventions.
- [KiroCrew](https://github.com/kirodotdev/KiroCrew) — example of an adjacent persistent agent workspace and orchestration runtime.

Product capabilities and marketplace status change quickly. Recheck target documentation before implementing or advertising an adapter.
