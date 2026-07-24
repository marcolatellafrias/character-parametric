# City Generation

Technical, code-level breakdown of the procedural city generator. Three subsystems each have their own file:

- [sidewalks.md](sidewalks.md) — sidewalk zones, physical instances, the sidewalk 3D matrix, delivery doors, and traversal infrastructure (stairs + floating sidewalks).
- [bridges.md](bridges.md) — bridge ownership, count, structure, archetypes, and placement.
- [traffic.md](traffic.md) — the ambient flying-car simulation.

## Steps in order

1. **Street graph** — Voronoi graph (Poisson sampling). Each edge gets a street type: boundary, small, medium, or large.
2. **Neighborhoods** — Each graph face (polygon) gets a neighborhood type.
3. **Blocks** — Each face gets a `BlockGenerator`. The edges of the block know which street type borders them, reserving an empty margin (street offset) that visually forms the street.
4. **Internal alleyways** — Inside each block, `PathGenerator` traces small and big alleyways in the `DistortedGrid`.
5. **Clusters** — Non-alleyway cells are grouped into `BuildingCluster` via flood-fill, then subdivided (1–8 cells each).
6. **Block hearts** — Interior clusters (not on the block perimeter) have a chance of becoming "hearts": their `floor_count` is set to 0, creating empty courtyards inside the block.
7. **Building modules** — Each cell in each cluster is a `BuildingModule` per floor. Each module knows what borders its 4 sides and shrinks its core area inward (facade/alleyway offset), forming the actual building footprint.
8. **Sidewalk zones** — The non-core cells of each building module define sidewalk zones: external (between the buildable zone boundary and the building face) and internal (alleyway offset areas between buildings). See [sidewalks.md](sidewalks.md).
9. **Sidewalk 3D matrices** — Each distorted grid cell gets a 3D matrix tracking cell availability in the sidewalk zones, extruded vertically. Combined per block for cross-cell queries.
10. **Sidewalk instances** — Physical walkable surfaces spawned within sidewalk zones. Floor 0 gets sidewalks everywhere. Higher-floor floating sidewalks are bridge-dependent (rules TBD).
11. **Bridges** — Placed on graph edges. Middle parts span between opposing buildable zone boundaries. Extremes extend through external sidewalk zones to the building face. See [bridges.md](bridges.md).

---

## Grid types — there are 3

| Level | Class | Approx. size |
|---|---|---|
| City | `BlockGenerator` per graph face | 100×100 cells |
| Block | `DistortedGrid` (sinusoidal distortion) | 6×6 cells |
| Building | `BuildingModule` per floor | 20×20 cells |

---

## Two cascaded offsets

```
[STREET]  ←street offset→  [external sidewalk]  ←facade offset→  [block core]
```

**Street offset** (block level, in distorted grid cells — creates the street):

| Street type | Cells |
|---|---|
| Boundary | 0 |
| Small | 6 |
| Medium | 8 |
| Large | 12 |

The street offset shrinks the block inward, creating the **buildable zone**. The space between opposing buildable zone boundaries forms the street.

**Facade offset** (module level, in building cells — creates sidewalks):

| Adjacent cell type | Cells |
|---|---|
| Normal | 0 |
| Boundary | 0 |
| Facade | 24 |
| Small alleyway | 18 |
| Big alleyway | 18 |

On street-facing (FACADE) edges, the facade offset creates the **external sidewalk** — the strip between the buildable zone boundary and the building face. On alleyway edges, it creates **internal sidewalks** — strips between adjacent building cores.

**Block core** = buildable zone minus external sidewalk. Contains buildings and alleyways (including internal sidewalk zones). Building faces sit at the block core boundary.

Within the block core, alleyways create additional gaps:
```
[building core A]  ←internal sidewalk→  [alleyway]  ←internal sidewalk→  [building core B]
```

---

## Building archetypes

Each `BuildingCluster` is assigned a **building archetype** + seed, the eventual driver of procedural building geometry. Currently the archetype only produces a **debug color** (`archetype.get_color(seed)`), which the renderer reads via `cluster.color`.

- **Base class** `BuildingArchetype` ([building_archetype.gd](../../building/building_archetype.gd)) defines the interface (`get_color`, `get_street_corner_chamfer_value`, future `generate_geometry`). The 8 concrete archetypes live as **inner classes** in the same file while small; an archetype can be promoted to its own file once its logic grows, with no caller changes.
- **Registry** `ArchetypeDefinitions.NEIGHBORHOOD_ARCHETYPES` ([archetype_definition.gd](../../building/archetype_definition.gd)) maps each neighborhood to **exactly 2 distinct archetypes**. `get_archetype_for_cluster()` seed-picks one and instantiates it.
- **Color scheme**: each archetype owns a fixed `base_hue`; the seed varies saturation/value within that family. So both the neighborhood and which of its 2 archetypes a cluster is are readable from color. (Color is a temporary debug variable, expected to be deprecated once real geometry exists.)

| Neighborhood | Archetypes |
|---|---|
| Shanty Town | `shanty_basic`, `shanty_makeshift` |
| Rich Residential | `mansion_classic`, `mansion_modern` |
| Industrial | `warehouse_basic`, `factory_modern` |
| Downtown | `office_tower`, `mixed_use` |

---

## Corner chamfers

Building modules can have **chamfered corners** — rectangular regions cut from the core at vertices where streets or alleyways meet. Chamfers are computed per-module in `BuildingModule._calculate_chamfers()`.

### Types

- **Street corner chamfers**: applied at DistortedGrid vertices where two streets intersect. Controlled by `BuildingArchetype.get_street_corner_chamfer_value()` (currently 16 cells, 100% probability).
- **Alleyway corner chamfers**: applied at vertices where two alleyway edges meet. The chamfer size equals the alleyway offsets of the two edges.

### Geometry

Each chamfer is `[c1, c2]` in building cells:
- `c1`: cells removed toward the previous vertex (clockwise)
- `c2`: cells removed toward the next vertex (clockwise)

The chamfer creates a rectangular exclusion rect within the core. For vertex 0 (BL): `c2` cells along +x, `c1` cells along +z from the core corner.

Chamfers affect the sidewalk vertical grid — building cells inside a chamfer rect are treated as "no building face" for bridge placement.

---

## DistortedGrid cell types

- `NORMAL` — buildable interior
- `FACADE` — block perimeter facing a street (facade offset = 20 → external sidewalk zone)
- `BOUNDARY` — block perimeter coinciding with the city boundary (facade offset = 0 → no sidewalk)
- `SMALL` / `BIG` — small / big alleyway
- `SMALL_ORIGIN` / `BIG_ORIGIN` — alleyway starting point

---

## Block hearts (courtyards)

After clusters are created, each **interior cluster** (not touching the block perimeter) has a probability of becoming a "block heart" — its `floor_count` is set to 0, leaving an empty courtyard inside the block.

Probability per neighborhood type (`block_heart_probability` in `NeighborhoodTypes.CONFIGS`):

| Neighborhood | Probability |
|---|---|
| Shanty Town | 30% |
| Rich Residential | 20% |
| Industrial | 20% |
| Downtown | 20% |

Only clusters that pass `is_interior_cluster()` are candidates. The check runs in `BlockGenerator._assign_block_hearts()` using a per-block RNG seeded from `cluster_seed`.

---

## Mesh generation — normals & winding

All city meshes are generated via `DebugUtil`. All variants use the same rendering approach:

- **Winding & normals**: every face goes through `_add_quad`, which computes the cross-product normal, checks it against the mesh centroid (computed from all 8 vertices), and swaps winding if the normal points inward. This auto-correction means input vertex order (CW or CCW) does not matter.
- **Cull mode**: `CULL_BACK` for all variants.
- **Godot/Vulkan convention**: CW front-face. The cross product `(b-a).cross(c-a)` points toward the CCW side. If it points away from the centroid (`n.dot(face_center - mesh_center) > 0`), winding is swapped so the front face points outward.

### Input formats

| Function | Input | Used for |
|---|---|---|
| `create_skewed_cube` | 4 base vertices `[BL, BR, TR, TL]` + height | In-grid objects: buildings, bridge extremes, sidewalks |
| `create_skewed_cube_from_planes` | Two opposing quads `[BL, BR, TR, TL]` each | Between-grids objects: bridge middles, lane volumes |
| `create_skewed_cube_advanced_grid` | Base vertices + height + chamfers dict + grid dims | Buildings with chamfered corners |

---

## Object placement — two systems

All objects placed on or between buildings use one of two systems. Both are managed through `FacadeHelper` which centralizes edge-direction logic.

### Edge conventions

Edges are numbered 0–3 per face: 0=north, 1=east, 2=south, 3=west. Edges 0/1 iterate cells in increasing order (x or z). Edges 2/3 iterate in decreasing order. The `reversed` flag (from graph node order vs face node order) may flip the iteration again.

The combination determines whether building cell indices within a module run in the same or opposite direction as the facade order:

```
needs_reversal = (edge_idx >= 2) XOR is_reversed
```

This formula lives in `FacadeHelper.needs_cell_reversal()`. It is the single source of truth for all facade-to-grid coordinate conversions.

### Between-grids placement (bridge middles, future pipes)

Objects that span the street between two blocks. Two facade planes (one per block) connected via `create_skewed_cube_from_planes`.

- **Position**: `c_a1.lerp(c_a2, t)` — linear interpolation between block core corners anchored at shared graph nodes. `t` is derived from integer cell indices: `t = cell_index / facade_building_cells`.
- **Vertex correspondence**: guaranteed because `c_a1/c_b1` both correspond to the same graph node (node1), and `c_a2/c_b2` to node2. Lerping at the same `t` gives points directly across the street.
- **Multi-cell spanning**: works naturally — the lerp is a single straight line regardless of how many distorted grid cells it crosses.
- **Implementation**: `_bridge_plane()` and `_add_bridge_section()` in city.gd.

### In-grid placement (bridge extremes, future windows, AC units, balconies, rooftop objects)

Objects that occupy cells within the sidewalk 3D matrix of a single block.

- **Position**: derived from building module `get_region_vertices()`, which uses bilinear interpolation within the module's distorted quad.
- **Cell mapping**: `FacadeHelper.facade_to_grid_rect()` converts facade-order cell indices to `(bx_min, bx_max, bz_min, bz_max)` in building grid coordinates, applying the reversal formula as needed.
- **Multi-cell spanning**: one piece per distorted grid cell. If an object crosses DG cell boundaries, it produces one mesh per DG cell.
- **Construction**: `create_skewed_cube` with base vertices from `get_region_vertices` and height in building cells.

### Alignment guarantee

At the facade edge (v=0 for north, u=0 for west, etc.), the distorted grid has zero wave distortion (edge falloff). So the in-grid outer face and the between-grids facade plane produce the same world position when the `t` values are cell-aligned. This is why bridge extremes connect perfectly with bridge middles.
