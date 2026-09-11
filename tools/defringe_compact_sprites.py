"""Punch leftover chroma-key magenta from Compact battle sprites.

The packed sheets already have binary alpha, but JPEG/chroma leftovers left
opaque purple/magenta pixels on the silhouette. The billboard shader keeps
anything with alpha >= 0.35, so those edges read as pink in battle.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
UNIT_DIR = ROOT / "assets" / "units" / "hearthkin"


def _magentaish(r: np.ndarray, g: np.ndarray, b: np.ndarray) -> np.ndarray:
    mag_score = np.minimum(r, b) - g
    dist = np.sqrt((r - 255.0) ** 2 + g * g + (b - 255.0) ** 2)
    dark_purple = (r > 28) & (b > 28) & (g < 48) & (np.abs(r - b) < 55)
    chroma = (mag_score > 16) & (np.minimum(r, b) > 36) & (g < 155)
    # Keep teal/cyan armor (G+B, R lower) and orange hostile paint (R high, B low).
    teal = (g >= 48) & (b > r + 22)
    orange = (r > b + 40) & (b < 90) & (g < r)
    return (dist < 128) | ((chroma | dark_purple) & ~teal & ~orange)


def _adj_transparent(alpha0: np.ndarray) -> np.ndarray:
    adj = np.zeros(alpha0.shape, dtype=bool)
    adj[1:, :] |= alpha0[:-1, :]
    adj[:-1, :] |= alpha0[1:, :]
    adj[:, 1:] |= alpha0[:, :-1]
    adj[:, :-1] |= alpha0[:, 1:]
    return adj


def defringe(im: Image.Image, passes: int = 3) -> Image.Image:
    arr = np.array(im.convert("RGBA"))
    rgb = arr[:, :, :3].astype(np.float32)
    a = arr[:, :, 3].copy()

    for _ in range(passes):
        r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
        mag = _magentaish(r, g, b)
        punch = (a >= 90) & mag & _adj_transparent(a < 90)
        # Near-pure magenta anywhere, even if boxed inside a cell gutter.
        punch |= (a >= 90) & (np.sqrt((r - 255.0) ** 2 + g * g + (b - 255.0) ** 2) < 78)
        if not punch.any():
            break
        a[punch] = 0
        rgb[punch] = 0

    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    mag = _magentaish(r, g, b)
    ring = (a >= 90) & _adj_transparent(a < 90) & mag
    excess = np.maximum(np.minimum(r, b) - g, 0.0)
    rgb[ring, 0] = np.clip(r[ring] - excess[ring] * 0.85, 0, 255)
    rgb[ring, 2] = np.clip(b[ring] - excess[ring] * 0.85, 0, 255)

    a[a < 90] = 0
    rgb[a == 0] = 0
    out = np.dstack([rgb.astype(np.uint8), a])
    return Image.fromarray(out, "RGBA")


def stats(im: Image.Image) -> str:
    arr = np.array(im.convert("RGBA"))
    rgb = arr[:, :, :3].astype(np.float32)
    a = arr[:, :, 3]
    r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
    vis = a >= 90
    vis_mag = vis & _magentaish(r, g, b)
    ring_mag = vis_mag & _adj_transparent(a < 90)
    return f"vis={int(vis.sum()):5d} vis_mag={int(vis_mag.sum()):4d} ring_mag={int(ring_mag.sum()):4d}"


def main() -> int:
    paths = sorted(UNIT_DIR.glob("*.png"))
    if not paths:
        print(f"no pngs in {UNIT_DIR}")
        return 1
    for p in paths:
        src = Image.open(p)
        before = stats(src)
        out = defringe(src)
        after = stats(out)
        out.save(p, "PNG")
        print(f"{p.name:42s} {before}  ->  {after}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
