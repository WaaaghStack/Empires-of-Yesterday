"""Write 32x32 nearest-neighbor battle FX sheets (RGBA PNG)."""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] if Path(__file__).name == "write_battle_fx.py" else Path("assets/fx/battle")


def png_rgba(w: int, h: int, pixels: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b""
    stride = w * 4
    for y in range(h):
        raw += b"\x00" + pixels[y * stride : (y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def blank(n: int = 32):
    return [[(0, 0, 0, 0) for _ in range(n)] for _ in range(n)]


def put(g, x, y, c):
    if 0 <= x < 32 and 0 <= y < 32:
        g[y][x] = c


def encode(g) -> bytes:
    b = bytearray()
    for row in g:
        for r, gch, bch, a in row:
            b.extend((r, gch, bch, a))
    return bytes(b)


W = (255, 252, 220, 255)
Y = (255, 210, 70, 255)
O = (255, 140, 40, 255)
C = (80, 220, 255, 255)
BR = (120, 92, 60, 220)
GR = (90, 90, 88, 200)
EM = (255, 120, 40, 255)


def muzzle():
    g = blank()
    cx, cy = 16, 16
    for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
        put(g, cx + dx, cy + dy, W)
    for dx, dy in ((-1, 0), (2, 0), (0, -1), (0, 2), (1, -1), (1, 2), (-1, 1), (2, 1)):
        put(g, cx + dx, cy + dy, Y)
    for dx, dy in ((-3, 0), (4, 0), (0, -3), (1, 4), (-2, -2), (3, -2), (-2, 3), (3, 3)):
        put(g, cx + dx, cy + dy, O)
    put(g, cx - 4, cy - 1, C)
    put(g, cx + 5, cy + 2, C)
    return g


def tracer():
    g = blank()
    for x in range(6, 26):
        put(g, x, 15, W)
        put(g, x, 16, Y)
        put(g, x, 17, O)
    put(g, 25, 15, C)
    put(g, 26, 16, C)
    return g


def spark():
    g = blank()
    cx, cy = 16, 16
    put(g, cx, cy, W)
    put(g, cx + 1, cy, Y)
    for dx, dy in ((0, -3), (0, 3), (-3, 0), (3, 0), (-2, -2), (2, -2), (-2, 2), (2, 2)):
        put(g, cx + dx, cy + dy, O)
        put(g, cx + dx // 2, cy + dy // 2, Y)
    put(g, cx + 4, cy - 1, C)
    put(g, cx - 4, cy + 2, C)
    return g


def bomb():
    g = blank()
    blobs = [(16, 16, 6, BR), (12, 14, 4, GR), (20, 18, 4, GR), (15, 12, 3, EM)]
    for cx, cy, rad, col in blobs:
        for y in range(32):
            for x in range(32):
                if (x - cx) ** 2 + (y - cy) ** 2 <= rad * rad:
                    put(g, x, y, col)
    put(g, 16, 16, Y)
    put(g, 17, 15, O)
    return g


def main():
    out = Path("assets/fx/battle")
    out.mkdir(parents=True, exist_ok=True)
    for name, grid in (("muzzle", muzzle()), ("tracer", tracer()), ("spark", spark()), ("bomb", bomb())):
        (out / f"{name}.png").write_bytes(png_rgba(32, 32, encode(grid)))
        print("wrote", out / f"{name}.png")


if __name__ == "__main__":
    main()
