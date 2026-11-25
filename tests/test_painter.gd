# Headless check:  godot --headless --path . --script res://tests/test_painter.gd
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
	var m := make(10, 10)
	check(Painter.brush(m, Vector2i(5, 5), 1, 1, 0).size() == 5, "brush radius 1 paints a plus of 5 cells")
	check(Painter.brush(m, Vector2i(5, 5), 0, 1, 0).size() == 1, "brush radius 0 paints one cell")
	var e := [Painter.brush(m, Vector2i(5, 5), 0, 2, 3)[0]]
	check(e[0].cell == Vector2i(5, 5) and e[0].old_type == 0 and e[0].old_h == 0 and e[0].new_type == 2 and e[0].new_h == 3, "edit records old and new values")
	check(m.get_type(Vector2i(5, 5)) == 0, "painter does not mutate the map")

	# Review Focus 1: brush and rect past the map edge
	var edge := Painter.brush(m, Vector2i(0, 0), 3, 1, 0)
	check(edge.all(func(x): return m.in_bounds(x.cell)) and edge.size() == 11, "brush at the corner stays in bounds (11 cells)")
	check(Painter.rect(m, Vector2i(-2, -2), Vector2i(1, 1), 1, 0).size() == 4, "rect clipped to the map")
	check(Painter.rect(m, Vector2i(1, 1), Vector2i(-2, -2), 1, 0).size() == 4, "rect corners in any order")
	check(Painter.fill(m, Vector2i(0, 0), 1, 0).size() == 100, "fill on an empty map covers it")
	check(Painter.fill(m, Vector2i(-1, 0), 1, 0).is_empty(), "fill from outside the map does nothing")

	var w := make(5, 1)
	for x in 5: w.set_cell(Vector2i(x, 0), 1, 0)
	w.set_cell(Vector2i(2, 0), 1, 3)
	check(Painter.fill(w, Vector2i(0, 0), 2, 0).size() == 2, "fill stops at a different height")

	check(Painter.brush(w, Vector2i(0, 0), 0, 1, 0).is_empty(), "unchanged cells produce no edits")

	# Review Focus 2: raise/lower clamp
	var c := make(3, 1)
	c.set_cell(Vector2i(0, 0), 1, 255)
	c.set_cell(Vector2i(1, 0), 1, 0)
	check(Painter.raise(c, Vector2i(0, 0), 0, 1).is_empty(), "raise at 255 does nothing")
	check(Painter.raise(c, Vector2i(1, 0), 0, -1).is_empty(), "lower at 0 does nothing")
	var r := Painter.raise(c, Vector2i(1, 0), 0, 2)
	check(r.size() == 1 and r[0].new_h == 2 and r[0].new_type == 1, "raise keeps type")
	check(Painter.raise(c, Vector2i(2, 0), 0, 1).is_empty(), "raise skips empty cells")
	var f := Painter.flatten(c, Vector2i(0, 0), 1, 7)
	check(f.size() == 2 and f.all(func(x): return x.new_h == 7), "flatten sets non-empty cells to h")

	var p := make(4, 4)
	for z in 4:
		for x in 4: p.set_cell(Vector2i(x, z), 1, 0)
	p.set_cell(Vector2i(2, 1), 1, 4)
	check(Painter.pick(p, Vector3(3.75, 10, 2.25), Vector3.DOWN) == Vector2i(2, 1), "pick the raised cell from above")
	check(Painter.pick(p, Vector3(0.75, 10, 0.75), Vector3.DOWN) == Vector2i(0, 0), "pick a ground cell from above")
	check(Painter.pick(p, Vector3(0.75, 10, 0.75), Vector3.UP) == Vector2i(-1, -1), "ray pointing up misses")
	check(Painter.pick(p, Vector3(-3, 10, 2.25), Vector3(1, -1, 0).normalized()) == Vector2i(2, 1), "slanted ray hits the raised cell before the ground behind it")
	check(Painter.pick(p, Vector3(-30, 4, 2.25), Vector3(1, 0.01, 0).normalized()) == Vector2i(-1, -1), "ray over the map misses")

	# stroke merge: first old_*, latest new_*
	var stroke := {}
	Painter.merge(stroke, [{cell = Vector2i(1, 1), old_type = 0, old_h = 0, new_type = 1, new_h = 2}])
	Painter.merge(stroke, [{cell = Vector2i(1, 1), old_type = 1, old_h = 2, new_type = 1, new_h = 3}])
	var merged: Array = stroke.values()
	check(merged.size() == 1 and merged[0].old_h == 0 and merged[0].old_type == 0 and merged[0].new_h == 3, "merge keeps first old and latest new")

	for n in [m, w, c, p]: n.free()
	print("FAILS: %d" % fails)
	quit(1 if fails else 0)
