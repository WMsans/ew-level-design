@tool
class_name TerrainMap
extends Node3D
## One room: painted tile types + heights. Cell (x,z) spans [x*TILE,(x+1)*TILE] on X/Z, top at h*STEP.
## types: 0 = empty, t > 0 -> palette[t-1]. Row-major (index = z*size.x + x).

## Map size in tiles. Changing it keeps overlapping cells (anchored at cell 0,0).
@export var size := Vector2i(32, 32):
	set(v):
		v = v.max(Vector2i.ZERO)
		if v == size:
			return
		var old := size
		_mark_all_dirty()  # old extent: chunks past a shrunk edge get removed
		size = v
		_cache_ok = false
		_reshape(old)
## Changing the palette on a live map rebuilds it.
@export var palette: Array[TileType] = []:
	set(v):
		palette = v
		if is_inside_tree():
			rebuild_all()
## Saved by the editor plugin on scene save (<scene>_<map>.terrain.res). Ignored when stale.
@export var mesh_cache: TerrainCache
@export_storage var types := PackedByteArray()
@export_storage var heights := PackedByteArray()

var dirty := {}  # chunk Vector2i -> true
var _cache_ok := false
var _warned := {}  # warnings already given during the current rebuild


func _init() -> void:
	if types.is_empty():
		_reshape(Vector2i.ZERO)


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < size.x and c.y < size.y


func get_type(c: Vector2i) -> int:
	return types[c.y * size.x + c.x] if in_bounds(c) else 0


func get_height(c: Vector2i) -> int:
	return heights[c.y * size.x + c.x] if in_bounds(c) else 0


func set_cell(c: Vector2i, type: int, h: int) -> void:
	if not in_bounds(c):
		return
	var i := c.y * size.x + c.x
	types[i] = type
	heights[i] = clampi(h, 0, 255)
	_cache_ok = false
	_mark_dirty(c)


func tile_type(t: int) -> TileType:
	return palette[t - 1] if t > 0 and t <= palette.size() else null


func resize(new_size: Vector2i) -> void:
	size = new_size


## Undo of an Inspector size edit: restores size and cells together (order-independent with the
## Inspector's own size undo, since setting an unchanged size is a no-op).
func restore_cells(sz: Vector2i, t: PackedByteArray, h: PackedByteArray) -> void:
	size = sz
	types = t.duplicate()
	heights = h.duplicate()
	_cache_ok = false
	_mark_all_dirty()


## Rebuild the cell arrays for the current size from data laid out at old_size.
func _reshape(old_size: Vector2i) -> void:
	var nt := PackedByteArray()
	var nh := PackedByteArray()
	nt.resize(size.x * size.y)
	nh.resize(size.x * size.y)
	if types.size() == old_size.x * old_size.y:  # on scene load the arrays arrive after size: nothing to copy
		for z in mini(old_size.y, size.y):
			for x in mini(old_size.x, size.x):
				nt[z * size.x + x] = types[z * old_size.x + x]
				nh[z * size.x + x] = heights[z * old_size.x + x]
	types = nt
	heights = nh
	_mark_all_dirty()


func local_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / LevelGrid.TILE), floori(p.z / LevelGrid.TILE))


func cell_top(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * LevelGrid.TILE, get_height(c) * LevelGrid.STEP, (c.y + 0.5) * LevelGrid.TILE)


func room_aabb() -> AABB:
	var max_h := 0
	for h in heights:
		max_h = maxi(max_h, h)
	return AABB(Vector3.ZERO, Vector3(size.x * LevelGrid.TILE, max_h * LevelGrid.STEP, size.y * LevelGrid.TILE))


## edits: [{cell, old_type, old_h, new_type, new_h}]. forward=false restores the old values (undo).
func apply_edits(edits: Array, forward: bool) -> void:
	for e in edits:
		if forward:
			set_cell(e.cell, e.new_type, e.new_h)
		else:
			set_cell(e.cell, e.old_type, e.old_h)


func _ready() -> void:
	rebuild_all()
	set_process(Engine.is_editor_hint())


func _process(_dt: float) -> void:
	if not dirty.is_empty():
		rebuild_dirty()


func chunk_node(ch: Vector2i) -> Node3D:
	return get_node_or_null("_chunk_%d_%d" % [ch.x, ch.y])


func rebuild_all() -> void:
	_fix_arrays()
	_cache_ok = mesh_cache != null and mesh_cache.key == cache_key()
	for n in get_children():
		if n.name.begins_with("_chunk_"):
			remove_child(n)
			n.free()
	_mark_all_dirty()
	rebuild_dirty()


func rebuild_dirty() -> void:
	_warned.clear()
	for ch in dirty:
		var old := chunk_node(ch)
		if old:
			remove_child(old)
			old.free()
		var rect := Rect2i(ch * LevelGrid.CHUNK, Vector2i(LevelGrid.CHUNK, LevelGrid.CHUNK)).intersection(Rect2i(Vector2i.ZERO, size))
		if rect.has_area():
			add_child(_build_chunk(ch, rect))  # owner stays null: generated, never saved
	dirty.clear()


func _build_chunk(ch: Vector2i, rect: Rect2i) -> Node3D:
	var node := Node3D.new()
	node.name = "_chunk_%d_%d" % [ch.x, ch.y]
	if _cache_ok:
		if mesh_cache.meshes.has(ch):
			_add_mesh(node, mesh_cache.meshes[ch], mesh_cache.shapes[ch], true)
	else:
		_build_generated(node, rect)
	for p in ProvidedBuilder.build(self, rect, _warned):
		var inst: Node3D = p.scene.instantiate()
		inst.transform = p.xform
		node.add_child(inst)
		if inst.find_children("*", "CollisionObject3D", true, false).is_empty():
			for m in inst.find_children("*", "MeshInstance3D", true, false):
				m.create_trimesh_collision()
	return node


## Data fingerprint for the mesh cache: cells + what each palette entry builds.
func cache_key() -> int:
	var pal := []
	for t in palette:
		pal.append([t.mode, t.is_ramp] if t else null)  # materials are re-applied from the palette, not cached
	return hash([size, types, heights, pal])


## Snapshot of the currently built chunk meshes + collision.
func make_cache() -> TerrainCache:
	var c := TerrainCache.new()
	c.key = cache_key()
	for n in get_children():
		if not n.name.begins_with("_chunk_"):
			continue
		var mis := n.find_children("*", "MeshInstance3D", false, false)
		var bodies := n.find_children("*", "StaticBody3D", false, false)
		if mis.is_empty() or bodies.is_empty():
			continue
		var p: PackedStringArray = String(n.name).trim_prefix("_chunk_").split("_")
		var ch := Vector2i(int(p[0]), int(p[1]))
		var mesh: ArrayMesh = mis[0].mesh.duplicate()
		for i in mesh.get_surface_count():
			mesh.surface_set_material(i, null)  # no material copies in the cache file
		c.meshes[ch] = mesh
		c.shapes[ch] = bodies[0].get_child(0).shape
	return c


func _add_mesh(node: Node3D, mesh: ArrayMesh, shape: Shape3D, from_cache := false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if from_cache:
		for i in mesh.get_surface_count():
			mi.set_surface_override_material(i, _slot_material(mesh.surface_get_name(i)))
	node.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	node.add_child(body)


func _build_generated(node: Node3D, rect: Rect2i) -> void:
	var surfaces := GenerateBuilder.build(self, rect, _warned)
	if not surfaces.is_empty():
		var mesh := ArrayMesh.new()
		var faces := PackedVector3Array()
		for mat in surfaces:
			var tris: PackedVector3Array = surfaces[mat]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in range(0, tris.size(), 3):
				# planar UVs per triangle: tops by X/Z, walls by (X+Z, -Y); triplanar materials ignore them
				var top := absf(Plane(tris[i], tris[i + 1], tris[i + 2]).normal.y) > 0.5
				for v in [tris[i], tris[i + 1], tris[i + 2]]:
					st.set_uv(Vector2(v.x, v.z) if top else Vector2(v.x + v.z, -v.y))
					st.add_vertex(v)
			st.generate_normals()
			st.set_material(mat)
			st.commit(mesh)
			mesh.surface_set_name(mesh.get_surface_count() - 1, _slot_name(mat))
			faces.append_array(tris)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		_add_mesh(node, mesh, shape)


## Surface name "<type index>:top|side" so a cached mesh can take its material from the palette.
func _slot_name(mat: Material) -> String:
	for i in palette.size():
		if palette[i] and palette[i].top_material == mat:
			return "%d:top" % (i + 1)
		if palette[i] and palette[i].side_material == mat:
			return "%d:side" % (i + 1)
	return ""


func _slot_material(slot: String) -> Material:
	var p := slot.split(":")
	var t := tile_type(int(p[0])) if p.size() == 2 else null
	if t == null:
		return null
	return t.top_material if p[1] == "top" else t.side_material


## Cell arrays not matching size (e.g. a bad merge): report once, pad/truncate to fit.
func _fix_arrays() -> void:
	var n := size.x * size.y
	if types.size() != n or heights.size() != n:
		push_error("TerrainMap %s: cell data (%d/%d) does not match size %s; resizing" % [name, types.size(), heights.size(), size])
		types.resize(n)
		heights.resize(n)


func _mark_dirty(c: Vector2i) -> void:
	# radius 2: a cell's faces depend on neighbours, and a ramp's corners on its neighbours' heights
	var lo := Vector2i(maxi(c.x - 2, 0), maxi(c.y - 2, 0)) / LevelGrid.CHUNK
	var hi := Vector2i(mini(c.x + 2, size.x - 1), mini(c.y + 2, size.y - 1)) / LevelGrid.CHUNK
	for cz in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			dirty[Vector2i(cx, cz)] = true


func _mark_all_dirty() -> void:
	for cz in ceili(size.y / float(LevelGrid.CHUNK)):
		for cx in ceili(size.x / float(LevelGrid.CHUNK)):
			dirty[Vector2i(cx, cz)] = true
