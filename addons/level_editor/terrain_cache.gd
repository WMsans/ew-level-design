class_name TerrainCache
extends Resource
## Built chunk meshes + collision saved next to a level so it loads without rebuilding.
## Used only while `key` matches the map's data (TerrainMap.cache_key()).

@export var key := 0
@export var meshes := {}  # chunk Vector2i -> ArrayMesh
@export var shapes := {}  # chunk Vector2i -> ConcavePolygonShape3D


## Sidecar file for one map: <scene>_<node path from root>.terrain.res (unique per map).
static func path_for(scene_path: String, map_path: NodePath) -> String:
	return "%s_%s.terrain.res" % [scene_path.get_basename(), String(map_path).replace("/", "_").validate_filename()]
