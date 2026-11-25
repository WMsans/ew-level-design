# Headless check:  godot --headless --path . --script res://tests/test_objects.gd
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok: fails += 1

func _initialize() -> void:
	var m := TerrainMap.new()
	m.size = Vector2i(4, 4)
	m.set_cell(Vector2i(0, 0), 1, 2)
	check(ObjectPlacer.snap(m, Vector3(1.1, 0, 0.3)).is_equal_approx(Vector3(0.75, 1.5, 0.0)), "snap X/Z to 0.75 and sit on the cell top")
	check(ObjectPlacer.snap(m, Vector3(1.6, 9, 1.6)).is_equal_approx(Vector3(1.5, 0.0, 1.5)), "snap onto an empty cell sits at 0")
	check(ObjectPlacer.snap(m, Vector3(-5, 3, -5)).y == 0.0, "snap off the map sits at 0")

	var scenes := ObjectPlacer.list_scenes("res://tests/fixtures/objects")
	check(scenes == PackedStringArray(["res://tests/fixtures/objects/a.tscn", "res://tests/fixtures/objects/sub/b.tscn"]), "list_scenes finds .tscn recursively, sorted: %s" % [scenes])
	check(ObjectPlacer.list_scenes("res://nope").is_empty(), "missing folder lists nothing")

	var root := Node3D.new()
	root.add_child(m)
	m.owner = root
	var obj := ObjectPlacer.place(m, root, "res://tests/fixtures/objects/a.tscn", Vector3(0.75, 1.5, 0), 1)
	check(obj.get_parent().name == "Objects" and obj.get_parent().get_parent() == m, "placed under the map's Objects node")
	check(obj.owner == root and obj.get_parent().owner == root, "placed object and Objects node are saved with the scene")
	check(obj.scene_file_path == "res://tests/fixtures/objects/a.tscn", "placed object keeps its scene link")
	check(is_equal_approx(obj.rotation.y, PI / 2), "quarter turns rotate about Y")
	var again := ObjectPlacer.place(m, root, "res://tests/fixtures/objects/a.tscn", Vector3.ZERO, 0)
	check(m.get_node("Objects").get_child_count() == 2, "Objects node reused")
	var ps := PackedScene.new()
	ps.pack(root)
	check(ps.get_state().get_node_count() == 5, "root, map, Objects and both objects are packed")
	root.free()
	print("FAILS: %d" % fails)
	quit(1 if fails else 0)
