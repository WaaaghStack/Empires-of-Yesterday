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
| [PHASE1_DECISIONS.md](PHASE1_DECISIONS.md) | Describes 8–10 room maps, static ship art, old mission flow — replaced by planet runs (24–32 rooms), Orbital Carrier, hives | **Delete** or move to `docs/archive/PHASE1_DECISIONS.md` |
| [MULTI_SQUAD_DESIGN.md](MULTI_SQUAD_DESIGN.md) | Opens with "design discussion only — no implementation"; 3×4 squads, hives, task board are **already shipped** | **Delete** or archive; fold any still-useful tables into `EMPIRE_VISION.md` |
| [UI_UX_REVIEW.md](UI_UX_REVIEW.md) | Fix log from pre-tab HUD (left comms/roster panel); mission UI is now **right-side tabs** | **Delete** or archive after skimming for any open follow-ups |

## Optional cleanup when deleting

1. Remove broken links from `README.md` / `EMPIRE_VISION.md` if archived files go away.
2. Grep repo for `PHASE1_DECISIONS`, `MULTI_SQUAD_DESIGN`, `UI_UX_REVIEW` and update references.
3. Do **not** delete `PERFORMANCE.md` — it tracks real knobs in `TacticalMap.gd`, `Hive.gd`, etc.

## Not in repo (no action)

- Agent/chat transcripts — not project docs.
- `qa_report.txt` / `logs/` — runtime output, already gitignored where appropriate.
