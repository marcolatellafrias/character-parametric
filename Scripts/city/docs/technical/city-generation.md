# City Generation

Technical, code-level breakdown of the procedural city generator. Three subsystems each have their own file:

- [sidewalks.md](sidewalks.md) — sidewalk zones, physical instances, the sidewalk 3D matrix, delivery doors, and traversal infrastructure (stairs + floating sidewalks).
- [bridges.md](bridges.md) — bridge ownership, count, structure, archetypes, and placement.
- [traffic.md](traffic.md) — the ambient flying-car simulation.

## Steps in order

0. **Terrain field** — a continuous, seeded height field over the whole city (`CityTerrain`). Everything else is eventually measured from it; see [Terrain](#terrain).
1. **Street graph** — Voronoi graph (Poisson sampling). Each edge gets a street type: boundary, small, medium, or large.
2. **Districts and heights** — Each graph face gets a **district** (what it is made of) and, from a separate set of patches, a **height tier** (how many floors). Two independent axes; see [Districts and heights](#districts-and-heights).
3. **Blocks** — Each face gets a `BlockGenerator`. The edges of the block know which street type borders them, reserving an empty margin (street offset) that visually forms the street.
4. **Internal alleyways** — Inside each block, `PathGenerator` traces small and big alleyways in the `DistortedGrid`.
5. **Clusters** — Non-alleyway cells are grouped into `BuildingCluster` via flood-fill, then subdivided (1–8 cells each).
6. **Block hearts** — Interior clusters (not on the block perimeter) have a chance of becoming "hearts": their `floor_count` is set to 0, creating empty courtyards inside the block.
7. **Building modules** — Each cell in each cluster is a `BuildingModule` per floor. Each module knows what borders its 4 sides and shrinks its core area inward (facade/alleyway offset), forming the actual building footprint.
8. **Sidewalk zones** — The non-core cells of each building module define sidewalk zones: external (between the buildable zone boundary and the building face) and internal (alleyway offset areas between buildings). See [sidewalks.md](sidewalks.md).
9. **Sidewalk 3D matrices** — Each distorted grid cell gets a 3D matrix tracking cell availability in the sidewalk zones, extruded vertically. Combined per block for cross-cell queries.
10. **Sidewalk instances** — Physical walkable surfaces spawned within sidewalk zones. Floor 0 gets sidewalks everywhere. Higher-floor floating sidewalks are bridge-dependent (rules TBD).
11. **Wall** — A closed barrier on the graph's boundary edges, the limit of the playable world. See [The wall](#the-wall).
12. **Bridges** — Placed on graph edges. Middle parts span between opposing buildable zone boundaries. Extremes extend through external sidewalk zones to the building face. See [bridges.md](bridges.md).

---

## Terrain

`CityTerrain` ([city_terrain.gd](../../core/city_terrain.gd)) is the city's relief: a **continuous function of the plane**, `height_at(x, z)`, not a per-node table. Two things that land on the same spot — a sidewalk and its street's lane volume, two blocks facing each other — therefore agree by construction, with no coordination and no seams.

It is **noise seeded from the world seed** (`WorldSeeds.derive(generation_seed, 3)`), so it is identical on every machine — the traffic system predicts routes across the network and needs the geometry to match. Two corrections are applied over the raw noise, in `fit_to_graph`, once the graph exists:

- **Stretched to the full range.** Raw noise never reaches its extremes — measured over one city's nodes it spans 22%–77% — so without this the relief is flattened and floats above zero, with no valley resting on it.
- **Slope-capped.** The steepest street (height difference between two adjacent graph nodes over their distance) is measured, and if it exceeds `max_slope` the amplitude of the whole field is scaled down until it fits. This matters because the character is a rigid-body capsule with friction 0, no slope limit and no step logic, and ground-hugging cars will have to follow the terrain.

The amplitude is authored in **floors** (`City.terrain_floors`) — how many floors of a building a hill eats — and converted to metres once the floor height is known. `terrain_floors = 0` gives the old flat city.

The **ground mesh** (`City._visualize_ground`) triangulates each graph face in a fan and subdivides every triangle `GROUND_SUBDIVISIONS` times per side, **sampling** the field at each vertex rather than interpolating between the corners — so a long street comes out curved, the way a real city on a slope does, instead of a straight ramp between two corners. It hangs from a `Ground` node in the `city_ground` group, with an optional trimesh collider.

### What rides on it

Everything placed **in-grid** does, because it all flows through one funnel: `BuildingModule`'s `get_region_vertices` / `get_core_vertices` / `get_cell_vertices` / `get_cell_position` (buildings, external sidewalks, delivery doors, stairs, floating sidewalks, bridge extremes, and future windows/AC/pipes). `DistortedGrid.get_cell_vertices` puts the grid's own vertices on the field too; the wave distortion stays purely horizontal.

**Everything follows the ground, at every height.** In the funnel each corner gets the terrain height at its own position, and the height index adds a **pure vertical offset** on top. So floor N is floor 0 raised in Y: every floor parallel, every floor tilted alike.

The visible mesh goes through that same funnel. `City._visualize_buildings` asks it for the floor's **two** faces — `get_core_vertices(index)` at the bottom and at the top of the floor — instead of computing the top itself, and the building colliders and roof props do the same. So a placed object lands on the face you actually see **by construction, not by agreement**. Neighbouring pieces agree for the same reason: they sample the same continuous field at the same corners.

**Not wired yet:** the **between-grids** placements — bridge middles and lane-volume planes — are still built at `y = 0` (`BlockGenerator`'s lane planes). Until they follow, a bridge's extremes ride the terrain while its middle stays at zero, and cars fly at the old height.

The relief **inside** a block does not live here: that one is discrete and stepped, rides on the `DistortedGrid`, and falls off to zero at the block perimeter so the border is worth exactly what this field says — the same trick the wave distortion already uses (see the alignment guarantee below).

---

## Output is merged; the modularity lives in the data

The scene the city emits is **coarser than the data behind it, on purpose**. Per building (`BuildingCluster`) it emits exactly **one mesh** and **one collider**, merged from every cell of every floor — not one node per cell per floor.

This is only the **last step**, the emission. Everything upstream stays per cell and per floor: `BuildingModule` (core area, chamfers, the funnel every placeable position flows through) and the sidewalk 3D matrix. Future placeables — windows, balconies, AC units, signs, roof tanks — will ask *those* for their position, never the scene tree, so merging the output costs them nothing. Splitting it back into pieces is a change to one function (`City._visualize_building_colliders` / `_visualize_buildings`) and nothing else.

**Why it matters** (measured on the 312-block city): colliders went from **145 264 collision shapes to 22 596** — the building half from 126 777 down to 4 109, one per building. Those shapes sit in Jolt's broadphase no matter where the player is, so this is a per-frame and memory win, not only a startup one. The collider is built from the **same geometry the mesh pass already computes** (`DebugUtil.get_skewed_cube_advanced_grid_geometry`), so nothing is calculated twice.

### Modules are cached by data, not by floor

`BuildingCluster.get_building_module()` keys its cache on **the cell plus its four edge types**, not on the floor. Edge types are still queried *with* the floor (`PathGenerator.get_path_edge_type_vertices(..., floor)`), so the day an alleyway changes with height, that cell yields a different key and is recomputed on its own — **the ability to vary per floor stays, but is only paid for where it actually varies**. Today nothing varies, and the city computes **10 560 modules instead of 126 777**: each one's chamfers walk the grid vertex by vertex, which was the single most expensive step of generation.

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

## Districts and heights

Two **independent axes**. They used to be one enum of four types, and that was the mistake: *Downtown* is not a culture, it is a density. A rich downtown is glass towers, a poor one is stacked tenements, an industrial one is silos packed together — so raising a slum's height forced it to become another neighbourhood.

- **District** (`NeighborhoodTypes.District`): who lives there and what it is built from — **poor, rich, industrial**. It drives building style (`ArchetypeDefinitions`), which cars drive through, how much traffic there is, and how often a block gets a courtyard. The two archetypes that used to be Downtown's became the dense face of poor (`MixedUse`) and rich (`OfficeTower`), so no style was lost.
- **Height** (`NeighborhoodTypes.Height`): how many floors, and with them how many bridges cross its streets. This is the **gameplay axis**, calibrated against the ship.

| Tier | Floors | Against the ship |
|---|---|---|
| Low | 1–4 | Flown over without touching anything — the breather, and it opens the view |
| Mid | 7–11 | Costs vertical thruster, and its tallest (11) cannot be cleared even with it |
| Tall | 15–22 | There is no *over*. You fly between them, and this is the norm |

The ship climbs **6 floors** on cruise and **10** with the vertical thruster, which burns. The **gaps** between tiers (4→7, 11→15) are deliberate: if the bands touched, the three tiers would read as one grey continuum instead of being legible at a glance.

Both axes are spread as **patches** (`_assign_patches`: seeds on random faces, all fronts growing one step per round until the city is covered), with **separate seeds and no radial rule** — so a slum can be a canyon downtown and a rich district can be low and open against the wall. Height patches get their tier by **quota**, not by independent draws: `HEIGHT_WEIGHTS` (55% tall, 25% mid, 20% low) is turned into exact counts and shuffled. Drawing each patch on its own let the realised share drift badly — 8% low against the 20% asked, because the draw is per *patch* and patches differ in size.

**Cracks.** Inside a block that is *not* low, each building has a `CRACK_CHANCE` (12%) of breaking its tier and building from the **low** range instead. They are the gaps a pilot can spot and cut through between towers — player expression, so the only options aren't "straight over a breather patch" or "along the street". A building is a cluster of 1–8 cells and a cell is ~27 m, so even the smallest crack is far wider than an alleyway: it does not break the rule that the ship never flies into alleyways. The majority stays tall, so the maze holds.

**Measured** over one 312-block city (1 782 m across, 10 district seeds, 28 height patches): tiers came out **18% low / 26% mid / 57% tall** against the 20/25/55 asked, 3 399 buildings with **none outside its patch's range**, and **392 cracks (11.5%)** with none in low blocks. Generating it takes **56 s**: 6.4 s of data (graph included) and **50 s of mesh and collider emission**, which is per built block and per floor — that is the number to attack if startup ever becomes unbearable, not the graph.

**History:** floors used to be blended toward the average of all types by `pow(distance_to_seed, neighborhood_height_falloff)`, with the exponent at 0.3. Because it is below 1 the blend rose very fast — 66% blended at a quarter of the distance — so only seed blocks kept their own range. Measured: **24 one-floor buildings in the whole map**, Downtown building 4-floor blocks where it asks for 8, and all four types averaging between 3.9 and 6.7 floors. The whole mechanism was removed with the four-type enum.

---

## The wall

The limit of the playable world: a barrier that cannot be cleared, not even with the thruster. **It is currently invisible**: `City.show_wall_mesh` is off, so the mesh is built and hidden while the collider stays. That flag is separate from `show_wall` on purpose — `show_wall` drops the collider too, and the ship then leaves the map. It rides the graph's **boundary edges** — the ones with a single adjacent face, already street type `-1` with neither sidewalk nor roadway — so it needs no path of its own; the city's edge was already there.

Its **base follows the terrain** and its **top stays at a constant altitude** (`City.wall_floors`, **13 floors ≈ 87 m**). That height is chosen against the ship, not against the buildings: its altitude target tops out at **8 floors** (53.5 m, `Ship.max_altitude`), so 13 floors stays out of reach by five without walling the city in. (The vertical thruster the design calls for does not exist in code yet — until it does, 8 floors is the whole ceiling. It previously sat at 90 m, i.e. 13.4 floors, which let the ship clear the wall outright.) The tallest buildings (11–18 floors, up to 120 m) **rise above it on purpose** — a wall taller than every tower makes the city read as a toy box. The constant top is the point: a top that followed the hills would dip in the valleys and stop being impassable exactly where the terrain already sinks the player. A square **post at each boundary node** covers the joint between two runs, which would otherwise leave a wedge of air at open corners.

Unlike buildings, bridges and floating sidewalks — which are cut at `WorldSettings.render_distance` by `City._fade_into_fog` — the wall carries **no distance range at all**: it is one mesh spanning the city, so its centre-of-geometry origin lands in the middle of the map and "distance to the wall" means nothing. Given a range it simply vanished from everywhere but the city centre. What keeps its silhouette from shrinking the city is the fog below, not culling.

### Meshes are built in world space — mind the origin

Almost every city mesh is built with **world-space vertices** and added with no transform, so its origin sits at `(0,0,0)` — the corner of the city — with the geometry hundreds of metres away. That is fine for drawing, and it is what lets separate pieces share one coordinate system.

It is **not** fine for anything Godot measures from the node's origin. `visibility_range_end` is exactly that: the distance it compares is *camera → node origin*, which for these meshes is *camera → corner of the city*, **the same for every building**. Move away from that corner and they all fade at once, including the ones right in front of you — and the symptom reads as a fog bug, not a culling one.

So `City._fade_into_fog` first calls `_center_on_own_geometry`: vertices become relative to the mesh's own AABB centre and the node moves there. The geometry stays put in the world; the distance Godot measures becomes the one you expect. `_add_box_occluder` already did this for occluders. **Any future per-piece LOD, visibility range or distance-based logic has to do the same** — or be given a node whose origin means something.

There is a second half to that rule: **a mesh that spans the whole city cannot use a distance range at all**. The wall is one mesh from edge to edge, so its centred origin lands in the middle of the city and "distance to the wall" is meaningless — given a 294 m range it only drew while the camera was near the city centre, i.e. almost never. The wall therefore has **no range**; what keeps its silhouette from shrinking the city is the fog.

### Pieces fade in, and the ring grows with distance

`City._fade_into_fog` gives every piece `visibility_range_end = render_distance + its AABB radius`, a `visibility_range_end_margin` of `WorldSettings.fade_ring_for(that distance)` and `VISIBILITY_RANGE_FADE_SELF`. Pieces dissolve in across that ring instead of appearing.

**The ring is not a constant.** The formula is San Andreas' own (`CVisibilityPlugins::CalculateFadingAtomicAlpha`): 20 units for anything drawn within 150, and `distance / 15 + 10` past that — **63 m** at our 800 m draw distance. A fixed 20 m ring is a gentle dissolve for something arriving at 100 m and a blink for something arriving at 800; scaling it keeps the *apparent* softness the same everywhere. Cars use the same rule, and `CarManager` holds their pooled visual until `render_distance + ring + margin` so the release never interrupts a fade.

For a long time there was no fade at all — hard cut — and it is worth keeping straight *why* that flipped, because the reasons changed rather than the taste:

- **Fading used to be impossible.** The fog was then a fullscreen pass reading the depth buffer, and a mesh mid-fade draws dithered, is not written to that buffer properly, and got skipped by the fog: it showed up crisp and unfogged in the distance, and the instant it turned opaque the fog landed on it all at once. Godot's **built-in fog is applied per fragment inside the material shader**, so a fading mesh stays correctly fogged the whole way through. The objection died with the old fog.
- **Fading is no longer load-bearing, and is kept anyway.** With the fog colour equal to the sky's horizon — true again today — a saturated piece at eye level is already indistinguishable from its background, so the cut would be almost invisible on its own. *Almost* is the operative word: the sky is a gradient and the fog is a single colour, so anything poking above the horizon still differs from what sits behind it. The fade absorbs that difference instead of the sky having to be bent to match, which is what the three hand-tuned colour bands of the old shader were doing.

Measured across the ring with a test box, as the largest channel difference between the box and the sky beside it: **0.227 at 400 m, 0.212 at 440, 0.133 at 470, 0.082 at 490, 0.059 at 500**. It dissolves; it never steps. (Those numbers come from the warm-fog/blue-sky configuration, where fog and background were as far apart as they ever got — the worst case, and therefore the useful one.)

Two things the threshold depends on:

- **It must include the piece's own radius.** Godot compares the distance to the node's *origin* — its centre — while the fog is computed per pixel. Without the radius, a building whose centre sits at the threshold still has its near face tens of metres closer, under noticeably less fog.
- **The fade is dithered**, so you see slightly through a mesh while it crosses the ring. In the last ~63 m before the cut it is under heavy fog and reads as haze, but once balconies, doors and signs are their own meshes, keep the ring where the fog is already thick. If real LOD is ever needed the tool is hierarchical `visibility_parent` — this fade is about entry, not detail.

### The weather: fog, sky, ambient and screen tint are one decision

`CityFog`, on the `WorldEnvironment`, owns all four, and `WeatherPresets` is the table it reads. The structure is lifted from **GTA San Andreas' `timecyc.dat`**, and the three things it gets right are worth stating plainly:

**1. Fog colour and sky colour are separate fields, and each preset decides whether to match them.** In the timecyc they are literally one column (`Sky bot`) used for both, and the eight San Andreas presets keep that: their `fog_color` equals their `sky_horizon`. It makes the silhouette problem structurally impossible — a piece saturated with fog ends up painted exactly the colour of what is behind it — but the price is that the colour of the distant city is dictated by the sky.

The **default preset does the opposite on purpose**: `original` reproduces the 25/6 build, a **stock Godot sky with dark blue fog that does not come from it**. Silhouettes are real there, which is exactly why the fade ring exists. Strong fog is wanted — without it the world reads monotonous — and the lesson from trying 800 m is that what keeps a city from feeling enclosed is the fog's *colour*, not its reach.

**2. Weather changes the colour, never the range.** Across the eight timecyc rows copied into `WeatherPresets`, `FarClp` is **2000 in every one**. San Andreas never closes the world in when the weather turns; it tints it. So the presets carry no distances at all — those live in `WorldSettings` and are identical for every weather, and changing weather can never make the city feel smaller.

**3. Two full-screen colour-correction layers** (`Alpha1 RGB1`, `Alpha2 RGB2`, at alpha 195/255 in every row seen). This is where a surprising share of the "look" lives. `Shaders/screen_tint.gdshader` approximates it as a multiply layer plus a wash; `CityFog.tint_strength` scales both, defaulting to 0.45 because our tonemapping is not RenderWare's and the full strength eats the contrast. **It is an approximation, not a port** — Rockstar's own implementation differs between PS2, PC and mobile (SkyGfx carries separate `COLORFILTER_PS2` and `COLORFILTER_PC` paths), and that code was not available.

**4. The sun belongs to the weather too.** `sun_core` and `sun_size` come straight from the timecyc (`SunCore`, `SunSz`), and they carry one detail worth copying: in **rain and sandstorm `SunSz` is 0** — San Andreas simply does not draw the disc, while keeping the directional light. `CityFog` reproduces that with `SKY_MODE_LIGHT_ONLY`. The sun's *position* is not in the timecyc (San Andreas derives it from the clock), so `sun_elevation` and `sun_azimuth` are ours, and they are what give dawn and dusk their long shadows.

> **Godot trap, and it cuts both ways:** `DirectionalLight3D.light_angular_distance` defaults to **0**, and at 0 the disc `ProceduralSkyMaterial` draws is a point — invisible. That default is the whole reason the world had no visible sun (measured: the pixel at the sun reads **1.000** brightness with a 3.2° disc against **0.384** where the preset hides it). But the *same* property is the sun's angular size for shadowing — the penumbra width, 0.53° in reality — so raising it to get a nice disc washes out the shadows buildings cast on each other. They are two different things sharing one property, so `CityFog` drives **two lights**: the one in the `sun` group lights and casts with `shadow_softness`, and a second one in `SKY_MODE_SKY_ONLY` draws the disc with `sun_size` while contributing neither light nor shadow.

Eight presets ship, each converted from a real timecyc row: clear midday, dense fog, rain, dawn, dusk, LA smog at dusk, a sandstorm and night. **F5** opens the list and picks one by number, the **Clima** tab of the F1 panel does the same with the mouse, and **F6** tunes the active one by hand — see [ui.md](ui.md). What F6 writes are **overrides**: `CityFog` layers them over the preset, picking any weather clears them, and nothing persists, so a setting that works has to be copied by hand into `WeatherPresets`.

Two Environment flags stay pinned at **0** on purpose. `fog_sky_affect`, because the sky already carries the fog colour along its bottom edge and tinting it again just dirties it twice. And `fog_aerial_perspective`, which sounds like exactly what we want but is not: it blends the fog with the sky's *radiance cubemap* — the whole dome convolved, dominated by the zenith — not with the sky in that direction. Measured at 0.9, a saturated box rendered (0.54, 0.47, 0.49) against a sky of (0.83, 0.64, 0.46): grey-blue geometry on a warm sky, which is the very pop it was supposed to remove.

The old fullscreen `radial_fog.gdshader` — a depth pass with three hand-tuned colour bands copied off the sky gradient — **was deleted**, along with its wiring in `AreaInstantiator` and the `fog_color*` fields in `WorldSettings` that only it read. There is one fog system now. Its history is in git if it is ever needed.

Measured on the 1 425.6 m city: top flat at 87 m, base following the terrain, trimesh collider. Planned: circular holes where cars fly in and out, to sell that the city continues beyond where the player can follow.

---

## Building archetypes

Each `BuildingCluster` is assigned a **building archetype** + seed, the eventual driver of procedural building geometry. Currently the archetype only produces a **debug color** (`archetype.get_color(seed)`), which the renderer reads via `cluster.color`.

- **Base class** `BuildingArchetype` ([building_archetype.gd](../../building/building_archetype.gd)) defines the interface (`get_color`, `get_street_corner_chamfer_value`, future `generate_geometry`). The 8 concrete archetypes live as **inner classes** in the same file while small; an archetype can be promoted to its own file once its logic grows, with no caller changes.
- **Registry** `ArchetypeDefinitions.NEIGHBORHOOD_ARCHETYPES` ([archetype_definition.gd](../../building/archetype_definition.gd)) maps each **district** to two or three archetypes. `get_archetype_for_cluster()` seed-picks one and instantiates it.
- **Color scheme**: each archetype owns a fixed `base_hue`; the seed varies saturation/value within that family, so a cluster's district and archetype are both readable from its colour. (Colour is a temporary debug variable, expected to disappear once real geometry exists.)

| District | Archetypes |
|---|---|
| `POOR` | `ShantyBasic`, `ShantyMakeshift`, `MixedUse` |
| `RICH` | `MansionClassic`, `MansionModern`, `OfficeTower` |
| `INDUSTRIAL` | `WarehouseBasic`, `FactoryModern` |

There is no "Downtown" district any more: density became its own axis when districts and heights were split in two (see `NeighborhoodTypes`), so the old fourth row's archetypes were folded into `POOR` and `RICH`.

---

## Buildings on sloped terrain

A building is a box whose floors are **parallel to the ground beneath it**. Each corner takes the terrain height at its own position (`BuildingModule._ground_at`), and each floor is that same quad raised by a pure vertical offset. No cluster is anchored to a single height, so none is buried on the uphill side or stilted on the downhill one: the box tilts with the hill.

Roofs tilt with it, which is the price. It is acceptable while the character gains slope handling, and it is the look that was approved on sight.

**Superseded — the average anchor and its taper.** Clusters used to be anchored at `ground_reference`, the mean ground under their cells, with `_ground_at` straightening the module toward it over `TAPER_FLOORS × cells_per_floor` so roofs came out horizontal. It never reached the geometry, because the wall mesh never called that path — it only displaced the **placement** grid, by up to 1.35 m from floor 2 up (see "Step 4" below). Removed, along with `ground_reference`, `taper_cells` and `TAPER_FLOORS`.

⚠ If horizontal roofs are ever wanted again, the **mesh and the placement grid have to change together**. Doing it in one alone is precisely the bug that was removed.

---

## The terrain plan, and where it stopped

Terrain was introduced as a seven-step plan. Three steps landed, one landed inconsistently, three were never started. It is written down here so the half-finished parts are visible instead of surprising.

### Why it is only two funnels

The whole plan rests on a finding worth keeping: **everything that sits in the city passes through two places**, so terrain never had to be threaded through the whole system.

- `BuildingModule.get_region_vertices()` / `get_core_vertices()` — doors, stairs, floating and street sidewalks, bridge ends, and later windows, pipes and props.
- `BlockGenerator.get_edge_lane_volume()` — all traffic.

Bilinear interpolation (`GridHelper`) is pure 2D; Y is added afterwards. The 3D sidewalk matrix, door `{cell, edge, floor}` triples and the bridge grid are **logical indices in module space**, not metres, so they keep working untouched.

### Status

| | Step | State |
|---|---|---|
| 1 | Height field at the graph nodes, plus the ground mesh and its collider | **done** — `CityTerrain`, `City._visualize_ground` |
| 2 | Heights at the distorted-grid vertices, falling off to zero at the block perimeter so neighbouring blocks still meet | **done** — `DistortedGrid.vertex_heights`, `edge_falloff_sharpness` |
| 3 | Lane volumes riding the field | **not started** — `get_edge_lane_volume` still writes `0.0` at the bottom and `max_height_global` at the top: one global height for the entire city |
| 4 | Buildings riding the field | **done** — every floor is the base quad raised in Y, so mesh and placement agree; the taper was removed rather than completed (see below) |
| 5 | A *buried* predicate in the 3D sidewalk matrix | **not started**, and largely unnecessary: ground-floor doors anchor at `height_index 0`, which follows the terrain |
| 6 | Stepped field inside the block, stairs in the alleys (parkour) | **partial** — `TraversalGenerator.stair_zones` exists; the stepped field does not |
| 7 | `GroundPlanner`: cars that hug the ground | **not started** — nothing in the traffic code reads the terrain |

### Step 4: how the contradiction was settled

There were **two definitions of "where floor N is"**, and the mesh used the one nobody was maintaining.

`City._visualize_buildings` builds every floor from `get_core_vertices(0)` plus a hand-added `floor_base_y`, and extrudes vertically — so to the mesh, floor N has always been floor 0 raised in Y, tilted like the ground. Placement went through `_ground_at`, which lerped toward `ground_reference` over `TAPER_FLOORS × cells_per_floor` and so returned a **horizontal** surface from floor 2 up.

Measured on a four-storey cluster with 8 m of drop: **0.00 m at floor 0, 0.68 m at floor 1, 1.35 m from floor 2 up**, plus a mismatch in *tilt* — flat against sloped. Anything placed against a facade above floor 1 was landing on a surface that did not exist on screen. It masqueraded as a centimetre-scale alignment bug in bridges, and was chased as one for a while.

**Resolved by making the relief independent of the height index**: `_ground_at(u, v)` returns the module's bilinear ground, full stop, and `_at_height` adds the vertical offset. Mesh and placement now agree on every floor, tilted or not, and the taper was deleted rather than completed.

**And made structural rather than coincidental.** Agreeing was not enough on its own: the mesh still worked out its floor heights with its own arithmetic — `floor_base_y` for the base, a scalar extrusion for the top — so anything that made height depend on the index again would have desynced the two a second time. Both deductions are gone. `_visualize_buildings`, the building colliders and the roof props **ask the grid for the faces they need**, and `DebugUtil.get_skewed_cube_advanced_geometry_from_planes` builds the box between two given quads; the old base-plus-height form delegates to it, so there is exactly one chamfered-box constructor. A taper could now be reintroduced in `_ground_at` alone and the mesh would follow it on its own.

Two approximations are left on purpose, both harmless while floors stay congruent: the cell-to-metre chamfer conversion is measured on the **bottom** quad and applied to both faces, and the cap normals are still hardcoded to ±Y, so a tilted roof is shaded as if it were level.

### Two constraints for whoever picks this up

- The field must derive from the **world seed**. Traffic assumes every peer generates identical geometry.
- Steps 3 and 7 are one subject: give the lane volumes the field, then copy the bridge planner's shape — an immutable route plus a Y profile frozen at spawn — into a `GroundPlanner`. Its one new rule is that a ground-hugging car may not duck *downwards* to avoid a bridge, because the ground is there.

---

## Props — objects built inside a quad

`Scripts/city/props/` holds procedural objects placed on the city: `PropGeometry` (the primitives) and `RoofProps` (what is composed from them). Today that is a water tank, a shed roof and a gable roof, all placeholders.

### Everything is built in the quad's own (u,v) space

This is the decision that matters, and it is what makes skew stop being a problem. A building's roof is not a rectangle: the distorted grid deforms it and the terrain tilts it. Building an axis-aligned object and then rotating it would mean carrying those angles everywhere.

Instead every point is given in **normalised `(u, v)` coordinates of the base quad** and interpolated — bilinear in XZ via `GridHelper.bilinear_interpolation`, bilinear in Y via `GridHelper.bilinear_height`. The object is therefore born deformed exactly like the surface it stands on. **There is no skew step anywhere**, because none is needed. A cylinder is the circle *inscribed in a sub-quad*, so on a deformed roof it comes out elliptical — which is what you want.

Quads run `[BL, BR, TR, TL]`, the order `get_region_vertices` and `get_core_vertices` return.

### Why a separate class instead of DebugUtil

`DebugUtil` is a large bag of debugging helpers; props are world **content**. Mixing them would leave neither legible. The one thing borrowed is **boxes**: `DebugUtil.get_skewed_cube_advanced_geometry` already produces a correctly wound skewed box from four base vertices, so `PropGeometry.add_box` delegates to it rather than reimplementing it. Output is the same `{vertices, normals, colors, indices}` dictionary `_visualize_buildings` merges.

### Two traps, both paid for once

**The roof quad must come from the mesh convention, not the placement one.** `City._visualize_roof_props` takes `get_core_vertices(0)` and adds the floor offset by hand, exactly as `_visualize_buildings` builds its walls. Using `get_region_vertices(..., roof_index)` would give the *placement* surface, which on upper floors sits up to 1.35 m below the roof you can see, and the props would float. See the terrain plan above.

**Winding.** The material uses `CULL_BACK`, so vertex order alone decides whether a face is visible. The convention, confirmed by rendering a single triangle against a control: for emitted order `(A, B, C)` the visible face has normal **`(C - A) × (B - A)`**. `City._ground_triangle` picks its order with that same product, and `get_skewed_cube_advanced_geometry` agrees once you account for it emitting `(v1, v3, v2)`. Writing the cross product the other way compiles, runs, and silently inverts every face — from outside you then see the inside of the far side. `PropGeometry.add_tri` orients each triangle away from a supplied interior point; `add_tri_facing` orients toward a given direction instead, for flat faces where the interior-point test degenerates (a shed roof's plane has its centroid exactly at that point).

### Placement

`show_roof_props` gates it. Per cluster, seeded from the block seed so every peer builds the same city: each cell takes a sloped roof with probability `roof_shape_chance` (0.35), and a cluster that still has a flat cell takes a water tank with probability `water_tank_chance` (0.12) — deliberately low, since a repeated tank stops reading as detail and becomes texture. A tank is skipped when it would not fit the roof. Measured on the current city: 2271 sloped roofs, 271 tanks, 67 826 triangles merged into one mesh per block.

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

Objects that span the street between two blocks. Two facade faces (one per block) connected via `create_skewed_cube_from_planes`.

- **Position**: both faces come from `FacadeHelper.facade_span_quad()`, which samples the building grid at the span's two end cells and at **both** height indices. The connector contributes no shape of its own — it only stretches one real facade face to the other.
- **Vertex correspondence**: each face is returned as `[start_bottom, end_bottom, end_top, start_top]`, the order `get_skewed_cube_from_planes_geometry` pairs vertex-to-vertex.
- **Multi-cell spanning**: only the two end cells are sampled, so any distorted-grid break in between falls inside the connector rather than on the face.
- **Implementation**: `_add_bridge_span()` and `_add_bridge_arc_spans()` in city.gd.

**Superseded:** the middle used to be built by `_bridge_plane()`, lerping between block core corners (`c_a1.lerp(c_a2, t)`) at a single scalar height per side. That gives a **horizontal** edge while the real facade face is torsioned — measured up to 0.205 m along one span — so the two met at a point and nowhere else. Connectors are the sole exception to the golden rule documented in `FacadeHelper`: they obey no grid, but they may not invent a plane either.

### In-grid placement (bridge extremes, future windows, AC units, balconies, rooftop objects)

Objects that occupy cells within the sidewalk 3D matrix of a single block.

- **Position**: derived from building module `get_region_vertices()`, which uses bilinear interpolation within the module's distorted quad.
- **Cell mapping**: `FacadeHelper.facade_to_grid_rect()` converts facade-order cell indices to `(bx_min, bx_max, bz_min, bz_max)` in building grid coordinates, applying the reversal formula as needed.
- **Multi-cell spanning**: one piece per distorted grid cell. If an object crosses DG cell boundaries, it produces one mesh per DG cell.
- **Construction**: `create_skewed_cube` with base vertices from `get_region_vertices` and height in building cells.

### Alignment guarantee

The middle and the extremes cannot diverge, because both read the same source at the same indices: the extremes are prisms between two sampled heights (`BuildingModule.get_region_prism`) and the middle's end faces are sampled from that same grid. The pathway's bottom sits at `floor_idx * cells_per_floor` — the **start of a floor** — so a building's floating sidewalk and the bridge pathway meet as one continuous walkable surface.

**Superseded:** this used to be justified by the distorted grid having zero wave distortion at the facade edge (edge falloff), which would make a lerped plane and a grid-sampled face agree there. The argument only covered XZ: it ignored the building grid's **Y** distortion, which comes from `_ground_at(u, v, height_index)` and does not vanish at the edge.
