---
name: eoy-qa-lifecycle
description: Runs Empires of Yesterday headless QA and smoke tests (qa_runner, ferry/island smokes, Godot 4.6+ path). Use before commits, after propagation/placement/routing/Rust changes, or when verifying a fix.
---

# EOY QA lifecycle

Canon: [QA_LIFECYCLE.md](../../../QA_LIFECYCLE.md)

## When

| Trigger | Action |
|---------|--------|
| Before commit / “done” | `qa_runner.tscn` headless |
| Propagation / flow / Rust sim | QA + ferry smoke; rebuild DLL if Rust src changed |
| Placement / routing | Ferry + island outpost smokes + in-game placement check |
| Godot upgrade | Full QA; watch typed arrays / `class_name` |

## Windows commands (Steam Godot 4.6+)

```powershell
$GODOT = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

& $GODOT --headless --path . res://qa_runner.tscn
& $GODOT --headless --path . -s res://bridge_invasion_smoke_test.gd
& $GODOT --headless --path . -s res://island_outpost_smoke_test.gd
```

- Exit `0` = PASS; see `qa_report.txt` and smoke `*_result.txt` / `*_smoke_result.txt`.
- `bridge_invasion_smoke_test.gd` is **ferry beachhead** under R1 (legacy filename).

## Notes

- Rust parity runs when the GDExtension loads; missing DLL → WARN. Skip with `BATTLE_RUST_COMPARE=0` only when intentional.
- Session logs: `logs/latest_run.txt`.
- If Rust sources changed first: skill `eoy-rust-gdextension`.
