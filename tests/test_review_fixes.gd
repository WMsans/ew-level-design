# Headless check:  godot --headless --path . --script res://tests/test_review_fixes.gd
# Regression tests for the final-review findings (cache key, resize, palette swap, bad arrays, warnings).
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails += 1

class WarnCounter extends Logger:
	var n := 0
	var errors := 0
	func _log_error(_f, _fi, _l, _c, _r, _en, error_type, _bt) -> void:
		if error_type == ERROR_TYPE_WARNING: n += 1
		else: errors += 1

func gen() -> TileType:
	var t := TileType.new()
	t.top_material = StandardMaterial3D.new()
	t.side_material = StandardMaterial3D.new()
	return t

func painted(w: int, h: int, pal: Array, height := 1) -> TerrainMap:
	var m := TerrainMap.new()
	m.palette.assign(pal)
	m.size = Vector2i(w, h)
	for z in h:
		for x in w: m.set_cell(Vector2i(x, z), 1, height)
	return m

func mesh_of(m: TerrainMap, ch: Vector2i) -> MeshInstance3D:
	var c := m.chunk_node(ch)
	if c == null: return null
	var mis := c.find_children("*", "MeshInstance3D", false, false)
	return mis[0] if mis else null

func _initialize() -> void:
	# C1: cache key must not depend on object addresses (fresh loads of the same TileType)
	ResourceSaver.save(gen(), "user://fix_type.tres")
	var t1: TileType = ResourceLoader.load("user://fix_type.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var t2: TileType = ResourceLoader.load("user://fix_type.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var k1 := painted(4, 4, [t1])
	var k2 := painted(4, 4, [t2])
	check(k1.cache_key() == k2.cache_key(), "cache key is stable across fresh loads of the same data")
	var k3 := painted(4, 4, [t1])
	t1.is_ramp = true
	check(k3.cache_key() != k2.cache_key(), "cache key changes when a type's build settings change")

	# C1: cache stores no material copies; a cached load takes materials from the palette
	var src := painted(20, 4, [gen()])
	src.rebuild_all()
	var cache := src.make_cache()
	var embedded := false
	for ch in cache.meshes:
		for i in cache.meshes[ch].get_surface_count():
			if cache.meshes[ch].surface_get_material(i) != null: embedded = true
	check(not embedded, "cache meshes carry no embedded materials")
	var dst := painted(20, 4, [gen()])
	dst.mesh_cache = cache
	dst.rebuild_all()
	var mi := mesh_of(dst, Vector2i(0, 0))
	var mats := [mi.get_active_material(0), mi.get_active_material(1)]
	check(mi.mesh == cache.meshes[Vector2i(0, 0)] and dst.palette[0].top_material in mats and dst.palette[0].side_material in mats,
		"cached load uses the cached mesh with the palette's materials")

	# I1: resize removes chunks past the edge and never reuses a stale cache
	var rs := painted(32, 16, [gen()])
	rs.rebuild_all()
	rs.size = Vector2i(16, 16)
	rs.rebuild_dirty()
	check(rs.chunk_node(Vector2i(1, 0)) == null, "shrinking removes chunks past the new edge")
	var rc := painted(32, 16, [gen()])
	rc.rebuild_all()
	rc.mesh_cache = rc.make_cache()
	rc.rebuild_all()
	rc.size = Vector2i(20, 16)
	rc.rebuild_dirty()
	var rmi := mesh_of(rc, Vector2i(1, 0))
	check(rmi != null and rmi.mesh.get_aabb().end.x <= 30.001, "resize rebuilds from the data, not the stale cache")

	# I4: cache file path is unique per map node path
	var p1 := TerrainCache.path_for("res://lvl/dungeon.tscn", NodePath("Floor1/Room"))
	var p2 := TerrainCache.path_for("res://lvl/dungeon.tscn", NodePath("Floor2/Room"))
	check(p1 != p2 and p1.begins_with("res://lvl/dungeon_") and p1.ends_with(".terrain.res") and not p1.trim_prefix("res://lvl/").contains("/"),
		"two maps named Room get different cache files: %s %s" % [p1, p2])

	# I5: changing the palette on a live map rebuilds it
	var live := painted(4, 4, [gen()])
	get_root().add_child(live)
	await process_frame  # the root enters the tree only once the main loop runs
	check(live.is_inside_tree() and mesh_of(live, Vector2i(0, 0)) != null, "live map built its generated mesh")
	var prov := TileType.new()
	prov.mode = TileType.Mode.PROVIDED
	var pr := Node3D.new()
	var ps := PackedScene.new()
	ps.pack(pr)
	pr.free()
	for n in ["full", "edge", "outer_corner", "inner_corner", "opposite_corners", "wall_edge", "wall_outer_corner", "wall_inner_corner"]:
		prov.set(n, ps)
	live.palette = [prov]
	check(mesh_of(live, Vector2i(0, 0)) == null and live.chunk_node(Vector2i(0, 0)).get_child_count() > 0,
		"palette swap rebuilds: generated mesh replaced by provided pieces")
	live.queue_free()

	# I6 + warnings: mismatched arrays are repaired once; a missing type warns once per rebuild
	var log := WarnCounter.new()
	OS.add_logger(log)
	var bad := TerrainMap.new()
	bad.palette.assign([gen()])
	bad.size = Vector2i(4, 4)
	bad.types = PackedByteArray([1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	bad.heights = PackedByteArray([1, 1, 1])
	log.errors = 0
	bad.rebuild_all()
	check(bad.types.size() == 16 and bad.heights.size() == 16, "mismatched cell arrays are resized to match size")
	check(log.errors == 1, "mismatch reported once (errors: %d)" % log.errors)
	var miss := painted(64, 64, [gen()])
	miss.set_cell(Vector2i(0, 0), 3, 1)
	miss.set_cell(Vector2i(40, 40), 3, 1)
	log.n = 0
	miss.rebuild_all()
	check(log.n == 1, "missing type index warns once per rebuild (got %d)" % log.n)
	OS.remove_logger(log)

	# I2: undoing a shrink restores the cropped paint, whichever order the size undo runs in
	for order in 2:
		var u := painted(4, 4, [gen()])
		u.set_cell(Vector2i(3, 3), 1, 5)
		var before := [u.size, u.types.duplicate(), u.heights.duplicate()]
		u.size = Vector2i(2, 2)
		if order == 1: u.size = before[0]  # Inspector's own size undo runs first
		u.restore_cells(before[0], before[1], before[2])
		u.size = before[0]                 # ...or after
		check(u.size == Vector2i(4, 4) and u.get_type(Vector2i(3, 3)) == 1 and u.get_height(Vector2i(3, 3)) == 5,
			"undo of a shrink restores cropped cells (order %d)" % order)
		u.free()

	# I3: provided and generate types meeting at the same height
	var P := TileType.new()
	P.mode = TileType.Mode.PROVIDED
	for n in ["full", "edge", "outer_corner", "inner_corner", "opposite_corners", "wall_edge", "wall_outer_corner", "wall_inner_corner"]:
		var pps := PackedScene.new()  # one scene per piece so the test can tell them apart
		var pn := Node3D.new()
		pps.pack(pn)
		pn.free()
		P.set(n, pps)
	for case in [[P, gen()], [gen(), P]]:
		var mm := TerrainMap.new()
		mm.palette.assign(case)
		mm.size = Vector2i(2, 1)
		var pi := 1 if case[0] == P else 2
		mm.set_cell(Vector2i(0 if pi == 1 else 1, 0), pi, 0)
		mm.set_cell(Vector2i(1 if pi == 1 else 0, 0), 3 - pi, 0)
		var at := ProvidedBuilder.build(mm, Rect2i(0, 0, 2, 1)).filter(func(p): return is_equal_approx(p.xform.origin.x, 1.5) and is_zero_approx(p.xform.origin.z))
		check(at.size() == 1 and P.outer_corner == at[0].scene,
			"provided cell next to a same-height generate cell gets its own corner (provided index %d)" % pi)
		mm.free()

	for n in [k1, k2, k3, src, dst, rs, rc, bad, miss]: n.free()
	print("FAILS: %d" % fails)
	quit(1 if fails else 0)
