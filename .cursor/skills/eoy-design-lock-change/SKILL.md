---
name: eoy-design-lock-change
description: Process for changing Empires of Yesterday design locks (R1, A13/F1, F5–F7, A14, R2, etc.). Use when proposing, documenting, or implementing an intentional product rule change — never silent lock breaks.
---

# EOY design lock change

Canon: [DESIGN.md](../../../DESIGN.md) § Design locks, [docs/INDEX.md](../../../docs/INDEX.md)

## Rule

Design locks are product law. Agents must not “fix” intentional asymmetry by coding around a lock without updating DESIGN.md first (or in the same change with explicit PM signoff).

## Procedure

1. **Identify** lock id(s) (e.g. R1, A13/F1, F5, F6, F7, A14, R2).
2. **Propose** — one paragraph: why, player-facing effect, what becomes illegal/obsolete.
3. **PM accept** — `product-manager` (or user) confirms.
4. **Update DESIGN.md** — lock table + any Direction / dictionary rows; bump “Last updated” if present.
5. **Update docs/INDEX.md** short lock index if the summary line changes.
6. **Implement** via `coding-architect` / `data-architect` as needed.
7. **QA** via `eoy-qa-lifecycle`; retarget smokes if filenames/behavior were lock-specific (e.g. ferry vs bridge).

## Output template

```markdown
## Lock change
- IDs:
- From → To:
- Player impact:
- Docs touched:
- Code / QA follow-ups:
```

## Common locks (do not contradict casually)

| ID | Meaning (short) |
|----|-----------------|
| R1 | Roads + land bridges removed; instant structure place |
| A13/F1 | Enemy AI outposts + barracks + hangars (no bridges) |
| F5 | Win ignores units |
| F6 | Unit caps |
| A14 | Bomber no continuous upkeep |
| R2 | Ferry water speed 0.25× |
| F7 | Shockwave visual cap (full economy credit) |
