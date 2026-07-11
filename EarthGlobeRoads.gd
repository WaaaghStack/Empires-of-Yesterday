class_name EarthGlobeRoads
extends RefCounted
## Pure MultiMesh buffer helpers for globe road ribbons (B3/I4/H2, C2).
##
## Godot 4 MultiMesh: raising `instance_count` clears all instance transforms.
## Grow capacity only inside `write_all_transforms` (full reseed from the caller's
## authoritative transform list). Append path must never raise capacity mid-run.

## Default prealloc — large enough that mid-match growth is rare on earth-scale maps.
const MIN_CAPACITY := 4096


## Next capacity that fits `needed` live instances (doubling growth, never shrinks).
static func next_capacity(needed: int, min_cap: int = MIN_CAPACITY) -> int:
	var cap: int = maxi(min_cap, 1)
	if needed <= 0:
		return cap
	while cap < needed:
		# Prefer geometric growth so we reseed rarely.
		var doubled: int = cap * 2
		cap = doubled if doubled > cap else needed
		if cap < needed:
			cap = needed
	return cap


## Grow capacity if needed, then write ALL transforms (safe reseed).
## Returns the number of visible instances written.
static func write_all_transforms(
	mm: MultiMesh, xforms: Array, min_cap: int = MIN_CAPACITY
) -> int:
	if mm == null:
		return 0
	var n: int = xforms.size()
	var want_cap: int = next_capacity(n, min_cap)
	# I4/B3: only touch instance_count when capacity must change — and always
	# rewrite every live transform immediately after (buffer wipe on grow).
	if mm.instance_count < want_cap:
		mm.instance_count = want_cap
	for i in range(n):
		mm.set_instance_transform(i, xforms[i] as Transform3D)
	mm.visible_instance_count = n
	return n


## Append without growing capacity. Returns new used count, or -1 if full
## (caller must rebuild via write_all_transforms from authoritative caches).
static func try_append_transforms(mm: MultiMesh, used: int, xforms: Array) -> int:
	if mm == null:
		return used
	if xforms.is_empty():
		return used
	var need: int = used + xforms.size()
	if need > mm.instance_count:
		return -1
	for i in range(xforms.size()):
		mm.set_instance_transform(used + i, xforms[i] as Transform3D)
	mm.visible_instance_count = need
	return need


## True when a full MultiMesh rebuild from caches is required for this sid change.
## Growth is append-only (false); shrink/remove needs rebuild (true).
static func needs_full_rebuild_for_seg_change(had_cache: bool, prev_segs: int, need_segs: int) -> bool:
	if not had_cache:
		return false
	return need_segs < prev_segs
