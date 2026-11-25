# Headless check:  godot --headless --path . --script res://tests/test_generate.gd
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails += 1

var top_a := StandardMaterial3D.new()
var side_a := StandardMaterial3D.new()
var top_b := StandardMaterial3D.new()
var side_b := StandardMaterial3D.new()

func gen_type(top: Material, side: Material, ramp := false) -> TileType:
	var t := TileType.new()
	t.top_material = top
	t.side_material = side
	t.is_ramp = ramp
	return t

func make(w: int, h: int, pal: Array) -> TerrainMap:
	var m := TerrainMap.new()
	m.resize(Vector2i(w, h))
	m.palette.assign(pal)
	return m

func y_range(v: PackedVector3Array) -> Vector2:
	var lo := INF
	var hi := -INF
	for p in v:
		lo = minf(lo, p.y); hi = maxf(hi, p.y)
	return Vector2(lo, hi)

func whole(m: TerrainMap) -> Rect2i:
	return Rect2i(Vector2i.ZERO, m.size)

func _initialize() -> void:
	var A := gen_type(top_a, side_a)
	var B := gen_type(top_b, side_b)

	var m := make(1, 1, [A])
	m.set_cell(Vector2i(0, 0), 1, 2)
	var g := GenerateBuilder.build(m, whole(m))
	check(g.get(top_a, PackedVector3Array()).size() == 6, "single cell: one top quad")
	check(y_range(g[top_a]) == Vector2(1.5, 1.5), "top at h*STEP")
	check(Plane(g[top_a][0], g[top_a][1], g[top_a][2]).normal.is_equal_approx(Vector3.UP), "top faces up (Godot winding)")
	check(g.get(side_a, PackedVector3Array()).size() == 24, "single cell: four side quads")
	check(y_range(g[side_a]) == Vector2(0, 1.5), "sides span ground to top")
	var s: PackedVector3Array = g[side_a]
	var outward := true
	for i in range(0, s.size(), 3):
		var n := Plane(s[i], s[i + 1], s[i + 2]).normal
		var mid := (s[i] + s[i + 1] + s[i + 2]) / 3.0
		if n.dot(mid - Vector3(0.75, mid.y, 0.75)) <= 0: outward = false
	check(outward, "side faces point outward")

	var two := make(2, 1, [A])
	two.set_cell(Vector2i(0, 0), 1, 2)
	two.set_cell(Vector2i(1, 0), 1, 2)
	g = GenerateBuilder.build(two, whole(two))
	check(g[top_a].size() == 12, "two cells: two tops")
	check(g[side_a].size() == 36, "two equal cells: shared face removed")

	var step := make(2, 1, [A, B])
	step.set_cell(Vector2i(0, 0), 1, 2)
	step.set_cell(Vector2i(1, 0), 2, 1)
	g = GenerateBuilder.build(step, whole(step))
	var between := PackedVector3Array()
	var sa: PackedVector3Array = g[side_a]
	for i in range(0, sa.size(), 3):
		if is_equal_approx(sa[i].x, 1.5) and is_equal_approx(sa[i + 1].x, 1.5) and is_equal_approx(sa[i + 2].x, 1.5):
			between.append_array([sa[i], sa[i + 1], sa[i + 2]])
	check(between.size() == 6, "higher cell owns the shared face")
	check(y_range(between) == Vector2(0.75, 1.5), "shared face spans the height difference")
	var b_side: PackedVector3Array = g.get(side_b, PackedVector3Array())
	var b_on_border := false
	for p in b_side:
		if is_equal_approx(p.x, 1.5) and p.y > 0.75: b_on_border = true
	check(not b_on_border, "lower cell draws no face on the shared border")

	var R := gen_type(top_a, side_a, true)
	var ramp := make(2, 1, [R, A])
	ramp.set_cell(Vector2i(0, 0), 1, 0)
	ramp.set_cell(Vector2i(1, 0), 2, 1)
	g = GenerateBuilder.build(ramp, Rect2i(0, 0, 1, 1))
	var high_ok := true
	var low_ok := true
	for p in g[top_a]:
		if is_equal_approx(p.x, 1.5) and not is_equal_approx(p.y, 0.75): high_ok = false
		if is_equal_approx(p.x, 0.0) and not is_equal_approx(p.y, 0.0): low_ok = false
	check(high_ok and low_ok, "ramp rises toward its higher neighbour")
	g = GenerateBuilder.build(ramp, Rect2i(1, 0, 1, 1))
	var faces_ramp := false
	var hs: PackedVector3Array = g.get(side_a, PackedVector3Array())
	for i in range(0, hs.size(), 3):
		if is_equal_approx(hs[i].x, 1.5) and is_equal_approx(hs[i + 1].x, 1.5) and is_equal_approx(hs[i + 2].x, 1.5):
			faces_ramp = true
	check(not faces_ramp, "no wall between ramp top and its higher neighbour")

	var flat := make(3, 3, [R, A])
	flat.set_cell(Vector2i(1, 1), 1, 0)
	flat.set_cell(Vector2i(2, 1), 2, 1)
	flat.set_cell(Vector2i(1, 0), 2, 1)
	g = GenerateBuilder.build(flat, Rect2i(1, 1, 1, 1))
	check(y_range(g[top_a]) == Vector2(0, 0), "ramp with two higher neighbours stays flat")

	# Review Focus 3: missing palette entry
	var miss := make(1, 1, [A])
	miss.set_cell(Vector2i(0, 0), 3, 1)
	g = GenerateBuilder.build(miss, whole(miss))
	var total := 0
	for k in g: total += g[k].size()
	check(total == 0, "unknown type index builds nothing and does not crash")

	var empty := make(2, 2, [A])
	g = GenerateBuilder.build(empty, whole(empty))
	check(g.is_empty(), "empty map builds nothing")

	for n in [m, two, step, ramp, flat, miss, empty]: n.free()
	print("FAILS: %d" % fails)
	quit(1 if fails else 0)
