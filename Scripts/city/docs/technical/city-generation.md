# City Generation

Technical, code-level breakdown of the procedural city generator. Three subsystems each have their own file:

- [sidewalks.md](sidewalks.md) — sidewalk zones, physical instances, delivery doors, and traversal infrastructure (stairs + floating sidewalks).
- [bridges.md](bridges.md) — bridge ownership, count, structure, archetypes, and placement.
- [traffic.md](traffic.md) — the ambient flying-car simulation.

## Steps in order

0. **Terrain field** — a continuous, seeded height field over the whole city (`CityTerrain`). Everything else is eventually measured from it; see [Terrain](#terrain).
1. **Street graph** — Voronoi graph (Poisson sampling). Each edge gets a street type: boundary, small, medium, or large.
2. **Districts and heights** — Each graph face gets a **district** (what it is made of) and, from a separate set of patches, a **height tier** (how many floors). Two independent axes; see [Districts and heights](#districts-and-heights).
3. **Blocks** — Each face gets a `BlockGenerator`. The edges of the block know which street type borders them, reserving an empty margin (street offset) that visually forms the street.
4. **Internal alleyways** — Inside each block, `PathGenerator` traces small and big alleyways in the `DistortedGrid`.
5. **Clusters** — Non-alleyway cells are grouped into `BuildingCluster` via flood-fill, then subdivided (1–8 cells each). Both steps ask `BlockGenerator._is_separated_by_alleyway`, and **a building never grows across an alley** — belonging to the same section is not enough, since a U-shaped section has grid-adjacent cells with the alley between them. ⚠ That test **must be symmetric**: the shared edge of two adjacent cells is always at the *larger* index. It once took the smaller one whenever the second cell came first, and 148 buildings straddled an alley with their roofs open across it.
6. **Block hearts** — Interior clusters (not on the block perimeter) become "hearts" with probability `block_heart_probability` per district (30 % poor, 20 % rich and industrial): `floor_count` 0, a paved plaza inside the block. Their floor-0 module still exists, and the sidewalk pass fills it.
7. **Building modules** — Each cell in each cluster is a `BuildingModule` per floor. Each module knows what borders its 4 sides and shrinks its core area inward (facade/alleyway offset), forming the actual building footprint. It is also the grid everything on the building is placed in; see [Placing objects](#placing-objects--one-grid-two-kinds-of-cells).
8. **Sidewalks** — Everything at ground level that is not building, decided per module. See [sidewalks.md](sidewalks.md).
9. **Wall** — A closed barrier on the graph's boundary edges, the limit of the playable world. See [The wall](#the-wall).
10. **Bridges** — Placed on graph edges. Middle parts span between opposing buildable zone boundaries; extremes occupy the modules they rest on. See [bridges.md](bridges.md).
11. **Roofs, doors and windows** — placed on the modules and on their surfaces, in that order. See [Roofs](#roofs--the-planner-decides-the-props-execute) and [Facades](#facades--windows-and-doors).

---

## Terrain

`CityTerrain` ([city_terrain.gd](../../core/city_terrain.gd)) is the city's relief: a **continuous function of the plane**, `height_at(x, z)`, not a per-node table. Two things that land on the same spot — a sidewalk and its street's lane volume, two blocks facing each other — therefore agree by construction, with no coordination and no seams.

It is **noise seeded from the world seed** (`WorldSeeds.derive(generation_seed, 3)`), so it is identical on every machine — the traffic system predicts routes across the network and needs the geometry to match. Two corrections are applied over the raw noise, in `fit_to_graph`, once the graph exists:

- **Stretched to the full range.** Raw noise never reaches its extremes — measured over one city's nodes it spans 22%–77% — so without this the relief is flattened and floats above zero, with no valley resting on it.
- **Slope-capped.** The steepest street (height difference between two adjacent graph nodes over their distance) is measured, and if it exceeds `max_slope` the amplitude of the whole field is scaled down until it fits. This matters because the character is a rigid-body capsule with friction 0, no slope limit and no step logic, and ground-hugging cars will have to follow the terrain.

The amplitude is authored in **floors** (`City.terrain_floors`) — how many floors of a building a hill eats — and converted to metres once the floor height is known. `terrain_floors = 0` gives the old flat city.

The **ground mesh** (`City._visualize_ground`) triangulates each graph face in a fan and subdivides every triangle `GROUND_SUBDIVISIONS` times per side, **sampling** the field at each vertex rather than interpolating between the corners — so a long street comes out curved, the way a real city on a slope does, instead of a straight ramp between two corners. It hangs from a `Ground` node in the `city_ground` group, with an optional trimesh collider.

### What rides on it

Everything placed **in-grid** does, because it all flows through one funnel: `BuildingModule.point_at_f`, and on top of it `get_region_vertices` / `get_core_vertices` / `get_facade_quad` (buildings, stairs, connector faces) and `GridPlacer` on any `PlacementGrid` (sidewalks, bridge extremes, roof pieces, tanks, doors, windows — see [Placing objects](#placing-objects--one-grid-two-kinds-of-cells)). `DistortedGrid.get_cell_vertices` puts the grid's own vertices on the field too; the wave distortion stays purely horizontal.

**Everything follows the ground, at every height.** In the funnel each corner gets the terrain height at its own position, and the height index adds a **pure vertical offset** on top. So floor N is floor 0 raised in Y: every floor parallel, every floor tilted alike.

The visible mesh goes through that same funnel: `City._visualize_buildings` asks it for the floor's **two** faces (`get_core_vertices` at the bottom and at the top of the floor) instead of computing the top itself, and so do the building colliders. A placed object therefore lands on the face you see **by construction, not by agreement** — see [Buildings on sloped terrain](#buildings-on-sloped-terrain) for the bug that rule closed.

**Not wired yet:** the lane volumes are still built at `y = 0` (`BlockGenerator.get_edge_lane_volume`), so cars fly at the old height. Bridge middles do follow, because they stretch between two facade faces that come from the funnel.

The relief **inside** a block does not live here: that one is discrete and stepped, rides on the `DistortedGrid`, and falls off to zero at the block perimeter so the border is worth exactly what this field says — the same trick the wave distortion already uses (see the alignment guarantee below).

---

## Output is merged; the modularity lives in the data

The scene the city emits is **coarser than the data behind it, on purpose**. Per building (`BuildingCluster`) it emits exactly **one mesh** and **one collider**, merged from every cell of every floor — not one node per cell per floor.

This is only the **last step**, the emission. Everything upstream stays per cell and per floor: `BuildingModule` (core area, chamfers, occupancy, the funnel every placeable position flows through). Future placeables — windows, balconies, AC units, signs, roof tanks — will ask *those* for their position, never the scene tree, so merging the output costs them nothing. Splitting it back into pieces is a change to one function (`City._visualize_building_colliders` / `_visualize_buildings`) and nothing else.

**Why it matters** (measured on the 312-block city): colliders went from **145 264 collision shapes to 22 596** — the building half from 126 777 down to 4 109, one per building. Those shapes sit in Jolt's broadphase no matter where the player is, so this is a per-frame and memory win, not only a startup one. The collider is built from the **same geometry the mesh pass already computes** (`DebugUtil.get_skewed_cube_advanced_grid_geometry`), so nothing is calculated twice.

### Modules are cached by data, not by floor

`BuildingCluster.get_building_module()` keys its cache on **the cell plus its four edge types**, not on the floor. Edge types are still queried *with* the floor (`PathGenerator.get_path_edge_type_vertices(..., floor)`), so the day an alleyway changes with height, that cell yields a different key and is recomputed on its own — **the ability to vary per floor stays, but is only paid for where it actually varies**. Today nothing varies, and the city computes **10 560 modules instead of 126 777**: each one's chamfers walk the grid vertex by vertex, which was the single most expensive step of generation.

---

## Grid types — there are 3

| Level | Class | Size |
|---|---|---|
| City | `BlockGenerator` per graph face | one per block |
| Block | `DistortedGrid` (sinusoidal distortion) | ~6×6 cells of ~11 m |
| Building | `BuildingModule` per cell | 80×80 cells of ~0.14 m, 32 cells (~0.21 m) per floor |

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

**Facade offset** (module level, in building cells — the module's core is inset by it):

| Adjacent cell type | Cells |
|---|---|
| Normal (attached neighbour) | 0 |
| Boundary (world edge) | 0 |
| Facade (street) | 24 |
| Small / big alleyway | 18 |

Toward a street the offset is the external sidewalk, up to the kerb; toward an alley it is the module's half of the alley, and the two modules flanking it pave it edge to edge. Building faces sit at the core boundary. Everything in the offset is decided per module (see [sidewalks.md](sidewalks.md)).

---

## Districts and heights

Two **independent axes**. They used to be one enum of four types, and that was the mistake: *Downtown* is not a culture, it is a density. A rich downtown is glass towers, a poor one is stacked tenements, an industrial one is silos packed together — so raising a slum's height forced it to become another neighbourhood.

- **District** (`NeighborhoodTypes.District`): who lives there and what it is built from — **poor, rich, industrial**. It drives building style (`ArchetypeDefinitions`), which cars drive through, how much traffic there is, and how often a block gets a courtyard. Each district has **one generic archetype** for now (see "Building archetypes").
- **Height** (`NeighborhoodTypes.Height`): how many floors, and with them how many bridges cross its streets. This is the **gameplay axis**, calibrated against the ship.

| Tier | Floors | Against the ship |
|---|---|---|
| Low | 1–4 | Flown over without touching anything — the breather, and it opens the view |
| Mid | 7–11 | Costs vertical thruster, and its tallest (11) cannot be cleared even with it |
| Tall | 15–22 | There is no *over*. You fly between them, and this is the norm |

The ship climbs **6 floors** on cruise and **10** with the vertical thruster, which burns. The **gaps** between tiers (4→7, 11→15) are deliberate: if the bands touched, the three tiers would read as one grey continuum instead of being legible at a glance.

Both axes are spread as **patches** (`_assign_patches`: seeds on random faces, all fronts growing one step per round until the city is covered), with **separate seeds and no radial rule** — so a slum can be a canyon downtown and a rich district can be low and open against the wall. Height patches get their tier by **quota**, not by independent draws: `HEIGHT_WEIGHTS` (55% tall, 25% mid, 20% low) is turned into exact counts and shuffled. Drawing each patch on its own let the realised share drift badly — 8% low against the 20% asked, because the draw is per *patch* and patches differ in size.

**Cracks.** Inside a block that is *not* low, each building has a `CRACK_CHANCE` (12%) of breaking its tier and building from the **low** range instead. They are the gaps a pilot can spot and cut through between towers — player expression, so the only options aren't "straight over a breather patch" or "along the street". A building is a cluster of 1–8 cells and a cell is ~27 m, so even the smallest crack is far wider than an alleyway: it does not break the rule that the ship never flies into alleyways. The majority stays tall, so the maze holds.

**Measured** over one 312-block city: tiers came out **18 % low / 26 % mid / 57 % tall** against the 20/25/55 asked, no building outside its patch's range, and **11.5 % cracks**, none in low blocks. Generation time is dominated by mesh emission, not by the graph.

**Superseded:** floors used to be blended toward the city average by `pow(distance_to_seed, 0.3)`; an exponent below 1 blends almost everything, so only seed blocks kept their own range (24 one-floor buildings in a whole map). Gone with the four-type enum.

---

## The wall

The limit of the playable world: a barrier that cannot be cleared, not even with the thruster. **It is currently invisible**: `City.show_wall_mesh` is off, so the mesh is built and hidden while the collider stays. That flag is separate from `show_wall` on purpose — `show_wall` drops the collider too, and the ship then leaves the map. It rides the graph's **boundary edges** — the ones with a single adjacent face, already street type `-1` with neither sidewalk nor roadway — so it needs no path of its own; the city's edge was already there.

Its **base follows the terrain** and its **top stays at a constant altitude** (`City.wall_floors`, **13 floors ≈ 87 m**). That height is chosen against the ship, not against the buildings: its altitude target tops out at **8 floors** (53.5 m, `Ship.max_altitude`), so 13 floors stays out of reach by five without walling the city in. (The vertical thruster the design calls for does not exist in code yet — until it does, 8 floors is the whole ceiling. It previously sat at 90 m, i.e. 13.4 floors, which let the ship clear the wall outright.) The tallest buildings (11–18 floors, up to 120 m) **rise above it on purpose** — a wall taller than every tower makes the city read as a toy box. The constant top is the point: a top that followed the hills would dip in the valleys and stop being impassable exactly where the terrain already sinks the player. A square **post at each boundary node** covers the joint between two runs, which would otherwise leave a wedge of air at open corners.

Measured on the 1 425.6 m city: top flat at 87 m, base following the terrain, trimesh collider. Planned: circular holes where cars fly in and out, to sell that the city continues beyond where the player can follow.

Unlike everything else the wall carries **no distance range** — see [Meshes are built in world space](#meshes-are-built-in-world-space--mind-the-origin).

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

### The weather: fog, sky, ambient, screen tint and clouds are one decision

`CityFog`, on the `WorldEnvironment`, applies all of them; the values are the defaults of `Weather` ([weather.gd](../../core/weather.gd)), a plain Resource. **The game ships one fixed weather** — there is no cycle and no changing state (see [world.md](../conceptual/world.md#climate) for the design that comes later). There used to be a table of nine presets converted from **GTA San Andreas' `timecyc.dat`** and an F5 list to alternate them; one was chosen and the rest is in git. What survived that reading are three structural decisions.

**1. Fog colour is not sky colour — unless you ask for it.** In the timecyc they are literally one column (`Sky bot`) used for both, which makes the silhouette problem impossible: a piece saturated with fog ends up painted exactly the colour of what is behind it. Elegant, but it ties the colour of the distant city to the sky, and that is what was not wanted. `Weather.fog_from_sky` is that argument turned into a switch — **off by default**, so fog has its own colour (a stock Godot sky with dark blue fog). Silhouettes are real there, which is exactly why the fade ring exists. Strong fog is wanted — without it the world reads monotonous — and the lesson from trying 800 m is that what keeps a city from feeling enclosed is the fog's *colour*, not its reach.

**2. Weather is colour, never range.** Across the nine timecyc rows read, `FarClp` is **2000 in every one**. So `Weather` carries no distances: they live in `WorldSettings`, because they also drive the city's distance cut and the car spawn radius. Changing the weather can never make the world smaller.

**3. The sun is two lights.** `DirectionalLight3D.light_angular_distance` defaults to **0**, and at 0 the disc `ProceduralSkyMaterial` draws is a point — invisible, which is why the world had no sun (measured: the pixel at the sun reads **1.000** brightness with a 3.2° disc against **0.384** without). But that same property is the sun's angular size for shadowing — the penumbra width, 0.53° in reality — so raising it to get a nice disc washes out the shadows buildings cast on each other. Two things sharing one property, so `CityFog` drives two lights: the one in the `sun` group lights and casts with `shadow_softness`, and a second in `SKY_MODE_SKY_ONLY` draws the disc with `sun_size` while contributing neither light nor shadow. At `sun_size` 0 there is no disc and still a sun — what San Andreas does in rain and sandstorm.

The **screen tint** is two full-screen colour-correction layers (`Alpha1 RGB1`, `Alpha2 RGB2`, at alpha 195/255 in every timecyc row seen), approximated in `Shaders/screen_tint.gdshader` as a multiply plus a wash. **It is an approximation, not a port** — Rockstar's own differs between PS2, PC and mobile. Both strengths default to 0: our tonemapping is not RenderWare's and at full strength it eats the contrast.

Two Environment flags stay pinned at **0** on purpose. `fog_sky_affect`, because the sky already carries the fog colour along its bottom edge and tinting it again just dirties it twice. And `fog_aerial_perspective`, which sounds like exactly what we want but is not: it blends the fog with the sky's *radiance cubemap* — the whole dome convolved, dominated by the zenith — not with the sky in that direction. Measured at 0.9, a saturated box rendered (0.54, 0.47, 0.49) against a sky of (0.83, 0.64, 0.46): grey-blue geometry on a warm sky, which is the very pop it was supposed to remove.

**Clouds** come from the **Sunshine Clouds 2** addon (`addons/SunshineClouds2/`, MIT): volumetric, rendered as a `CompositorEffect`. The settings live in [Scenes/clouds.tres](../../../../Scenes/clouds.tres), referenced twice from `Demo.tscn` — by the `WorldEnvironment`'s `Compositor` and by the `Clouds` node (`SunshineCloudsDriverGD`), which animates the wind and tracks the sun, so moving the sun relights the clouds. ⚠ **Both references are required**: the driver's setter only adds the resource to the Compositor when the node is already in the tree, which never happens while a scene loads. The compositor cannot see the `Environment`, so the clouds keep their own copy of the fog colour; `CityFog.apply()` writes it from the weather, which is why the tuner does not offer it. Needs Forward+ (compute shaders); invisible in headless.

⚠ **The shaders are compiled for one Godot version.** `addons/SunshineClouds2/CloudsInc.comp` defines `GODOT_VERSION_MAJOR`/`MINOR`, and with them the layout of the engine's scene-data block the shaders read (projection matrices, near/far). The addon ships set to 4.6; on 4.5 the block is read with the wrong offsets and **nothing renders**, with no error — the addon's tutorial blames the camera's 4 000 m far plane for that, but the shader treats sky pixels as infinitely far; the version was the cause here. The plugin's dock rewrites the number when the editor opens a scene, half a second in — a headless `--editor --quit` exits first, so it never ran here. It is set to **5** by hand. After changing it the six `.glsl` imports must be rebuilt (delete their `.godot/imported/SunshineClouds*.glsl-*` entries and reopen, or the resource's **Refresh Compute**). Updating the addon or Godot means checking this again.

⚠ **The addon's defaults are planet-scale**: noise patterns of 300, 85 and 20 km, a layer between 1.5 and 15 km, ray steps of 100–500 m. From a 1.8 km city under heavy fog, the whole visible sky falls inside a single sample of each pattern, so it is either one uniform veil or nothing — never separate clouds. `clouds.tres` is rescaled to the city: layer at 350–1 100 m (above the towers and the ship), patterns of 12 km / 4 km / 1.5 km / 500 m, steps of 15–40 m, wind speeds scaled down with them, and less atmospheric haze.

All of it is tuned live from **F6** and pasted back by hand — see [ui.md](ui.md#layer-2--debug-panel-f1-tabbed). Nothing persists.

The old fullscreen `radial_fog.gdshader` — a depth pass with three hand-tuned colour bands copied off the sky gradient — **was deleted**, along with its wiring in `AreaInstantiator` and the `fog_color*` fields in `WorldSettings` that only it read. There is one fog system now. Its history is in git if it is ever needed.

---

## Building archetypes

Each `BuildingCluster` is assigned a **building archetype** + seed. A building works like a person: the archetype says what *class* of building it is, and the seed varies the individual within that class.

- **Base class** `BuildingArchetype` ([building_archetype.gd](../../building/building_archetype.gd)) defines the interface (`get_color`, `get_street_corner_chamfer_value`, future `generate_geometry`) and carries the **parameters that feed the rules** — `roof_pitch_height`, `flat_roof_chance`, and the `window_*` fields. The archetype holds no rules of its own: who decides a roof's shape is `RoofPlanner`, and who decides where windows go is `FacadePlanner`; both read these. Concrete archetypes live as **inner classes** while small; one can be promoted to its own file once its logic grows, with no caller changes.
- **Registry** `ArchetypeDefinitions.NEIGHBORHOOD_ARCHETYPES` ([archetype_definition.gd](../../building/archetype_definition.gd)) maps each **district** to its archetypes. `get_archetype_for_cluster()` seed-picks one and instantiates it — the pick stays even with one entry per district, so adding a second changes nothing else.
- **Color scheme**: each archetype owns a fixed `base_hue`; the seed varies saturation/value within that family, so a cluster's district is readable from its colour. (Colour is a temporary debug variable, expected to disappear once real geometry exists.)

| District | Archetype | Windows (style trial) |
|---|---|---|
| `POOR` | `GenericPoor` | random, small |
| `RICH` | `GenericRich` | stacked, tall, tight rhythm |
| `INDUSTRIAL` | `GenericIndustrial` | stacked, wide and low, far apart |

**One generic archetype per district**, and the three are identical apart from hue and windows — deliberately. The layer exists so that changing a district's roof, windows or material is changing *data* here, not rules elsewhere.

**Superseded:** there used to be eight archetypes (`ShantyBasic`, `ShantyMakeshift`, `MixedUse`, `MansionClassic`, `MansionModern`, `OfficeTower`, `WarehouseBasic`, `FactoryModern`) that differed **only in `base_hue`** — a distinction that does not exist for the player. Named archetypes come back when there is something real to tell them apart with. There is no "Downtown" district either: density became its own axis when districts and heights were split in two (see `NeighborhoodTypes`).

---

## Facades — windows and doors

The same split as roofs, for walls ([facade_planner.gd](../../building/facade_planner.gd)): the **archetype** says which criterion a building uses and with what numbers; **`FacadePlanner`** has the rules and returns candidate regions in the cells of a wall's `RigidMatrix`; **`GridPlacer.place`** places, indexes, occupies and rejects whatever collides. The planner checks nothing against what is already there — the matrix does.

⚠ **Primitive on purpose.** Two window criteria exist to try out a style; doors (ground floor and upper floors) are meant to become further criteria of the same planner.

- **Where a wall is visible** — `has_wall(block, cluster, cell, module, side, floor)`: toward a street or alley, always; toward the world boundary, never; on an *attached* side, when the building across it has no floor at that height — a shorter neighbour (the floors that rise above it) or a block heart (walls facing a plaza are facades). Only against a cell of the same building is a side interior. The edge type alone is not enough.
- **`STACKED`** — columns of `window_width_m` separated by `window_gap_m`, as many as fit, centred, at `window_sill_m`. They depend only on the matrix width, which is the same on every floor, so a side's windows line up vertically with nothing stored.
- **`RANDOM`** — `window_attempts` positions drawn per facade per floor between the sill and a top margin; the ones that collide are dropped by the matrix.
- **Pieces** are in `FacadeProps` ([facade_props.gd](../../props/facade_props.gd)). ⚠ A facade's frame is not a roof's: `x` along the wall, **`y` out toward the street**, `z` up. The `y = 0` face rests on the wall and is not drawn.
- **One pass per block** (`City._visualize_facade_objects`): doors first (gameplay), then windows, sharing one matrix per `(module, side, floor)` so a window can only avoid a door by reading the matrix the door occupies. Randomness is seeded from the block seed, cluster, cell, side and floor.
- **Cost, measured:** ~377 000 windows, 3.8 M triangles, one mesh per block, **no collider and no shadow**. The pass takes **~28 s** of a 63 s headless run, all of it per-vertex work in GDScript — see the caveat below. Three things keep it there and not higher: `point_at_f` allocates nothing, `place` writes each piece in bulk with the region's bilinear precomputed, and a floor's facade grid is floor 0's translated rather than rebuilt.
- ⚠ **Windows are not individually pointable**: without a collider the inspector's ray hits the wall. They are indexed under the building's object, so highlighting the building includes them.
- ⚠ **The residual cost is structural.** A rigid object is, by definition, its unit mesh under one affine transform — exactly what a GPU instance is. Hundreds of thousands of identical windows written triangle by triangle in GDScript are the expensive way to draw a transform. Moving rigid repeated pieces to `MultiMesh` would remove most of the pass and the triangles from the CPU side, at the price of not copying their triangles for highlighting. Not done: it is a decision, not a fix.

## Roofs — the planner decides, the props execute

A roof is **a small catalogue of modular pieces placed on the building grid through `GridPlacer`** — the same interface every placed object uses (see [Placing objects](#placing-objects--one-grid-two-kinds-of-cells)). One style is chosen per building.

- `RoofPlanner` ([roof_planner.gd](../../building/roof_planner.gd)) is a **pure function** of the cluster's footprint, its edge types, its chamfers and the seed. `layout()` returns `{"style", "pieces", "fallback"}`: each piece is a module, a region of building cells, a `UnitMesh`, and which catalogue piece it is. It touches no mesh.
- `RoofProps` ([roof_props.gd](../../props/roof_props.gd)) is the catalogue: each piece authored **once**, in the unit cube, in a canonical orientation, and rotated in quarter turns for the other three.
- `City._visualize_roof_props` decides nothing — it calls `placer.place()` per piece.

### The catalogue

| Piece | Where it goes | Geometry in the unit cube |
|---|---|---|
| **top** | the flat inside | a quad at `y = 1` |
| **skirt** | each straight outline run, `s` cells deep | plane rising from the outer edge to `y = 1` |
| **corner** | `s × s` at a convex vertex | `min(x, z)` — two triangles meeting on the hip |
| **inner corner** | `s × s` at a reflex vertex | `max(x, z)` — the valley where two skirts meet |
| **chamfer** | the ochava's own square | three skirts (two edges, the cut) and the remaining top |
| **slope** | one band of a gable or shed, per module | plane from `h_low` to `h_high`, with optional walls on three sides |
| **tank** | a flat roof | legs, cylinder, cone |

Pieces carry **numeric parameters** — heights at their edges, where a chamfer's cut falls — rather than existing in one variant per size. That is what lets a skirt that crosses three modules be placed as three skirts that meet exactly, and what keeps a gable's ridge at the same height whatever the building's width (if each band rose a fixed step, a four-cell-wide building would get a nine-metre roof). It is still a finite catalogue placed by rule; the pieces just know how to stretch.

### Everything is reasoned in whole building cells

The block's building grid is one integer lattice: cell `(cx, cz)` contributes its 80×80 cells from `cx·80`. Cores of two cells in one building touch on an exact shared edge (offset 0 on a `NORMAL` edge), so the footprint is a **union of integer rectangles**, and its outline always lies on cell lines. No polygons, no insets, no clipping:

1. **Vertices.** Every rectangle corner is classified by which of its four surrounding cells are inside the union: 1 → convex corner, 3 → reflex corner, 2 adjacent → straight, 2 diagonal → two footprints touching at a point, which is rejected.
2. **Runs.** Each rectangle side minus the intervals covered by other rectangles across the line — plain 1-D interval subtraction — gives the outline runs. Each run is shortened at its ends by whatever the corner piece there occupies (`s`, or the chamfer square, or nothing at a reflex or straight vertex) and becomes a skirt.
3. **Tops.** Each core rectangle minus every piece that intersects it, as rectangles.
4. **Validation.** No two regions overlap and none crosses a module line; otherwise the roof is flat and counted **by reason** in the visualizer's print (`planos por no cerrar`). The placer's own occupancy check is the second line of defence — `piezas rechazadas` must stay at 0, and any other value means the planner and the placer disagree.

Cutting pieces where the exposure changes, not in fixed quadrants, is what makes the awkward cases fall out: the strip where a neighbour's core does not reach (different setbacks on the same side) is just a shorter skirt plus an inner corner, produced by the same walk.

**One chamfer piece covers both kinds of chamfer**, because they differ only in what each flank faces:

- A **street** chamfer is the ochava at a block corner: both flanks face the street, so each is a skirt, and the cut's skirt meets them at mitre points.
- An **alley** chamfer sits at the dead end of an alley, on a cell whose two neighbours are attached but set back from the alley by 18 cells — the same 18 as the cut, so the diagonal runs exactly from one step to the other. Each flank faces a cell of the **same building**, and what arrives there is the neighbour's skirt, at top height at the far corner: the flank is a **valley** (the neighbour's plane meeting the cut's plane on a hip-valley line), not a skirt. The piece already contains that valley, so the step's reflex vertex is struck off and gets no inner-corner piece of its own.

The region is `cut + s` per axis — where the neighbour's skirt reaches — which is whole cells without rounding since both are integers. The piece's points are computed in cells in its canonical frame and passed as fractions; `chamfer_unit` takes each flank's mode. Strips have every chamfer region subtracted as rectangles rather than being shortened at the vertex, which is what lets a chamfer consume a whole run: both legs of an alley notch live inside its piece. The cut can differ per axis (`c1 ≠ c2`), and a quarter turn swaps a piece's x and z, so cuts are crossed for odd rotations.

This replaced an approximation that ignored alley chamfers and set a convex corner piece there: the roof overhung the ochavated wall at every alley dead end, visibly.

### Gable and shed

Only on a footprint whose cores form a **single rectangle** (they fill their bounding box). The ridge runs along the **longer** side measured in **world metres** — cells are not square. Each half (or the whole depth, for a shed) is split into bands at every module line in both axes, and each band is a slope piece with its start and end heights as fractions of the half's depth. Walls go on the pieces that touch the rectangle's short ends (the gable ends) and, for a shed, on the high long side. The shed drops toward the more exposed long side (`Exposure`: street > alley > lower neighbour > blocked neighbour, sampled over the cells along that side).

### What each footprint may become

| Footprint | Options (the seed picks) |
|---|---|
| Single cell | shed · gable |
| 2×2 | gable · French |
| Strip (N×1) | gable · shed · French |
| Rectangle (N×M) | gable · French |
| L | French |
| Irregular | — |

A single cell never gets French. If the cell footprint is rectangular but the cores are not (different setbacks on a side leave a step), shed and gable are removed from the options.

**Chamfer decides before footprint.** `BuildingModule.chamfer_kinds` records what each chamfer is a corner *of*: a **street** chamfer → French or flat (flat on a single cell); **alley-only** → flat; both → street wins.

**Flat is an option, not a fallback.** It is in every row on purpose: flat roofs give the skyline variety, and they are the only ones a water tank sits on. Irregular footprints have no options for now, although the walk above works on any union of rectangles, courtyards included, so they could take French once wanted.

**The skirt is measured in building cells** (`BuildingArchetype.roof_skirt_building_cells`, 8 by default, ~1.4 m) so it is the same size on a narrow building as on a wide one; with the 2.2 m pitch that is the steep slope of a mansard.

### Superseded — three earlier designs, each easy to reintroduce

- **A piece per cell chosen from the cell's neighbourhood**: neighbouring pieces disagreed on the profile of the edge they share. *A cell cannot decide on its own.*
- **A height field on a half-cell lattice**: continuity, but at a resolution the grid does not have — a one-cell building had no room for a top and looked like a gable (651 of 929), and it ignored real chamfers.
- **A procedural outline (polygon union + inset)**: right shapes, but not the modular interface every other object uses — whoever placed something had to think in silhouettes.

### In the index

One record **per piece**: ids are `a` = building, `b` = piece (`RoofPlanner.Piece`), `c` = outline side or −1, `d` = style or −1. The inspector names them — "faldon de techo frances · edificio 16 · lado 3". Colour is per style, with French set apart in slate blue-grey — the real material of a mansard — and vertical walls in the side colour.

---

## Identity of a piece

Every visualizer receives data with a name — *this* cluster, *this* cell, *this* floor — and **throws it away when it bakes the merged mesh**. The identity exists at generation time and is gone by the `append_array`. Without somewhere to put it, identifying anything again means reverse-engineering it with rays and point-in-polygon, and that deduction has to be written **again for every new system** (pipes, stairs, windows).

`CityIndex` ([city_index.gd](../../debug/city_index.gd)) is where the identity gets written down, *at the moment it still exists* — right beside the line that already computes the merge offset:

```gdscript
var offset := merged_verts.size()
var idx_from := merged_idxs.size()
...
city_index.add(scope, object_id, Kind.BUILDING, cluster.id, cell.x, cell.y, floor_idx,
    idx_from, merged_idxs.size(), geo.vertices)
```

What each piece stores: its **kind**, four **ids** whose meaning depends on the kind, its **triangle range** within the mesh's index array, and its **AABB**.

- **Parallel packed arrays, not a dictionary per piece.** Buildings alone bake tens of thousands of pieces; a `Dictionary` each would be a real memory cost. Each piece is a handful of ints and two `Vector3`s.
- **The scope** ties a collider to its pieces: the body that stops the ray carries its scope in a meta, and the search runs only inside it. Scope granularity follows *mesh* granularity — per cluster for buildings, per block for roofs, per bridge for bridges. The index also holds each scope's `MeshInstance3D`, so a piece can be drawn without knowing which collider the ray hit.
- **The object id** is what makes "the whole building" mean something. It **crosses scopes**: a building's walls live in its cluster's mesh and its roof in the block's roof mesh, and both record the same object id, so highlighting the object covers both. ⚠ `cluster.id` cannot be used for this — clusters are numbered **per block** starting at zero, so cluster 5 exists in all 191 blocks; the id is allocated globally by `City._object_for_cluster`.
- **Two ways to resolve a hit, both generic.** `face_index` from the raycast would give the exact triangle, which works because each collider is built from the **same triangles in the same order** as its mesh — that ordering is a contract, not an accident. Otherwise the smallest AABB containing the point wins. Neither path knows whether it is looking at a roof, a wall or a pipe.

  **Measured in game: the ray does not return `face_index`** — presumably Jolt does not report it — so the **AABB path is the live one**. It is accurate in practice because a building piece *is* a box; the exact-triangle path stays in place, costing nothing, in case a future engine version provides the index.
- **The triangle range is also what draws the outline**: the inspector copies exactly those triangles out of the city mesh. That is what makes it possible to outline **one cell** of a mesh that merges a whole block — the grabbable outline path works per `MeshInstance3D` and would light up everything.

### Making a new system identifiable

**If the object is placed through `GridPlacer`, steps 5 and 7 below happen inside `place()`** — the placer is built with the scope and object id and records the piece itself. What remains yours is the per-mesh part (a scope and its mesh, the object id, the collider stamp). See [Placing objects](#placing-objects--one-grid-two-kinds-of-cells).

Everything below happens **inside the builder that bakes the geometry**. Nothing registers anywhere, and no interface is implemented — which is the point, but it also means there is no compiler error if a step is skipped. **The symptom of a missed step is the inspector saying "sin identificar" when you point at the thing.** That is the thing to check first.

In `CityIndex`:

1. Add a value to `Kind`, and its label to `KIND_NAMES` (same order).
2. Add a branch to `describe()` turning the four ids back into a sentence. This is the *only* place the ids mean anything, and it is the only per-system logic in the whole mechanism.

In the builder, per **mesh** (scope granularity follows mesh granularity — one per merged mesh):

3. `var scope := city_index.new_scope()` before filling the buffer.
4. `city_index.set_scope_mesh(scope, mesh_instance)` right after creating the `MeshInstance3D`. Skipping this costs the highlight, not the identification — the piece is named but nothing is drawn on it.

Per **piece**, around the append that already exists:

5. Capture the index range: `var idx_from := <indices>.size()` before, and pass `<indices>.size()` after.
6. Get an object id — `City._object_for_cluster(cluster)` to belong to an existing building (this is how a roof joins its walls), or `City._new_object()` for something standalone.
7. `city_index.add(scope, object_id, Kind.X, id_a, id_b, id_c, id_d, idx_from, idx_to, piece_verts)`, where `piece_verts` are just that piece's vertices — they are only used to compute its AABB, which is the path that actually resolves hits.

On the **collider**:

8. `body.set_meta(CityIndex.SCOPE_META, scope)`. Without this the ray stops on the object and the inspector has nothing to ask about. If the system has no collider it cannot be pointed at at all — which is deliberate: identity rides on the thing that is already mandatory for anything solid, so it cannot be silently forgotten.
9. Build the collider's triangles **in the same order as the mesh's**. Only the `face_index` path depends on it, which is currently dormant, so getting it wrong degrades precision rather than breaking anything — but it is a contract worth keeping.

⚠ Types: `<buffer>["indices"].size()` comes out of an untyped `Dictionary` and is therefore `Variant`. `:=` cannot infer from it and it cannot be passed to a typed parameter — declare `var idx_from: int = ...` explicitly. Warnings are errors in this project.

What stays system-specific is only *which ids it writes down* — data, not logic — plus one line in `describe()`. Identity rides on the collider on purpose: a collider is already mandatory for anything solid, so it cannot be silently forgotten, while an interface everything is supposed to implement is optional by construction, and gets skipped.

---

## Buildings on sloped terrain

A building is a box whose floors are **parallel to the ground beneath it**: each corner takes the terrain height at its own position and each floor is that quad raised by a pure vertical offset. No cluster is anchored to a single height, so none is buried uphill or stilted downhill; roofs tilt with the hill, which is the price, and the look that was approved on sight.

⚠ **There must be one definition of "where floor N is", and the mesh must ask for it.** There were two once: the mesh built floor N as floor 0 raised, while placement went through a taper that straightened the module toward the cluster's mean height over the first floors — a horizontal surface from floor 2 up, 1.35 m off the visible wall, chased for a while as a centimetre-scale bridge bug. The taper is gone, and the fix was made structural: `_visualize_buildings`, the colliders and every placed object **ask the grid for the faces they need** (`point_at_f`, `get_core_vertices` at both floor indices), and `DebugUtil.get_skewed_cube_advanced_geometry_from_planes` builds the box between two given quads. If horizontal roofs are ever wanted again, change `point_at_f` and everything follows; changing the mesh or the placement alone is precisely the bug that was removed.

Two approximations are left on purpose, both harmless while floors stay congruent: the cell-to-metre chamfer conversion is measured on the **bottom** quad and applied to both faces, and the cap normals are hardcoded to ±Y.

### The terrain plan, and where it stopped

Everything that sits in the city passes through two places, so terrain never had to be threaded through the whole system: `BuildingModule.point_at_f()` for everything on a building, and `BlockGenerator.get_edge_lane_volume()` for all traffic. Module occupancy, door triples and the bridge grid are logical indices in module space, not metres, so they never noticed.

| | Step | State |
|---|---|---|
| 1 | Height field at the graph nodes, plus the ground mesh and its collider | **done** — `CityTerrain`, `City._visualize_ground` |
| 2 | Heights at the distorted-grid vertices, falling off to zero at the block perimeter so neighbouring blocks still meet | **done** — `DistortedGrid.vertex_heights`, `edge_falloff_sharpness` |
| 3 | Lane volumes riding the field | **not started** — `get_edge_lane_volume` still writes `0.0` at the bottom and `max_height_global` at the top |
| 4 | Buildings riding the field | **done** — see above |
| 5 | A *buried* predicate for placed objects | **dropped**: ground-floor objects anchor at height index 0, which follows the terrain |
| 6 | Stepped field inside the block, stairs in the alleys (parkour) | **partial** — `TraversalGenerator.stair_zones` exists; the stepped field does not |
| 7 | `GroundPlanner`: cars that hug the ground | **not started** — nothing in the traffic code reads the terrain |

Two constraints for whoever picks this up: the field must derive from the **world seed** (traffic assumes every peer generates identical geometry); and steps 3 and 7 are one subject — give the lane volumes the field, then copy the bridge planner's shape (an immutable route plus a Y profile frozen at spawn) into a `GroundPlanner`, whose one new rule is that a ground-hugging car may not duck *downwards* to avoid a bridge.

---

## Placing objects — one grid, two kinds of cells

Everything that goes on a building is placed the same way: a **mesh authored in the unit cube** goes into a **region of cells of a grid**, and the grid's cells decide its geometry. There is one grid class, `PlacementGrid` ([placement_grid.gd](../../block/placement_grid.gd)), and one call, `GridPlacer.place` ([grid_placer.gd](../../block/grid_placer.gd)). What differs between "deformable" and "rigid" is only **which grid** an object goes into, i.e. what its cells are:

- **Deformable** — can be stretched without looking wrong, *and* has to line up with its neighbours across modules: roof pieces, sidewalks, bridge extremes, columns, pipes, walkways. It goes into the **building module** (`BuildingModule extends PlacementGrid`): the distorted-grid cell with its relief, `axis_n` up, 80×80 cells of ~0.14 m and no ceiling. Its cells bend with the city, so what is placed in them bends the same way, and two pieces in neighbouring modules that share an edge coincide there — on a shared edge both bilinears reduce to the same line. No distortion threshold, ever — that is what deformable means.
- **Rigid** — should keep its proportions: windows, doors, water tanks, balconies. It goes into the **rigid grid of a surface** (`RigidMatrix extends PlacementGrid`, [rigid_matrix.gd](../../block/rigid_matrix.gd)): the surface's own quad, `axis_n` its outward normal, and cells **recomputed to be as close to cubes as possible** at `TARGET_CELL_M` (0.25 m). Because the surface is nearly flat and nearly a parallelogram, its bilinear is nearly affine, so what goes in is *barely* deformed — but it *is* the same mechanism, and that is the point.

### The grid

A `PlacementGrid` is four corners in the world, an outward axis, and a cell count per axis. A point in cells `(x, y, z)` goes to the world by **the bilinear of the corners in `(x, z)` plus `y` cells along the axis** (`cell_to_world`). That is the whole mechanism, and every vertex of everything placed in the city passes through it. **A piece cannot end up tilted against its grid, even on purpose**: there is no other source of position, the way a connector only fits one way round. (`BuildingModule.point_at_f(u, v, h)` is `cell_to_world` with normalised `(u, v)`; everything that samples a module still goes through it.)

⚠ Why this matters: the first rigid grid had its own **orthonormal frame** — `u` along the floor line, `v = u × n` — and mapped meshes affinely in it. A facade is a parallelogram (floors follow the terrain), so a rectangle cannot be parallel to both its floor line and its vertical edges; windows came out **rotated within the wall by 1.5° median, 7.4° worst (6–31 cm of lean over a 2.4 m window)**, visibly misaligned against the module's edge. That frame is gone. With the surface's own bilinear, a facade's cells are parallelograms with vertical sides and a tilted floor line — the building's own shear — and a window follows both. Along with it went the inscribed-rectangle logic, the per-object saddle lift (`surface_offset`) and its planar shortcut: a tank's base now sits *exactly* on the roof's saddle because the cells do.

The grid also owns:

- **Occupancy** — a list of boxes in cells, `is_free` (bounds included) and `occupy`. A list and not a 3D array: a module is 80×80 by 32 per floor, tens of millions of entries per city (the reason the old `SidewalkMatrix` never ran outside a debug view, and was deleted); objects are few.
- **Projection of one grid onto another** — `occupied_world_corners(index_from, index_to)` gives the eight world corners of every region occupied in a grid (filtered to a height range), and `mark_world_hexahedron` marks on the other grid the cells they cover, **column by column along `n`**: for each depth slice it clips the region's twelve edges against the slice and marks only what remains. Not the world envelope: a sidewalk that drops 12 % over its 3 m has an envelope ~40 cm tall and projected in one go it marked 40 cm of facade; sliced, next to the wall it marks its real thickness, which is what a door has to stand on. Conservative inside each slice, never under. `world_to_cell` (the inverse bilinear, by Newton — one step on a parallelogram) is what makes it possible.
- **Sizes in metres** — `cells_for(x_m, n_m, z_m)` per grid axis, rounded *up*: an object never shrinks to fit. What "height" means depends on the grid: `n` on a roof, `z` on a facade.
- **Standing on things** — `first_free_along_z(lo, size, max_rise)` slides a region up along `z` to the first free row: how a door rests on the sidewalk instead of going through it; above `max_rise` (`DOOR_MAX_STEP_M`, 0.5 m) the obstacle is not a kerb and the object is dropped. **Residual:** rows are ~0.25 m and the sidewalk 0.21 m thick, so a door on a sidewalk floats **4–4.7 cm** above the slab — the grid's granularity; closing it would mean fractional positions, a decision not made.

### The placer

```gdscript
placer.place(grid, lo, size, mesh, kind, id_a, id_b, id_c, id_d)  # -> bool
```

Whoever places something thinks about two things: the **region** (`lo` and `size`, in cells of that grid) and the **mesh** (`UnitMesh`, [unit_mesh.gd](../../props/unit_mesh.gd)): x, y, z from 0 to 1, a colour and an outward direction per triangle. Nothing else — never silhouettes, never neighbours, never slopes. Inside `place`: the region's bilinear is precomputed once (`PlacementGrid.region_frame`) and every vertex goes through it; face orientation is measured **in the world** with the bilinear's derivative, because a grid can mirror an axis; the piece is recorded in `CityIndex` with the placer's scope and object; the region is occupied. If it was not free or did not fit, `place` returns `false` and places nothing: two objects cannot overlap by oversight.

### Surfaces

A **surface** is one face able to host rigid objects: the side of **one module on one floor**, the flat roof of a cell, the diagonal face of a chamfer (not yet used). An object that would cross modules is, by definition, deformable.

- `RigidMatrix.from_quad(quad, depth_m, outward)`: `x` runs c0→c1, `z` runs c0→c3, depth along the normal up to what the surface type allows (`City.ROOF_SURFACE_DEPTH_M` 10 m, `FACADE_SURFACE_DEPTH_M` 2 m). A surface shorter than half a cell on a side yields no cells.
- **A unit mesh's `y` points out of the surface.** On a roof that is up; on a facade it is toward the street and `z` goes up (`get_facade_quad` runs bottom to top in `z`; the direction of `x` is irrelevant, faces are oriented in the world).
- **The facade surface** is `BuildingModule.get_facade_quad(edge, index_bottom, index_top)`: the core's face on that side, **shortened by the chamfers** at both ends (`get_facade_span`, the one definition of "where there is wall" on a side — `TraversalGenerator._door_span` draws door positions from it too, so a door cannot land on the ochava). One grid per `(module, side, floor)`, shared by everything on that face — doors and windows only see each other if they read the same grid. Only floor 0's is built from the quad; every other floor's is that one translated in Y (`RigidMatrix.translated`), with the occupancy of its own height range projected.
- **There is no threshold.** A narrow surface just yields few cells and an object that needs more does not fit. ⚠ This also means a skewed surface no longer rejects: with the old inscribed rectangle, 40 of 147 tank roofs were dropped as too skewed; now all **147** tanks are placed and follow their roof's skew, like the roof pieces around them. Whether that reads well is judged in game.

### Order of generation

```
1. deformable structure   buildings, roof pieces, sidewalks, bridge extremes, pipes   → occupy the module
2. surfaces               facades, flat roofs, skirts                                → each builds its rigid grid
3. rigid objects          doors, windows, tanks, balconies                            → read projected availability
```

Deformables always go first, so occupancy flows one way — and `City.visualize_graph` runs them in that order: bridges (whose extremes occupy), sidewalks, roof props, then doors and windows. The bug this order exists to make impossible had already happened: **doors (rigid) placed straight through floating sidewalks (deformable)**, because nothing recorded that the sidewalk was there. Now the sidewalk occupies the module, the facade's grid reads it, and the door stands on it.

Roof windows that protrude from a mansard skirt are deliberately out of scope: a rigid object crossing an inclined surface is the hardest case of all.

**What goes through it today.** On the module: roof pieces, the floor-0 sidewalks and the bridge extremes (`_place_bridge_extreme`, collider from the very vertices the placer wrote). On surfaces: the tank on the roof, doors and windows on the facade. All indexed (`CityIndex.Kind`) and baked by one function, `_bake_placed`. Generation prints counters that must stay at 0 — sidewalk rejections, extremes without room, doors without room — and the roof planner's `piezas rechazadas`; any other value is a bug between a planner and the placer. Not yet: floating sidewalks above floor 0 and the stairs (`_visualize_stair_zones` still draws its own cubes over empty zones).

---

## Props — the catalogues

`Scripts/city/props/` holds what gets placed, all authored in the **unit cube** as `UnitMesh` ([unit_mesh.gd](../../props/unit_mesh.gd)): `x`, `y`, `z` from 0 to 1, a colour and an outward direction per triangle. Whoever designs a piece never thinks in metres, grids or terrain — only in proportions inside the cube; `GridPlacer` takes it to a region of cells and the grid's cells give it its real shape (see [Placing objects](#placing-objects--one-grid-two-kinds-of-cells)).

- `RoofProps` — the roof pieces and the water tank. Each authored **once**, canonical, and turned in quarters (`UnitMesh.rotated`) for the other orientations.
- `SidewalkProps` — slab, curved corner, chamfer fill.
- `FacadeProps` — door and window panels. ⚠ In a facade's grid `y` points **out of the wall** and `z` up, so the face at `y = 0` is the one against the wall and is not drawn.

**A triangle stores which way it faces, not a vertex order.** A grid can mirror an axis, so the order is decided in the world by the placer, from that direction. See [Mesh generation](#mesh-generation--normals--winding) for the convention.

---

## Corner chamfers

Building modules can have **chamfered corners** — rectangular regions cut from the core at vertices where streets or alleyways meet. Chamfers are computed per-module in `BuildingModule._calculate_chamfers()`.

### Types — and why they are opposite situations

- **Street corner chamfers**: applied at DistortedGrid vertices where two streets intersect. Controlled by `BuildingArchetype.get_street_corner_chamfer_value()` (currently 16 cells, 100% probability).
- **Alleyway corner chamfers**: applied at vertices where two alleyway edges meet. The chamfer size equals the alleyway offsets of the two edges.

The two are the same cut in the module's geometry but **sit in opposite situations**, and everything placed at a chamfered corner has to know which:

- A street chamfer is **convex**: the ochava of a block corner. Both flanks of the cut face the street — open air on both sides.
- An alley chamfer is **concave**: it sits at the **dead end of an alley**, on the corner of a cell whose two neighbours are attached to it but set back from the alley. Because the cut equals the alley setback (both 18 cells), the diagonal runs exactly from one neighbour's step to the other's. Both flanks of the cut face **attached building**, so the cut is the inner corner of a notch, not the outer corner of a mass.

`BuildingModule.chamfer_kinds` records which kind each chamfer is; the geometry alone cannot tell them apart. The roof planner uses it to decide style (see [Roofs](#roofs--the-planner-decides-the-props-execute)) and, more importantly, the chamfer *piece* changes shape with the situation: skirts on both flanks for the convex case, valleys meeting the neighbours' skirts for the concave one. Treating the concave case as convex — the first version did — puts a full outer corner where the wall is cut, visibly overhanging the notch at every alley dead end. Anything else that lands on a chamfered corner (future windows, pipes, balconies) faces the same distinction.

### Geometry

Each chamfer is `[c1, c2]` in building cells:
- `c1`: cells removed toward the previous vertex (clockwise)
- `c2`: cells removed toward the next vertex (clockwise)

The chamfer creates a rectangular exclusion rect within the core. For vertex 0 (BL): `c2` cells along +x, `c1` cells along +z from the core corner.

`BuildingModule.get_facade_span` is the one definition of where a side still has wall once its chamfers are removed: the facade surface, the door positions and the bridge facade mask all read it.

---

## DistortedGrid cell types

- `NORMAL` — buildable interior
- `FACADE` — block perimeter facing a street (facade offset 24 → external sidewalk)
- `BOUNDARY` — block perimeter coinciding with the city boundary (facade offset = 0 → no sidewalk)
- `SMALL` / `BIG` — small / big alleyway
- `SMALL_ORIGIN` / `BIG_ORIGIN` — alleyway starting point

---

## Mesh generation — normals & winding

The building material uses `CULL_BACK`, so vertex order alone decides whether a face is visible. The convention, confirmed by rendering a single triangle against a control: for emitted order `(A, B, C)` the visible face has normal **`(C − A) × (B − A)`**. `City._ground_triangle` picks its order with that product, `GridPlacer.place` flips a triangle whose product disagrees with the direction its `UnitMesh` says it faces, and `DebugUtil._add_quad` orients each quad away from the box's centroid. Writing the cross product the other way compiles, runs, and silently inverts every face.

`DebugUtil` still builds the boxes that are not placed pieces:

| Function | Input | Used for |
|---|---|---|
| `get_skewed_cube_advanced_grid_geometry_from_planes` | two quads `[BL, BR, TR, TL]` + chamfers in cells | building floors and their colliders |
| `get_skewed_cube_from_planes_geometry` / `create_collision_shape_from_planes` | two opposing quads | bridge middles, lane volumes |
| `create_skewed_cube` (+ `_collider`) | 4 base vertices + height | the stair-zone debug view only |

---

## Connectors between grids

A bridge middle joins two facades across a street. It lives in no grid: it takes the **real face** of each facade and stretches one to the other. `FacadeHelper` centralises the edge-direction logic both ends need.

### Edge conventions

Edges are numbered 0–3 per face: 0=north, 1=east, 2=south, 3=west. Edges 0/1 iterate cells in increasing order (x or z), edges 2/3 in decreasing order, and the `reversed` flag (graph node order vs face node order) may flip the iteration again. Whether building cell indices within a module run with or against the facade order is `FacadeHelper.needs_cell_reversal()`: `(edge_idx >= 2) XOR is_reversed`, the single source of truth for every facade-to-grid conversion.

### The middle

Two facade faces (one per block) connected via `get_skewed_cube_from_planes_geometry`.

- **Position**: both faces come from `FacadeHelper.facade_span_quad()`, which samples the building grid at the span's two end cells and at **both** height indices. The connector contributes no shape of its own — it only stretches one real facade face to the other.
- **Vertex correspondence**: each face is returned as `[start_bottom, end_bottom, end_top, start_top]`, the order `get_skewed_cube_from_planes_geometry` pairs vertex-to-vertex.
- **Multi-cell spanning**: only the two end cells are sampled, so any distorted-grid break in between falls inside the connector rather than on the face.
- **Implementation**: `_add_bridge_span()` and `_add_bridge_arc_spans()` in city.gd.

**Superseded:** the middle used to be built by `_bridge_plane()`, lerping between block core corners (`c_a1.lerp(c_a2, t)`) at a single scalar height per side. That gives a **horizontal** edge while the real facade face is torsioned — measured up to 0.205 m along one span — so the two met at a point and nowhere else. Connectors are the sole exception to the golden rule documented in `FacadeHelper`: they obey no grid, but they may not invent a plane either.

### The extremes

Deformable pieces placed through `GridPlacer` on the modules they rest on (`City._place_bridge_extreme`): `FacadeHelper.facade_to_grid_rect()` converts facade-order cell indices to a module region, one region per distorted-grid cell the extreme crosses, and the convex collider is built from the vertices the placer just wrote. Occupying the module is how the facade knows a bridge rests on it.

### Alignment guarantee

The middle and the extremes cannot diverge, because both read the same source at the same indices: the extremes are deformed by `point_at_f` at the two sampled heights and the middle's end faces are sampled from that same grid. The pathway's bottom sits at `floor_idx * cells_per_floor` — the **start of a floor** — so a building's floating sidewalk and the bridge pathway meet as one continuous walkable surface.

**Superseded:** this used to be justified by the wave distortion vanishing at the facade edge, which would make a lerped plane and a grid-sampled face agree there. The argument only covered XZ and ignored the terrain's Y, which does not vanish at the edge.
