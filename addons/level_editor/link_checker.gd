class_name LinkChecker
## Validates Exit -> EntryPoint links between level scenes.


## entry_name of every EntryPoint in the scene (including inside sub-scenes). Empty if missing.
static func entries_in(scene_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not ResourceLoader.exists(scene_path):
		return out
	var root: Node = load(scene_path).instantiate()
	for n in _walk(root):
		if n is EntryPoint:
			out.append(String(n.entry_name))
	root.free()
	return out


## Human-readable problems: missing target levels, missing target entries, duplicate entry names.
static func check(level_paths: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var cache := {}
	for path in level_paths:
		var root: Node = load(path).instantiate()
		var seen := {}
		for n in _walk(root):
			if n is EntryPoint:
				if seen.has(n.entry_name):
					var msg := "%s: duplicate entry '%s'" % [path, n.entry_name]
					if msg not in out:
						out.append(msg)
				seen[n.entry_name] = true
			elif n is Exit:
				var where := root.get_path_to(n)
				if not ResourceLoader.exists(n.target_level):
					out.append("%s: Exit %s → missing level %s" % [path, where, n.target_level])
					continue
				if not cache.has(n.target_level):
					cache[n.target_level] = entries_in(n.target_level)
				if String(n.target_entry) not in cache[n.target_level]:
					out.append("%s: Exit %s → no entry '%s' in %s" % [path, where, n.target_entry, n.target_level])
		root.free()
	return out


## Every .tscn under dir that contains a TerrainMap (text check on the scene file).
static func find_levels(dir := "res://") -> PackedStringArray:
	var out := PackedStringArray()
	for p in ObjectPlacer.list_scenes(dir):
		if FileAccess.get_file_as_string(p).contains("res://addons/level_editor/terrain_map.gd"):
			out.append(p)
	return out


static func _walk(n: Node) -> Array[Node]:
	var out: Array[Node] = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
