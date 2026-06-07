# Documentation housekeeping

*Created May 23, 2026 — review before deleting anything.*

## Keep (source of truth)

| File | Why |
|------|-----|
| [README.md](README.md) | Player-facing how to play — update when flow/UI changes |
| [EMPIRE_VISION.md](EMPIRE_VISION.md) | North-star fantasy and phase checklist |
| [PERFORMANCE.md](PERFORMANCE.md) | Living tuning notes (fog, hives, pathfind, HUD intervals) |
| [QA_LIFECYCLE.md](QA_LIFECYCLE.md) | When/how to run headless QA |
| [V2_ROADMAP.md](V2_ROADMAP.md) | Next-version plan (discussion draft) |

## Safe to remove or archive

These were useful during implementation but are **out of date** or duplicate info now in code + the docs above.

| File | Why it's stale | Suggested action |
|------|----------------|------------------|
| ~~PHASE1_DECISIONS.md~~ | Removed — superseded by planet runs, Orbital Carrier, hives | **Done** |
| ~~MULTI_SQUAD_DESIGN.md~~ | Removed — features shipped | **Done** |
| ~~UI_UX_REVIEW.md~~ | Removed — pre-tab HUD fix log | **Done** |

## Optional cleanup when deleting

1. Remove broken links from `README.md` / `EMPIRE_VISION.md` if archived files go away.
2. Grep repo for `PHASE1_DECISIONS`, `MULTI_SQUAD_DESIGN`, `UI_UX_REVIEW` and update references.
3. Do **not** delete `PERFORMANCE.md` — it tracks real knobs in `TacticalMap.gd`, `Hive.gd`, etc.

## Not in repo (no action)

- Agent/chat transcripts — not project docs.
- `qa_report.txt` / `logs/` — runtime output, already gitignored where appropriate.
