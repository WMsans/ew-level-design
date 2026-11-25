# Bench:  godot --headless --path . --script res://tests/bench_overworld.gd
# Targets (spec): single-cell rebuild_dirty < 16 ms, rebuild_all of 512x512 < 200 ms.
extends SceneTree

func _initialize() -> void:
	var a := TileType.new(); a.top_material = StandardMaterial3D.new(); a.side_material = StandardMaterial3D.new()
	var b := TileType.new(); b.top_material = StandardMaterial3D.new(); b.side_material = StandardMaterial3D.new()
	var m := TerrainMap.new()
	m.palette.assign([a, b])
	m.size = Vector2i(512, 512)
	var n := FastNoiseLite.new()
	n.frequency = 0.02
	for z in 512:
		for x in 512:
			var v := n.get_noise_2d(x, z) * 0.5 + 0.5
			m.set_cell(Vector2i(x, z), 1 if v < 0.6 else 2, int(v * 8))
	var t := Time.get_ticks_usec()
	m.rebuild_all()
	var all_ms := (Time.get_ticks_usec() - t) / 1000.0
	m.set_cell(Vector2i(100, 100), 2, 8)
	t = Time.get_ticks_usec()
	m.rebuild_dirty()
	var one_ms := (Time.get_ticks_usec() - t) / 1000.0
	m.mesh_cache = m.make_cache()
	var copy := TerrainMap.new()
	copy.palette = m.palette
	copy.size = m.size
	copy.types = m.types
	copy.heights = m.heights
	copy.mesh_cache = m.mesh_cache
	t = Time.get_ticks_usec()
	copy.rebuild_all()
	var cached_ms := (Time.get_ticks_usec() - t) / 1000.0
	copy.free()
	print("rebuild_all 512x512: %.1f ms (target < 200)" % all_ms)
	print("cached load 512x512: %.1f ms (target < 200)" % cached_ms)
	print("single-cell rebuild_dirty: %.1f ms (target < 16)" % one_ms)
	m.free()
	quit()
