# Headless check:  godot --headless --path . --script res://tests/test_provided.gd
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails += 1

func piece(n: String) -> PackedScene:
	var root := Node3D.new()
	root.name = n
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps

func provided_type() -> TileType:
	var t := TileType.new()
	t.mode = TileType.Mode.PROVIDED
	for n in ["full", "edge", "outer_corner", "inner_corner", "opposite_corners", "wall_edge", "wall_outer_corner", "wall_inner_corner"]:
		t.set(n, piece(n))
	return t

func make(w: int, h: int, pal: Array) -> TerrainMap:
	var m := TerrainMap.new()
	m.resize(Vector2i(w, h))
	m.palette.assign(pal)
	return m

func names(placements: Array, t: TileType) -> Array:
	var out := []
	for p in placements:
		for n in ["full", "edge", "outer_corner", "inner_corner", "opposite_corners", "wall_edge", "wall_outer_corner", "wall_inner_corner"]:
			if t.get(n) == p.scene: out.append(n)
	return out

func turns(x: Transform3D) -> int:
	# quarter turns about +Y from where +X ends up
	return posmod(roundi(atan2(-x.basis.x.z, x.basis.x.x) / (PI / 2)), 4)

func _initialize() -> void:
	var cases := {15: [&"full", 0], 8: [&"outer_corner", 0], 12: [&"edge", 0], 14: [&"inner_corner", 0],
		9: [&"opposite_corners", 0], 1: [&"outer_corner", 2], 3: [&"edge", 2], 7: [&"inner_corner", 2],
		6: [&"opposite_corners", 1], 2: [&"outer_corner", 1], 5: [&"edge", 3], 0: [&"", 0]}
	for mask in cases:
		check(ProvidedBuilder.piece_for_mask(mask) == cases[mask], "mask %d -> %s" % [mask, cases[mask]])

	var P := provided_type()
	var one := make(1, 1, [P])
	one.set_cell(Vector2i(0, 0), 1, 0)
	var pl := ProvidedBuilder.build(one, Rect2i(0, 0, 1, 1))
	check(pl.size() == 4 and names(pl, P).count("outer_corner") == 4, "1x1 at h0: four outer corners")
	var rots := {}
	for p in pl: rots[turns(p.xform)] = true
	check(rots.size() == 4, "the four corners have four different rotations")
	check(pl.all(func(p): return is_zero_approx(p.xform.origin.y)), "h0 pieces at y=0")
	var corner_at_origin = pl.filter(func(p): return p.xform.origin.is_equal_approx(Vector3.ZERO))
	check(corner_at_origin.size() == 1 and turns(corner_at_origin[0].xform) == 0, "corner (0,0) sees the cell at SE: outer_corner turn 0")

	var tall := make(1, 1, [P])
	tall.set_cell(Vector2i(0, 0), 1, 2)
	pl = ProvidedBuilder.build(tall, Rect2i(0, 0, 1, 1))
	var n := names(pl, P)
	check(pl.size() == 12, "1x1 at h2: 4 tops + 8 walls")
	check(n.count("wall_outer_corner") == 8, "walls are wall_outer_corner")
	var ys := {}
	for p in pl: if t_is(P, p, "wall_outer_corner"): ys[snappedf(p.xform.origin.y, 0.01)] = true
	check(ys.has(0.75) and ys.has(0.0) and ys.size() == 2, "walls stacked at y=0.75 and y=0")

	var step := make(2, 1, [P])
	step.set_cell(Vector2i(0, 0), 1, 2)
	step.set_cell(Vector2i(1, 0), 1, 1)
	pl = ProvidedBuilder.build(step, Rect2i(0, 0, 2, 1))
	var at := pl.filter(func(p): return is_equal_approx(p.xform.origin.x, 1.5) and is_zero_approx(p.xform.origin.z))
	var desc := []
	for p in at: desc.append([names([p], P)[0], snappedf(p.xform.origin.y, 0.01)])
	desc.sort()
	check(desc == [["edge", 0.75], ["outer_corner", 1.5], ["wall_edge", 0.0], ["wall_outer_corner", 0.75]], "step corner: outer at L2 + 1 wall, edge at L1 + 1 wall  %s" % [desc])

	# chunk border: corners shared by two rects are placed once
	var wide := make(32, 1, [P])
	for x in 32: wide.set_cell(Vector2i(x, 0), 1, 0)
	var left := ProvidedBuilder.build(wide, Rect2i(0, 0, 16, 1))
	var right := ProvidedBuilder.build(wide, Rect2i(16, 0, 16, 1))
	check(left.size() + right.size() == 33 * 2, "adjacent chunks place each corner once")

	# Review Focus 4: missing piece scene
	var gap := provided_type()
	gap.wall_edge = null
	var g := make(2, 1, [gap])
	g.set_cell(Vector2i(0, 0), 1, 2)
	g.set_cell(Vector2i(1, 0), 1, 1)
	pl = ProvidedBuilder.build(g, Rect2i(0, 0, 2, 1))
	check(pl.all(func(p): return p.scene != null), "missing piece is skipped, not placed as null")

	# Review Focus 3: unknown type index
	var miss := make(1, 1, [P])
	miss.set_cell(Vector2i(0, 0), 4, 1)
	check(ProvidedBuilder.build(miss, Rect2i(0, 0, 1, 1)).is_empty(), "unknown type builds nothing")

	var gen := make(1, 1, [TileType.new()])
	gen.set_cell(Vector2i(0, 0), 1, 1)
	check(ProvidedBuilder.build(gen, Rect2i(0, 0, 1, 1)).is_empty(), "generate-mode cells are ignored")

	for m in [one, tall, step, wide, g, miss, gen]: m.free()
	print("FAILS: %d" % fails)
	quit(1 if fails else 0)

func t_is(t: TileType, p: Dictionary, n: String) -> bool:
	return t.get(n) == p.scene
