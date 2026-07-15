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
| Small | 6 |
| Medium | 8 |
| Large | 12 |

The street offset shrinks the block inward, creating the **buildable zone**. The space between opposing buildable zone boundaries forms the street.

**Facade offset** (module level, in building cells — creates sidewalks):

| Adjacent cell type | Cells |
|---|---|
| Normal | 0 |
| Boundary | 0 |
| Facade | 20 |
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

## Sidewalk zones

The non-building-core cells of the building grid form **sidewalk zones** — areas where sidewalks, bridge extremes, and facade objects (windows, balconies, AC units, etc.) can be placed.

### External sidewalk zone

The facade offset strip (20 building cells deep) between the buildable zone boundary and the building face, wrapping around the block perimeter.

**Geometry** — decomposed into **8 pieces** per block:
- **4 corners**: `facade_offset × facade_offset` squares (e.g. 20×20) at each block corner, where two perimeter edges meet. These sit at the outermost part of the sidewalk, nearest the street intersection, farthest from any building face.
- **4 sides**: rectangular strips connecting adjacent corners along each block edge. Each side is a single piece spanning the full edge.

### Internal sidewalk zone

The alleyway offset strips (18 building cells deep) between adjacent building cores, inside the block.

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
Each `LaneVolume` has a `TrafficPlane` child with a `traffic_index` (0 or 1). Volumes with opposing flow directions at the same intersection get the same index. The city toggles **one global phase** on a timer (`TrafficPlane.global_active_index` + `global_yellow_phase`, set in `city.gd _on_traffic_cycle_changed`), and each plane's `is_blocking` is a **computed property** derived from it on read (red unless its index is active; both indices block during the yellow phase). There is deliberately **no per-plane light state** — the old push-loop that wrote `is_blocking` onto every plane silently skipped any plane whose volume bookkeeping had broken, freezing ~20 lanes red forever and gridlocking their nodes; deriving from the global phase makes a "frozen light" impossible by construction (and syncs across the network as just two ints). Red planes are registered as quad claims in the `TrafficClaimRegistry`; a car's corridor crossing a red, lane-relevant quad produces a stop point (no physics involved). `LightWatchdog` guards the invariant.

### Car movement
A car enters a volume at a grid position `(u, v)` within the start plane. A `Curve3D` path is created from start to end plane via bilinear interpolation. The car holds the curve directly (no `Path3D`/`PathFollow3D`/`Timer` nodes — `PathController` is `RefCounted`): a float progress advances along the baked curve (`bake_interval` 2.0, cars don't need the default 0.2u precision) and transition/end checks run inline in `advance()`. Segment-transition offsets are computed analytically (the shared straight segment carries progress over by subtraction), so no `get_closest_offset` search. When the car reaches the end, it checks the traffic light, then queries `get_lane_volume_continuations()` to find the next volumes and picks one. A new curve is built and the cycle repeats.

A car is not a node: `FlyingCar` extends `Object` (`CollisionAvoidance` and `PathController` are `RefCounted`), and the whole fleet is ticked by one `CarManager` loop — camera positions are computed once per frame and there are no per-node `_process` callbacks. Cars inside `render_distance` borrow a pooled `MeshInstance3D` visual from the manager, released a small margin past the fog wall so boundary oscillation doesn't churn the pool; fully fogged cars are pure data with no node, no mesh and no transform updates. All cars of an archetype share one `BoxMesh`+`StandardMaterial3D` (debug tint uses a lazy per-car `material_override` on the pooled visual).

```
Enter volume (u,v) → build Curve3D path → follow path
→ check traffic light → pick next volume → repeat
```

### Car archetypes

9 types defined in `CarArchetypes`. Each has dimensions, speed range, spawn weight, and global cap. Neighborhood-specific weight tables in `NeighborhoodTypes.CAR_WEIGHTS` override default weights at spawn time (a type missing from a table falls back to its default weight, so explicit 0.0 entries matter).

The **ambient pool** is poor car, motorcycle, rich car, police, taxi, plus the four **big trucks** as rare spawns (small weight, low global cap). The trucks are absent from every `CAR_WEIGHTS` table, so their default weight applies in all neighborhoods.

| Type | Weight | Global max |
|---|---|---|
| Poor Car | 0.30 | 150 |
| Motorcycle | 0.20 | 30 |
| Rich Car | 0.15 | 100 |
| Police Car | 0.10 | 15 |
| Taxi | 0.05 | 20 |
| Utility Truck | 0.03 | 3 |
| Garbage Truck | 0.03 | 2 |
| Vending Truck | 0.03 | 1 |
| Advertisement Truck | 0.03 | 1 |

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

**Side padding** (`FlyingCar.SIDE_PADDING`): each car's claim radius is inflated by a lateral half-padding (perpendicular to travel only — the capsule's *length* / front-back extent is untouched, so the speed-dependent following gap is unchanged). The **same** amount is reserved in path validation (`get_front_face_at_segment` and the spawn cross-section are widened by `2 × padding`), so a car only ever commits to lane positions where its full padded claim fits inside the lane, the whole route. The trick: across a two-way boundary the fatter claim and the extra reserved clearance **cancel**, so opposing lanes are unaffected while same-lane cars gain a side gap and stop driving abreast. Lanes too narrow for `width + 2 × padding` simply reject spawns there.

**Spawn overlap check**: a capsule gap query against the `TrafficClaimRegistry` (`is_capsule_free`), covering car bodies and ghost claims — no world iteration. Newly spawned cars publish their body claim immediately (`set_path`), so multiple spawns in the same tick can't overlap. Bridges have no claims, so in-slab spawn positions are rejected analytically (`BridgePlanner.point_blocked`, same skewed-box math the profile planner uses).

### Despawning

Pure distance check: the `CarManager` frees any car whose XZ distance to the nearest camera exceeds `spawn_radius`. No volume-based or frustum-based despawn logic. Cars drive freely through the graph and die only when they leave the outermost ring (fully hidden by fog).

### Path — one immutable full route (no teleports by construction)

A car's **entire route is committed at spawn**. `FlyingCar._build_route` runs a seeded, traffic-weighted continuation walk (the same seeded draw as before, just eagerly to completion) from the spawn volume to a city-boundary node, and `PathController.create_route` freezes it into **one immutable `Curve3D`** (smooth bezier turns at every intersection) plus **one immutable Y-profile** (the whole-route bridge plan above). The car only ever advances its arc forward along them.

Nothing the car's position is read from is *ever recomputed while it drives* — there is no per-segment rebuild, no `carry`, no mutable offset layer. That makes a vertical (or any) teleport **structurally impossible**: the entire class of "the plan changed under the car" bugs is designed out rather than guarded against. Segment crossings emit a bookkeeping signal (for spawn occupancy counts and light relevance) but change nothing.

**Route termination** is guaranteed finite and boundary-ending:
- **No repeated streets**: the walk never re-enters an edge it has driven, so it's a *trail* — bounded by the edge count, can't loop. Also kills tight seed-loops around one block.
- **Arterial gravitation**: continuations are weighted by traffic density **× a street-type bias** (`STREET_TYPE_BIAS`, large > medium > small), so cars pull toward big streets and arterials carry more through-traffic.
- **Boundary exit**: the walk ends when it reaches a boundary node (city edge). Since the boundary is far outside the despawn radius, the car always despawns by distance, off-screen, long before route-end — no mid-view pops. On a rare local dead-end the no-repeat filter relaxes so the walk keeps heading out; a hard `ROUTE_MAX_SEGMENTS` cap backstops finiteness regardless.

This is **more** multiplayer-deterministic than before, not less: the route is fully seed-determined, so a remote client reconstructs it from the spawn event with no per-transition state to sync.

### Collision avoidance — claim registry (no physics)

Cars carry **no Area3D and issue no physics queries**. Everything that occupies traffic space publishes a **claim** into the `TrafficClaimRegistry`, a spatial hash (default 32u cells) of world-space shapes:

| Claim | Shape | Published by |
|---|---|---|
| `CAR_BODY` | capsule segment through the car | every car, every frame |
| `CAR_BROADCAST` | continuous swept capsule along the car's committed route (its "ghost"), length `current_speed × broadcast_distance_multiplier` (vanishes at a stop), capped at a red light / co-linear leader ahead | every moving car |
| `TRAFFIC_LIGHT` | quad (the `TrafficPlane` face) | `AreaInstantiator` when a volume enters the tracking cylinder |
| `OBSTACLE` | capsule polyline | reserved for future dynamic obstacles (bridges are handled by the planned vertical profile, not claims) |

**Detection**: **every frame for every car** — there is no staggered cadence and no fog optimisation. (The old "fogged cars cruise blind, no detection" shortcut produced visible clips in the fade ring, where a car stays rendered a little past the fog wall, so it was removed; the whole fleet now runs full avoidance every frame.) A car samples its future path into a corridor polyline (spacing `ghost_spacing`, length `base_speed × ghost_distance_multiplier`, clamped) and queries the registry — segment-vs-segment / segment-vs-quad math against the few claims in nearby hash cells. Sampling uses `sample_profiled` (position along the flown 3D path, bridge climbs included), so a climbing car's corridor really sweeps the upper lane and vertical conflicts fall out of the same query. Corridor/scratch/hit buffers are reused across ticks. A car's relevant volume ids (current + next street) come from the immutable route, indexed by arc.

**Double buffering**: the registry swaps read/write buffers each frame (`process_priority = -100`); cars publish into the write buffer and query the previous frame's completed read buffer. Every car sees the same claim set regardless of processing order — no order dependence, multiplayer-determinism friendly.

**The governor — two layers, one job each** (`CollisionAvoidance`):

**Layer 1 — safety (bodies, enforced at motion time).** The car finds the **nearest** thing its 3D corridor hits and sets speed to converge there. Because the corridor is sampled along the path actually flown (`sample_profiled` — base curve + bridge climb), following and vertical conflicts are the same query. The nearest hit is classified:

- **`CAR_BODY` — inviolable, *no exceptions*.** Never entered, ever. A same-direction body is a leader (converge to its speed at a headway gap); a crossing/oncoming body is a hard wall. The rule is *also enforced every frame*: `clamp_travel` hard-limits travel against the last known contact arc (a tracked leader moves that arc forward exactly as far as it has driven — O(1), thanks to immutable routes). A body cannot be entered *between* decisions either. **Directionality** is the one refinement: a same-direction car *behind* my nose is my follower, not my leader, so its overlapping tail never walls me. (There is no longer any body-ignore — no cycle-winner, no drive-through. Layer 2's total-order priority keeps bodies from ever being left stopped on another car's path, so nothing ever needs to be driven through.)
- **`TRAFFIC_LIGHT`** (blocking, on a lane my route actually uses) and generic **`OBSTACLE`**: hard walls.

**Gap-restoring follow law**: `min(base, lead_speed + sqrt(2 × comfortable_deceleration × free_gap))` against a safe distance of `min_safe_distance + speed × HEADWAY_TIME`. *Inside* the safe distance the follower runs **slower** than its leader (scaling to 0 at contact), so a too-small gap actively re-opens — spacing is an attractor, not just a bound. This matters because fogged cars cruise blind and can interpenetrate: with a naive law (`target = lead_speed` when inside), an overlapped pair drives *welded together* forever; here the rear car drops back and the overlap heals.


**Layer 2 — scheduling (shrink-to-contact ghosts + total-order priority).** Every car claims the swept capsule of route ahead of it — a continuous "ghost" of itself along its committed path (`CAR_BROADCAST`), no gaps. The claim's length is **shrink-to-contact**: it reaches exactly to the car's nearest constraint (`gap`) — a leader, a red light, its own turn entrance, or a crossing claim it yields to — and no further (`_set_broadcast`, set at the end of `update_target` where `gap` is known). This one rule replaces the earlier speed-scaled-with-`_intent_limit`-cap version and is the heart of the system:

- **Self-limiting.** On open road the claim is long (speed-scaled), so cross-traffic sees the car coming from far — *that* is the reaction buffer. Stopped behind something, the claim collapses to that something. So it can **persist while stopped** (no vanish-at-stop) without a stopped car ever projecting a phantom arm across a crossing — the freeze that both "always-on floor" and the plain crossing-claim caused. Growth is gradual (speed-scaled, `BROADCAST_GROW_RATE`) for a stable claim; shrink is instant so a car that stops at a red retracts its claim off the green cross-traffic in the same frame.
- **Winner claims through, loser holds the boundary.** For a converging (crossing/merging) claim, **I cross if my `car_id` is lower, else I yield** (total order — cannot form a cycle, so no ring of cars can all wait on one another, and it never flips frame to frame). A claim I *outrank* is skipped in the scan, so it is not in my `gap` and my claim expands straight **through** the box; the loser makes that same conflict its `gap`, so its claim shrinks back **before** the box and it halts on its own lane, body clear of the winner's path. That asymmetry is what removes the symmetric merge/cross standoff — the deadlock the old 5s unlock crutch existed to paper over — with no crutch. (`next_turn_arc` still floors `gap` so the claim never projects past the car's own turn entrance even when geometric contact lies beyond it.)
- **Directionality** — a claim owned by a car **behind our nose** (`(other.pos − nose)·forward < 0`) never applies. A follower's ghost spilling forward past us can't stop us (the leading bug); the leader is handled by its *body*, the nearer hit.

**There is NO unstuck/timeout escape hatch.** A car is never driven through another — bodies are inviolable, full stop. If cars permanently stall, that is a rule bug to surface via `stuck_report.md` and fix at the root, not to paper over.

This whole layer is **deterministic and stateless across cars** — every decision is a function of published positions/claims + `car_id` order, with no shared mutable arbitration state — so it reproduces identically on every peer given synced car transforms and the two global light scalars: multiplayer-ready by construction.

**Overtaking (up only)**: while a car tails a *slower* leader, a "frustration" bar fills at the rate of its speed deficit (`overtake_bar`); past `OVERTAKE_BAR_THRESHOLD` it lifts **up** over the leader, passes, and drops back. The lift is a **second dynamic offset layer** on `PathController` (`overtake_knots`), independent of the immutable bridge `profile` — knots are only ever appended ahead of the car (rise now, descend once past), so it never rewrites where the car already is: **no teleport**, and the base route is untouched. It only commits if `_airspace_clear()` confirms the lifted corridor is free of other cars, and if no bridge within `OVERTAKE_HORIZON` would be clipped by the lift. Because a pass can hold across several streets, it stays **bridge-aware for its whole duration**: the route's crossing bands are published on `PathController.bridge_bands`, and `bridge_would_clip` (base + bridge profile + lift, vs. each band) is re-checked every frame — if a slab looms (`_bridge_imminent`), the car **drops back to lane level early** (the profile safely handles the bridge down there) rather than sailing the lift into it. This closes both failure modes the clip-reporter surfaced: lifting into a bridge the car would pass *under*, and an overtake lift *cancelling* an active duck-under. The descent otherwise waits until the car is past the leader and `_lane_ahead_clear()`; `overtake_descend` rebuilds the profile as a clean *current-height*→0 ramp, so even a mid-rise bail-out stays continuous (no teleport). Because body/broadcast claims are published along `sample_profiled` (which now includes the lift), a lifted car is automatically seen by everyone at its raised altitude, so the existing safety layers keep holding throughout. The debug bar floats over each car (green→red as it fills, cyan while passing). Currently up-only; the same offset layer trivially extends to *down* (mirror of the bridge duck-under) if wanted.

**Debug** (`Traffic Debug` export group on `AreaInstantiator`): `TrafficDebugDrawer` renders everything from registry data into one shared `ImmediateMesh` (one draw call, near-zero cost when off) — corridors color-coded by state (cruising/following/braking/yielding/stopped), ghost-claim overlays, leader links, stop-point markers, optional hash-cell wireframes, car tint by state, and inspect `Label3D`s only for cars within `traffic_debug_label_distance` (30u) of a camera.

**Diagnostic reports — the traffic system's regression harness** (`CarManager.record_diagnostics`, each a Markdown file in the project root, overwritten per run). These *are* the "unit tests" for the traffic rules: there is no way to assert on emergent multi-agent behaviour up front, so instead each report continuously watches the live fleet for one class of rule failure and writes a compact, self-explaining incident log. **Run the game yourself and read the files afterwards — never trust a headless run** (too short to reach steady state; see the memory note). Each `RefCounted` reporter is owned by `CarManager` and polled on its own frame cadence. How to read a healthy run: `stuck` and `clip` and `discontinuity` empty, `light_watchdog` says "all cycling", `traffic_health` shows `%stopped` oscillating around a stable value with `done/min` healthy.
- `stuck_report.md` (`StuckReporter`) — **the primary correctness test.** Captures only PERMANENTLY stuck *roots*, never followers. Ground truth is movement (no motion for 15 s — longer than a light cycle — so a normal red wait can't qualify), with a 90 s bootstrap grace and per-node/per-class caps. Walks the stationary blocking chain to its root: a mutual **cycle** (the originators) or a terminal **head**, classified as `LIGHT QUEUE NOT DRAINING` (remembers the non-light cause seen during green → spillback), `IGNORED GREEN` (governor/light bug), `GHOST STALL`, or `NO CONSTRAINT`. Each car prints a `gov` line (state, target speed, clamp room, `claim=` broadcast length) and a `diag` line (body vs ghost block, relative position, overlap). **The success test for the shrink-to-contact rework: any `ISOLATED` cycle (all members at one node — a merge/cross standoff) is tagged "should be impossible; a rule regression."** Zero ISOLATED cycles = the priority + shrink-to-contact rules are holding; only `SPILLBACK` cycles (a jammed ring spanning nodes) are an accepted edge.
- `clip_report.md` (`ClipReporter`) — car-on-car and car-in-bridge body overlaps (true extents, rendered cars only) with a best-guess cause. Should always be empty.
- `discontinuity_report.md` (`DiscontinuityReporter`) — teleports and true orientation snaps (large rotation with near-zero travel; rotation *with* travel is legitimate curvature and is excluded). Should always be empty.
- `traffic_health.md` (`TrafficHealth`) — the flow heartbeat, and the only trend (not incident) report: one line per 10 s with car count, `%stopped`, average speed, routes completed/min, and the hottest nodes. Distinguishes "bootstrap wave that cleared" from "city-wide gridlock" and names where to look.
- `light_watchdog.md` (`LightWatchdog`) — flags any traffic plane that stays red >20 s (a full cycle is ~10 s), with its `traffic_index` and world position; healthy output is a single "all cycling" line. Settles "stuck light vs stuck queue" independently of the stuck report. (Since lights became a computed property of one global phase, a frozen light is impossible by construction — this now guards that invariant.)

### Bridges — planned vertical profile (`BridgePlanner`)

Bridges are static and the whole route is known at spawn, so the vertical detour is **planned once, over the entire route, and frozen** — `BridgePlanner.plan_route` runs at `create_route` and never again. It gathers every bridge on every street of the route (`generator.get_bridges_for_lane`), walks the full baked curve, and intersects it against each bridge's **skewed box** — the same corner/height math the renderer uses (`city.gd _draw_bridge`), arc openings included (mid-span passable, facade ends blocked to the arc bottom). The output is a **knot polyline** on `PathController.profile` — `(arc, vertical offset)` points, smoothstep-eased. Because it spans the whole route it can hold altitude across intersections and start a climb a full street early, so slopes stay gentle even where bridges sit off-center. The rules:

- **Up or down, decided per group**: a conflict means the path is *inside* a bridge's band, and the car clears it by going over the top (`up_off`) or ducking under the bottom (`down_off`). The direction is chosen per fused **group** (`_choose_levels`), never per bridge — a group is a maximal run that can't comfortably return to baseline between its members, so it must share one signed level (you can't be up here and down there across a held span). The cheaper feasible direction wins: **up is always available** (open sky) and is the fallback; **down** is taken only when the whole group is duckable, the drop stays within `MAX_DUCK` of baseline, and the ducked segment clips no other bridge band (`_duck_clears`). Deciding per group is what keeps the path from wiggling up-then-down between close bridges. Escalation stays monotonic-up: conflicts found on the *flown* path in later rounds (a ramp clipping a band) are always cleared upward, so the iteration is bounded and can't oscillate — a duck that would dip into another slab is caught and its group forced up instead.
- **The slope is sacred and ramps stretch**: every ramp fills its runway up to `MAX_RAMP` (50u); `CLIMB_SLOPE` is the *worst allowed*, not the norm. Below the slope minimum nothing may go. The crossing window is derived from the bridge's **exact along-path footprint** (its four corners projected onto the drive direction), so the ramp always finishes before the *real* slab edge — not before an estimate that under-covered skewed crossings. Spawn placement rejects positions too close ahead of a conflicting bridge to climb gently (~50u look-ahead).
- **One curve beats many — when in doubt, stay up**: near-touching crossings fuse; crossings with no comfortable baseline return between them share one level (the max) — one climb, one hold, one descent. The car returns to baseline only when a *comfortable* round trip (stretched ramps) fits.
- **Planned against the base path, verified against the flown one**: the scan sees where the *base* path conflicts, but the car flies the *offset* path — a ramp or held plateau can rise into a band the base cleared under. So after building the knots the planner **re-scans the flown path**; any conflict becomes a new crossing and the plan is rebuilt, iterated to a fixed point. Handles ramp-clips, held-plateau clips and arc legs uniformly, converges in a couple of rounds (levels only ever rise, bounded by the tallest bridge). Scan step adapts to **half the narrowest footprint**; the footprint test carries the car's **half-width**; a small `CLEAR_MARGIN` keeps levels strictly above band tops.
- Fogged cars keep their profile (it *is* their path), so bridges are never clipped, and spawns inside slabs are rejected analytically — bridges need **no registry claims at all**.

There is **no carry, no re-plan, no per-segment profile** — the single immutable profile is the whole story, which is what makes a vertical teleport structurally impossible.

### Overtaking — removed (for now)

The reactive overtake layer was removed: it fought the planned bridge profile over the same axis and generated more edge cases than it was worth. Slow leaders are simply followed. If it returns it will be a *planned* lateral profile on the immutable curve (the same machinery as the vertical one), gated by the occupancy governor — not a reactive swerve.

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
| Base extreme | Grey | `total_width` cells | `base_height` cells | `facade_offset` cells (20) | Always |
| Arc extreme | Red | = base | `arc_height` cells | `facade_offset` cells (20) | Only if `arc_height > 0` |

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
