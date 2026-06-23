# City Generation — Quick Overview

## Steps in order

1. **Street graph** — Voronoi graph (Poisson sampling). Each edge gets a street type: boundary, small, medium, or large.
2. **Neighborhoods** — Each graph face (polygon) gets a neighborhood type.
3. **Blocks** — Each face gets a `BlockGenerator`. The edges of the block know which street type borders them, reserving an empty margin (street offset) that visually forms the street.
4. **Internal alleyways** — Inside each block, `PathGenerator` traces small and big alleyways in the `DistortedGrid`.
5. **Clusters** — Non-alleyway cells are grouped into `BuildingCluster` via flood-fill, then subdivided (1–8 cells each).
6. **Block hearts** — Interior clusters (not on the block perimeter) have a chance of becoming "hearts": their `floor_count` is set to 0, creating empty courtyards inside the block.
7. **Building modules** — Each cell in each cluster is a `BuildingModule` per floor. Each module knows what borders its 4 sides and shrinks its core area inward (alleyway offset), forming the actual building footprint.

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
[STREET]  ←block offset→  [buildable zone]  ←module offset→  [building core]
```

**Street offset** (block level, shrinks from outside):

| Street type | Cells |
|---|---|
| Boundary | 0 |
| Small | 4 |
| Medium | 6 |
| Large | 9 |

**Alleyway offset** (module level, shrinks the core):

| Adjacent cell type | Cells |
|---|---|
| Normal | 0 |
| Small alleyway / Facade | 12 |
| Big alleyway | 16 |

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

Chamfers affect the facade mask — building cells inside a chamfer rect are treated as "no wall" for bridge placement.

---

## DistortedGrid cell types

- `NORMAL` — buildable interior
- `FACADE` — block perimeter
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

## Traffic system

### Lane volumes
Each street edge in the graph becomes a `LaneVolume`: a 3D rectangular region with a `start_plane` and an `end_plane`. Cars travel from one plane to the other. Volumes are connected at shared graph nodes — the end node of one volume is the start node of the next.

### Traffic lights
Each `LaneVolume` has a `TrafficPlane` child with a `traffic_index` (0 or 1). Volumes with opposing flow directions at the same intersection get the same index. The city toggles the `active_traffic_index` on a timer. If a volume's index matches the active one, its collision layer is cleared (car passes); otherwise it blocks the car physically.

### Car movement
A car enters a volume at a grid position `(u, v)` within the start plane. A `Curve3D` path is created from start to end plane via bilinear interpolation. `PathFollow3D` advances the car along the curve. When it reaches the end, it checks the traffic light, then queries `get_lane_volume_continuations()` to find the next volumes and picks one. A new path is created and the cycle repeats.

```
Enter volume (u,v) → build Curve3D path → follow path
→ check traffic light → pick next volume → repeat
```

### Car archetypes

9 types defined in `CarArchetypes`. Each has dimensions, speed range, spawn weight, per-volume cap, and global cap. Neighborhood-specific weight tables in `NeighborhoodTypes.CAR_WEIGHTS` override default weights at spawn time.

| Type | Weight | Per-volume | Global max |
|---|---|---|---|
| Poor Car | 0.30 | 30 | 150 |
| Motorcycle | 0.20 | 10 | 30 |
| Rich Car | 0.15 | 30 | 100 |
| Police Car | 0.10 | 10 | 15 |
| Utility Truck | 0.08 | 1 | 1 |
| Taxi | 0.05 | 15 | 20 |
| Vending Truck | 0.05 | 1 | 1 |
| Garbage Truck | 0.04 | 1 | 1 |
| Ad Truck | 0.03 | 1 | 1 |

Both per-volume and global limits are enforced at spawn time. Per-volume counts are tracked via `volume_type_counts` (nested dict: `vol_id → {car_type → count}`), updated on spawn, volume transitions, and despawn.

### Neighborhood affinity (routing)

Each car type has an affinity value per neighborhood type (defined in `CarArchetypes.NEIGHBORHOOD_AFFINITY`). When choosing a continuation at an intersection, two factors are weighted:

| Factor | Weight | Source |
|---|---|---|
| Angle (prefer straight) | 60% | `(PI - angle_diff) / PI`, normalized to 0–1 |
| Neighborhood affinity | 40% | `CarArchetypes.get_neighborhood_affinity()` |

### Fog and zone radii (`AreaInstantiator`)

Three concentric cylindrical zones (XZ distance from camera):

| Zone | Radius | Purpose |
|---|---|---|
| Inner (clear) | `0 → inner_radius` | No fog |
| Fade ring | `inner_radius → outer_radius` | Fog 0% → 100% |
| Outer | `outer_radius → spawn_radius` | Full fog; safe for spawning |

A single cylindrical `Area3D` per camera at `spawn_radius` (mask = layer 4) tracks which `LaneVolume`s are in range (`all_lane_volumes`).

### Radial fog

A fullscreen spatial shader (`radial_fog.gdshader`) on a `MeshInstance3D` quad reads the depth buffer, reconstructs world position, and computes XZ distance from the player. Fog is `smoothstep(inner_radius, outer_radius)` — completely clear inside the inner zone, fully opaque at the outer boundary. The sky (depth = 1.0) is discarded so it's never fogged.

### Spawning — demand-pull system

Instead of spawning cars at edges and hoping they drive into view, the system is **demand-pull**: each volume has a target occupancy and the system fills it to target.

**Target occupancy** per volume: `int(traffic_density × path_length / car_spacing)`. Big downtown streets want 3–4 cars; small alleys want 0.

**Three mechanisms fill volumes:**

1. **Bootstrap** (first `bootstrap_duration` seconds): `_topup_volumes()` runs every `spawn_interval` (0.15s), spawning up to `bootstrap_batch_size` (30) cars per tick with no frustum safety check. Populates the entire scene before the player notices.
2. **On-enter seeding**: after bootstrap, when a new `LaneVolume` enters the cylinder (`area_entered`), it is immediately seeded to target — but only if safe (out of frustum or beyond `outer_radius`, where fog hides pop-in).
3. **Periodic top-up**: every `spawn_interval`, `_topup_volumes()` iterates active volumes and spawns up to `max_topup_per_tick` (5) cars in underpopulated volumes that pass the safety check.

**Mid-volume placement**: seeded cars are placed at random positions along the volume's length (`start.lerp(end, along_t)` with `along_t ∈ [0, 1)`), so they appear mid-drive rather than at volume edges.

**Pop-in mitigation** (`_is_safe_to_seed`): cars only materialize where the player can't see them — either out of camera frustum or beyond `outer_radius` (fully fogged). The 50-unit buffer between `outer_radius` and `spawn_radius` gives cars time to settle before the fog clears.

**Archetype selection**: weighted random from neighborhood-specific car weights (`NeighborhoodTypes.CAR_WEIGHTS`). Checked against both global type caps and per-volume type caps. Big vehicles have `min_spawn_v > 0` so they don't appear at ground level.

### Despawning

Pure distance check: each frame, if the car's XZ distance to the nearest camera exceeds `spawn_radius`, it's `queue_free()`d. No volume-based or frustum-based despawn logic. Cars drive freely through the graph and die only when they leave the outermost ring (fully hidden by fog).

### Collision avoidance

Ghost-based forward scanning. Each frame, `CollisionAvoidance` places shape queries ("ghosts") along the car's future path. If a ghost overlaps another car's detection area or broadcast area, the car smoothly decelerates (quadratic ease). If the obstacle is within `min_safe_distance`, speed drops to 0.

**Broadcast ghosts**: a moving car also places collision shapes ahead of itself on its broadcast area (monitorable but not monitoring). Other cars' detection ghosts can detect these, allowing early braking before the actual car body is reached.

**Timeout system**: if two cars are mutually blocking and neither moves for `timeout_duration` seconds, one ignores the other and drives through. Ignored cars are un-ignored once their ghosts no longer detect them. A traffic-light chain check (up to 20 cars deep) prevents the timeout from firing when the chain is legitimately waiting for a red light.

### Online sync design note

The car system is designed for deterministic prediction in online multiplayer. Given a car's seed, spawn volume, and grid position `(u, v)`, its archetype, speed, and path are fully determined. Continuation selection uses a seeded RNG. This means a remote client can reconstruct any car's trajectory without continuous position updates — only the initial spawn event needs to be synchronized.

---

## Mesh generation — normals & winding

All city meshes are generated via `DebugUtil`. There are two construction patterns:

### Base + height (buildings)

`create_skewed_cube`, `create_skewed_cube_advanced`, `create_skewed_cube_advanced_grid`

- Input: 4 base vertices in **CW order** `[BL, BR, TR, TL]` + height.
- Top vertices = base + `Vector3(0, height, 0)`.
- Each side face computes its normal via cross product, then flips it if it points toward the mesh centroid.
- Triangle winding is hardcoded inverted to match the CW input convention (comments say "INVERTIDO EL WINDING ORDER").
- Basic variant uses `CULL_DISABLED` (both sides visible). Advanced variant uses `CULL_BACK`.

### Two planes (lane volumes, bridges)

`create_skewed_cube_from_planes`

- Input: two quads of 4 vertices each `[BL, BR, TR, TL]`.
- Uses `_add_quad` which auto-corrects **both** winding and normals:
  1. Computes cross-product normal `n = (b-a).cross(c-a)`.
  2. If `n` points **away** from the mesh centroid (`n.dot(face_center - mesh_center) > 0`), swaps `b↔d` to reverse winding.
  3. Computes the final normal via `_quad_outward_normal` (always points outward).
- Vertex order (CW or CCW) does not matter — the auto-correction handles it.

### Why the check is `> 0` (Godot/Vulkan convention)

Godot 4 uses Vulkan's CW front-face convention. The cross product `(b-a).cross(c-a)` points toward the CCW side of the triangle. For CW front-face rendering:
- Cross product pointing **inward** (toward centroid) → front face is outward → correct.
- Cross product pointing **outward** (away from centroid) → front face is inward → wrong → swap needed.

### Convention summary

| What | Standard |
|---|---|
| Vertex order for quads | CW: `[BL, BR, TR, TL]` |
| Normal direction | Always outward from mesh centroid |
| Winding correction | Automatic in `_add_quad` (from-planes path) |
| Cull mode | `CULL_BACK` for from-planes and advanced buildings; `CULL_DISABLED` for basic buildings |

---

## Bridges and object spawning

### Ownership

Bridges belong to **graph edges**, not blocks. Each edge between two non-boundary faces can host 0–6 bridges. The bridge data lives in `GraphCityGenerator.bridges` (keyed by `edge_key`).

### Bridge count per edge

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

### Placement algorithm

`GraphCityGenerator._create_bridges()` runs after block grids are generated. For each non-boundary edge with 2 adjacent faces:

1. Get the facade lines on both sides via `get_block_corner_with_offset()` → 4 corner points (2 per face).
2. Find the edge index in each face and compute the facade DistortedGrid cells for both sides.
3. **Build facade masks** for both sides (computed once per edge, reused for all attempts).
4. Compute `max_height = min(block_a.max_height, block_b.max_height)`.
5. For each bridge to place (up to 20 attempts):
   - Instantiate a random `Bridge` archetype (seed-based).
   - Pick a random `t` position along the facade.
   - **Floor-aligned height**: pick a random floor (≥ 1). The pathway bottom aligns with the floor start, so `h_base = floor * floor_height - base_height * cell_height`. This ensures people can walk from a building floor directly onto the bridge pathway.
   - **Facade mask check**: verify that ALL building cells within the bridge's t range on both sides have sufficient height (see below).
   - Compute a **slot**: `{t_start, t_end, h_start, h_end}` where h includes the arc below.
   - Check overlap against all previously placed slots on this edge.
   - If no overlap and fits within `max_height`, accept.
6. Store placed bridges with their facade corners, parametric positions, and archetype.

### Facade mask (building support validation)

Bridges must connect to solid building wall on both sides. The validation uses a **facade mask** — a 1D array at the building-cell level (one entry per building cell along the facade). Each entry stores the building height at that position, or 0 if there's no wall.

The mask is built by iterating each DistortedGrid cell along the facade edge:

1. Get the cell's cluster. If none or `floor_count == 0` → all entries for this cell are 0.
2. Get the building module (floor 0) and read its **core area** (`core_min/max`). The core already accounts for alleyway offsets — cells outside the core (shrunk by alleyway gaps) have no wall.
3. Get the module's **chamfer rects** (diagonal corner cuts from street corners and alleyway corners). Cells inside a chamfer rect are excluded.
4. For each building cell along the facade that is inside the core AND not in a chamfer → set the mask entry to the cluster's height.

This naturally handles all three exclusion cases:
- **Alleyway gaps**: the alleyway offset shrinks the core on each side of the alleyway, leaving a gap of `2 × offset` building cells with 0 height in the mask.
- **Corner chamfers**: the chamfer rects at building module corners set those positions to 0.
- **Missing buildings**: cells with no cluster or 0 floors are already 0.

The bridge check then simply verifies: every building cell within `[t_start, t_end]` has height ≥ `h_top` (bridge top including railing). If any cell is too short or has no wall, the placement is rejected.

### Slot system (anti-overlap + spacing)

Each placed bridge occupies a rectangular slot in `(t, h)` space:
- `t ∈ [0, 1]` — parametric position along the facade edge.
- `h` — world-space height range, including the arc that hangs below.

Two slots overlap if they intersect in **both** t and h dimensions. This same system will extend to pipes, signage, and other edge-mounted objects.

**Spacing** — three independent mechanisms prevent clustering:

1. **Physical overlap** (`occupied` slots): actual bridge bounding boxes in `(t, h)` space — prevents bridges from intersecting.
2. **Horizontal separation** (`used_t_ranges`): padded t-ranges (`+0.06` on each side). Checked independently of height — prevents bridges from lining up vertically when viewed from above, regardless of floor.
3. **Floor exclusion** (`used_floors`): once a bridge is placed at floor N, no other bridge on the same edge can use floor N.

### Bridge parts (bottom to top)

Each part has a distinct layout:

| Part | Color (debug) | Width | Height | Depth | Description |
|---|---|---|---|---|---|
| Arc | Red | = base | `arc_height` below base | Fixed `arc_length` cells from each end | Two structural arches at bridge endpoints |
| Base | Grey | `total_width` cells | `base_height` cells | Full bridge span | Main structural volume |
| Pathway | Yellow | = base | 1 cell | Full bridge span | Walking surface, sits on top of base |
| Railing | Cyan | 1 cell × 2 | `railing_height` cells | Full bridge span | Two strips on outer edges of pathway |

### Bridge archetypes (`Bridge` class)

| Archetype | Width | Base | Arc height | Arc depth (cells) | Pathway | Railing |
|---|---|---|---|---|---|---|
| `wooden_simple` | 16 | 8 | 0 | 0 | 1 | 4 |
| `stone_arched` | 24 | 10 | 8 | 20 | 1 | 4 |
| `iron_suspension` | 24 | 10 | 10 | 20 | 1 | 4 |

Arc depth is a **fixed size** in building cells (world depth = `arc_length × cell_height`), not proportional to bridge span. The rendering computes the fraction at draw time from the actual bridge depth.

### Archetype selection

Archetypes are chosen via weighted random selection using `Bridge.select_archetype(rng, context)`. The context dictionary carries placement data; weights are computed per-archetype based on:

- **Floor height**: low floors strongly favor `wooden_simple` (floor 1 = always wooden). Higher floors shift toward `stone_arched` and `iron_suspension`.
- **Bridge length**: if the bridge span (shorter lateral side, in cells) is less than `arc_length × 3`, archetypes with arcs are excluded — the bridge is too short to fit them.

The weight function (`_get_archetype_weights`) is extensible: new factors (neighborhood type, street type, etc.) can be added by passing more keys in the context dictionary.

---

## Cell availability (BuildingGridHelper)

`BuildingGridHelper` tracks the state of every cell `(bx, bz, by)` in the building grid with `CellState`:

| State | Value | Meaning |
|---|---|---|
| `AVAILABLE` | 0 | In building core, normal floor — can receive windows, props, bridge endpoints |
| `UNAVAILABLE` | 1 | Outside core (alleyway), in chamfer, or occupied |
| `ROOF_ONLY` | 2 | In core but on the rooftop extra floor — only roof props (antennas, tanks) |

Rules:
- A cell starts `UNAVAILABLE`.
- If it's inside the `BuildingModule` core (`is_cell_in_core`): → `AVAILABLE`.
- If it's inside a chamfer rectangle: → back to `UNAVAILABLE`.
- If it's on the rooftop extra floor and still available: → `ROOF_ONLY`.

Derived availability (lazy, not stored):
- **Vertex**: available if any of its 8 neighbor cells is `AVAILABLE`.
- **Edge**: available if any of its 4 neighbor cells is `AVAILABLE`.
- **Face**: available if any of its 2 neighbor cells is `AVAILABLE`.
