# Level editor plugin — design

Date: 2026-11-24 · Project: `ew-level-design` (Godot 4.7, GDScript) · Background: `docs/research/eow-level-format.md`

## Intent
Our game is a top-down 3D action-adventure in the style of Echoes of Wisdom: the layout is a 2D grid with height steps, and dungeon floors are separate rooms joined by stairs. Modelling every room in Blender (what Grezzo effectively does with their DCC tool) is too much work for our team. We want to **paint** levels inside the Godot editor (tile types plus heights) and have the 3D geometry built for us, then place game objects and link rooms in the same place.

Users: the game's designers (not players). Success means a designer can block out a room, place its chests, doors and enemies, link it to the next room, and hit Play without opening another tool or writing code.

## Goals
1. Paint a room's **tile type** and **height** per cell directly in the 3D viewport.
2. Turn cells into geometry **per tile type**, in one of two modes:
   - **Generate:** the tool builds tops, cliff sides, walls and edges itself.
   - **Provided:** the tool picks and rotates designer-supplied pieces based on neighbouring cells (autotile).
3. Place **objects** (the game's own scenes) snapped to the grid, with each scene's exported settings edited in the Inspector.
4. **Link** rooms and levels with doors, stairs and entry points; flag broken links.
5. Work for several designers under version control (text scenes, per-room files where possible).

## Non-goals (for now)
- Side-view (2D platforming) rooms.
- Stacked floors or overpasses inside one room. A room is a single heightfield.
- Player-facing or in-game editing.
- Freeform sculpting or arbitrary mesh editing.

## Anti-goals (failure even if it "works")
- Designers have to touch code or a modelling tool for ordinary rooms.
- A separate level format that the game must parse, or a build step whose output can go stale.
- Objects defined twice (once as game scenes, again for the editor).

## Constraints
- Godot 4.7 editor plugin (`addons/level_editor/`), GDScript, `@tool` scripts. No new dependencies.
- Grid: **tile = 1.5 m**, **height step = 0.75 m**, objects snap to **0.75 m** (half-tile) on X/Z. These match the measured EoW values; they are constants, not settings.
- Every edit is undoable (`EditorUndoRedoManager`).
- Scale target: the overworld is roughly 500 × 350 tiles. A map up to 512 × 512 must stay responsive while painting (a stroke should rebuild only what changed).

## Approaches considered
- **A. Terrain node painted in the 3D viewport — chosen.** Each room is a `TerrainMap` node inside a normal scene. It stores cell data and rebuilds its own meshes and collision. Objects are ordinary child scene instances. One source of truth, no build step, and you see the real result while painting. Cost: we write the brush tools ourselves.
- **B. Paint on Godot's 2D TileMapLayer, convert to 3D.** Gets the painting UI and terrain autotiling for free, but you paint in 2D and look at 3D elsewhere, and heights fit awkwardly. Rejected because painting in 3D is the point.
- **GridMap — dropped.** It only places pieces (provided mode). Generate mode would need a second system.

The designer picked A.

## Decided design

### Scenes and rooms
- **One level = one `.tscn`.** It contains one or more `TerrainMap` nodes; **each `TerrainMap` is a room**. The overworld can be one big map (or a few). A dungeon has one map per room, placed apart in world space like EoW.
- A room's camera/bounds box is its map's extent (exposed as an AABB for the game to read).

### Cell data (stored on `TerrainMap`, saved in the scene)
- `size: Vector2i` (in tiles), plus `types: PackedByteArray` (tile-type index, 0 = empty / no ground) and `heights: PackedByteArray` (steps, 0–255), both row-major.
- `palette: Array[TileType]`, which maps a type index to a shared `TileType` resource.

### `TileType` resource (`.tres`, shared across levels)
- `mode`: Generate | Provided.
- Generate: `top_material`, `side_material` (cliffs and walls are vertical faces between cells of different height; the side always belongs to the **higher** cell's type).
- Provided: a **dual-grid** piece set, modelled for one tile and rotated by the tool (each a `PackedScene`; if it has no collision, a trimesh is made from its mesh). The designer supplies these. *(My call: dual-grid needs the fewest pieces of the standard autotile schemes.)*
  - **Top pieces** (ground surface plus rim): `full`, `edge`, `outer_corner`, `inner_corner`, `opposite_corners`.
  - **Wall pieces**, one height step (0.75 m) tall: `wall_edge`, `wall_outer_corner`, `wall_inner_corner`. They are stacked once per step of drop below the rim.
  - **Selection rule:** each dual cell looks at its 4 surrounding cells. Its top height is the highest of the 4. The mask is which of the 4 cells are at that height and of this type. The mask picks the top piece and its rotation. Lower cells get wall pieces stacked down to their own height. *(My call.)*
- `is_ramp`: a ramp cell rises one step toward its single higher cardinal neighbour. Stairs are ramp types with a stair look. *(My call.)*
- Free-form `tags` (e.g. `water`, `hurt`) the game can query. The editor gives them no special behaviour.
- **Where two types meet:** the shared border/cliff uses the higher cell's type. At equal heights each cell draws its own top.

### Painting (3D viewport, via `_forward_3d_gui_input`)
- Dock with: tile-type palette, tool (brush / rectangle / fill / raise / lower / flatten-to-picked-height / eyedropper), and brush size.
- A cursor highlight shows the target cells. Strokes are one undo step.
- Geometry rebuilds per **16 × 16-tile chunk**; only dirty chunks rebuild. *(My call.)*

### Generated output
- Each chunk is a `MeshInstance3D` (one surface per material) plus a `StaticBody3D` collision built from the same faces.
- Built at edit time and again in-game on load, so `TerrainMap`'s script ships with the game (it is not editor-only). **If loading the overworld takes over 200 ms in-game, cache the chunk meshes in a sidecar `.res` next to the scene.** *(My call.)*

### Objects
- The plugin's object palette lists scenes from a project folder (default `res://objects/`). Click to place a copy under the room's `Objects` child node.
- Snaps to 0.75 m on X/Z, sits on the terrain top at that point, and rotates in 90° steps. After that it's a normal node: move it, delete it, and edit its exported settings in the Inspector.

### Links
- The plugin ships two small scripts the game's scenes use:
  - `EntryPoint` (a unique `entry_name` within its level)
  - `Exit` (`target_level: String` path to a level `.tscn`, `target_entry: StringName`)
- A door or stairs scene attaches `Exit`. The Inspector offers a dropdown of the target level's entry names.
- **Check links** (dock button) lists every Exit whose target level or entry doesn't exist.
- The editor only stores links. Transitions are game code.

### Collaboration
- Scenes and `TileType`s are text resources. Cell arrays live on each room's node, so two designers editing different rooms in the same level conflict only if both touch the same `TerrainMap`.

## Left to the builder
- Generated geometry details: UVs (world-space triplanar is fine), edge trim/bevel or none, ramp shape, normals.
- Collision shape type (concave trimesh per chunk is fine).
- Dock layout, shortcuts, cursor visuals.
- Map resize behaviour (anchor and fill).
- Exact plugin file layout.
- Tests: a headless `godot --headless --script` check for the cell → geometry and autotile rules (same style as `../tk-building-engine/tests/`).
