class_name Painter
## Pure painting ops. Each returns edits for TerrainMap.apply_edits ({cell, old_type, old_h, new_type, new_h})
## and never mutates the map. Only cells whose values change are included; out-of-bounds cells are skipped.


static func brush(map: TerrainMap, center: Vector2i, radius: int, type: int, h: int) -> Array:
	var out := []
	for c in disc(map, center, radius):
		_edit(map, c, type, h, out)
	return out


static func rect(map: TerrainMap, a: Vector2i, b: Vector2i, type: int, h: int) -> Array:
	var out := []
	var lo := Vector2i(maxi(mini(a.x, b.x), 0), maxi(mini(a.y, b.y), 0))
	var hi := Vector2i(mini(maxi(a.x, b.x), map.size.x - 1), mini(maxi(a.y, b.y), map.size.y - 1))
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			_edit(map, Vector2i(x, z), type, h, out)
	return out


## 4-connected flood over cells with the same type and height as start.
static func fill(map: TerrainMap, start: Vector2i, type: int, h: int) -> Array:
	var out := []
	if not map.in_bounds(start):
		return out
	var want := Vector2i(map.get_type(start), map.get_height(start))
	if want == Vector2i(type, clampi(h, 0, 255)):
		return out
	var seen := {start: true}
	var todo: Array[Vector2i] = [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		_edit(map, c, type, h, out)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if map.in_bounds(n) and not seen.has(n) and Vector2i(map.get_type(n), map.get_height(n)) == want:
				seen[n] = true
				todo.append(n)
	return out


## Adds delta to non-empty cells (clamped 0..255); negative delta lowers.
static func raise(map: TerrainMap, center: Vector2i, radius: int, delta: int) -> Array:
	var out := []
	for c in disc(map, center, radius):
		if map.get_type(c) != 0:
			_edit(map, c, map.get_type(c), map.get_height(c) + delta, out)
	return out


static func flatten(map: TerrainMap, center: Vector2i, radius: int, h: int) -> Array:
	var out := []
	for c in disc(map, center, radius):
		if map.get_type(c) != 0:
			_edit(map, c, map.get_type(c), h, out)
	return out


## First non-empty cell the ray hits (its top, or its side when the ray enters below the top), in
## map-local space. Walks the cells the ray crosses on X/Z. Returns (-1,-1) on a miss.
static func pick(map: TerrainMap, from: Vector3, dir: Vector3) -> Vector2i:
	var miss := Vector2i(-1, -1)
	var T := LevelGrid.TILE
	if Vector2(dir.x, dir.z).length_squared() < 1e-12:
		var c := map.local_to_cell(from)
		if dir.y < 0 and map.get_type(c) != 0 and from.y >= map.get_height(c) * LevelGrid.STEP:
			return c
		return miss
	# clip the ray to the map rectangle on X/Z
	var t0 := 0.0
	var t1 := INF
	var lo := [0.0, 0.0]
	var hi := [map.size.x * T, map.size.y * T]
	var o := [from.x, from.z]
	var d := [dir.x, dir.z]
	for i in 2:
		if absf(d[i]) < 1e-12:
			if o[i] < lo[i] or o[i] > hi[i]:
				return miss
			continue
		var a: float = (lo[i] - o[i]) / d[i]
		var b: float = (hi[i] - o[i]) / d[i]
		t0 = maxf(t0, minf(a, b))
		t1 = minf(t1, maxf(a, b))
	if t0 >= t1:
		return miss
	var p := from + dir * (t0 + 1e-6)
	var c := Vector2i(clampi(floori(p.x / T), 0, map.size.x - 1), clampi(floori(p.z / T), 0, map.size.y - 1))
	var step := Vector2i(1 if dir.x > 0 else -1, 1 if dir.z > 0 else -1)
	var t := t0
	while map.in_bounds(c) and t < t1:
		var tx := INF if absf(dir.x) < 1e-12 else ((c.x + (1 if step.x > 0 else 0)) * T - from.x) / dir.x
		var tz := INF if absf(dir.z) < 1e-12 else ((c.y + (1 if step.y > 0 else 0)) * T - from.z) / dir.z
		var t_out := minf(minf(tx, tz), t1)
		if map.get_type(c) != 0:
			var top := map.get_height(c) * LevelGrid.STEP
			if minf(from.y + dir.y * t, from.y + dir.y * t_out) <= top:
				return c
		t = t_out
		if tx < tz:
			c.x += step.x
		else:
			c.y += step.y
	return miss


## Fold edits into a stroke (cell -> edit): keeps each cell's first old_* and latest new_*.
static func merge(stroke: Dictionary, edits: Array) -> void:
	for e in edits:
		if stroke.has(e.cell):
			stroke[e.cell].new_type = e.new_type
			stroke[e.cell].new_h = e.new_h
		else:
			stroke[e.cell] = e.duplicate()


static func disc(map: TerrainMap, center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := center + Vector2i(dx, dz)
			if dx * dx + dz * dz <= radius * radius and map.in_bounds(c):
				out.append(c)
	return out


static func _edit(map: TerrainMap, c: Vector2i, type: int, h: int, out: Array) -> void:
	h = clampi(h, 0, 255)
	var ot := map.get_type(c)
	var oh := map.get_height(c)
	if ot != type or oh != h:
		out.append({cell = c, old_type = ot, old_h = oh, new_type = type, new_h = h})
