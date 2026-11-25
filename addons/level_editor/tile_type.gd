@tool
class_name TileType
extends Resource
## One paintable tile type. Shared .tres across levels.

enum Mode { GENERATE, PROVIDED }

@export var mode: Mode = Mode.GENERATE
@export var is_ramp := false
@export var tags: PackedStringArray

@export_group("Generate")
@export var top_material: Material
@export var side_material: Material

@export_group("Provided pieces")
@export var full: PackedScene
@export var edge: PackedScene
@export var outer_corner: PackedScene
@export var inner_corner: PackedScene
@export var opposite_corners: PackedScene
@export var wall_edge: PackedScene
@export var wall_outer_corner: PackedScene
@export var wall_inner_corner: PackedScene
