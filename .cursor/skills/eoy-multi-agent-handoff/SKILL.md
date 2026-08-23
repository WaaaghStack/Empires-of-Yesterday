---
name: eoy-multi-agent-handoff
description: Coordinates Empires of Yesterday multi-agent work (PM → architect/UI/data → exterminator → PM signoff). Use when a feature spans roles, when spawning Task subagents, or when the user asks for a coordinated agent pass.
---

# EOY multi-agent handoff

## Default pipeline

1. **product-manager** — stories + acceptance + out of scope  
2. Parallel as needed:
   - **ui-ux-designer** — look/feel specs (presentation)
   - **data-architect** — authority / SCD1 / economy truth
   - **coding-architect** — plan + implement
3. **exterminator** — evidence-based review of the diff / failure
4. **product-manager** — accept against stories; gate with `eoy-qa-lifecycle`

Skip roles that do not apply (e.g. pure bugfix may be exterminator → architect only).

## Parent agent duties

When launching a Task subagent:

- Paste **goal**, **constraints**, **file focus**, and **acceptance** (subagents do not see parent chat history).
- Point them at the matching skill (`eoy-qa-lifecycle`, `eoy-scd1-presentation`, `eoy-ui-theme`, `eoy-rust-gdextension`).
- Require a compact return format (plan / findings / done checklist) so the next role can consume it.

## Anti-patterns

- Inventing features mid-pipeline without PM / DESIGN.md update
- Re-prompting the same role with contradictory acceptance
- Claiming done without QA when sim/placement/Rust touched
