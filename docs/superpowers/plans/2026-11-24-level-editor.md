# Level Editor Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Godot 4.7 editor plugin for painting tile types and heights in the 3D viewport. It builds room geometry per tile type, in generate or provided mode, and places and links the game's object scenes.

**Architecture:** A `@tool` `TerrainMap` node is one room. It stores the cell arrays and rebuilds 16×16-tile chunks from two pure builders (`GenerateBuilder`, `ProvidedBuilder`). The editor plugin forwards 3D-viewport input to pure painting ops (`Painter`) and applies them through `EditorUndoRedoManager`. Objects are ordinary scene instances; links are two small node scripts plus a pure checker.

**Tech Stack:** Godot 4.7.2, GDScript, headless SceneTree test scripts (same style as `../tk-building-engine/tests/test_ultra_hand.gd`).

**Spec:** `docs/superpowers/specs/2026-11-24-level-editor-design.md`

## Global Constraints

- Godot 4.7, GDScript only, no new dependencies. Plugin lives in `addons/level_editor/`.
- `TILE = 1.5` m, `STEP = 0.75` m (height step), `SNAP = 0.75` m (object X/Z snap), `CHUNK = 16` tiles. These are constants, not settings.
- Cell `(x, z)` occupies local X `[x*TILE, (x+1)*TILE]` and Z `[z*TILE, (z+1)*TILE]`. Its top is at `y = h*STEP`.
- Type value `0` = empty (no ground). Value `t > 0` → `palette[t-1]`. Heights are `0..255`.
- Every editor edit goes through `EditorUndoRedoManager`. One stroke = one undo action.
- Generated chunk nodes are never saved into the scene (`owner` left null). They are rebuilt in `_ready`, in both the editor and the game.
- The `TerrainMap`, `TileType`, `EntryPoint` and `Exit` scripts ship with the game. They must not reference `EditorInterface` or other editor-only APIs.
- After adding any `class_name` script, run `godot --headless --path . --import` once so headless tests can resolve the class.
- Tests: `godot --headless --path . --script res://tests/<file>.gd` prints `ok`/`FAIL` lines and exits with code 1 on any failure (`quit(1 if fails else 0)`). Each test file copies the 4-line `check()` helper from `../tk-building-engine/tests/test_ultra_hand.gd`.
- This folder is not a git repo. Skip commits unless the user initialises git; if they do, commit after each task.

## Review Focus

1. **Brush or fill reaching past the map edge** (cursor near the border, big brush). Expected: only in-bounds cells change, no error. Test in Task 4.
2. **Raising at 255 or lowering at 0.** Expected: the height clamps and there's no wrap-around. Test in Task 4.
3. **A cell references a palette slot that is null or missing** (a designer removed a TileType). Expected: that cell is skipped, one warning appears, and the rest still builds. Tests in Tasks 2 and 3.
4. **A provided TileType with an unset piece scene.** Expected: that piece is skipped with a warning and nothing crashes. Test in Task 3.
5. **Resizing a map that already has paint.** Expected: overlapping cells keep their values (anchored at cell 0,0), new cells are empty, and chunks rebuild. Test in Task 1.

---

## File Structure

```
addons/level_editor/
  plugin.cfg, plugin.gd       EditorPlugin: dock, 3D input, undo (Task 5)
  grid.gd                     class_name LevelGrid: constants (Task 1)
  tile_type.gd                class_name TileType extends Resource (Task 1)
  terrain_map.gd              class_name TerrainMap extends Node3D, @tool (Tasks 1, 3b)
  generate_builder.gd         class_name GenerateBuilder: pure, generate mode (Task 2)
  provided_builder.gd         class_name ProvidedBuilder: pure, dual-grid (Task 3)
  painter.gd                  class_name Painter: pure brush ops + picking (Task 4)
  dock.tscn, dock.gd          palette/tool UI (Task 5)
  object_placer.gd            class_name ObjectPlacer: list scenes, snap (Task 6)
  entry_point.gd, exit.gd     class_name EntryPoint / Exit (Task 7)
  link_checker.gd             class_name LinkChecker: pure (Task 7)
tests/
  test_terrain_map.gd, test_generate.gd, test_provided.gd, test_chunks.gd,
  test_painter.gd, test_objects.gd, test_links.gd, bench_overworld.gd
```

---

### Task 1: Grid constants, TileType, TerrainMap data

**Files:** Create `addons/level_editor/grid.gd`, `tile_type.gd`, `terrain_map.gd` (data part only). Test: `tests/test_terrain_map.gd`.

**Interfaces — Produces:**
- `LevelGrid.TILE`, `.STEP`, `.SNAP`, `.CHUNK` (const float/int).
- `TileType extends Resource`:
  - `enum Mode { GENERATE, PROVIDED }`, `@export var mode: Mode`
  - `@export var top_material: Material`, `@export var side_material: Material`
  - `@export var is_ramp: bool`, `@export var tags: PackedStringArray`
  - Provided pieces, `@export var` each a `PackedScene`: `full, edge, outer_corner, inner_corner, opposite_corners, wall_edge, wall_outer_corner, wall_inner_corner`
- `TerrainMap extends Node3D` (`@tool`), with `@export var size: Vector2i`, `@export var types: PackedByteArray`, `@export var heights: PackedByteArray`, `@export var palette: Array[TileType]`, and:
  - `in_bounds(c: Vector2i) -> bool`
  - `get_type(c) -> int`, `get_height(c) -> int`: return 0 when out of bounds
  - `set_cell(c: Vector2i, type: int, h: int) -> void`: ignores out-of-bounds; clamps h to 0..255; marks the chunk dirty
  - `tile_type(t: int) -> TileType`: null for 0, out-of-range or a null slot
  - `resize(new_size: Vector2i) -> void`
  - `local_to_cell(p: Vector3) -> Vector2i` (floor of p.x/TILE, p.z/TILE)
  - `cell_top(c) -> Vector3`: the cell's centre at its top height
  - `room_aabb() -> AABB`: from (0,0,0) to (size.x*TILE, max_h*STEP, size.y*TILE)
  - `apply_edits(edits: Array, forward: bool) -> void`: each edit is `{cell, old_type, old_h, new_type, new_h}`; sets new values when forward is true, old values when false
  - `var dirty: Dictionary` (chunk `Vector2i` → true). Rebuild comes in Task 3b.

- [ ] **Step 1: Write the failing tests** in `tests/test_terrain_map.gd`:
  - New 4×3 map: `types.size() == 12`, all cells `get_type == 0`.
  - `set_cell(Vector2i(1,2), 1, 3)`, then `get_height(Vector2i(1,2)) == 3`. Out-of-bounds `get_height(Vector2i(-1,0)) == 0`. `set_cell(Vector2i(9,9),1,1)` gives no error and no change.
  - `set_cell(c, 1, 300)` → height `255`.
  - `local_to_cell(Vector3(1.6, 0, 3.0)) == Vector2i(1, 2)`. `cell_top(Vector2i(1,2)) == Vector3(2.25, 2.25, 3.75)` with h=3.
  - `tile_type(0) == null`. `tile_type(5) == null` with a 1-entry palette. `tile_type(1)` is that entry.
  - **Resize (Review Focus 5):** paint (1,1)=type 1,h 2 and (3,2)=type 1,h 4; `resize(Vector2i(2,5))` → (1,1) still type 1/h 2, (1,4) type 0, `size == Vector2i(2,5)`, `types.size() == 10`.
  - `apply_edits([{cell=Vector2i(0,0), old_type=0, old_h=0, new_type=1, new_h=2}], true)` then `false` → back to 0/0.
  - `set_cell(Vector2i(17,0),…)` → `dirty.has(Vector2i(1,0))`.
- [ ] **Step 2:** Run `godot --headless --path . --import`, then `godot --headless --path . --script res://tests/test_terrain_map.gd`. Expected: FAIL (scripts missing).
- [ ] **Step 3:** Implement the three scripts as specified above.
- [ ] **Step 4:** Re-run the import and the test. Expected: all `ok`, exit 0.

### Task 2: GenerateBuilder (generate-mode geometry)

**Files:** Create `addons/level_editor/generate_builder.gd`. Test: `tests/test_generate.gd`.

**Interfaces:**
- Consumes: `TerrainMap` getters, `tile_type()`, `LevelGrid`.
- Produces: `static func build(map: TerrainMap, rect: Rect2i) -> Dictionary`, mapping `Material → PackedVector3Array` (triangle list, 6 verts per quad, counter-clockwise when seen from outside). It only emits geometry for cells inside `rect` whose type is `GENERATE` mode.

Rules:
- Top quad at `h*STEP`, using `top_material`.
- For each of the 4 cardinal neighbours whose height is lower, add a vertical side quad from `h*STEP` down to the neighbour's `h*STEP`, using this cell's `side_material`. Empty and out-of-bounds neighbours count as height 0.
- No side where the neighbour is equal or higher; the higher cell owns the border.
- **Ramp** (`is_ramp`): if exactly one cardinal neighbour has height `h+1`, the top is a sloped quad rising toward it, and the two side faces become triangles. Otherwise the ramp cell is flat.

- [ ] **Step 1: Write failing tests:**
  - A single cell at type 1, h=2 on a 1×1 map → the top-material array has 6 verts, all y=1.5. The side-material array has 24 verts (4 quads) with y-range [0, 1.5].
  - Two adjacent cells both at h=2 → 12 top verts, 36 side verts (the shared face is gone).
  - Cells at h=2 (type A) and h=1 (type B), adjacent → the face between them uses A's `side_material`, spanning y [0.75, 1.5].
  - A ramp at h=0 next to a cell at h=1 on +X → the top verts on the +X edge have y=0.75 and those on the −X edge have y=0.
  - A ramp with two higher neighbours → flat top (all y=0).
  - **Review Focus 3:** a cell with type 3 and a 1-entry palette → no crash, the result has no geometry for that cell, `push_warning` called. Pass `rect` covering only the cell.
- [ ] **Step 2:** Run `godot --headless --path . --script res://tests/test_generate.gd`. Expected: FAIL.
- [ ] **Step 3:** Implement `GenerateBuilder.build`. Warn once per missing type index per build (track it in a local `Dictionary`).
- [ ] **Step 4:** Re-run. Expected: all ok.

### Task 3: ProvidedBuilder (dual-grid autotile)

**Files:** Create `addons/level_editor/provided_builder.gd`. Test: `tests/test_provided.gd`.

**Interfaces:**
- Consumes: as in Task 2.
- Produces: `static func build(map: TerrainMap, rect: Rect2i) -> Array`. Each entry is `{scene: PackedScene, xform: Transform3D}`. Also `static func piece_for_mask(mask: int) -> Array`, returning `[piece_name: StringName, quarter_turns: int]`.
  - Mask bits: NW=1 (cell x-1,z-1), NE=2 (x,z-1), SW=4 (x-1,z), SE=8 (x,z).
  - Canonical models: `outer_corner` filled at SE only; `edge` filled at SW+SE; `inner_corner` filled everywhere except NW; `opposite_corners` filled at NW+SE.
  - `quarter_turns` rotates about +Y counter-clockwise seen from above. 0 bits → `[&"", 0]`.

Algorithm for dual corner `(x, z)`, where x is in `rect.position.x .. rect.end.x` (inclusive end) and likewise for z:
```
cells = the 4 cells around corner (x,z); empty/out-of-bounds cells are ignored.
levels = distinct heights of non-empty cells, sorted descending.
for i in levels.size():
    L = levels[i]; below = levels[i+1] if i+1 < levels.size() else 0
    mask = bits of non-empty cells with height >= L
    T = type of the cell(s) at exactly L (lowest type index if several)
    if tile_type(T) is null or not PROVIDED: continue
    [piece, turns] = piece_for_mask(mask)
    place piece at (x*TILE, L*STEP, z*TILE), rotated turns*90°
    for k in (L - below) steps: place wall_<piece> at y=(L-1-k)*STEP
        (edge→wall_edge, outer_corner→wall_outer_corner, inner_corner→wall_inner_corner,
         opposite_corners→ two wall_outer_corner at its two diagonal rotations, full→none)
```
`# ponytail:` comment: lower levels also emit a top piece hidden under higher ones (overdraw). Cull it later if profiling shows it matters.

- [ ] **Step 1: Write failing tests:**
  - `piece_for_mask`: 15→`full`,0. 8→`outer_corner`,0. 12→`edge`,0. 7→`inner_corner`,0. 9→`opposite_corners`,0. Plus one rotated case for each: 1, 3, 14 and 6, each with its turns value. Pick the values by drawing them out and write them into the test.
  - A 1×1 provided map at h=0 → 4 placements, all `outer_corner`, with 4 distinct quarter-turns, at y=0.
  - A 1×1 map at h=2 → 4 top pieces at y=1.5, plus 2 `wall_outer_corner` under each corner at y=0.75 and y=0 (12 placements in total).
  - A 2×1 map, (0,0)=h2 and (1,0)=h1, at corner (1,0) (cells SW=(0,0), SE=(1,0)):
    - at L=2: `outer_corner` (mask 4) at y=1.5, plus 1 `wall_outer_corner` at y=0.75
    - at L=1: `edge` (mask 12) at y=0.75, plus 1 `wall_edge` at y=0
  - **Review Focus 4:** a type with `wall_edge` unset → those placements are skipped, `push_warning` is called, no crash.
  - **Review Focus 3:** an unknown type index → skipped, no crash.
- [ ] **Step 2:** Run `godot --headless --path . --script res://tests/test_provided.gd`. Expected: FAIL.
- [ ] **Step 3:** Implement as specified.
- [ ] **Step 4:** Re-run. Expected: all ok.

### Task 3b: Chunk rebuild on TerrainMap

**Files:** Modify `addons/level_editor/terrain_map.gd`. Test: `tests/test_chunks.gd`.

**Interfaces — Produces:** `TerrainMap.rebuild_dirty() -> void`, `rebuild_all() -> void`, `chunk_node(ch: Vector2i) -> Node3D`.
- Each chunk is a child `Node3D` named `_chunk_<x>_<z>`, with `owner` left null. It contains:
  - one `MeshInstance3D` (an `ArrayMesh`, one surface per material, normals via `SurfaceTool.generate_normals()`)
  - one `StaticBody3D` with a `ConcavePolygonShape3D` built from the same triangles
  - the provided-piece instances
- `set_cell` marks a chunk dirty. On a chunk border it also marks the neighbouring chunk(s): cell edges and dual corners touch neighbours.
- `_ready` calls `rebuild_all()`. In the editor, `_process` calls `rebuild_dirty()` when `dirty` isn't empty.

- [ ] **Step 1: Write failing tests:**
  - A 32×16 map with all cells painted generate type 1 → after `rebuild_all()` there are 2 chunk nodes, each with a `MeshInstance3D` and a `StaticBody3D`.
  - `set_cell(Vector2i(5,5),…)` → `dirty` has only `(0,0)`. `set_cell(Vector2i(15,5),…)` → `dirty` has `(0,0)` and `(1,0)`.
  - Chunk nodes have `owner == null` after the map is added to a tree with an owner.
  - Pack the map with `PackedScene.pack()` → the packed state's node count is 1 (the chunk nodes aren't saved).
- [ ] **Step 2:** Run `godot --headless --path . --script res://tests/test_chunks.gd`. Expected: FAIL.
- [ ] **Step 3:** Implement as specified.
- [ ] **Step 4:** Re-run, along with all earlier tests. Expected: all ok.

### Task 4: Painter (pure painting ops + picking)

**Files:** Create `addons/level_editor/painter.gd`. Test: `tests/test_painter.gd`.

**Interfaces — Produces:** all static functions; each returns an edit `Array` in `TerrainMap.apply_edits` format and doesn't mutate the map.
- `brush(map, center: Vector2i, radius: int, type: int, h: int) -> Array`: cells within a circle (`dx²+dz² <= radius²`). Radius 0 = one cell.
- `rect(map, a: Vector2i, b: Vector2i, type: int, h: int) -> Array`
- `fill(map, start: Vector2i, type: int, h: int) -> Array`: 4-connected flood fill over cells with the same type and height as `start`
- `raise(map, center, radius, delta: int) -> Array`: keeps type, clamps 0..255, skips empty cells
- `flatten(map, center, radius, h: int) -> Array`: keeps type
- `pick(map, ray_from: Vector3, ray_dir: Vector3) -> Vector2i`, in map-local space: the first cell whose top quad the ray hits, walking cells along the ray (2D DDA over X/Z). Returns `Vector2i(-1,-1)` on a miss.
- Edits only include cells whose values actually change.

- [ ] **Step 1: Write failing tests:**
  - A brush of radius 1 at (5,5) on a 10×10 map → 5 edits.
  - **Review Focus 1:** brush radius 3 at (0,0) → every edit cell is `in_bounds`, and the count is 11 (the in-bounds quarter-disc including the axes). Rect (−2,−2)→(1,1) → 4 edits. Fill on a fresh 10×10 → 100 edits.
  - **Review Focus 2:** `raise(+1)` on h=255 → no edit. `raise(−1)` on h=0 → no edit.
  - A fill doesn't cross a cell of a different height.
  - `pick`: 4×4 map, all h=0 except (2,1) at h=4. A ray from `(3.75, 10, 2.25)` going straight down → `(2,1)`. A ray from above (0.75, ·, 0.75) going down → `(0,0)`. A ray pointing up → `(-1,-1)`.
- [ ] **Step 2:** Run `godot --headless --path . --script res://tests/test_painter.gd`. Expected: FAIL.
- [ ] **Step 3:** Implement as specified.
- [ ] **Step 4:** Re-run. Expected: all ok.

### Task 5: Editor plugin, dock and 3D painting

**Files:** Create `addons/level_editor/plugin.cfg` (name "Level Editor", script `plugin.gd`), `plugin.gd`, `dock.gd`, `dock.tscn`. Modify `project.godot` to enable the plugin (`[editor_plugins] enabled=PackedStringArray("res://addons/level_editor/plugin.cfg")`).

**Interfaces:**
- Consumes: `TerrainMap`, `Painter`.
- Produces: dock signals the plugin listens to: `tool_changed(tool: StringName)`, where tool is one of `&"brush", &"rect", &"fill", &"raise", &"lower", &"flatten", &"pick"`, plus `type_changed(type: int)`, `radius_changed(r: int)`, `height_changed(h: int)`.

Behaviour:
- `_handles(obj)` → `obj is TerrainMap`.
- `_forward_3d_gui_input(camera, event)`:
  - Convert the mouse ray to map-local space (`map.global_transform.affine_inverse()`) and call `Painter.pick`.
  - Draw a cursor highlight: an `ImmediateMesh` outline over the targeted cells, as a child of the map with `owner` null.
  - Left-drag applies the tool live with `map.apply_edits(e, true)`, merging edits per cell and keeping the first `old_*`.
  - On release, wrap the stroke in one `EditorUndoRedoManager` action ("Paint terrain") using `add_do_method(map, "apply_edits", edits, true)` and `add_undo_method(map, "apply_edits", edits, false)`, committed with `execute=false`.
  - `pick` sets the dock's type and height from the clicked cell.
  - Return `AFTER_GUI_INPUT_STOP` for handled mouse events.
- The dock lists `map.palette` entries (resource name, or the file name) plus "Empty". The type index is list index + 1, with Empty = 0.

- [ ] **Step 1:** Implement the plugin, dock and project setting.
- [ ] **Step 2:** Run `godot --headless --path . --import` and then `godot --headless --path . --editor --quit`. Expected: no script errors in the output.
- [ ] **Step 3 (manual, in the editor):**
  1. Create a `TerrainMap` with size 32×32 and a palette of two GENERATE TileTypes (grass: green top, brown side; stone: grey).
  2. Paint a cliff with brush and raise.
  3. Confirm Ctrl+Z undoes a whole stroke and Ctrl+Shift+Z redoes it.
  4. Save, reopen the scene, and confirm the terrain rebuilds and the `.tscn` contains no `_chunk_` nodes.

### Task 6: Object palette and placement

**Files:** Create `addons/level_editor/object_placer.gd`. Modify `plugin.gd` and `dock.gd`. Test: `tests/test_objects.gd`.

**Interfaces — Produces:**
- `ObjectPlacer.list_scenes(dir: String) -> PackedStringArray`: recursive, `.tscn` only, sorted. Returns empty if `dir` is missing, with no error.
- `ObjectPlacer.snap(map: TerrainMap, local_pos: Vector3) -> Vector3`: X/Z rounded to the nearest `SNAP`, and Y set to the top height of the cell under the snapped point (0 off-map).
- In the editor, the dock has an "Objects" list from `res://objects/`. With an object selected:
  - a click places an instance under the map's child `Objects` node (created on demand, owned by the scene root) at the snapped position
  - R rotates the pending object 90°
  - placement is one undo action
  - the instance is added with `owner = scene root` so it saves, and keeps its scene link (`instantiate()` plus `scene_file_path` preserved)

- [ ] **Step 1: Write failing tests:**
  - `snap(map, Vector3(1.1, 0, 0.3)) == Vector3(0.75, h*0.75, 0.0)`, with cell (0,0) at h=2 → y=1.5.
  - `list_scenes("res://tests/fixtures/objects")` returns the 2 fixture scenes in sorted order. Create `tests/fixtures/objects/a.tscn` and `sub/b.tscn` (plain `Node3D` scenes).
  - `list_scenes("res://nope")` → empty.
- [ ] **Step 2:** Run `godot --headless --path . --script res://tests/test_objects.gd`. Expected: FAIL.
- [ ] **Step 3:** Implement `ObjectPlacer` and the editor wiring.
- [ ] **Step 4:** Re-run. Expected: all ok.
- [ ] **Step 5 (manual):** Place a fixture object on a raised cell, undo it, place it again, save and reopen. The object persists and the Inspector shows its exported vars.

### Task 7: Links (EntryPoint, Exit, LinkChecker)

**Files:** Create `addons/level_editor/entry_point.gd`, `exit.gd`, `link_checker.gd`. Modify `dock.gd` (add a "Check links" button and results list). Test: `tests/test_links.gd`.

**Interfaces — Produces:**
- `EntryPoint extends Node3D`: `@export var entry_name: StringName`.
- `Exit extends Node3D`: `@export_file("*.tscn") var target_level: String`, `@export var target_entry: StringName`. In the editor, `_validate_property` gives `target_entry` a `PROPERTY_HINT_ENUM` of `LinkChecker.entries_in(target_level)`. Exit nodes are added as children of door or stairs scenes.
- `LinkChecker.entries_in(scene_path: String) -> PackedStringArray`: instantiate the scene, collect `entry_name` from every `EntryPoint` (including those inside sub-scenes), free it. Empty if the path doesn't exist.
- `LinkChecker.check(level_paths: PackedStringArray) -> PackedStringArray`, returning human-readable problems:
  - `"<level>: Exit <node path> → missing level <target>"`
  - `"<level>: Exit <node path> → no entry '<name>' in <target>"`
  - `"<level>: duplicate entry '<name>'"`
- The dock button runs `check` over every `.tscn` under `res://` that contains a `TerrainMap`, then lists the results.

- [ ] **Step 1: Write failing tests** with fixtures in `tests/fixtures/levels/`:
  - `a.tscn`: EntryPoint "start", Exit → `b.tscn`/"door"
  - `b.tscn`: EntryPoint "door" twice, Exit → `c.tscn`/"x", Exit → `a.tscn`/"nope"

  Assertions:
  - `entries_in(a) == ["start"]`
  - `check([a, b])` returns exactly 3 problems: missing level c, no entry 'nope' in a, duplicate 'door' in b
- [ ] **Step 2:** Run `godot --headless --path . --script res://tests/test_links.gd`. Expected: FAIL.
- [ ] **Step 3:** Implement as specified.
- [ ] **Step 4:** Re-run. Expected: all ok.

### Task 8: Scale check (512×512, overworld load)

**Files:** Create `tests/bench_overworld.gd`.

- [ ] **Step 1:** Write the bench.
  - Build a 512×512 `TerrainMap` with 2 GENERATE types, painted with height noise (`FastNoiseLite`, 0..8 steps).
  - Print the `rebuild_all()` time in ms.
  - Change one cell, then print the `rebuild_dirty()` time in ms.
- [ ] **Step 2:** Run `godot --headless --path . --script res://tests/bench_overworld.gd`. Targets: single-cell `rebuild_dirty` < 16 ms, `rebuild_all` < 200 ms.
- [ ] **Step 3:** Only if `rebuild_all` exceeds 200 ms, add the spec's sidecar cache.
  - Add `@export var mesh_cache: Resource` to `TerrainMap`: a resource holding a `Dictionary` (chunk → `ArrayMesh` + shape), saved as `<scene>.terrain.res` from the plugin on scene save.
  - `_ready` uses the cache when its stored `hash(types + heights)` matches, and otherwise rebuilds.
  - Re-run the bench, timing the cached load. Report the numbers to the user either way.
