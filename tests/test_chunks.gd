# Headless check:  godot --headless --path . --script res://tests/test_chunks.gd
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails += 1

func gen() -> TileType:
	var t := TileType.new()
	t.top_material = StandardMaterial3D.new()
	t.side_material = StandardMaterial3D.new()
	return t

func chunks(m: TerrainMap) -> Array:
	return m.get_children().filter(func(n): return n.name.begins_with("_chunk_"))

func _initialize() -> void:
	var m := TerrainMap.new()
	m.palette.assign([gen()])
	m.resize(Vector2i(32, 16))
	for z in 16:
		for x in 32:
			m.set_cell(Vector2i(x, z), 1, 1)
	m.rebuild_all()
	var cs := chunks(m)
	check(cs.size() == 2, "32x16 map builds 2 chunks")
	check(cs.all(func(c): return c.find_children("*", "MeshInstance3D", false, false).size() == 1 \
		and c.find_children("*", "StaticBody3D", false, false).size() == 1), "each chunk has a mesh and a static body")
	var body: StaticBody3D = m.chunk_node(Vector2i(0, 0)).find_children("*", "StaticBody3D", false, false)[0]
	var shape: ConcavePolygonShape3D = (body.get_child(0) as CollisionShape3D).shape
	check(shape.get_faces().size() > 0, "collision faces built")
	check(m.dirty.is_empty(), "rebuild_all clears dirty")

	m.set_cell(Vector2i(5, 5), 1, 2)
	check(m.dirty.keys() == [Vector2i(0, 0)], "edit inside a chunk dirties only that chunk")
	m.dirty.clear()
	m.set_cell(Vector2i(15, 5), 1, 2)
	var d := m.dirty.keys()
	d.sort()
	check(d == [Vector2i(0, 0), Vector2i(1, 0)], "edit on a chunk border dirties the neighbour too")
	m.dirty.clear()
	m.set_cell(Vector2i(14, 5), 1, 2)
	check(m.dirty.has(Vector2i(1, 0)), "edit two cells from the border dirties the neighbour (ramps)")

	m.dirty.clear()
	var right_before := m.chunk_node(Vector2i(1, 0)).get_instance_id()
	m.set_cell(Vector2i(3, 3), 1, 3)
	m.rebuild_dirty()
	check(m.chunk_node(Vector2i(1, 0)).get_instance_id() == right_before, "untouched chunk is not rebuilt")
	check(m.dirty.is_empty(), "rebuild_dirty clears dirty")

	var root := Node3D.new()
	root.add_child(m)
	m.owner = root
	m.rebuild_all()
	check(chunks(m).all(func(c): return c.owner == null), "chunk nodes are never owned (not saved)")
	var ps := PackedScene.new()
	ps.pack(root)
	check(ps.get_state().get_node_count() == 2, "packed scene holds root + map only")

	# provided pieces are instanced into the chunk
	var p := TileType.new()
	p.mode = TileType.Mode.PROVIDED
	var piece_root := Node3D.new()
	var ps2 := PackedScene.new()
	ps2.pack(piece_root)
	piece_root.free()
	for n in ["full", "edge", "outer_corner", "inner_corner", "opposite_corners", "wall_edge", "wall_outer_corner", "wall_inner_corner"]:
		p.set(n, ps2)
	var pm := TerrainMap.new()
	pm.palette.assign([p])
	pm.resize(Vector2i(1, 1))
	pm.set_cell(Vector2i(0, 0), 1, 0)
	pm.rebuild_all()
	check(pm.chunk_node(Vector2i(0, 0)).get_child_count() >= 4, "provided pieces instanced in the chunk")

	# mesh cache: a matching cache is used instead of rebuilding; edits or stale data bypass it
	var src := TerrainMap.new()
	src.palette.assign([gen()])
	src.size = Vector2i(20, 4)
	for x in 20: src.set_cell(Vector2i(x, 1), 1, 2)
	src.rebuild_all()
	var cache := src.make_cache()
	check(cache.meshes.size() == 2 and cache.shapes.size() == 2, "cache holds a mesh and shape per built chunk")
	ResourceSaver.save(cache, "user://test_cache.terrain.res")
	var loaded: TerrainCache = ResourceLoader.load("user://test_cache.terrain.res", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded.key == cache.key and loaded.meshes.has(Vector2i(1, 0)) and loaded.shapes[Vector2i(1, 0)] is ConcavePolygonShape3D, "cache survives a save/load round trip")
	var dst := TerrainMap.new()
	dst.palette = src.palette
	dst.size = src.size
	dst.types = src.types
	dst.heights = src.heights
	dst.mesh_cache = cache
	dst.rebuild_all()
	var mi0: MeshInstance3D = dst.chunk_node(Vector2i(0, 0)).find_children("*", "MeshInstance3D", false, false)[0]
	check(mi0.mesh == cache.meshes[Vector2i(0, 0)], "matching cache mesh is reused")
	dst.set_cell(Vector2i(1, 1), 1, 3)
	dst.rebuild_dirty()
	mi0 = dst.chunk_node(Vector2i(0, 0)).find_children("*", "MeshInstance3D", false, false)[0]
	check(mi0.mesh != cache.meshes[Vector2i(0, 0)], "edited chunk is rebuilt, not taken from the cache")
	var stale := TerrainMap.new()
	stale.palette = src.palette
	stale.size = src.size
	stale.mesh_cache = cache
	stale.rebuild_all()
	check(stale.chunk_node(Vector2i(0, 0)).find_children("*", "MeshInstance3D", false, false).is_empty(), "cache for different data is ignored")

	for n in [src, dst, stale]: n.free()
	root.free()
	pm.free()
	print("FAILS: %d" % fails)
	quit(1 if fails else 0)
