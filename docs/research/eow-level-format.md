# How Echoes of Wisdom builds its levels (research notes, 2026-11-24)

Source: base game v1.0 RomFS (program NCA `7f18d795…`), Grezzo engine. 10,963 files.
Extraction scripts (throwaway, scratchpad): `tools/xci.py` (XCI→NCA→compressed RomFS), `tools/elo.py`.

## File layout (`/region_common/`)
| Path | What |
|---|---|
| `level/<Level>.elo` | One per level (189). `Field.elo` = whole overworld (18,442 actors). Dungeons, houses, boss rooms each get one. |
| `map/<Level>_NNN.bfres` | Room/chunk render mesh — one baked mesh per room, modelled in room-local space. Materials are shared instances (`MI_OP_tile_00`, `MI_OP_wall_00`…), i.e. kit textures reused across rooms. |
| `map/<Level>_NNN.cide` | Collision mesh (`CIDE`/`MESH`). |
| `map/<Level>_NNN.bfgrid` | Sparse voxel octree, 0.75 m voxels, byte per voxel (0 empty / 1 solid). Header: depth u16, origin xyz (cells, i16), size xyz (cells), cell size f32 = 0.75. Probably drives echo placement / spatial queries. |
| `navMesh/<Level>/AreaNNNNChunkNNNN.bfnvms` | AI nav mesh per level/area. |
| `himap/Field.himap` | Small (2 KB) overworld height/region map. Not decoded. |
| `datasheets/*.gsheet` | Tables (Region, MajorDungeonDefinition, InstancedModelList for grass/trees…). |
| `actor/`, `bfactr/` | Actor definitions (456 `.bfactr`). |

## `.elo` (magic `elo `, inner `LVLE`)
- Header: 32 `(count u32, offset u32)` pairs at 0x0C.
- **Section 0 — actors**, 124 bytes each:
  - `0x00` position f32×3 (world space)
  - `0x10` bounds: center f32×3, min f32×3, max f32×3
  - `0x44` 8 × u16 param refs (strings/values)
  - `0x54` instance hash u32, `0x58` index u32, **`0x5C` type = CRC32(actor name)** (e.g. `crc32("Pot") = 0x26f035ef`)
  - `0x60` u32 room index the actor belongs to, then flags
- **Section 7 — rooms/groups**, 48 bytes: world AABB min/max + (start,count) into section 3 (u16 actor index list). In dungeons 1 entry = 1 room (L_Dungeon001: 22 rooms = 22 map chunks). In Field it's 1,397 spatial groups.
- Section 30/31 — string offset table + string pool.
- A per-room actor (type `0xf530c40`) names the map chunk and sits at the room's world origin; mesh/grid/collision are local to it.

## Design facts that matter for our tool
- **Grid:** tile = 1.5 m, half-tile 0.75 m. 95 % of actors snap to 0.375, 81 % to 0.75 on X/Z; heights snap similarly. Room sizes are multiples of 1.5 m (e.g. 21 × 19.5 m).
- **Level = rooms + actors.** Geometry is a baked mesh per room; all gameplay (spawns, exits, doors, chests, pots, enemies, switches, grass) is typed actor placement with string params.
- **Entrances/exits are named actors** (`AreaStartCommon:WalkIn`, `AreaExitCommon:WalkOut`) linking `Level` + entry name (e.g. house → `Field` / `F_SouthernVillage001_005`).
- **Dungeons:** each room is its own chunk placed far apart in world space; side-view (2D platforming) rooms are thin slabs (4.5 m deep, at z≈0) — floors aren't stacked physically, they're separate rooms linked by ladder/warp actors.
- **Overworld:** one continuous level, 742 × 515 m, made of ~59 `Field_*` chunks + boundaries; mostly flat with a few height steps (chunk grids ~6–18 m tall).
- Grass/trees are instanced (`InstancedModelList`), placed as ordinary actors (`Lawn` alone = 3,863 in Field).
