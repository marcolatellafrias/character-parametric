# Traffic System

The ambient flying-car simulation that populates the city. Part of [city generation](city-generation.md); the bridges the cars navigate are generated in [bridges.md](bridges.md).

## Lane volumes
Each street edge in the graph becomes two opposite facing contiguous `LaneVolume`s: a 3D rectangular region with a `start_plane` and an `end_plane`. Cars travel from one plane to the other. Volumes are connected at shared graph nodes — the end node of one volume is the start node of the next.

## Traffic lights (generation only — deprecated)
Each `LaneVolume` still gets a `TrafficPlane` child with a `traffic_index` (0 or 1), and the plane geometry is kept in generation so lights can be re-enabled later. **The car simulation no longer reads them**: light planes are not registered as claims and cars never stop at a red. Traffic is regulated purely by the ray-broadcast governor below, so yielding happens *everywhere along the path*, not only at signalled intersections. (Historically each plane published a quad claim into the `TrafficClaimRegistry` and a `LightWatchdog` reporter guarded the phase invariant; both were removed with the rest of the car-side light plumbing.)

## Car movement
A car enters a volume at a grid position `(u, v)` within the start plane. A `Curve3D` path is created from start to end plane via bilinear interpolation. The car holds the curve directly (no `Path3D`/`PathFollow3D`/`Timer` nodes — `PathController` is `RefCounted`): a float progress advances along the baked curve (`bake_interval` 2.0, cars don't need the default 0.2u precision) and transition/end checks run inline in `advance()`. Segment-transition offsets are computed analytically (the shared straight segment carries progress over by subtraction), so no `get_closest_offset` search. When the car reaches the end, it checks the traffic light, then queries `get_lane_volume_continuations()` to find the next volumes and picks one. A new curve is built and the cycle repeats.

A car is not a node: `FlyingCar` extends `Object` (`CollisionAvoidance` and `PathController` are `RefCounted`), and the whole fleet is ticked by one `CarManager` loop — camera positions are computed once per frame and there are no per-node `_process` callbacks. Cars inside `render_distance` borrow a pooled `MeshInstance3D` visual from the manager, released a small margin past the fog wall so boundary oscillation doesn't churn the pool; fully fogged cars are pure data with no node, no mesh and no transform updates. All cars of an archetype share one `BoxMesh`+`StandardMaterial3D` (debug tint uses a lazy per-car `material_override` on the pooled visual).

```
Enter volume (u,v) → build Curve3D path → follow path
→ check traffic light → pick next volume → repeat
```

## Car archetypes

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

## Routing

When choosing a continuation at an intersection, cars weight candidates by **traffic density** (`LaneVolume.get_traffic_density()` — the same street × neighborhood constant the spawner uses for targets), so routing and spawning push toward the same distribution: big streets attract and keep more cars. The seeded weighted draw itself provides the random variation into less dense routes. U-turns are structurally excluded by `get_lane_volume_continuations()` (the same graph edge in either direction is skipped). Population composition is controlled entirely at spawn time by the per-neighborhood weight tables.

The weighted draw happens **before** validation: only the drawn volume runs the (expensive) projection-validation, falling back to the next draw if it fails — instead of validating every candidate and discarding all but one.

## Fog and zone radii (`AreaInstantiator`)

Three concentric cylindrical zones (XZ distance from camera):

| Zone | Radius | Purpose |
|---|---|---|
| Inner (clear) | `0 → inner_radius` | No fog |
| Fade ring | `inner_radius → outer_radius` | Fog 0% → 100% |
| Outer | `outer_radius → spawn_radius` | Full fog; safe for spawning |

A single cylindrical `Area3D` per camera at `spawn_radius` (mask = layer 4) tracks which `LaneVolume`s are in range (`all_lane_volumes`).

## Radial fog

A fullscreen spatial shader (`radial_fog.gdshader`) on a `MeshInstance3D` quad reads the depth buffer, reconstructs world position, and computes XZ distance from the player. Fog is `smoothstep(inner_radius, outer_radius)` — completely clear inside the inner zone, fully opaque at the outer boundary. The sky (depth = 1.0) is discarded so it's never fogged.

## Spawning — demand-pull system

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

## Despawning

Pure distance check: the `CarManager` frees any car whose XZ distance to the nearest camera exceeds `spawn_radius`. No volume-based or frustum-based despawn logic. Cars drive freely through the graph and die only when they leave the outermost ring (fully hidden by fog).

## Path — one immutable full route (no teleports by construction)

A car's **entire route is committed at spawn**. `FlyingCar._build_route` runs a seeded, traffic-weighted continuation walk (the same seeded draw as before, just eagerly to completion) from the spawn volume to a city-boundary node, and `PathController.create_route` freezes it into **one immutable `Curve3D`** (smooth bezier turns at every intersection) plus **one immutable Y-profile** (the whole-route bridge plan above). The car only ever advances its arc forward along them.

Nothing the car's position is read from is *ever recomputed while it drives* — there is no per-segment rebuild, no `carry`, no mutable offset layer. That makes a vertical (or any) teleport **structurally impossible**: the entire class of "the plan changed under the car" bugs is designed out rather than guarded against. Segment crossings emit a bookkeeping signal (for spawn occupancy counts and light relevance) but change nothing.

**Route termination** is guaranteed finite and boundary-ending:
- **No repeated streets**: the walk never re-enters an edge it has driven, so it's a *trail* — bounded by the edge count, can't loop. Also kills tight seed-loops around one block.
- **Arterial gravitation**: continuations are weighted by traffic density **× a street-type bias** (`STREET_TYPE_BIAS`, large > medium > small), so cars pull toward big streets and arterials carry more through-traffic.
- **Boundary exit**: the walk ends when it reaches a boundary node (city edge). Since the boundary is far outside the despawn radius, the car always despawns by distance, off-screen, long before route-end — no mid-view pops. On a rare local dead-end the no-repeat filter relaxes so the walk keeps heading out; a hard `ROUTE_MAX_SEGMENTS` cap backstops finiteness regardless.

This is **more** multiplayer-deterministic than before, not less: the route is fully seed-determined, so a remote client reconstructs it from the spawn event with no per-transition state to sync.

## Collision avoidance — claim registry (no physics)

Cars carry **no Area3D and issue no physics queries**. Everything that occupies traffic space publishes a **claim** into the `TrafficClaimRegistry`, a spatial hash (default 32u cells) of world-space shapes:

| Claim | Shape | Published by |
|---|---|---|
| `CAR_BODY` | capsule segment through the car | every car, every frame |
| `CAR_BROADCAST` | the car's forward "ray": the front slice of its look corridor out to `speed × LOOKAHEAD_TIME` (long when fast, empty when stopped) | every moving car |
| `OBSTACLE` | capsule polyline | reserved for future dynamic obstacles (bridges are handled by the planned vertical profile, not claims) |

**Detection cadence**: motion (integrate speed + advance + pose) runs **every frame**, but the expensive avoidance decision (rebuild corridor + pick target speed) runs at a **distance-scaled, id-staggered cadence** (`DECISION_INTERVAL_NEAR/MID/FAR` in `FlyingCar.tick`) — braking latency is invisible at range, so far cars decide less often. A car samples its future path into a corridor polyline (spacing `ghost_spacing`, length `speed × LOOKAHEAD_TIME`, floored/capped) and queries the registry — pure segment-vs-segment math against the few claims in nearby hash cells. Sampling uses `sample_profiled` (position along the flown 3D path, bridge climbs included), so a climbing car's corridor really sweeps the upper lane and vertical conflicts fall out of the same query. Corridor/scratch/hit buffers are reused across ticks.

**Double buffering**: the registry swaps read/write buffers each frame (`process_priority = -100`); cars publish into the write buffer and query the previous frame's completed read buffer. Every car sees the same claim set regardless of processing order — no order dependence, multiplayer-determinism friendly.

**The governor — one continuous rule** (`CollisionAvoidance`). There is a **single rule and nothing else**:

> Every car continuously broadcasts a ray ahead of itself along the route it will drive, whose length is simply `speed × LOOKAHEAD_TIME` — long when fast, nothing when stopped. Every car reads the rays and bodies of others, takes the **nearest** one crossing its own path ahead, and sets its speed so it can always ease to a halt just short of it. That is the whole system.

- **No priority, no `car_id` tie-breaks, no claims arbitration, no "stop before the box", no hard travel clamp, no inviolable walls.** Slowing is a smooth function of how far the nearest thing ahead is (`target = min(base, sqrt(2 × comfortable_deceleration × free_gap))`), recomputed each decision tick. A stopped car is merely a car whose target speed is momentarily zero; the instant the space ahead opens it moves again, so a permanent deadlock has nothing to latch onto.
- **The one filter — directionality.** A body/ray owned by a car **behind my nose** (`(other.pos − my_pos)·forward < 0`) is ignored: that is my follower, not an obstacle ahead. Pure geometry, not a vote.
- **Crossings resolve themselves.** As two cars near an intersection their rays reach across it and both slow; whichever is faster keeps the longer ray while the other yields — and because a slowing car's ray *shrinks* (it is `speed × time`), yielding frees the faster car, which speeds up, extends its ray and holds the yielder back. The asymmetry feeds itself. The one unresolved case is a perfectly symmetric arrival, which may briefly **clip** rather than deadlock — the deliberate trade: a transient overlap, never a permanent stall.

**Keep the box clear.** One geometric add-on to the pure ray rule (`update_target` + `PathController.next_box`): if braking for whatever is ahead would leave a car stopped *inside* the next intersection turn, it holds *before* the box instead, so cross traffic is never walled by a car parked in the crossing. This is the only intersection-specific piece; the rest of the governor treats all path points alike.

**Unstuck watchdog** (`FlyingCar.tick`). Since the pure ray rule tolerates a rare symmetric clip and the frozen-route residual can still wedge a car, a deliberately-simple watchdog forces a car that has sat still for `UNSTUCK_AFTER` (~4 s) and is *not* merely tailing a same-direction leader to drive straight **through** whatever blocks it for `UNSTUCK_CLIP_TIME` — a brief accepted clip beats a permanent stall. (This is a pragmatic crutch, not part of the pure design; if the underlying wedge is ever root-caused it can go.)

**Debug** (`Traffic Debug` export group on `AreaInstantiator`): `TrafficDebugDrawer` renders everything from registry data into one shared `ImmediateMesh` (one draw call, near-zero cost when off) — corridors color-coded by state (cruising/following/braking/yielding/stopped), ghost-ray overlays, leader links, stop-point markers, optional hash-cell wireframes, car tint by state, and inspect `Label3D`s only for cars within `traffic_debug_label_distance` (30u) of a camera.

**Diagnostic reports — removed.** The traffic system previously wrote five Markdown regression reports to the project root (`stuck_report.md`, `clip_report.md`, `discontinuity_report.md`, `traffic_health.md`, `light_watchdog.md`), each a `RefCounted` reporter owned by `CarManager`. They were the "unit tests" for the emergent multi-agent rules but added significant surface area and were removed during the traffic-system simplification. If regression coverage is wanted again, reintroduce a single focused reporter rather than the full suite.

## Bridges — planned vertical profile (`BridgePlanner`)

Bridges are static and the whole route is known at spawn, so the vertical detour is **planned once, over the entire route, and frozen** — `BridgePlanner.plan_route` runs at `create_route` and never again. It gathers every bridge on every street of the route (`generator.get_bridges_for_lane`), walks the full baked curve, and intersects it against each bridge's **skewed box** — the same corner/height math the renderer uses (`city.gd _draw_bridge`), arc openings included (mid-span passable, facade ends blocked to the arc bottom). The output is a **knot polyline** on `PathController.profile` — `(arc, vertical offset)` points, smoothstep-eased. Because it spans the whole route it can hold altitude across intersections and start a climb a full street early, so slopes stay gentle even where bridges sit off-center. See [bridges.md](bridges.md) for how the bridges themselves are generated. The rules:

- **Up or down, decided per group**: a conflict means the path is *inside* a bridge's band, and the car clears it by going over the top (`up_off`) or ducking under the bottom (`down_off`). The direction is chosen per fused **group** (`_choose_levels`), never per bridge — a group is a maximal run that can't comfortably return to baseline between its members, so it must share one signed level (you can't be up here and down there across a held span). The cheaper feasible direction wins: **up is always available** (open sky) and is the fallback; **down** is taken only when the whole group is duckable, the drop stays within `MAX_DUCK` of baseline, and the ducked segment clips no other bridge band (`_duck_clears`). Deciding per group is what keeps the path from wiggling up-then-down between close bridges. Escalation stays monotonic-up: conflicts found on the *flown* path in later rounds (a ramp clipping a band) are always cleared upward, so the iteration is bounded and can't oscillate — a duck that would dip into another slab is caught and its group forced up instead.
- **The slope is sacred and ramps stretch**: every ramp fills its runway up to `MAX_RAMP` (50u); `CLIMB_SLOPE` is the *worst allowed*, not the norm. Below the slope minimum nothing may go. The crossing window is derived from the bridge's **exact along-path footprint** (its four corners projected onto the drive direction), so the ramp always finishes before the *real* slab edge — not before an estimate that under-covered skewed crossings. Spawn placement rejects positions too close ahead of a conflicting bridge to climb gently (~50u look-ahead).
- **One curve beats many — when in doubt, stay up**: near-touching crossings fuse; crossings with no comfortable baseline return between them share one level (the max) — one climb, one hold, one descent. The car returns to baseline only when a *comfortable* round trip (stretched ramps) fits.
- **Planned against the base path, verified against the flown one**: the scan sees where the *base* path conflicts, but the car flies the *offset* path — a ramp or held plateau can rise into a band the base cleared under. So after building the knots the planner **re-scans the flown path**; any conflict becomes a new crossing and the plan is rebuilt, iterated to a fixed point. Handles ramp-clips, held-plateau clips and arc legs uniformly, converges in a couple of rounds (levels only ever rise, bounded by the tallest bridge). Scan step adapts to **half the narrowest footprint**; the footprint test carries the car's **half-width**; a small `CLEAR_MARGIN` keeps levels strictly above band tops.
- Fogged cars keep their profile (it *is* their path), so bridges are never clipped, and spawns inside slabs are rejected analytically — bridges need **no registry claims at all**.

There is **no carry, no re-plan, no per-segment profile** — the single immutable profile is the whole story, which is what makes a vertical teleport structurally impossible.

## Overtaking — removed (for now)

The reactive overtake layer was removed: it fought the planned bridge profile over the same axis and generated more edge cases than it was worth. Slow leaders are simply followed. If it returns it will be a *planned* lateral profile on the immutable curve (the same machinery as the vertical one), gated by the occupancy governor — not a reactive swerve.

## Online sync design note

The car system is designed for deterministic prediction in online multiplayer. Given a car's seed, spawn volume, and grid position `(u, v)`, its archetype, speed, and path are fully determined. Continuation selection uses a seeded RNG. This means a remote client can reconstruct any car's trajectory without continuous position updates — only the initial spawn event needs to be synchronized. The claim system reinforces this: detection is pure float math on double-buffered data (Godot physics is not cross-machine deterministic, claims are), and a car's motion between decisions is analytic, so only decisions — spawn events, lane transitions, target-speed changes — would need to go on the wire.
