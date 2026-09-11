"""Punch magenta from generated 8-frame soldier strips and pack even RGBA cells."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC_DIR = Path(
    r"C:\Users\Komba\.cursor\projects\c-Users-Komba-OneDrive-Documents-GitHub-Empires-of-Yesterday\assets"
)
OUT_DIR = ROOT / "assets" / "units"
COLS = 8
CELL = 64


def chromakey(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            dist = ((r - 255) ** 2 + g * g + (b - 255) ** 2) ** 0.5
            if dist < 110.0:
                px[x, y] = (r, g, b, 0)
            elif dist < 140.0:
                na = int(255.0 * (dist - 110.0) / 30.0)
                px[x, y] = (r, g, b, min(a, na))
    return im


def content_bbox(im: Image.Image) -> tuple[int, int, int, int]:
    px = im.load()
    w, h = im.size
    x0, y0, x1, y1 = w, h, 0, 0
    found = False
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 16:
                found = True
                if x < x0:
                    x0 = x
                if y < y0:
                    y0 = y
                if x > x1:
                    x1 = x
                if y > y1:
                    y1 = y
    if not found:
        return (0, 0, w, h)
    pad = 2
    return (max(x0 - pad, 0), max(y0 - pad, 0), min(x1 + 1 + pad, w), min(y1 + 1 + pad, h))


def split_cells(im: Image.Image) -> list[Image.Image]:
    w, h = im.size
    cell_w = w // COLS
    cells: list[Image.Image] = []
    for i in range(COLS):
        crop = im.crop((i * cell_w, 0, (i + 1) * cell_w if i < COLS - 1 else w, h))
        cells.append(crop)
    return cells


def fit_square(im: Image.Image, box: tuple[int, int, int, int], size: int) -> Image.Image:
    cropped = im.crop(box)
    cw, ch = cropped.size
    side = max(cw, ch, 1)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(cropped, ((side - cw) // 2, side - ch))
    return canvas.resize((size, size), Image.Resampling.NEAREST)


def pack(src: Path, dest: Path) -> None:
    im = chromakey(Image.open(src))
    cells = split_cells(im)
    boxes = [content_bbox(c) for c in cells]
    max_w = max(b[2] - b[0] for b in boxes)
    max_h = max(b[3] - b[1] for b in boxes)
    # Keep feet on a shared baseline: use each cell's own bbox width, shared height from max.
    out = Image.new("RGBA", (CELL * COLS, CELL), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        x0, y0, x1, y1 = boxes[i]
        # Expand to shared height so run frames don't hop.
        cy1 = min(cell.size[1], max(y1, y0 + max_h))
        cy0 = max(0, cy1 - max_h)
        cx0 = max(0, x0 - (max_w - (x1 - x0)) // 2)
        cx1 = min(cell.size[0], cx0 + max_w)
        fitted = fit_square(cell, (cx0, cy0, cx1, cy1), CELL)
        out.paste(fitted, (i * CELL, 0))
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest, "PNG")
    print(f"wrote {dest} ({out.size[0]}x{out.size[1]}) from {src.name}")


def main() -> None:
    pack(SRC_DIR / "soldier_friendly_sheet.png", OUT_DIR / "soldier_friendly_sheet.png")
    pack(SRC_DIR / "soldier_hostile_sheet.png", OUT_DIR / "soldier_hostile_sheet.png")


if __name__ == "__main__":
    main()
