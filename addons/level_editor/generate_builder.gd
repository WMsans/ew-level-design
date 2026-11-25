class_name GenerateBuilder
## Generate-mode geometry: per cell a top (flat or ramp) plus side faces down to lower neighbours.
## The higher cell owns a shared face. Output: { Material: PackedVector3Array } triangle list,
## Godot front-face winding (normal = Plane(a, b, c).normal points outward).

# Corner order: NW (x0,z0), NE (x1,z0), SE (x1,z1), SW (x0,z1).
const _CORNER := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
# Per edge: neighbour offset, my two corners, the neighbour's matching corners, outward normal.
const _EDGES := [
	[Vector2i(0, -1), 0, 1, 3, 2, Vector3(0, 0, -1)],
	[Vector2i(1, 0), 1, 2, 0, 3, Vector3(1, 0, 0)],
	[Vector2i(0, 1), 2, 3, 1, 0, Vector3(0, 0, 1)],
	[Vector2i(-1, 0), 3, 0, 2, 1, Vector3(-1, 0, 0)],
]


static func build(map: TerrainMap, rect: Rect2i, warned := {}) -> Dictionary:
	var acc := {}  # Material -> Array[Vector3] (reference type, appended in place)
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, z)
			var t := map.get_type(c)
			if t == 0:
				continue
			var tt := map.tile_type(t)
			if tt == null:
				var msg := "TerrainMap %s: no TileType for type index %d" % [map.name, t]
				if not warned.has(msg):
					warned[msg] = true
					push_warning(msg)
				continue
			if tt.mode != TileType.Mode.GENERATE:
				continue
			var y := corner_heights(map, c)
			var p: Array[Vector3] = []
			for i in 4:
				p.append(Vector3((x + _CORNER[i].x) * LevelGrid.TILE, y[i], (z + _CORNER[i].y) * LevelGrid.TILE))
			var top: Array = acc.get_or_add(tt.top_material, [])
			_tri(top, p[0], p[1], p[2], Vector3.UP)
			_tri(top, p[0], p[2], p[3], Vector3.UP)
			var side: Array = acc.get_or_add(tt.side_material, [])
			for e in _EDGES:
				var ny := corner_heights(map, c + e[0])
				var a: Vector3 = p[e[1]]
				var b: Vector3 = p[e[2]]
				var qa := Vector3(a.x, minf(ny[e[3]], a.y), a.z)
				var qb := Vector3(b.x, minf(ny[e[4]], b.y), b.z)
				_tri(side, a, b, qb, e[5])
				_tri(side, a, qb, qa, e[5])
	var out := {}
	for m in acc:
		if not acc[m].is_empty():
			out[m] = PackedVector3Array(acc[m])
	return out


## Corner heights in metres [NW, NE, SE, SW]. Empty / out-of-bounds cells are ground level 0.
## A ramp cell raises the two corners facing its single neighbour at h+1.
static func corner_heights(map: TerrainMap, c: Vector2i) -> PackedFloat32Array:
	var h := map.get_height(c) if map.get_type(c) != 0 else 0
	var y := float(h) * LevelGrid.STEP
	var out := PackedFloat32Array([y, y, y, y])
	var tt := map.tile_type(map.get_type(c))
	if tt == null or not tt.is_ramp or tt.mode != TileType.Mode.GENERATE:
		return out
	var up := -1
	for i in 4:
		var n: Vector2i = c + _EDGES[i][0]
		if map.get_type(n) != 0 and map.get_height(n) == h + 1:
			if up != -1:
				return out  # more than one higher neighbour: flat
			up = i
	if up != -1:
		out[_EDGES[up][1]] = y + LevelGrid.STEP
		out[_EDGES[up][2]] = y + LevelGrid.STEP
	return out


static func _tri(out: Array, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	var cr := (a - c).cross(a - b)  # same orientation as Plane(a, b, c).normal
	if cr.length_squared() < 1e-10:
		return
	if cr.dot(n) < 0:
		out.append_array([a, c, b])
	else:
		out.append_array([a, b, c])
