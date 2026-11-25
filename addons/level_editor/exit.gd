@tool
class_name Exit
extends Node3D
## Add as a child of a door / stairs scene. The game moves the player to target_entry in target_level.

@export_file("*.tscn") var target_level: String:
	set(v):
		target_level = v
		notify_property_list_changed()
@export var target_entry: StringName


func _validate_property(property: Dictionary) -> void:
	# editor only: offer the target level's entry names as a dropdown
	if property.name == "target_entry" and Engine.is_editor_hint() and target_level != "":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(LinkChecker.entries_in(target_level))
