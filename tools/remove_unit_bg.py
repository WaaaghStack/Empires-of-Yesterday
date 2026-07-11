"""Remove solid/flat backgrounds from unit sprites → clean RGBA PNG.

Strategy:
1. Sample edge/corner colors to detect chroma key (magenta or near-white).
2. Flood-fill from all borders (connected background only — keeps magenta in art).
3. Also key pure-ish white and pure magenta by color distance.
4. Optional nearest-neighbor downscale/upscale for harder pixel edges.
"""
from __future__ import annotations

import sys
from collections import deque
from pathlib import Path

from PIL import Image

try:
	import numpy as np
except ImportError:
	import subprocess

	subprocess.check_call([sys.executable, "-m", "pip", "install", "numpy", "-q"])
	import numpy as np


# Latest pixel-art batch (session images 7–12) + legacy 1–6 if present
PIXEL_BATCH = {
	7: "bomber_hostile",
	8: "soldier_hostile",
	9: "soldier_friendly",
	10: "soldier_base",
	11: "bomber_friendly",
	12: "bomber_base",
}


def _color_dist(c: np.ndarray, ref: np.ndarray) -> np.ndarray:
	return np.sqrt(((c - ref) ** 2).sum(axis=-1))


def remove_background(
	img: Image.Image,
	*,
	pixelate: int = 0,
	edge_tol: float = 48.0,
	white_tol: float = 28.0,
	magenta_tol: float = 70.0,
) -> Image.Image:
	rgba = img.convert("RGBA")
	arr = np.asarray(rgba).copy()
	h, w = arr.shape[:2]
	rgb = arr[:, :, :3].astype(np.float32)

	# Dominant edge color (background guess)
	edge_pixels = np.concatenate(
		[
			rgb[0, :, :],
			rgb[-1, :, :],
			rgb[:, 0, :],
			rgb[:, -1, :],
		],
		axis=0,
	)
	# Median is robust to a few subject pixels touching the edge
	bg_ref = np.median(edge_pixels, axis=0)

	white = np.array([255.0, 255.0, 255.0], dtype=np.float32)
	magenta = np.array([255.0, 0.0, 255.0], dtype=np.float32)

	dist_bg = _color_dist(rgb, bg_ref)
	dist_white = _color_dist(rgb, white)
	dist_mag = _color_dist(rgb, magenta)

	# Seed mask: pixels that look like background color
	is_bg_color = (
		(dist_bg <= edge_tol)
		| (dist_white <= white_tol)
		| (dist_mag <= magenta_tol)
	)

	# Also: very bright low-chroma (paper white)
	mn = rgb.min(axis=-1)
	mx = rgb.max(axis=-1)
	chroma = mx - mn
	is_bg_color |= (mn >= 248) & (chroma <= 12)

	# Flood-fill from border using only bg-colored pixels (connected component)
	visited = np.zeros((h, w), dtype=bool)
	q: deque[tuple[int, int]] = deque()
	for x in range(w):
		for y in (0, h - 1):
			if is_bg_color[y, x]:
				q.append((y, x))
				visited[y, x] = True
	for y in range(h):
		for x in (0, w - 1):
			if is_bg_color[y, x] and not visited[y, x]:
				q.append((y, x))
				visited[y, x] = True

	while q:
		y, x = q.popleft()
		for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			ny, nx = y + dy, x + dx
			if ny < 0 or ny >= h or nx < 0 or nx >= w:
				continue
			if visited[ny, nx]:
				continue
			if not is_bg_color[ny, nx]:
				continue
			visited[ny, nx] = True
			q.append((ny, nx))

	alpha = np.where(visited, 0, 255).astype(np.uint8)
	# Kill any leftover pure-white / pure-magenta islands not connected? optional hard key:
	hard_key = (dist_white <= 12) | (dist_mag <= 40) | ((mn >= 252) & (chroma <= 6))
	alpha = np.where(hard_key, 0, alpha).astype(np.uint8)

	out = arr.copy()
	out[:, :, 3] = alpha
	# Zero RGB on transparent so no white fringe when filtered
	out[alpha == 0, 0:3] = 0
	# Strip residual magenta fringe (anti-aliased chroma-key leftovers on outlines)
	r, g, b = out[:, :, 0].astype(np.float32), out[:, :, 1].astype(np.float32), out[:, :, 2].astype(np.float32)
	mag_score = np.minimum(r, b) - g
	is_mag = (mag_score > 40) & (g < 140) & (np.minimum(r, b) > 120)
	is_mag |= (r > 200) & (b > 200) & (g < 80)
	out[is_mag, 3] = 0
	out[is_mag, 0:3] = 0

	result = Image.fromarray(out, "RGBA")
	if pixelate and pixelate > 0:
		# Nearest-neighbor crunch → hard pixel edges, then back up for game use
		small = result.resize((pixelate, pixelate), Image.Resampling.NEAREST)
		# Crop transparent margins on small grid first
		bbox = small.getbbox()
		if bbox:
			small = small.crop(bbox)
		# Scale up to ~256 for crisp billboards
		tw = max(small.width * 4, 64)
		th = max(small.height * 4, 64)
		# Keep square-ish pad
		side = max(tw, th, 128)
		result = small.resize((tw, th), Image.Resampling.NEAREST)
		canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
		ox = (side - result.width) // 2
		oy = (side - result.height) // 2
		canvas.paste(result, (ox, oy), result)
		result = canvas
	return result


def main() -> int:
	src = Path(
		r"C:\Users\Komba\.grok\sessions\C%3A%5CUsers%5CKomba\019f4764-fa46-7223-a0d6-b615d0902eb1\images"
	)
	dst = Path(r"C:\Users\Komba\OneDrive\Documents\GitHub\Empires-of-Yesterday\assets\units")
	dst.mkdir(parents=True, exist_ok=True)

	for i, name in PIXEL_BATCH.items():
		p = src / f"{i}.jpg"
		if not p.exists():
			print(f"missing {p}")
			continue
		# Two outputs: clean full-res alpha + pixel-crunched
		clean = remove_background(Image.open(p), pixelate=0)
		pix = remove_background(Image.open(p), pixelate=96)
		for label, im in (("clean", clean), ("pixel", pix)):
			path = dst / f"{name}_{label}.png"
			im.save(path, "PNG")
			a = np.array(im)[:, :, 3]
			clear = float((a == 0).mean())
			corners = [int(a[0, 0]), int(a[0, -1]), int(a[-1, 0]), int(a[-1, -1])]
			print(f"{path.name}: clear={clear:.1%} corners={corners} size={im.size}")
		# Default game name points at pixel version (hardest edges)
		pix.save(dst / f"{name}.png", "PNG")
		print(f"  -> {name}.png (pixel default)")
	print("done")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
