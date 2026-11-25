# Headless check:  godot --headless --path . --script res://tests/test_terrain_map.gd
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails += 1

func make(w: int, h: int) -> TerrainMap:
	var m := TerrainMap.new()
	m.resize(Vector2i(w, h))
	return m

func _initialize() -> void:
	var m := make(4, 3)
	check(m.types.size() == 12 and m.heights.size() == 12, "4x3 map has 12 cells")
	var all_empty := true
	for z in 3:
		for x in 4:
			if m.get_type(Vector2i(x, z)) != 0: all_empty = false
	check(all_empty, "new map cells are empty")

	m.set_cell(Vector2i(1, 2), 1, 3)
	check(m.get_height(Vector2i(1, 2)) == 3, "set_cell stores height")
	check(m.get_type(Vector2i(1, 2)) == 1, "set_cell stores type")
	check(m.get_height(Vector2i(-1, 0)) == 0, "out of bounds height is 0")
	m.set_cell(Vector2i(9, 9), 1, 1)
	check(m.types.size() == 12, "out of bounds set_cell is ignored")
	m.set_cell(Vector2i(0, 0), 1, 300)
	check(m.get_height(Vector2i(0, 0)) == 255, "height clamps to 255")
	m.set_cell(Vector2i(0, 0), 1, -4)
	check(m.get_height(Vector2i(0, 0)) == 0, "height clamps to 0")

	check(m.local_to_cell(Vector3(1.6, 0, 3.0)) == Vector2i(1, 2), "local_to_cell")
	check(m.cell_top(Vector2i(1, 2)).is_equal_approx(Vector3(2.25, 2.25, 3.75)), "cell_top")

	var t := TileType.new()
	m.palette = [t]
	check(m.tile_type(0) == null, "type 0 is empty")
	check(m.tile_type(5) == null, "out of range type is null")
	check(m.tile_type(1) == t, "type 1 is palette[0]")

	# Review Focus 5: resize keeps overlapping paint
	var r := make(4, 3)
	r.set_cell(Vector2i(1, 1), 1, 2)
	r.set_cell(Vector2i(3, 2), 1, 4)
	r.resize(Vector2i(2, 5))
	check(r.size == Vector2i(2, 5) and r.types.size() == 10, "resize changes size")
	check(r.get_type(Vector2i(1, 1)) == 1 and r.get_height(Vector2i(1, 1)) == 2, "resize keeps overlapping cell")
	check(r.get_type(Vector2i(1, 4)) == 0, "resize new cells empty")

	var s := TerrainMap.new()
	check(s.types.size() == s.size.x * s.size.y and s.size.x > 0, "new map has arrays matching its default size")
	s.size = Vector2i(3, 2)
	check(s.types.size() == 6 and s.heights.size() == 6, "setting size in the Inspector resizes the arrays")
	s.free()

	var e := make(2, 2)
	var edits := [{cell = Vector2i(0, 0), old_type = 0, old_h = 0, new_type = 1, new_h = 2}]
	e.apply_edits(edits, true)
	check(e.get_type(Vector2i(0, 0)) == 1 and e.get_height(Vector2i(0, 0)) == 2, "apply_edits forward")
	e.apply_edits(edits, false)
	check(e.get_type(Vector2i(0, 0)) == 0 and e.get_height(Vector2i(0, 0)) == 0, "apply_edits backward")

	var d := make(40, 4)
	d.dirty.clear()
	d.set_cell(Vector2i(17, 0), 1, 1)
	check(d.dirty.has(Vector2i(1, 0)), "set_cell marks chunk dirty")

	var a := make(2, 2)
	a.set_cell(Vector2i(1, 1), 1, 4)
	check(a.room_aabb().is_equal_approx(AABB(Vector3.ZERO, Vector3(3, 3, 3))), "room_aabb")

	for n in [m, r, e, d, a]: n.free()
	print("FAILS: %d" % fails)
	quit(1 if fails else 0)
