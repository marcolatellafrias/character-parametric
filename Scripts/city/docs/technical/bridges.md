# Bridges

Bridge generation — ownership, count, structure, archetypes, and the placement algorithm. For how flying cars navigate bridges at runtime, see the planned vertical profile in [traffic.md](traffic.md#bridges--planned-vertical-profile-bridgeplanner). Part of [city generation](city-generation.md).

## Ownership

Bridges belong to **graph edges**, not blocks. Each edge between two non-boundary faces can host 0–6 bridges. The bridge data lives in `GraphCityGenerator.bridges` (keyed by `edge_key`).

## Bridge count per edge

Decided by **street type** for the base, biased by the **height tier** of the blocks around it (`_get_bridge_count`):

| Street type | Base count |
|---|---|
| Small (0) | 0–1 |
| Medium (1) | 1–2 |
| Large (2) | 2–3 |
| Boundary (-1) | always 0 |

The edge's tier is the **taller of its two blocks** (`get_height_for_edge`), and it shifts the count by `NeighborhoodTypes.FLOORS[tier].bridge_bias`: **-1 for low, 0 for mid, +1 for tall**, clamped at zero. There is nothing to hang a bridge from in a low district, so they mostly vanish there — measured over one city: 562 bridges, only **7** on streets whose blocks are both low (a large avenue can still roll one).

**Superseded:** this used to be documented as a range read from `min_crossings`/`max_crossings` in `NeighborhoodTypes.CONFIGS` per neighbourhood. That table was never read by the code — `_get_bridge_count` ignored its node arguments entirely and keyed off street type alone — and it is gone now that height is its own axis.

## Bridge structure — two placement systems

A bridge has two parts placed in two different ways (see [Connectors between grids](city-generation.md#connectors-between-grids)):

- **Middle part** (between grids): spans between the two facade faces across the street. Uses `get_skewed_cube_from_planes_geometry` with both faces from `FacadeHelper.facade_span_quad()` — sampled from the building grid at the span's end cells and at **both** height indices, so the connector inherits the facade's torsion instead of imposing a horizontal plane of its own.
- **Extremes** (in grid): extend from the buildable zone boundary inward through the sidewalk to the building face. Placed through `GridPlacer`, so they occupy the building module.

## Bridge parts — middle (from-planes)

| Part | Color (debug) | Width | Height | Depth |
|---|---|---|---|---|
| Arc | Red | = base | `arc_height` below base | Fixed `arc_length` cells from each end |
| Base | Grey | `total_width` cells | `base_height` cells | Full bridge span |
| Pathway | Yellow | = base | 1 cell | Full bridge span |
| Railing | Cyan | 1 cell × 2 | `railing_height` cells | Full bridge span |

## Bridge parts — extremes

| Part | Color (debug) | Width | Height | Depth | Condition |
|---|---|---|---|---|---|
| Base extreme | Grey | `total_width` cells | `base_height` cells | `facade_offset` cells (24) | Always |
| Arc extreme | Red | = base | `arc_height` cells | `facade_offset` cells (24) | Only if `arc_height > 0` |

2 base extremes per bridge (one per side). 2 arc extremes per bridge if the archetype has arcs. Total: 4 or 2 extremes per bridge.

Each extreme extends from the buildable zone boundary inward to the building face. It is placed through `GridPlacer` and so **occupies its region of the building module** — which is how the facade's rigid matrix knows a bridge rests there (see [city-generation.md](city-generation.md#placing-objects--one-grid-two-kinds-of-cells)). It is indexed with the bridge's own ids, so the inspector names it as its bridge.

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
3. **Build the facade mask** for both sides (computed once per edge, reused for all attempts).
4. Compute `max_height = min(block_a.max_height, block_b.max_height)`.
5. For each bridge to place (up to 20 attempts):
   - Instantiate a random `Bridge` archetype (seed-based).
   - Pick a random `t` position along the facade.
   - **Floor-aligned height**: pick a random floor (≥ 1). The pathway bottom aligns with the floor start, so `h_base = floor * floor_height - base_height * cell_height`. This ensures people can walk from a building floor directly onto the bridge pathway.
   - **Facade mask check**: verify that ALL building cells within the bridge's t range on both sides have wall up to the required height.
   - Compute a **slot**: `{t_start, t_end, h_start, h_end}` where h includes the arc below.
   - Check overlap against all previously placed slots on this edge.
   - If no overlap and fits within `max_height`, accept.
6. Store placed bridges with their facade corners, parametric positions, archetype, and extreme data. The extremes occupy their modules when they are placed, at visualisation.

## Facade mask (bridge/pipe validation)

Validates that a middle part has solid building wall to anchor to: per building cell along the edge, the height up to which there is wall (`GraphCityGenerator._build_facade_mask`).

Built by iterating each DistortedGrid cell along the facade edge:

1. Get the cell's cluster. If none or `floor_count == 0` → all entries for this cell are unavailable.
2. Get the building module (floor 0) and ask it where there is wall on that side: `BuildingModule.get_facade_span(edge)` — the core's edge minus the chamfers at both ends, the same definition the facade's rigid surface and the door positions use.
3. Every building cell in that span → available up to the cluster's height (`GraphCityGenerator._build_facade_mask`).

**Corner exclusion**: at each end of the edge, `max(facade_offset, chamfer_along_this_edge)` building cells are excluded. These correspond to the external sidewalk corner zones (the `facade_offset × facade_offset` squares at block corners) which have no building face behind them. The exclusion is applied per-end as a number of building cells from the edge's start/end — it manifests as unavailable entries in the horizontal axis of the grid, spanning all heights.

**Alleyway positions**: NOT excluded. Bridges can land on alleyway positions — floating sidewalks (rules TBD) will handle the connection to buildings.

**Anti-overlap**: placed objects occupy a cell range along the facade and a height range. New placements are checked against existing ones — they must not intersect in both dimensions. Additional spacing rules prevent clustering: a padded horizontal margin around each bridge, and a floor-exclusion rule (one bridge per floor per edge).
