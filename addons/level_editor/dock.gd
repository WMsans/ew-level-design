@tool
extends VBoxContainer
## Level Editor dock. The plugin reads tool / type / radius / height directly.

const TOOLS := [&"brush", &"rect", &"fill", &"raise", &"lower", &"flatten", &"pick", &"object"]
const OBJECTS_DIR := "res://objects"

var tool: StringName = &"brush"
var type := 1
var radius := 0
var height := 0
var object_path := ""
var turns := 0  ## quarter turns for the next placed object (R)

var _tools := OptionButton.new()
var _types := ItemList.new()
var _radius := SpinBox.new()
var _height := SpinBox.new()
var _map: TerrainMap
var _objects := ItemList.new()
var _scenes := PackedStringArray()
var _links := ItemList.new()


func _init() -> void:
	name = "Level Editor"
	add_child(_label("Tool"))
	for t in TOOLS:
		_tools.add_item(String(t).capitalize())
	_tools.item_selected.connect(func(i): tool = TOOLS[i])
	add_child(_tools)

	add_child(_label("Tile type"))
	_types.custom_minimum_size.y = 140
	_types.item_selected.connect(func(i): type = i)
	add_child(_types)
	var refresh := Button.new()
	refresh.text = "Refresh types"
	refresh.pressed.connect(func(): set_map(_map))
	add_child(refresh)

	_radius.max_value = 16
	_radius.value_changed.connect(func(v): radius = int(v))
	add_child(_row("Brush radius", _radius))
	_height.max_value = 255
	_height.value_changed.connect(func(v): height = int(v))
	add_child(_row("Height (steps)", _height))

	add_child(_label("Objects (%s) — tool 'Object', R rotates" % OBJECTS_DIR))
	_objects.custom_minimum_size.y = 140
	_objects.item_selected.connect(func(i): object_path = _scenes[i])
	add_child(_objects)
	var refresh_obj := Button.new()
	refresh_obj.text = "Refresh objects"
	refresh_obj.pressed.connect(refresh_objects)
	add_child(refresh_obj)
	refresh_objects()

	var check := Button.new()
	check.text = "Check links"
	check.pressed.connect(_check_links)
	add_child(check)
	_links.custom_minimum_size.y = 100
	add_child(_links)


func _check_links() -> void:
	_links.clear()
	var problems := LinkChecker.check(LinkChecker.find_levels())
	for p in problems:
		_links.add_item(p)
		push_warning(p)
	if problems.is_empty():
		_links.add_item("All links OK")


func refresh_objects() -> void:
	_scenes = ObjectPlacer.list_scenes(OBJECTS_DIR)
	_objects.clear()
	for s in _scenes:
		_objects.add_item(s.trim_prefix(OBJECTS_DIR + "/").get_basename())
	if object_path not in _scenes:
		object_path = ""


func set_map(map: TerrainMap) -> void:
	_map = map
	_types.clear()
	_types.add_item("Empty")
	if map:
		for t in map.palette:
			var n := "(missing)"
			if t:
				n = t.resource_name if t.resource_name else t.resource_path.get_file().get_basename()
			_types.add_item(n)
	set_type(mini(type, _types.item_count - 1))


func set_type(t: int) -> void:
	type = t
	if t < _types.item_count:
		_types.select(t)


func set_height(h: int) -> void:
	_height.value = h  # emits value_changed -> height


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _row(t: String, c: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	var l := _label(t)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(l)
	r.add_child(c)
	return r
