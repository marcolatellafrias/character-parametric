# Bridges

Bridge generation — ownership, count, structure, archetypes, and the placement algorithm. For how flying cars navigate bridges at runtime, see the planned vertical profile in [traffic.md](traffic.md#bridges--planned-vertical-profile-bridgeplanner). Part of [city generation](city-generation.md).

## Ownership

Bridges belong to **graph edges**, not blocks. Each edge between two non-boundary faces can host 0–6 bridges. The bridge data lives in `GraphCityGenerator.bridges` (keyed by `edge_key`).

## Bridge count per edge

Determined by neighborhood type and street type:

1. Get the edge's neighborhood type via `get_neighborhood_type_for_edge()` (higher-hierarchy of the two adjacent faces).
2. Read `min_crossings` / `max_crossings` from `NeighborhoodTypes.CONFIGS`.
3. Adjust range by street type:
   - **Small (0)**: upper bound halved → fewer bridges.
   - **Medium (1)**: full range.
   - **Large (2)**: lower bound raised to midpoint → more bridges.
   - **Boundary (-1)**: always 0.

| Neighborhood | Config range | Small street | Medium | Large |
|---|---|---|---|---|
| Shanty Town | 0–0 | 0 | 0 | 0 |
| Rich Residential | 0–1 | 0 | 0–1 | 0–1 |
| Industrial | 1–1 | 1 | 1 | 1 |
| Downtown | 1–2 | 1 | 1–2 | 1–2 |

## Bridge structure — two placement systems

A bridge has two distinct placement systems (see "Object placement — two systems" in [city-generation.md](city-generation.md#object-placement--two-systems)):

- **Middle part** (between-grids): spans between opposing buildable zone boundaries across the street. Uses `create_skewed_cube_from_planes` with facade planes from `_bridge_plane()`.
- **Extremes** (in-grid): extend from the buildable zone boundary inward through the external sidewalk zone to the building face. Live inside the sidewalk 3D matrix. Uses `create_skewed_cube` with base vertices from `get_region_vertices`.

## Bridge parts — middle (from-planes)

| Part | Color (debug) | Width | Height | Depth |
|---|---|---|---|---|
| Arc | Red | = base | `arc_height` below base | Fixed `arc_length` cells from each end |
| Base | Grey | `total_width` cells | `base_height` cells | Full bridge span |
| Pathway | Yellow | = base | 1 cell | Full bridge span |
| Railing | Cyan | 1 cell × 2 | `railing_height` cells | Full bridge span |

## Bridge parts — extremes (skewed cubes)

| Part | Color (debug) | Width | Height | Depth | Condition |
|---|---|---|---|---|---|
| Base extreme | Grey | `total_width` cells | `base_height` cells | `facade_offset` cells (24) | Always |
| Arc extreme | Red | = base | `arc_height` cells | `facade_offset` cells (24) | Only if `arc_height > 0` |

2 base extremes per bridge (one per side). 2 arc extremes per bridge if the archetype has arcs. Total: 4 or 2 extremes per bridge.

Each extreme extends from the buildable zone boundary inward to the building face. It occupies cells in the sidewalk 3D matrix, marking them as `UNAVAILABLE`.

## Bridge archetypes (`Bridge` class)

| Archetype | Width | Base | Arc height | Arc depth (cells) | Pathway | Railing |
|---|---|---|---|---|---|---|
| `wooden_simple` | 16 | 8 | 0 | 0 | 1 | 4 |
| `stone_arched` | 24 | 10 | 8 | 20 | 1 | 4 |
| `iron_suspension` | 24 | 10 | 10 | 20 | 1 | 4 |

`wooden_simple` has no arcs, so it produces 2 extremes (base only). `stone_arched` and `iron_suspension` produce 4 extremes (base + arc).

Arc depth is a **fixed size** in building cells (world depth = `arc_length × cell_height`), not proportional to bridge span. The rendering computes the fraction at draw time from the actual bridge depth.

## Archetype selection

Archetypes are chosen via weighted random selection using `Bridge.select_archetype(rng, context)`. The context dictionary carries placement data; weights are computed per-archetype based on:

- **Floor height**: low floors strongly favor `wooden_simple` (floor 1 = always wooden). Higher floors shift toward `stone_arched` and `iron_suspension`.
- **Bridge length**: if the bridge span (shorter lateral side, in cells) is less than `arc_length × 3`, archetypes with arcs are excluded — the bridge is too short to fit them.

The weight function (`_get_archetype_weights`) is extensible: new factors (neighborhood type, street type, etc.) can be added by passing more keys in the context dictionary.

## Placement algorithm

`GraphCityGenerator._create_bridges()` runs after block grids are generated. For each non-boundary edge with 2 adjacent faces:

1. Get the buildable zone boundary lines on both sides via `get_block_corner_with_offset()` → 4 corner points (2 per face).
2. Find the edge index in each face and compute the DistortedGrid cells along the facade for both sides.
3. **Build sidewalk vertical grids** for both sides (computed once per edge, reused for all attempts).
4. Compute `max_height = min(block_a.max_height, block_b.max_height)`.
5. For each bridge to place (up to 20 attempts):
   - Instantiate a random `Bridge` archetype (seed-based).
   - Pick a random `t` position along the facade.
   - **Floor-aligned height**: pick a random floor (≥ 1). The pathway bottom aligns with the floor start, so `h_base = floor * floor_height - base_height * cell_height`. This ensures people can walk from a building floor directly onto the bridge pathway.
   - **Sidewalk vertical grid check**: verify that ALL building cells within the bridge's t range on both sides have sufficient height.
   - Compute a **slot**: `{t_start, t_end, h_start, h_end}` where h includes the arc below.
   - Check overlap against all previously placed slots on this edge.
   - If no overlap and fits within `max_height`, accept.
6. Store placed bridges with their facade corners, parametric positions, archetype, and extreme data.
7. Mark extreme cells as `UNAVAILABLE` in the sidewalk 3D matrices on both sides.

## Sidewalk vertical grid (bridge/pipe validation)

Validates that bridge/pipe middle parts have solid building wall to anchor to. A **2D vertical grid** along the buildable zone boundary: one axis is horizontal position (building cells along the edge), the other is height (vertical building cells). Each cell is available or not.

Built by iterating each DistortedGrid cell along the facade edge:

1. Get the cell's cluster. If none or `floor_count == 0` → all entries for this cell are unavailable.
2. Get the building module (floor 0) and read its **core area** (`core_min/max`).
3. Get the module's **chamfer rects**. Cells inside a chamfer rect are excluded.
4. For each building cell along the facade that is inside the core AND not in a chamfer → mark as available up to the cluster's height.

**Corner exclusion**: at each end of the edge, `max(facade_offset, chamfer_along_this_edge)` building cells are excluded. These correspond to the external sidewalk corner zones (the `facade_offset × facade_offset` squares at block corners) which have no building face behind them. The exclusion is applied per-end as a number of building cells from the edge's start/end — it manifests as unavailable entries in the horizontal axis of the grid, spanning all heights.

**Alleyway positions**: NOT excluded. Bridges can land on alleyway positions — floating sidewalks (rules TBD) will handle the connection to buildings.

**Anti-overlap**: placed objects occupy a cell range along the facade and a height range. New placements are checked against existing ones — they must not intersect in both dimensions. Additional spacing rules prevent clustering: a padded horizontal margin around each bridge, and a floor-exclusion rule (one bridge per floor per edge).
