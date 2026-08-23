---
name: eoy-ui-theme
description: Empires of Yesterday UI/UX and GameTheme conventions for menu, match HUD, command bar, and globe chrome. Use for presentation passes, theme tokens, layout specs, or visual QA — not for new mechanics.
---

# EOY UI theme

## Canon files

- `GameTheme.gd` — tokens / control styles
- `MainMenu.gd` / `MainMenu.tscn` / `MenuHeroGlobe.gd`
- `WorldConquestScreen.gd` / `.tscn` — ribbon, command bar, overlays
- `EarthGlobeMap.gd` — globe entities / feedback
- [DESIGN.md](../../../DESIGN.md) — controls + run loop + teach beats

## Defaults for presentation work

- Prefer **GameTheme** primary vs ghost vs latched (accent border) — avoid ad-hoc modulate tints on icons unless theme defines it.
- Match chrome should stay thin; command tools clustered; no resurrecting **Land Bridge** UI (R1).
- First-run clarity = non-blocking top banners (`RunState.first_run_clarity`); QA harnesses leave it false.
- Deploy pick is part of the run loop (~5 s lock window) — preserve orbit/zoom + land-only lock.

## Spec → build

1. `ui-ux-designer` writes surface specs + acceptance.
2. `coding-architect` implements minimal scene/script diffs.
3. `ui-ux-designer` or `product-manager` QA against acceptance.
4. Optional: `exterminator` for regressions (click targets, mouse filters, pause).

## Out of scope unless story says otherwise

- New mechanics, Rust FFI, pack-format bumps
- Reintroducing roads/bridges/strain UX
- Purple/glow generic redesigns that ignore GameTheme

## Quick acceptance prompts

- Can the player complete menu → deploy → place outpost → inspect without dead controls?
- Does Esc cancel build/paint (and clear deploy lock) as documented?
- Does Battle Over offer Play Again / Same Map / Menu correctly?
