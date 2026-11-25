@tool
extends EditorPlugin
## Paints the selected TerrainMap in the 3D viewport. One drag = one undo action.

const MISS := Vector2i(-1, -1)

var dock: Control
var map: TerrainMap
var stroke := {}       # cell -> edit, for the drag in progress
var painting := false
var rect_from := MISS
var cursor: MeshInstance3D


func _enter_tree() -> void:
	dock = preload("dock.gd").new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	add_undo_redo_inspector_hook_callback(_size_undo_hook)


func _exit_tree() -> void:
	remove_undo_redo_inspector_hook_callback(_size_undo_hook)
	_clear_cursor()
	remove_control_from_docks(dock)
	dock.free()


## Before a scene save: write each TerrainMap's built meshes to <scene>_<map>.terrain.res.
func _save_external_data() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path == "":
		return
	for m in root.find_children("*", "TerrainMap", true, false) + ([root] if root is TerrainMap else []):
		m.rebuild_dirty()
		var path := TerrainCache.path_for(root.scene_file_path, root.get_path_to(m))
		var cache: TerrainCache = m.make_cache()
		if ResourceSaver.save(cache, path) == OK:
			cache.take_over_path(path)
			m.mesh_cache = cache


## Inspector edits of TerrainMap.size: make undo restore the cropped cells too.
func _size_undo_hook(undo_redo: Object, object: Object, property: String, _new_value: Variant) -> void:
	if object is TerrainMap and property == "size":
		undo_redo.add_undo_method(object, &"restore_cells", object.size, object.types.duplicate(), object.heights.duplicate())


func _handles(object: Object) -> bool:
	return object is TerrainMap


func _edit(object: Object) -> void:
	if painting:
		_commit()
	_clear_cursor()
	map = object as TerrainMap
	dock.set_map(map)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if map == null or not is_instance_valid(map) or not map.is_inside_tree():
		return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and dock.tool == &"object":
		dock.turns = (dock.turns + 1) % 4
		return AFTER_GUI_INPUT_STOP
	if not event is InputEventMouse:
		return AFTER_GUI_INPUT_PASS
	var inv := map.global_transform.affine_inverse()
	var from := inv * camera.project_ray_origin(event.position)
	var dir := (inv.basis * camera.project_ray_normal(event.position)).normalized()
	var c := Painter.pick(map, from, dir)
	_draw_cursor(c)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if c == MISS:
				return AFTER_GUI_INPUT_PASS
			if dock.tool == &"object":
				_place_object(c, from, dir)
				return AFTER_GUI_INPUT_STOP
			if dock.tool == &"pick":
				dock.set_type(map.get_type(c))
				dock.set_height(map.get_height(c))
				return AFTER_GUI_INPUT_STOP
			painting = true
			stroke.clear()
			rect_from = c
			if dock.tool != &"rect":
				_apply(c)
			return AFTER_GUI_INPUT_STOP
		if painting:
			if dock.tool == &"rect" and c != MISS:
				_apply_edits(Painter.rect(map, rect_from, c, dock.type, dock.height))
			_commit()
			return AFTER_GUI_INPUT_STOP
	elif event is InputEventMouseMotion and painting:
		if c != MISS and dock.tool not in [&"rect", &"fill"]:
			_apply(c)
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _apply(c: Vector2i) -> void:
	var r: int = dock.radius
	var edits: Array
	match dock.tool:
		&"brush": edits = Painter.brush(map, c, r, dock.type, dock.height)
		&"fill": edits = Painter.fill(map, c, dock.type, dock.height)
		&"raise": edits = Painter.raise(map, c, r, 1)
		&"lower": edits = Painter.raise(map, c, r, -1)
		&"flatten": edits = Painter.flatten(map, c, r, dock.height)
	if dock.tool in [&"raise", &"lower"]:
		edits = edits.filter(func(e): return not stroke.has(e.cell))  # once per cell per stroke
	_apply_edits(edits)


func _apply_edits(edits: Array) -> void:
	map.apply_edits(edits, true)  # live preview; the undo action is committed on release
	Painter.merge(stroke, edits)


func _place_object(c: Vector2i, from: Vector3, dir: Vector3) -> void:
	if dock.object_path == "":
		return
	var top := map.get_height(c) * LevelGrid.STEP
	var hit := map.cell_top(c)
	if absf(dir.y) > 1e-6:
		var p := from + dir * ((top - from.y) / dir.y)
		if map.local_to_cell(p) == c:
			hit = p
	var root := EditorInterface.get_edited_scene_root()
	var obj := ObjectPlacer.place(map, root, dock.object_path, ObjectPlacer.snap(map, hit), dock.turns)
	var parent := obj.get_parent()
	var ur := get_undo_redo()
	ur.create_action("Place object", UndoRedo.MERGE_DISABLE, map)
	ur.add_do_method(parent, &"add_child", obj, true)
	ur.add_do_property(obj, &"owner", root)
	ur.add_do_reference(obj)
	ur.add_undo_method(parent, &"remove_child", obj)
	ur.commit_action(false)


func _commit() -> void:
	painting = false
	if stroke.is_empty():
		return
	var edits := stroke.values()
	stroke = {}
	var ur := get_undo_redo()
	ur.create_action("Paint terrain", UndoRedo.MERGE_DISABLE, map)
	ur.add_do_method(map, &"apply_edits", edits, true)
	ur.add_undo_method(map, &"apply_edits", edits, false)
	ur.commit_action(false)


func _draw_cursor(c: Vector2i) -> void:
	if cursor == null or not is_instance_valid(cursor):
		cursor = MeshInstance3D.new()
		cursor.name = "_cursor"
		cursor.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mat.albedo_color = Color(1, 0.85, 0.2)
		cursor.material_override = mat
		map.add_child(cursor)  # owner stays null: never saved
	var im: ImmediateMesh = cursor.mesh
	im.clear_surfaces()
	if c == MISS:
		return
	var cells: Array[Vector2i] = []
	if painting and dock.tool == &"rect":
		for z in range(mini(rect_from.y, c.y), maxi(rect_from.y, c.y) + 1):
			for x in range(mini(rect_from.x, c.x), maxi(rect_from.x, c.x) + 1):
				cells.append(Vector2i(x, z))
	elif dock.tool in [&"fill", &"pick"]:
		cells = [c]
	else:
		cells = Painter.disc(map, c, dock.radius)
	var T := LevelGrid.TILE
	var lines := PackedVector3Array()
	for cell in cells:
		if not map.in_bounds(cell):
			continue
		var y := map.get_height(cell) * LevelGrid.STEP + 0.02
		var p := [Vector3(cell.x * T, y, cell.y * T), Vector3((cell.x + 1) * T, y, cell.y * T),
			Vector3((cell.x + 1) * T, y, (cell.y + 1) * T), Vector3(cell.x * T, y, (cell.y + 1) * T)]
		for i in 4:
			lines.append_array([p[i], p[(i + 1) % 4]])
	if lines.is_empty():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for v in lines:
		im.surface_add_vertex(v)
	im.surface_end()


func _clear_cursor() -> void:
	if cursor and is_instance_valid(cursor):
		cursor.queue_free()
	cursor = null
