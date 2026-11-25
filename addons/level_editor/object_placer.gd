class_name ObjectPlacer
## Object palette + grid placement. Objects are ordinary instances of the game's own scenes.


## Every .tscn under dir (recursive), sorted. Empty if dir is missing.
static func list_scenes(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(list_scenes(dir.path_join(sub)))
	out.sort()
	return out


## X/Z to the nearest SNAP, Y on top of the cell under that point (0 off-map or on empty cells).
static func snap(map: TerrainMap, local_pos: Vector3) -> Vector3:
	var p := Vector3(snappedf(local_pos.x, LevelGrid.SNAP), 0, snappedf(local_pos.z, LevelGrid.SNAP))
	var c := map.local_to_cell(p)
	if map.get_type(c) != 0:
		p.y = map.get_height(c) * LevelGrid.STEP
	return p


## Instances scene_path under map/Objects (created on demand) at local_pos, turned quarter_turns x 90° about Y.
## owner = scene_root so it saves. Returns the new node (already added).
static func place(map: TerrainMap, scene_root: Node, scene_path: String, local_pos: Vector3, quarter_turns: int) -> Node3D:
	var objects: Node3D = map.get_node_or_null("Objects")
	if objects == null:
		objects = Node3D.new()
		objects.name = "Objects"
		map.add_child(objects)
		objects.owner = scene_root
	var obj: Node3D = load(scene_path).instantiate()
	obj.position = local_pos
	obj.rotation.y = quarter_turns * PI / 2
	objects.add_child(obj, true)
	obj.owner = scene_root
	return obj
