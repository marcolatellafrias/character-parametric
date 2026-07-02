# City Generation — Quick Overview

## Steps in order

1. **Street graph** — Voronoi graph (Poisson sampling). Each edge gets a street type: boundary, small, medium, or large.
2. **Neighborhoods** — Each graph face (polygon) gets a neighborhood type.
3. **Blocks** — Each face gets a `BlockGenerator`. The edges of the block know which street type borders them, reserving an empty margin (street offset) that visually forms the street.
4. **Internal alleyways** — Inside each block, `PathGenerator` traces small and big alleyways in the `DistortedGrid`.
5. **Clusters** — Non-alleyway cells are grouped into `BuildingCluster` via flood-fill, then subdivided (1–8 cells each).
6. **Block hearts** — Interior clusters (not on the block perimeter) have a chance of becoming "hearts": their `floor_count` is set to 0, creating empty courtyards inside the block.
7. **Building modules** — Each cell in each cluster is a `BuildingModule` per floor. Each module knows what borders its 4 sides and shrinks its core area inward (facade/alleyway offset), forming the actual building footprint.
8. **Sidewalk zones** — The non-core cells of each building module define sidewalk zones: external (between the buildable zone boundary and the building face) and internal (alleyway offset areas between buildings).
9. **Sidewalk 3D matrices** — Each distorted grid cell gets a 3D matrix tracking cell availability in the sidewalk zones, extruded vertically. Combined per block for cross-cell queries.
10. **Sidewalk instances** — Physical walkable surfaces spawned within sidewalk zones. Floor 0 gets sidewalks everywhere. Higher-floor floating sidewalks are bridge-dependent (rules TBD).
11. **Bridges** — Placed on graph edges. Middle parts span between opposing buildable zone boundaries. Extremes extend through external sidewalk zones to the building face.

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
| Small | 4 |
| Medium | 6 |
| Large | 9 |

The street offset shrinks the block inward, creating the **buildable zone**. The space between opposing buildable zone boundaries forms the street.

**Facade offset** (module level, in building cells — creates sidewalks):

| Adjacent cell type | Cells |
|---|---|
| Normal | 0 |
| Boundary | 0 |
| Facade | 18 |
| Small alleyway | 18 |
| Big alleyway | 18 |

On street-facing (FACADE) edges, the facade offset creates the **external sidewalk** — the strip between the buildable zone boundary and the building face. On alleyway edges, it creates **internal sidewalks** — strips between adjacent building cores.

**Block core** = buildable zone minus external sidewalk. Contains buildings and alleyways (including internal sidewalk zones). Building faces sit at the block core boundary.

Within the block core, alleyways create additional gaps:
```
[building core A]  ←internal sidewalk→  [alleyway]  ←internal sidewalk→  [building core B]
```

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
- `FACADE` — block perimeter facing a street (facade offset = 18 → external sidewalk zone)
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

## Sidewalk zones

The non-building-core cells of the building grid form **sidewalk zones** — areas where sidewalks, bridge extremes, and facade objects (windows, balconies, AC units, etc.) can be placed.

### External sidewalk zone

The facade offset strip (18 building cells deep) between the buildable zone boundary and the building face, wrapping around the block perimeter.

**Geometry** — decomposed into **8 pieces** per block:
- **4 corners**: `facade_offset × facade_offset` squares (e.g. 18×18) at each block corner, where two perimeter edges meet. These sit at the outermost part of the sidewalk, nearest the street intersection, farthest from any building face.
- **4 sides**: rectangular strips connecting adjacent corners along each block edge. Each side is a single piece spanning the full edge.

### Internal sidewalk zone

The alleyway offset strips (12 or 18 building cells deep) between adjacent building cores, inside the block.

**Geometry** — decomposed into:
- **Connecting sectors**: straight strips running along alleyway edges between buildings.
- **Corners**: where two alleyways intersect.

**Corner ownership**: where an internal sidewalk zone meets an external sidewalk zone, the corner is always owned by the external zone — external has higher hierarchy. There must never be conflicting ownership of corners.

---

## Sidewalk instances

A sidewalk instance is a physical walkable surface: a **1-cell-tall skewed cube** at a specific floor. Sidewalks are always **floor-aligned** — the bottom sits at the start of a floor.

### Spawn rules

- **Floor 0**: all external sidewalk zones get a sidewalk.
- **Higher floors (floating sidewalks)**: generated by the traversal infrastructure system. Placed at stair endpoints and horizontal traversal waypoints.
- **Internal sidewalks**: TBD.

---

## Delivery doors

Each block has a set of **delivery door zones** — locations where package delivery doors can spawn. A door zone is a cell-edge-floor on a specific cluster.

**Data**: `BlockGenerator.delivery_doors` — array of `{cell: Vector2i, edge: int, floor: int, cluster_id: int}`.

**Constraints**: edges must be FACADE or alleyway (not NORMAL or BOUNDARY). Cluster must have `floor_count > 0`. Currently 4 per block.

---

## Traversal infrastructure (stairs + floating sidewalks)

Connects floor 0 to each delivery door via a bottom-up convergent path of stairs and floating sidewalks.

### Data

- `BlockGenerator.stair_zones` — array of `{cell, edge, floor, cluster_id, along_start}`. A stair at floor F connects floor F to floor F+1. `along_start` is the stair's position in building cells along the edge.
- `BlockGenerator.floating_sidewalk_zones` — array of `{cell, edge, floor, cluster_id, along_min, along_max}`. A walkable surface section at floor F on that cell-edge, covering building cells `[along_min, along_max]` along the face.

### Path-building algorithm (bottom-up convergent)

Doors are processed sorted by floor ascending. For each delivery door at floor > 0:

1. **Pick start** at floor 0 within `1 + target_floor/2` Manhattan hops of the door's cell. Prefer FACADE edges and closer positions.
2. **Each floor f** (0 to target_floor-1):
   - If `dist > floors_remaining`: must traverse (walk toward target to converge in time).
   - Otherwise: 50% chance to traverse one step.
   - When traversing: step cell-by-cell toward target, placing floating sidewalk sections on both sides of each non-NORMAL/non-BOUNDARY crossing (cross-cluster connections via alleyways).
   - After traversal: place stair at current position (if cluster tall enough, no door overlap, stair spacing OK).
   - Place floating sidewalk sections at stair's bottom and top floors.
3. **Final connection**: if not at target cell/edge after reaching target floor, walk remaining distance placing crossing sidewalks.

### Constraints

- **Height check**: stairs only placed where `cluster.floor_count > floor + 1` (no terrace stairs).
- **Door exclusion**: stairs never overlap delivery door positions.
- **Stair spacing**: no two stairs within Manhattan distance 1 on the same floor.
- **Convergence guarantee**: `must_traverse` forces enough steps to reach the target by the target floor.

### External sidewalk geometry (floor 0)

**4 corners** — one per block corner. Each is a `facade_offset × facade_offset` skewed cube from the corner DG cell's building module, covering the square where two facade edges meet. Vertices from `get_region_vertices` on the corner module.

**4 × N connectors** — one per DG cell per edge (excluding corner overlap). Each connector follows the distorted grid by using `get_region_vertices` from its own building module, so it matches building boundaries exactly. A single flat quad per edge would deviate from the wave distortion.

At the corner DG cells, connectors are **trimmed** to avoid overlapping the corner piece:
- First cell on the edge: the along-axis start is clipped to `core_min` (the corner piece covers `[0, core_min-1]`)
- Last cell on the edge: the along-axis end is clipped to `core_max` (the corner piece covers `[core_max+1, cols/rows-1]`)
- Middle cells: full module width, no trimming

The iteration goes low-to-high index for all edges (x=0→cols-1 or z=0→rows-1), so `is_first` always corresponds to the low-index corner and `is_last` to the high-index corner.

---

## Sidewalk 3D matrix

Per distorted grid cell, a 3D matrix `(bx, bz, by)` tracking cell availability in the **non-building-core** space. Restructured from the former `BuildingGridHelper`.

### Cell states (`CellState`)

| State | Value | Meaning |
|---|---|---|
| `AVAILABLE` | 0 | Outside building core, on a normal floor — can receive objects, bridge extremes, sidewalks |
| `UNAVAILABLE` | 1 | Inside building core, in chamfer, or occupied by a placed object |
| `ROOF_ONLY` | 2 | Above building's floor count — only roof objects (antennas, water tanks) |

Rules (inverted from the former BuildingGridHelper):
- A cell starts `AVAILABLE` if it is **outside** the building core.
- If it's **inside** the building core: → `UNAVAILABLE`.
- If it's inside a chamfer rectangle: → `UNAVAILABLE`.
- If it's above the building's floor count and not inside core: → `ROOF_ONLY`.

### Sidewalk 3D matrices (per block)

All per-cell sidewalk 3D matrices from every distorted grid cell in a block, combined into one queryable collection. Objects and bridge extremes that span multiple distorted grid cells query this combined structure.

### Derived availability (lazy, not stored)

- **Vertex**: available if any of its 8 neighbor cells is `AVAILABLE`.
- **Edge**: available if any of its 4 neighbor cells is `AVAILABLE`.
- **Face**: available if any of its 2 neighbor cells is `AVAILABLE`.

---

## Traffic system

### Lane volumes
Each street edge in the graph becomes a `LaneVolume`: a 3D rectangular region with a `start_plane` and an `end_plane`. Cars travel from one plane to the other. Volumes are connected at shared graph nodes — the end node of one volume is the start node of the next.

### Traffic lights
Each `LaneVolume` has a `TrafficPlane` child with a `traffic_index` (0 or 1). Volumes with opposing flow directions at the same intersection get the same index. The city toggles the `active_traffic_index` on a timer, which sets `is_blocking` on each plane. Red planes are registered as quad claims in the `TrafficClaimRegistry`; a car's corridor crossing a red, lane-relevant quad produces a stop point (no physics involved).

### Car movement
A car enters a volume at a grid position `(u, v)` within the start plane. A `Curve3D` path is created from start to end plane via bilinear interpolation. The car holds the curve directly (no `Path3D`/`PathFollow3D`/`Timer` nodes — `PathController` is `RefCounted`): a float progress advances along the baked curve (`bake_interval` 2.0, cars don't need the default 0.2u precision) and transition/end checks run inline in `advance()`. Segment-transition offsets are computed analytically (the shared straight segment carries progress over by subtraction), so no `get_closest_offset` search. When the car reaches the end, it checks the traffic light, then queries `get_lane_volume_continuations()` to find the next volumes and picks one. A new curve is built and the cycle repeats.

Each car is 2 nodes (root + `MeshInstance3D`); `CollisionAvoidance` is also `RefCounted`. All cars of an archetype share one `BoxMesh`+`StandardMaterial3D` (debug tint uses a lazy per-car `material_override`), and meshes are hidden beyond `render_distance` — the fog fully covers them there anyway.

```
Enter volume (u,v) → build Curve3D path → follow path
→ check traffic light → pick next volume → repeat
```

### Car archetypes

9 types defined in `CarArchetypes`. Each has dimensions, speed range, spawn weight, and global cap. Neighborhood-specific weight tables in `NeighborhoodTypes.CAR_WEIGHTS` override default weights at spawn time (a type missing from a table falls back to its default weight, so explicit 0.0 entries matter).

The **ambient pool** is poor car, motorcycle, rich car, police, taxi. The four **one-of trucks** have weight 0 everywhere — they never spawn ambiently and will be placed individually by the future special-car system (their archetype definitions remain).

| Type | Weight | Global max |
|---|---|---|
| Poor Car | 0.30 | 150 |
| Motorcycle | 0.20 | 30 |
| Rich Car | 0.15 | 100 |
| Police Car | 0.10 | 15 |
| Taxi | 0.05 | 20 |
| Utility / Vending / Garbage / Ad Truck | 0 (special-only) | 1 |

Global caps are enforced at spawn time. There are no per-volume type caps — total per-volume occupancy is already bounded by target occupancy (~3–4 cars max), so per-type caps could never bind.

### Routing

When choosing a continuation at an intersection, cars weight candidates by **traffic density** (`LaneVolume.get_traffic_density()` — the same street × neighborhood constant the spawner uses for targets), so routing and spawning push toward the same distribution: big streets attract and keep more cars. The seeded weighted draw itself provides the random variation into less dense routes. U-turns are structurally excluded by `get_lane_volume_continuations()` (the same graph edge in either direction is skipped). Population composition is controlled entirely at spawn time by the per-neighborhood weight tables.

The weighted draw happens **before** validation: only the drawn volume runs the (expensive) projection-validation, falling back to the next draw if it fails — instead of validating every candidate and discarding all but one.

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

**Target occupancy** per volume: `traffic_density × path_length / car_spacing × distance_falloff`, with the fractional part resolved by a **per-volume die roll** (hash of the volume id, stable across runs/machines): a street "worth" 0.4 cars carries one car on 40% of streets instead of always truncating to zero — individual streets get a fixed personality. The **distance falloff** is 1.0 inside `fog_start_distance`, thinning linearly to `far_density_fraction` (0.3) at `spawn_radius` — ring area grows with radius squared, so without it most of the car budget lands where no player can see it.

**Three mechanisms fill volumes:**

1. **Bootstrap** (first `bootstrap_duration` seconds): `_topup_volumes()` runs every `spawn_interval` (0.15s), spawning up to `bootstrap_batch_size` (30) cars per tick with no visibility check. Populates the entire scene before the player notices.
2. **On-enter seeding**: after bootstrap, when a new `LaneVolume` enters the cylinder (`area_entered`), it is queued and seeded to target on the next physics tick (space queries can't run inside the area flush).
3. **Periodic top-up**: every `spawn_interval`, `_topup_volumes()` iterates active volumes and spawns up to `max_topup_per_tick` (5) cars in underpopulated volumes.

**Mid-volume placement**: seeded cars are placed at random positions along the volume's length (`start.lerp(end, along_t)` with `along_t ∈ [0, 1)`), so they appear mid-drive rather than at volume edges. `along_t` is re-rolled per attempt, so a partially visible street can still spawn cars in its hidden sections.

**Pop-in mitigation — position-based line of sight** (`_is_point_hidden`): a candidate spawn point is hidden if, for every camera, it is beyond `outer_radius` (fully fogged) or a static occluder (building, sidewalk, bridge — collision layer 1) blocks the raycast from the camera *position* to the car's top. Camera orientation is never used — turning the camera can't reveal a spawn, and in multiplayer the check depends only on replicated player positions, so it stays deterministic-friendly. There is no frustum check anywhere. Spawning runs in `_physics_process` because `intersect_ray` needs a physics context.

**Archetype selection**: weighted random from neighborhood-specific car weights (`NeighborhoodTypes.CAR_WEIGHTS`), via `CarArchetypes.select_type_seeded()` — the same seeded draw the car itself makes in `initialize_from_seed`, so caps can be checked without allocating a car. Checked against global type caps. Big vehicles have `min_spawn_v > 0` so they don't appear at ground level. The spawn altitude `v` is drawn as `pow(randf(), spawn_height_bias)` (default 2.5), biasing traffic toward street level — bias 1 = uniform.

**Spawn overlap check**: a capsule gap query against the `TrafficClaimRegistry` (`is_capsule_free`), covering car bodies, broadcast corridors, and obstacles — no world iteration. Newly spawned cars publish their body claim immediately (`set_path`), so multiple spawns in the same tick can't overlap.

### Despawning

Pure distance check: each frame, if the car's XZ distance to the nearest camera exceeds `spawn_radius`, it's `queue_free()`d. No volume-based or frustum-based despawn logic. Cars drive freely through the graph and die only when they leave the outermost ring (fully hidden by fog).

### Collision avoidance — claim registry (no physics)

Cars carry **no Area3D and issue no physics queries**. Everything that occupies traffic space publishes a **claim** into the `TrafficClaimRegistry`, a spatial hash (default 32u cells) of world-space shapes:

| Claim | Shape | Published by |
|---|---|---|
| `CAR_BODY` | capsule segment through the car | every car, every frame |
| `CAR_BROADCAST` | capsule polyline along the car's future path, length `current_speed × broadcast_distance_multiplier` | moving cars |
| `TRAFFIC_LIGHT` | quad (the `TrafficPlane` face) | `AreaInstantiator` when a volume enters the tracking cylinder |
| `OBSTACLE` | capsule polyline | anything (`register_obstacle()`) — cars adapt automatically |

**Detection**: at a distance-scaled cadence (staggered by instance id — every 2 frames inside `fog_start_distance`, 4 in the near fade ring, 8 in the far half; braking latency is invisible at fog range), a car samples its future path into a corridor polyline (spacing `ghost_spacing`, length `base_speed × ghost_distance_multiplier`, clamped) and queries the registry — segment-vs-segment / segment-vs-quad math against the few claims in nearby hash cells. Sampling uses `sample_baked` (position only); speed smoothing still runs every frame. Corridor buffers, query scratch arrays, and hit lists are reused across ticks (`publish_capsule` copies points into the claim's own buffer, so callers can pass reused arrays). A car's relevant volume ids are cached and refreshed only on segment transitions.

**Fogged tick**: fully fogged cars do real work every 4th frame with the accumulated delta (motion is analytic, so batching is exact); on skipped frames they only republish their body claim from the last transform, since the registry's double buffer clears every frame.

**Double buffering**: the registry swaps read/write buffers each frame (`process_priority = -100`); cars publish into the write buffer and query the previous frame's completed read buffer. Every car sees the same claim set regardless of processing order — no order dependence, multiplayer-determinism friendly.

**Directionality**: claims carry their owner. Another car's broadcast only applies if that car is *ahead* along my forward axis — a tailing car's broadcast spilling past the leader can no longer stop the leader. Body claims of cars behind are also ignored.

**Merge priority**: when two corridors converge (a `CAR_BROADCAST` hit from a car that isn't simply ahead in my lane), the conflict is resolved by comparing time-to-conflict-point (`arc / speed` on each side); the later car yields, ties break deterministically by `car_id`. No mutual braking standoffs.

**Leader-aware speed control**: the decision step produces a `target_speed` — `min(base, leader_speed + sqrt(2 × comfortable_deceleration × gap))`. Following a moving leader converges to matching its speed at `min_safe_distance` (no accordion oscillation); a stopped car, red light, reserved corridor, or obstacle makes it the analytic braking curve to a stop point. `integrate_speed()` then applies per-frame accel/decel clamps (`max_acceleration` / `max_deceleration`) for smooth motion.

**Timeout system** (slim): directional evaluation makes same-lane mutual blocks impossible, so the timeout only covers genuine geometric standoffs — if both cars have been stopped for `timeout_duration` and the blocker's chain (followed via `blocking_car_ref`, up to 20 deep) isn't waiting on a red light, the blocker is ignored for 5 seconds.

**Debug** (`Traffic Debug` export group on `AreaInstantiator`): `TrafficDebugDrawer` renders everything from registry data into one shared `ImmediateMesh` (one draw call, near-zero cost when off) — corridors color-coded by state (cruising/following/braking/yielding/stopped), broadcast overlays, leader links, stop-point markers, optional hash-cell wireframes, car tint by state, and inspect `Label3D`s only for cars within `traffic_debug_label_distance` (30u) of a camera.

### Online sync design note

The car system is designed for deterministic prediction in online multiplayer. Given a car's seed, spawn volume, and grid position `(u, v)`, its archetype, speed, and path are fully determined. Continuation selection uses a seeded RNG. This means a remote client can reconstruct any car's trajectory without continuous position updates — only the initial spawn event needs to be synchronized. The claim system reinforces this: detection is pure float math on double-buffered data (Godot physics is not cross-machine deterministic, claims are), and a car's motion between decisions is analytic, so only decisions — spawn events, lane transitions, target-speed changes — would need to go on the wire.

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

---

## Bridges

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

### Bridge structure — two placement systems

A bridge has two distinct placement systems (see "Object placement — two systems" above):

- **Middle part** (between-grids): spans between opposing buildable zone boundaries across the street. Uses `create_skewed_cube_from_planes` with facade planes from `_bridge_plane()`.
- **Extremes** (in-grid): extend from the buildable zone boundary inward through the external sidewalk zone to the building face. Live inside the sidewalk 3D matrix. Uses `create_skewed_cube` with base vertices from `get_region_vertices`.

### Bridge parts — middle (from-planes)

| Part | Color (debug) | Width | Height | Depth |
|---|---|---|---|---|
| Arc | Red | = base | `arc_height` below base | Fixed `arc_length` cells from each end |
| Base | Grey | `total_width` cells | `base_height` cells | Full bridge span |
| Pathway | Yellow | = base | 1 cell | Full bridge span |
| Railing | Cyan | 1 cell × 2 | `railing_height` cells | Full bridge span |

### Bridge parts — extremes (skewed cubes)

| Part | Color (debug) | Width | Height | Depth | Condition |
|---|---|---|---|---|---|
| Base extreme | Grey | `total_width` cells | `base_height` cells | `facade_offset` cells (18) | Always |
| Arc extreme | Red | = base | `arc_height` cells | `facade_offset` cells (18) | Only if `arc_height > 0` |

2 base extremes per bridge (one per side). 2 arc extremes per bridge if the archetype has arcs. Total: 4 or 2 extremes per bridge.

Each extreme extends from the buildable zone boundary inward to the building face. It occupies cells in the sidewalk 3D matrix, marking them as `UNAVAILABLE`.

### Bridge archetypes (`Bridge` class)

| Archetype | Width | Base | Arc height | Arc depth (cells) | Pathway | Railing |
|---|---|---|---|---|---|---|
| `wooden_simple` | 16 | 8 | 0 | 0 | 1 | 4 |
| `stone_arched` | 24 | 10 | 8 | 20 | 1 | 4 |
| `iron_suspension` | 24 | 10 | 10 | 20 | 1 | 4 |

`wooden_simple` has no arcs, so it produces 2 extremes (base only). `stone_arched` and `iron_suspension` produce 4 extremes (base + arc).

Arc depth is a **fixed size** in building cells (world depth = `arc_length × cell_height`), not proportional to bridge span. The rendering computes the fraction at draw time from the actual bridge depth.

### Archetype selection

Archetypes are chosen via weighted random selection using `Bridge.select_archetype(rng, context)`. The context dictionary carries placement data; weights are computed per-archetype based on:

- **Floor height**: low floors strongly favor `wooden_simple` (floor 1 = always wooden). Higher floors shift toward `stone_arched` and `iron_suspension`.
- **Bridge length**: if the bridge span (shorter lateral side, in cells) is less than `arc_length × 3`, archetypes with arcs are excluded — the bridge is too short to fit them.

The weight function (`_get_archetype_weights`) is extensible: new factors (neighborhood type, street type, etc.) can be added by passing more keys in the context dictionary.

### Placement algorithm

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

### Sidewalk vertical grid (bridge/pipe validation)

Validates that bridge/pipe middle parts have solid building wall to anchor to. A **2D vertical grid** along the buildable zone boundary: one axis is horizontal position (building cells along the edge), the other is height (vertical building cells). Each cell is available or not.

Built by iterating each DistortedGrid cell along the facade edge:

1. Get the cell's cluster. If none or `floor_count == 0` → all entries for this cell are unavailable.
2. Get the building module (floor 0) and read its **core area** (`core_min/max`).
3. Get the module's **chamfer rects**. Cells inside a chamfer rect are excluded.
4. For each building cell along the facade that is inside the core AND not in a chamfer → mark as available up to the cluster's height.

**Corner exclusion**: at each end of the edge, `max(facade_offset, chamfer_along_this_edge)` building cells are excluded. These correspond to the external sidewalk corner zones (the `facade_offset × facade_offset` squares at block corners) which have no building face behind them. The exclusion is applied per-end as a number of building cells from the edge's start/end — it manifests as unavailable entries in the horizontal axis of the grid, spanning all heights.

**Alleyway positions**: NOT excluded. Bridges can land on alleyway positions — floating sidewalks (rules TBD) will handle the connection to buildings.

**Anti-overlap**: placed objects occupy a cell range along the facade and a height range. New placements are checked against existing ones — they must not intersect in both dimensions. Additional spacing rules prevent clustering: a padded horizontal margin around each bridge, and a floor-exclusion rule (one bridge per floor per edge).
