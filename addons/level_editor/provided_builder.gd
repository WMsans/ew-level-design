class_name ProvidedBuilder
## Provided-mode geometry: dual-grid autotile. Pieces sit on grid corners (each covers a quarter of
## the 4 cells around it, modelled centred on the origin, TILE x TILE). Output: [{scene, xform}].
##
## Mask bits around corner (x,z): NW=1 (x-1,z-1), NE=2 (x,z-1), SW=4 (x-1,z), SE=8 (x,z).
## Canonical models (turn 0): outer_corner = SE filled, edge = SW+SE, inner_corner = all but NW,
## opposite_corners = NW+SE. A turn is +90° about +Y (counter-clockwise seen from above).

const _CELLS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]  # NW NE SW SE
const _BASE := {&"full": 15, &"outer_corner": 8, &"edge": 12, &"inner_corner": 14, &"opposite_corners": 9}
const _WALL := {&"outer_corner": &"wall_outer_corner", &"edge": &"wall_edge", &"inner_corner": &"wall_inner_corner"}

static var _lookup := {}  # mask -> [piece, turns]


static func piece_for_mask(mask: int) -> Array:
	if _lookup.is_empty():
		for p in _BASE:
			var m: int = _BASE[p]
			for t in 4:
				if not _lookup.has(m):
					_lookup[m] = [p, t]
				m = _rot(m)
	return _lookup.get(mask, [&"", 0])


## One +90° turn: SE->NE, NE->NW, NW->SW, SW->SE.
static func _rot(m: int) -> int:
	return (8 if m & 4 else 0) | (2 if m & 8 else 0) | (1 if m & 2 else 0) | (4 if m & 1 else 0)


static func build(map: TerrainMap, rect: Rect2i, warned := {}) -> Array:
	var out := []
	if not map.palette.any(func(t): return t != null and t.mode == TileType.Mode.PROVIDED):
		return out  # nothing to place: skip the corner scan (most of a generate-only rebuild)
	var x_end := rect.end.x + (1 if rect.end.x >= map.size.x else 0)
	var z_end := rect.end.y + (1 if rect.end.y >= map.size.y else 0)
	for z in range(rect.position.y, z_end):
		for x in range(rect.position.x, x_end):
			_corner(map, Vector2i(x, z), out, warned)
	return out


static func _corner(map: TerrainMap, corner: Vector2i, out: Array, warned: Dictionary) -> void:
	var levels := []
	for i in 4:
		var c: Vector2i = corner + _CELLS[i]
		if map.get_type(c) != 0 and not levels.has(map.get_height(c)):
			levels.append(map.get_height(c))
	levels.sort()
	levels.reverse()
	# ponytail: lower levels also place a top piece hidden under the higher ones (overdraw); cull if profiling says so
	for li in levels.size():
		var L: int = levels[li]
		var below: int = levels[li + 1] if li + 1 < levels.size() else 0
		var higher := 0  # cells above L count as filled for every type at L (the cliff above covers the rim)
		var at_l := {}   # type index -> mask of its cells at exactly L
		for i in 4:
			var c: Vector2i = corner + _CELLS[i]
			var t := map.get_type(c)
			if t == 0:
				continue
			if map.get_height(c) > L:
				higher |= 1 << i
			elif map.get_height(c) == L:
				at_l[t] = at_l.get(t, 0) | (1 << i)
		for t in at_l:
			var tt := map.tile_type(t)
			if tt == null:
				_warn(warned, "TerrainMap %s: no TileType for type index %d" % [map.name, t])
				continue
			if tt.mode != TileType.Mode.PROVIDED:
				continue
			var pt: Array = piece_for_mask(at_l[t] | higher)
			var pos := Vector3(corner.x * LevelGrid.TILE, L * LevelGrid.STEP, corner.y * LevelGrid.TILE)
			_place(out, tt, pt[0], pt[1], pos, warned)
			if pt[0] == &"full":
				continue
			for k in L - below:
				var wy := Vector3(pos.x, (L - 1 - k) * LevelGrid.STEP, pos.z)
				if pt[0] == &"opposite_corners":
					_place(out, tt, &"wall_outer_corner", pt[1], wy, warned)
					_place(out, tt, &"wall_outer_corner", pt[1] + 2, wy, warned)
				else:
					_place(out, tt, _WALL[pt[0]], pt[1], wy, warned)


static func _place(out: Array, tt: TileType, piece: StringName, turns: int, pos: Vector3, warned: Dictionary) -> void:
	var scene: PackedScene = tt.get(piece)
	if scene == null:
		_warn(warned, "TileType %s: provided piece '%s' is not set" % [tt.resource_path, piece])
		return
	out.append({scene = scene, xform = Transform3D(Basis(Vector3.UP, turns * PI / 2), pos)})


static func _warn(warned: Dictionary, msg: String) -> void:
	if not warned.has(msg):
		warned[msg] = true
		push_warning(msg)
