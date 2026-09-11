"""Pack Compact battle sprites: shared cell scale, magenta punch, 2-frame guns."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
UNIT = ROOT / "assets" / "units" / "hearthkin"
UNITS = ROOT / "assets" / "units"
SRC = ROOT / "tools" / "sprite_src"
CURSOR_ASSETS = Path(
    r"C:\Users\Komba\.cursor\projects\c-Users-Komba-OneDrive-Documents-GitHub-Empires-of-Yesterday\assets"
)
CELL = 64
PERSON_COLS = 8
LEDGER_CELL = 128

sys.path.insert(0, str(Path(__file__).resolve().parent))
from defringe_compact_sprites import defringe, stats  # noqa: E402


def chromakey(im: Image.Image) -> Image.Image:
    arr = np.array(im.convert("RGBA"))
    rgb = arr[:, :, :3].astype(np.float32)
    a = arr[:, :, 3].astype(np.float32)
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    dist = np.sqrt((r - 255.0) ** 2 + g * g + (b - 255.0) ** 2)
    mag_score = np.minimum(r, b) - g
    key = dist < 118
    key |= (mag_score > 28) & (np.minimum(r, b) > 70) & (g < 140)
    a = np.where(key, 0.0, a)
    mid = (dist >= 118) & (dist < 150) & (a > 0)
    a[mid] *= (dist[mid] - 118.0) / 32.0
    arr[:, :, 3] = np.clip(a, 0, 255).astype(np.uint8)
    arr[arr[:, :, 3] < 24, 0:3] = 0
    arr[arr[:, :, 3] < 24, 3] = 0
    return Image.fromarray(arr, "RGBA")


def bbox(arr: np.ndarray) -> tuple[int, int, int, int]:
    a = arr[:, :, 3]
    ys, xs = np.where(a > 16)
    if len(xs) == 0:
        h, w = a.shape
        return (0, 0, w, h)
    return (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)


def fit_cells(cells: list[np.ndarray], size: int) -> list[Image.Image]:
    """Same body height across poses; feet on the bottom; clamp to the cell."""
    boxes = [bbox(c) for c in cells]
    target_h = max(b[3] - b[1] for b in boxes)
    target_h = max(target_h, 1)
    out: list[Image.Image] = []
    for cell, (x0, y0, x1, y1) in zip(cells, boxes):
        crop = Image.fromarray(cell[y0:y1, x0:x1], "RGBA")
        h = max(crop.height, 1)
        scale = target_h / float(h)
        nw = max(1, int(round(crop.width * scale)))
        nh = max(1, int(round(crop.height * scale)))
        if nw > size:
            s2 = size / float(nw)
            nw = size
            nh = max(1, int(round(nh * s2)))
        if nh > size:
            s2 = size / float(nh)
            nh = size
            nw = max(1, int(round(nw * s2)))
        im = crop.resize((nw, nh), Image.Resampling.NEAREST)
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        canvas.paste(im, ((size - nw) // 2, size - nh), im)
        out.append(canvas)
    return out


def pack_row(fitted: list[Image.Image], cell: int) -> Image.Image:
    n = len(fitted)
    row = Image.new("RGBA", (cell * n, cell), (0, 0, 0, 0))
    for i, im in enumerate(fitted):
        row.paste(im, (i * cell, 0), im)
    return defringe(row)


def split_row(im: Image.Image, cols: int) -> list[np.ndarray]:
    arr = np.array(defringe(chromakey(im)))
    h, w = arr.shape[:2]
    cw = w // cols
    return [arr[:, i * cw : (i + 1) * cw if i < cols - 1 else w] for i in range(cols)]


def punch_magenta(im: Image.Image) -> Image.Image:
    arr = np.array(im.convert("RGBA"))
    rgb = arr[:, :, :3].astype(np.float32)
    a = arr[:, :, 3]
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    score = np.minimum(r, b) - g
    punch = (a > 16) & (score > 20) & (np.minimum(r, b) > 50) & (g < 140)
    # Dark chroma-key leftovers: low G, R and B both up, not a hot muzzle (R>>B).
    punch |= (a > 8) & (g < 22) & (r > 50) & (b > 30) & (np.abs(r - b) < 80)
    arr[punch] = 0
    arr[a < 16, 0:3] = 0
    return Image.fromarray(arr, "RGBA")


def teal_to_rust(im: Image.Image) -> Image.Image:
    """Map teal armor to the Compact hostile rust. Leave muzzle fire and brown iron."""
    arr = np.array(im.convert("RGBA"))
    r = arr[:, :, 0].astype(np.float32)
    g = arr[:, :, 1].astype(np.float32)
    b = arr[:, :, 2].astype(np.float32)
    a = arr[:, :, 3]
    teal = (a >= 16) & (b > r + 18) & (b > 50) & (g > 30)
    out = arr.copy()
    out[teal, 0] = np.clip(b[teal] * (201.0 / 186.0), 0, 255).astype(np.uint8)
    out[teal, 1] = np.clip(g[teal] * (46.0 / 122.0), 0, 255).astype(np.uint8)
    out[teal, 2] = np.clip(r[teal] * 0.5 + 2.0, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def pack_person(name: str) -> None:
    src_f = UNIT / f"{name}_friendly_sheet.png"
    src_h = UNIT / f"{name}_hostile_sheet.png"
    fitted_f = fit_cells(split_row(Image.open(src_f), PERSON_COLS), CELL)
    friendly = pack_row(fitted_f, CELL)
    friendly.save(src_f, "PNG")
    fitted_h = fit_cells(split_row(Image.open(src_h), PERSON_COLS), CELL)
    hostile = pack_row(fitted_h, CELL)
    hostile.save(src_h, "PNG")
    print(f"repacked {name} {friendly.size}  {stats(friendly)} | {stats(hostile)}")


def _ledger_src(name: str) -> Path:
    for folder in (SRC, CURSOR_ASSETS):
        p = folder / name
        if p.exists():
            return p
    raise SystemExit(f"missing {name} under {SRC} or {CURSOR_ASSETS}")


def pack_ledger() -> None:
    idle = np.array(chromakey(Image.open(_ledger_src("ledger_idle_friendly.png"))))
    fire = np.array(chromakey(Image.open(_ledger_src("ledger_fire_friendly.png"))))
    fitted = fit_cells([idle, fire], LEDGER_CELL)
    friendly = pack_row(fitted, LEDGER_CELL)
    dest_f = UNIT / "ledger_pieces_friendly_sheet.png"
    dest_h = UNIT / "ledger_pieces_hostile_sheet.png"
    friendly = punch_magenta(friendly)
    friendly.save(dest_f, "PNG")
    hostile = punch_magenta(defringe(teal_to_rust(friendly)))
    hostile.save(dest_h, "PNG")
    idle_stamp = punch_magenta(fitted[0])
    idle_stamp.save(UNIT / "ledger_pieces_friendly.png", "PNG")
    punch_magenta(defringe(teal_to_rust(idle_stamp))).save(UNIT / "ledger_pieces_hostile.png", "PNG")
    print(f"wrote ledger sheet {friendly.size}  {stats(friendly)} | {stats(hostile)}")


def punch_stamp(path: Path) -> None:
    im = defringe(chromakey(Image.open(path)))
    im.save(path, "PNG")
    print(f"punched {path.name} {im.size}  {stats(im)}")


def main() -> int:
    SRC.mkdir(parents=True, exist_ok=True)
    mode = sys.argv[1] if len(sys.argv) > 1 else "--ledger"
    if mode in ("--ledger", "--all"):
        pack_ledger()
    if mode == "--ledger":
        return 0
    for name in ("stovebreakers", "ash_wardens", "walk_mappers", "ceiling_clerks"):
        pack_person(name)
    punch_stamp(UNIT / "rolling_hearths_friendly.png")
    punch_stamp(UNIT / "rolling_hearths_hostile.png")
    for p in (
        UNITS / "soldier_friendly_sheet.png",
        UNITS / "soldier_hostile_sheet.png",
        UNITS / "bomber_friendly.png",
        UNITS / "bomber_hostile.png",
    ):
        if p.exists():
            punch_stamp(p)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
