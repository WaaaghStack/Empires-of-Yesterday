# Empires of Yesterday

Xenopurge-style 2D real-time tactical command prototype with a **branching campaign run loop** (Godot 4.6+).

## How to play — Campaign (primary)

1. **Main Menu** → **New Planet Run** (or **Daily Seed Run**).
2. **Orbital Carrier** — configure each squad (presets, traits, stances, mutators).
3. **Launch** → **Navigation** screen: pick your path through combat sectors (W/S, Enter).
4. Each node loads a **smaller tactical mission** (8–18 rooms); squad HP and injuries carry over.
5. Clear sectors until you reach and beat the **Overmind Sanctum** (boss node) → **Run Summary**.

### Navigation controls

- **W / S** — move cursor between available sectors  
- **Enter** — commit and launch that mission  
- **Esc** — abort run  

### Commander controls (tactical)

- **F1 / F2 / F3** — select Alpha / Bravo / Charlie  
- **O** objective doctrine, **S** search & destroy, **E** extract  
- Real-time combat (no global pause)  

### Boss finale

The boss sector uses a **large** map with nest hives + **Overmind** (same purge flow as legacy planet finale, but as one mission in the campaign).

### Campaign depth

- **Navigation map** shows sector type, mutators (or classified until intel), and reward hints.
- **Rest / Armory / Intel Broker** nodes skip combat (heal, spend biomass, reveal intel).
- After each combat sector, pick a **sector reward** (evolution upgrade, heal, or biomass).
- **Ascension** stacks extra mutators on new runs after beating the campaign; **codex achievements** grant tokens.

## Legacy modes (Main Menu → More…)

- **Legacy 4-op run** — linear ops with Between-Op Hub  
- **Legacy planet run** — single persistent 12–16 room facility (old default)  

## Headless QA

```bash
godot --headless --path . res://qa_runner.tscn
```

See [PERFORMANCE.md](PERFORMANCE.md) for tuning notes (multiple smaller maps per campaign vs one planet hull).
