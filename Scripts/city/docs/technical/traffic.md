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

## Fog and zone radii

Every distance comes from `WorldSettings`:

| Distance | Value | Meaning |
|---|---|---|
| `fog_start_distance` | 0 m | Fog begins. |
| `fog_distance` | 670 m | Fog is total. **Fog only**: geometry is drawn at any distance. |
| `spawn_radius` | 760 m | `fog_distance + spawn_buffer`. Cars exist out to here; past it they are freed. |

The fog distance and the draw distance used to be one number, on purpose, so that nothing could be cut while still visible. They were **decoupled** because the coupling had a cost the other way: bringing the fog in to make the city feel larger also cut the distant silhouettes of the buildings. Now the city is drawn whole and only the fog hides; a real distance LOD is a later, separate system. The spawn radius still follows the fog, so with a short fog a car can be born in view — accepted for now, improving spawning is its own task.

A single cylindrical `Area3D` per camera at `spawn_radius` (mask = layer 4) tracks which `LaneVolume`s are in range (`all_lane_volumes`).

## Fog

Godot's built-in depth fog, configured by `CityFog` on the `WorldEnvironment` — see [city-generation.md](city-generation.md) for why it replaced the old fullscreen `radial_fog.gdshader`, which has since been deleted.

One consequence matters for traffic: the old shader measured **XZ** distance, a cylinder around the player, while the built-in fog measures depth from the camera, a sphere. Flying high, the ground below is now fogged too — it was not before.

A car's pooled visual lives exactly as long as the car is inside `spawn_radius`; the two are released together. It used to fade in over a visibility range like the buildings did — that machinery went with the draw cutoff.

> **Traffic does not know about the terrain yet.** `BlockGenerator.get_edge_lane_volume` builds every lane volume from `0.0` up to one height shared by the whole city (`max_height_global`), so lane volumes are flat boxes over sloped ground. Making them ride the field, and adding a `GroundPlanner` for cars that hug it, are steps 3 and 7 of the terrain plan in [city-generation.md](city-generation.md).

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

⚠ **One source of where a bridge is.** The planner's bridge box comes from `FacadeHelper.bridge_faces` — the very facade quads, sampled from the grid with the relief and the facade's twist, that `City._add_bridge_span` draws the bridge from. Heights are kept per corner and interpolated in `blocked_band`; the planning band takes the conservative extremes. Until this, the planner computed heights as *floor × cells × cell height from y = 0*, so on any hill the band it dodged sat metres below the real slab and cars flew straight through bridges. The same rule as the lane volumes and the streets: nothing about height is computed twice.

Bridges are static and the whole route is known at spawn, so the vertical detour is **planned once, over the entire route, and frozen** — `BridgePlanner.plan_route` runs at `create_route` and never again. It gathers every bridge on every street of the route (`generator.get_bridges_for_lane`), walks the full baked curve, and intersects it against each bridge's **skewed box** — the same corner/height math the renderer uses (`city.gd _draw_bridge`), arc openings included (mid-span passable, facade ends blocked to the arc bottom). The output is a **knot polyline** on `PathController.profile` — `(arc, vertical offset)` points, smoothstep-eased. Because it spans the whole route it can hold altitude across intersections and start a climb a full street early, so slopes stay gentle even where bridges sit off-center. See [bridges.md](bridges.md) for how the bridges themselves are generated. The rules:

- **Up or down, decided per group**: a conflict means the path is *inside* a bridge's band, and the car clears it by going over the top (`up_off`) or ducking under the bottom (`down_off`). The direction is chosen per fused **group** (`_choose_levels`), never per bridge — a group is a maximal run that can't comfortably return to baseline between its members, so it must share one signed level (you can't be up here and down there across a held span). The cheaper feasible direction wins: **up is always available** (open sky) and is the fallback; **down** is taken only when the whole group is duckable, the drop stays within `MAX_DUCK` of baseline, and the ducked segment clips no other bridge band (`_duck_clears`). Deciding per group is what keeps the path from wiggling up-then-down between close bridges. Escalation stays monotonic-up: conflicts found on the *flown* path in later rounds (a ramp clipping a band) are always cleared upward, so the iteration is bounded and can't oscillate — a duck that would dip into another slab is caught and its group forced up instead.
- **The slope is sacred and ramps stretch**: every ramp fills its runway up to `MAX_RAMP` (50u); `CLIMB_SLOPE` is the *worst allowed*, not the norm. Below the slope minimum nothing may go. The crossing window is derived from the bridge's **exact along-path footprint** (its four corners projected onto the drive direction), so the ramp always finishes before the *real* slab edge — not before an estimate that under-covered skewed crossings. Spawn placement rejects positions too close ahead of a conflicting bridge to climb gently (~50u look-ahead).
- **One curve beats many — when in doubt, stay up**: near-touching crossings fuse; crossings with no comfortable baseline return between them share one level (the max) — one climb, one hold, one descent. The car returns to baseline only when a *comfortable* round trip (stretched ramps) fits.
- **Planned against the base path, verified against the flown one**: the scan sees where the *base* path conflicts, but the car flies the *offset* path — a ramp or held plateau can rise into a band the base cleared under. So after building the knots the planner **re-scans the flown path**; any conflict becomes a new crossing and the plan is rebuilt, iterated to a fixed point. Handles ramp-clips, held-plateau clips and arc legs uniformly, converges in a couple of rounds (levels only ever rise, bounded by the tallest bridge). Scan step adapts to **half the narrowest footprint**; the footprint test carries the car's **half-width**; a small `CLEAR_MARGIN` keeps levels strictly above band tops.
- Fogged cars keep their profile (it *is* their path), so bridges are never clipped, and spawns inside slabs are rejected analytically — bridges need **no registry claims at all**.

There is **no carry, no re-plan, no per-segment profile** — the single immutable profile is the whole story, which is what makes a vertical teleport structurally impossible.

## Overtaking — removed (for now)

The reactive overtake layer was removed: it fought the planned bridge profile over the same axis and generated more edge cases than it was worth. Slow leaders are simply followed. If it returns it will be a *planned* lateral profile on the immutable curve (the same machinery as the vertical one), gated by the occupancy governor — not a reactive swerve.

## Lockout — the one escape valve

The governor above has nothing to latch onto, but rings can still form: four cars each holding before a box whose exit is occupied by the next, or a lane walled by a fixed obstacle. The valve is one timer in `CollisionAvoidance`: a car **held at zero for `LOCKOUT_AFTER` (4 s) by anything that is not a leader driving its way** — a crossing, a box hold, an obstacle, oncoming or crossing traffic — drives at `base_speed` for `LOCKOUT_FOR` (1.5 s) ignoring every claim. A brief clip beats a permanent jam. A car queued behind a stopped car heading the same way (`_queued_behind_leader`, heading dot > 0.5) never triggers it: the leader frees itself and the queue drains from the front. A red light is not a jam either. `lockouts` counts how often a car did it (the debug label shows `LOCKOUT` while it lasts and `destrabado xN`). This replaces the earlier per-car "unstuck watchdog" in `FlyingCar`, which did the same thing with three timers and a movement epsilon.

**Headless test:** `Scenes/tests/traffic_lockout.tscn` — no city: a registry, a fixed obstacle across a straight lane, and two cars in a queue. Run `godot --headless --path . res://Scenes/tests/traffic_lockout.tscn --quit-after 3000`; it prints `[LockoutTest] PASS` when the leader locks out once at the obstacle, the follower waits behind it without locking out, and both pass. Cases like these are impractical to reproduce by driving around the city; put the next one here.

## Relief — lane volumes follow the graph

A lane volume is the skewed box between two closing planes, one per node of its street edge, and each plane's base is at **its node's height** (`base_y` in `lane_planes`, from `CityTerrain.height_of` — the same height the street is drawn with). So on a sloped street the volume tilts with it, and everything measured inside the volume — a car's point at `(u, v)`, the spawn altitude band — tilts along. It is structure of the graph, not a system on top: before this the base was always `y = 0` and cars flew under the ground wherever the relief rose. If cars always flying at an angle on slopes reads badly, the alternative is a per-node vertical profile inside the volume; this one is kept because it is simple and robust.

## Passive collision — parked cars today, moving cars and pedestrians next

**Parked cars** (`City._visualize_parked_cars`, pass *autos estacionados*): every block side facing a street owns a **kerb strip** — `PARKING_STRIP_M` wide, from the kerb toward the street, along the facade — that is a `FreePlacement` (see [city-generation.md](city-generation.md#placing-objects--three-ways-in-passes)). It is walked with the block's seed leaving gaps, picking types with the district's traffic weights (`NeighborhoodTypes.get_car_weights`, `CarArchetypes.select_type_seeded`), never in front of a delivery door (`block_span`). Each car is a `ParkedCar` — the same box the traffic draws for that type — a `RigidBody3D` you can push (`MASS` is a tuning value: the heaviest character must move it), registered with `PassiveBodies`. In the sandbox's scaled block sample they are plain boxes.

**`PassiveBodies`** ([passive_bodies.gd](../../entities/passive_bodies.gd)) is the generic mechanism: a registered body is **frozen as static** — for Jolt a still shape, like a wall — and wakes up (dynamic, gravity, pushable) when a *toucher* comes within `wake_radius`: a player capsule or a ship. When every toucher is gone and the body is at rest, it freezes again where it lies. One node walks all bodies every `CHECK_EVERY` physics frames; no script per body. Not touchers yet: grabbable objects and pedestrians (edge cases to decide together). Pushes are **not synced** over the network yet.

**Moving cars** (`CarBody`, [car_body.gd](../../entities/car/car_body.gd)): a `FlyingCar` stays what it is — a route and a transform, no physics, the thing that will be synced. While a player or ship is within `CarManager.BODY_RADIUS` (25 m) the manager gives it a **body** — a `RigidBody3D` with the archetype's box and its own mesh (the pooled visual goes back to the pool) — in one of three phases:

- **Kinematic** while nothing touches it: frozen in kinematic mode and set to the sim's transform every frame. It follows the route *exactly* — corners, starts — pushes whatever is in its way and is moved by nothing. ⚠ The first version was a dynamic body chasing the sim with capped forces, and that cannot work: at a corner or a start it falls behind, exceeds the "lost" distance and drops out of the sky without anyone touching it.
- **Recovering** from the first real contact with something that can hit it (`body_entered`: a capsule, a ship, an unfrozen rigid body — never a wall or a sleeping parked car): it goes dynamic with the velocity it had, takes the hit for real, and a soft force controller (`FOLLOW_GAIN` 3, `MAX_ACCEL` 20, spring-damper torque like `Ship.upright_*`) pulls it toward a point `LEAD_M` ahead on its route — while **the sim waits for it**: `CarManager` sets the sim's progress to the body's projection on the curve (`PathController.snap_to`) and the sim does not advance, speed zero, no ray, so other cars treat it as a stopped car. A tap can therefore never "lose" it: what it chases is always right there. Back on the route (`RESUME_DISTANCE`, `RESUME_TILT`) it is kinematic again and the sim resumes.
- **Fallen** if a hit takes it `LOST_DISTANCE` off the route, flips it past `LOST_TILT`, or leaves it inside a bridge box (`BridgePlanner.point_blocked` — a body forced against a slab would tunnel through it): gravity, no controller, the momentum it had. The sim leaves the traffic (`pending_despawn`) and the wreck stays until it has rested `FALLEN_REST` seconds.

No toucher near: a kinematic body is freed and the pooled visual returns. The sim waiting for its body is local; a synced sim would need the host to own that. Nothing of this is synced yet.

**Hover cars** (`AreaInstantiator.hover_fraction`, `hover_height_m`): about a third of spawns (never the big archetypes, `min_spawn_v > 0`) go at a fixed `hover_height_m` (2.5 m) over the street, in the middle band — `u` drawn from past the **parking strip** plus half a car to the centre line — as obstacles for anyone crossing on foot. The route walk keeps a car's grid cell, so it stays there street after street. The strips themselves are **fixed obstacles** in the claim registry (`register_obstacle`, a capsule over each kerb with a street at hover height, radius 0.6 × that height — narrow vertically on purpose, so ground-level traffic passes underneath and the high traffic above), so neither spawns nor continuations enter them at hover height.

The body is `top_level` and is placed with its **global** transform: `CarManager` hangs under a node that is not at the origin, and a local transform there put every body metres off its sim on creation — the "teleport" seen at a corner.

Next on this list: **pedestrians** (path-driven, physical only near players, recovery to be designed), the spawn budget (the occlusion-based spawn near the player already exists — `_is_point_hidden` — what is missing is control over where the budget lands; see *Spawning* above), garage doors on buildings, and what happens when a player parks a car in the middle of a lane.

## Online sync design note

The car system is designed for deterministic prediction in online multiplayer. Given a car's seed, spawn volume, and grid position `(u, v)`, its archetype, speed, and path are fully determined. Continuation selection uses a seeded RNG. This means a remote client can reconstruct any car's trajectory without continuous position updates — only the initial spawn event needs to be synchronized. The claim system reinforces this: detection is pure float math on double-buffered data (Godot physics is not cross-machine deterministic, claims are), and a car's motion between decisions is analytic, so only decisions — spawn events, lane transitions, target-speed changes — would need to go on the wire.
