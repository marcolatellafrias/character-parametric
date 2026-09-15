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
9. **Outskirts** — A skirt of terrain pushed out from the graph's boundary ring, climbing to an impassable crest. See [The outskirts](#the-outskirts).
10. **Bridges** — Placed on graph edges. Middle parts span between opposing buildable zone boundaries; extremes occupy the modules they rest on. See [bridges.md](bridges.md).
11. **Roofs, doors and windows** — placed on the modules and on their surfaces, in that order. See [Roofs](#roofs--the-planner-decides-the-props-execute) and [Facades](#facades--windows-and-doors).

---

## Terrain

`CityTerrain` ([city_terrain.gd](../../core/city_terrain.gd)) is the city's relief, and it is **one height per graph node** — not a free field of the plane. From there the height **travels with the geometry**, carried by the same bilinear that already computes x and z: the block from its 4 corners, the grid cell from the block, the module from the cell. Two things that land on the same spot therefore agree by construction, with no coordination and no seams.

That it is topology and not a field is what makes it come out right without special cases. **A street tilts along its run, never sideways**, because the two blocks facing it share the same two nodes, so both kerbs interpolate between the *same* pair of heights on the same axis — a free noise field gave each kerb a different value and the street came out cambered. And **nothing clips through the ground**, because the ground is built from the very quads the sidewalks and modules use.

There is also a `height_at(x, z)`, the same noise with the same stretch applied, and at a node's position it returns that node's height **exactly** (measured: 4.7·10⁻⁷ m worst case over 211 nodes, which is float32 noise). It is not a substitute inside the city — between two nodes the city interpolates linearly while the noise wobbles, so they agree only *at* the nodes. It exists for what lies **outside** the graph, where there are no nodes to interpolate: see [The outskirts](#the-outskirts).

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

The scene the city emits is **coarser than the data behind it, on purpose**. Per building (`BuildingCluster`) it emits **two meshes** and **one collider**, merged from every cell of every floor — not one node per cell per floor. The two meshes are the same surface built for two readers (see [Two meshes per building](#two-meshes-per-building-the-semantic-one-and-the-skin)): the **debug** one keeps a piece per module per floor and is what the index and the collider describe; the **final** one is rebuilt by position — no interior faces, coplanar faces merged — and is only what the player sees.

This is only the **last step**, the emission. Everything upstream stays per cell and per floor: `BuildingModule` (core area, chamfers, occupancy, the funnel every placeable position flows through). Future placeables — windows, balconies, AC units, signs, roof tanks — will ask *those* for their position, never the scene tree, so merging the output costs them nothing. Splitting it back into pieces is a change to one function (`City._visualize_buildings`) and nothing else.

**Why it matters** (measured on the 312-block city): colliders went from **145 264 collision shapes to 22 596** — the building half from 126 777 down to 4 109, one per building. Those shapes sit in Jolt's broadphase no matter where the player is, so this is a per-frame and memory win, not only a startup one. The collider is **the debug mesh's faces, literally** (`Mesh.get_faces` on the mesh `BuildingShell` built), so nothing is calculated twice and the ray's `face_index` lands in the ranges the index recorded.

### Two meshes per building: the semantic one and the skin

Both come out of one pass over the module's faces (`BuildingShell`, [building_shell.gd](../../building/building_shell.gd)), and the **F3 view** only flips which one is visible (`City._apply_view`): nothing regenerates.

- **The debug mesh** is the *semantic* one: district colour (`NeighborhoodTypes.debug_color`, the saturated hues that exist to tell districts apart), floors alternately darkened and modules in a checkerboard, the basic form with no openings, one group of triangles per `(module, floor)`. `CityIndex` records its ranges and the collider is its faces, so pointing at a building names the cell and the floor whichever mesh is on screen. It has **two surfaces** — walls, then caps — and the index ranges live in `Mesh.get_faces` order (all walls, then all caps); `CityInspector._collect` concatenates surfaces the same way. Every vertex also carries its **coordinates in both placement grids** (module cells in `UV`, the surface's `RigidMatrix` cells in `UV2`, module height in `CUSTOM0`), which is what [building_debug.gdshader](../../../../Shaders/building_debug.gdshader) draws as the *deformable* or *rigid* grid: a translucent tint per cell over the colour. On walls those coordinates interpolate exactly (parallelograms); caps are general quads with a saddle, so their surface also carries the core's bilinear in XZ and the shader inverts it by Newton per fragment — the same computation as `PlacementGrid.world_to_cell`, projected vertically.
- **The final mesh** is the *skin* (`BuildingSkin`, [building_skin.gd](../../building/building_skin.gd)): archetype colour, rebuilt **by position, knowing nothing about modules or floors**. Walls are grouped by plane (canonical normal + offset, 1 mm); in a plane's own frame — `u` along its horizontal, `v` the height minus the floor line's slope — every wall is an axis-aligned rectangle, and so is every **opening** (a door or window region is a piece of the same parallelogram). *One side, minus the other side, minus its openings* is then rectangle arithmetic done as a grid (`_carve`: every edge in `u` and `v` splits the plane into cells, cells are painted solid or cut, solid cells fuse into full-height columns) — exact, linear in the openings, and a facade of twelve floors with five window columns comes out as a handful of rectangles with shared vertices. Around each opening the skin shows the **wall thickness** (`BuildingArchetype.wall_thickness_m`, independent of how thick the piece is): the *reveals* — jambs, lintel, sill, `wall_thickness` inward — skipped on an edge where the wall itself ends; and if the piece declares an **arch** (`arch_height_m`, `arch_segments` on `WindowArchetype`/`DoorArchetype`: the arch section is a rectangle inscribed in the opening's top) the two upper corners come back as fans and the lintel reveal follows the arc. The piece is sunk into the wall by the placer (`GridPlacer.place(..., sink_cells)`) so it sits inside the reveals. Caps live in their module's cell space (they have a saddle, not a plane): equal caps cancel by comparison, unequal ones go through `Geometry2D` with holes split by a line through them. A face that does not fit its plane's frame is emitted as-is and counted (`paredes fuera de marco` in the generation log; any number is a case to look at). A stepped building — a smaller upper floor — needs nothing here: the lower floor's cap minus the upper's footprint is the cornice.
  ⚠ **`City.window_openings`** — doors always get their opening; windows only with this flag, because 630 000 windows sunk, cut and revealed vertex by vertex in GDScript cost ~70 s and hundreds of MB. `Demo.tscn` turns it off (windows stay flush, no hole — the panel covers the wall); the sandbox sample keeps it on. The structural fix is the one already noted for windows: instances (MultiMesh), with the reveals as part of the instanced piece.
- **Hollow buildings** (`BuildingSkin.hollow`, from `BuildingArchetype.hollow`): a building you walk into. The skin adds the *inside* of every exterior wall — the same rectangles, `wall_thickness` inward, facing in, carved by the same openings, so the reveals end exactly on them — and the underside of whatever faces the sky (the roof, a cornice) at the same thickness. No slabs between floors: intermediate caps already cancel, and the floor is the block's ground, which is drawn under buildings anyway. For a hollow building the **collider is the skin**, not the semantic mesh (the semantic one would put invisible walls at every module boundary and a floor between storeys), so its identity in the index is one range over the whole skin (`edificio N · celda (-1, -1)`), and it gets no box occluder. An archetype can also say how it occupies its lot instead of leaving it to the draw: `fixed_floors` (the cluster takes that many) and `whole_section` (the cluster grows over its whole section). The first user is the **branch** (`BranchArchetype`, [branch_archetype.gd](../../building/branch_archetype.gd)): 2 × 2 modules, 2 floors, hollow, industrial windows, one garage door; it is not in the district registry — where branches go in the city is decided separately (four per company, see [run-setup.md](../conceptual/run-setup.md)).
- **Gates** (`DoorArchetype.moving`, [gate.gd](../../props/gate.gd)): a door whose leaf moves is not baked into the wall. The door pass places it like any door — same span, same slide-until-it-fits, same opening recorded for the skin — but with an **empty piece**, which the placer now accepts (it occupies the region and bakes nothing), and builds a `Gate` node on the opening quad: a `StaticBody3D` leaf in the middle of the wall's thickness that **shrinks upward** (top edge fixed, collider disabled once open — the ship's `BoxHull` door motion, driven by the same `ShipDoor`), and a momentary button on each face of the wall, each a one-control `ProceduralDashboard` (`DashboardPreset.single`) wired in `Gate._ready`. One gate per building. Gate state is local, like the ship door's. Headless test: `Scenes/tests/branch.tscn` (hollow skin, skin collider, gate opens on the button).
- **Placement boxes** (`City._visualize_placement_boxes`): every region something occupied is recorded with its bilinear frame (`CityIndex.add_region`, five vectors of `PlacementGrid.region_frame`) and drawn on demand as a translucent box — one `MultiMesh` and one colour per **way of placing** (`CityIndex.Grid`): red for the module grid, green for surfaces, blue for free placement, where there are no cells and the region is the entity's own box, recorded by `City._place_entity` itself so anything placed that way shows up without being told. The [placement_box.gdshader](../../../../Shaders/placement_box.gdshader) applies the frame's cross term per instance, so a box *is* its region with its grid's curvature, not an affine approximation.

Colours: the archetype's `base_color` is the building's family (cream, ochre, warm grey — never pure white against the light fog), jittered per building by seed; the district's saturated hue is debug-only.

### Modules are cached by data, not by floor

`BuildingCluster.get_building_module()` keys its cache on **the cell plus its four edge types**, not on the floor. Edge types are still queried *with* the floor (`PathGenerator.get_path_edge_type_vertices(..., floor)`), so the day an alleyway changes with height, that cell yields a different key and is recomputed on its own — **the ability to vary per floor stays, but is only paid for where it actually varies**. Today nothing varies, and the city computes **10 560 modules instead of 126 777**: each one's chamfers walk the grid vertex by vertex, which was the single most expensive step of generation.

---

## Grid types — there are 3

| Level | Class | Size |
|---|---|---|
| City | `BlockGenerator` per graph face | one per block |
| Block | `DistortedGrid` (sinusoidal distortion) | ~6×6 cells of ~11 m |
| Building | `BuildingModule` per cell | N×N cells of a **fixed 0.213 m** (`City.building_cell_m`), N derived from the block's width — 117 today; 32 cells (6.8 m) per floor |

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

**The building cell is a fixed metre unit, and the module's cell count is derived from it — not the other way round.** It used to be 80 cells per module with the cell sized by whatever the block came out at, so widening blocks widened the cell, and with it every floor (32 cells), alley (18) and sidewalk (24), all counted in cells. Now `building_cell_m` is 0.213 m and `GraphCityGenerator` derives the count from the measured block width. Widening the blocks (`min_distance` 164 → 246, `region_size` scaled with it so the block count stays at ~180) therefore widened **only the buildings**, measured on one city: module 16.6 → 24.8 m, core width per module median 12.7 → **21.0 m**, cores under 10 m from 30 % to **none**; floor 6.80 m, alley 3.82 m per side and sidewalk 5.10 m unchanged. Street half-widths are in metres too (`BlockGenerator.STREET_HALF_WIDTH_M`), converted to block-grid cells per block, so they hold as well — 9.9 / 12.3 / 19.7 m against 9.9 / 13.1 / 19.7 before, the medium one losing 0.8 m to cell rounding.

**Facade offset** (module level, in building cells — the module's core is inset by it):

| Adjacent cell type | Cells |
|---|---|
| Normal (attached neighbour) | 0 |
| Boundary (world edge) | 24 |
| Facade (street) | 24 |
| Small / big alleyway | 18 |

Toward a street the offset is the external sidewalk, up to the kerb; toward an alley it is the module's half of the alley, and the two modules flanking it pave it edge to edge. **The world's edge takes a street's offset** even though no roadway lies beyond it — the city ends in a sidewalk, and the sidewalk pass never learns the side is special. A roadway there would be the expensive part, not the sidewalk: `_ground_streets` skips any edge without two adjacent faces, and lane volumes and traffic assume two. Building faces sit at the core boundary. Everything in the offset is decided per module (see [sidewalks.md](sidewalks.md)).

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

Both axes are spread as **patches** (`_assign_patches`: seeds on random faces, all fronts growing one step per round until the city is covered), with **separate seeds and no radial rule** — so a slum can be a canyon downtown and a rich district can be low and open against the city's edge. Height patches get their tier by **quota**, not by independent draws: `HEIGHT_WEIGHTS` (55% tall, 25% mid, 20% low) is turned into exact counts and shuffled. Drawing each patch on its own let the realised share drift badly — 8% low against the 20% asked, because the draw is per *patch* and patches differ in size.

**Cracks.** Inside a block that is *not* low, each building has a `CRACK_CHANCE` (12%) of breaking its tier and building from the **low** range instead. They are the gaps a pilot can spot and cut through between towers — player expression, so the only options aren't "straight over a breather patch" or "along the street". A building is a cluster of 1–8 cells and a cell is ~27 m, so even the smallest crack is far wider than an alleyway: it does not break the rule that the ship never flies into alleyways. The majority stays tall, so the maze holds.

**Measured** over one 312-block city: tiers came out **18 % low / 26 % mid / 57 % tall** against the 20/25/55 asked, no building outside its patch's range, and **11.5 % cracks**, none in low blocks. Generation time is dominated by mesh emission, not by the graph.

**Superseded:** floors used to be blended toward the city average by `pow(distance_to_seed, 0.3)`; an exponent below 1 blends almost everything, so only seed blocks kept their own range (24 one-floor buildings in a whole map). Gone with the four-type enum.

---

## The outskirts

What lies beyond the city: a skirt of terrain climbing from the city's edge into a mountain range. It replaced a wall, and the reason is worth keeping: the wall had been **invisible** for a long time (`show_wall_mesh` off, collider kept), so what made the city feel boxed in was never the wall — it was the **void behind it**, with the player standing on a hidden 3 km collision plane that the scene carried.

**Containing the world and shaping it are two different jobs, and they are two different objects.** An invisible vertical ribbon on the outermost strip (`enable_outskirts_barrier`, collision only, overshooting the terrain by 200 m above and below) is the only thing that actually holds anything in. That is what buys the mountains their freedom: as long as the mountain *was* the barrier, every crest had to reach the same impassable height or the world leaked out the lowest one — and a ring of identical peaks is exactly what read as bland. Raising them instead was not an option either: peaks tall enough to look varied make the city look like a model.

It is built by **pushing the city's edge outward along rays from the city's centre**. The edge already exists as a ring of graph nodes (`GraphGenerator.boundary_ring`), so nothing has to invent a path — the same thing that was true of the wall.

**Why radial and not perpendicular to each run.** Offsetting each boundary edge along its own normal folds the mesh at concave corners. From a single centre it cannot, as long as the outline is *star-shaped* about that centre — and it is: measured over one city, **38 boundary nodes, 0 segments that go backwards in angle, largest angular gap 17°**, radii from 573 to 1 027 m. That 1.79 spread is also why the result does not read as a ring: the starting contour is already far from circular.

**The seam is exact, not agreed.** The first strip uses the boundary nodes' own heights, which is what the city interpolates along that same edge. Beyond it the height comes from `CityTerrain.height_at`, the **same noise field** that shaped the relief inside — matching the node heights to 4.7·10⁻⁷ m.

**Distance to the crest varies by direction**, which is what keeps the limit from feeling like a circle: it is drawn from that same field, sampled far out along the outward ray, so it is deterministic, adds no state, and stays uncorrelated with the edge's own height. In some directions the mountain starts close and in others far — but every direction reaches the crest.

All of the shape is tuned live from **F7** (see [ui.md](ui.md#layer-2--debug-panel-f1-tabbed)), which is worth the wiring because the skirt rebuilds in **5 ms** while the city behind it takes half a minute.

**Where the outskirts level off is signed.** `outskirts_crest_floors` is the mountains' target and it is a *different number* from `impassable_floors`: positive raises a range around the city, **negative sinks the skirt** and leaves the city on a plateau with the land falling away (measured at −8 floors: crests from −55 m, terrain down to −61 m). That freedom is the barrier's doing — while the mountain had to contain, the shape could only ever go up.

**Every direction gets its own crest**, drawn from a second, much coarser noise field (`outskirts_feature_size`, over a kilometre against the city relief's 300 m). Since the field's shapes are ten times longer than a boundary run, neighbouring nodes draw similar values: the result is ridges and passes, not a comb. The draw is **stretched to the full range** the same way `CityTerrain` stretches the relief and for the same reason — raw noise does not reach its extremes, and over 38 nodes it sat between 0.53 and 0.82, so `outskirts_crest_variation` was promising a spread it never delivered.

A skirt vertex is three things summed. The **profile** rises as t² to that direction's crest — gentle foothills leaving the city, steepening toward the top, the way a mountain reads — and drops back past it so the silhouette has thickness instead of a knife edge in mid-air. The **coarse relief** then cuts valleys and raises spurs *over* that profile; it is signed, so it subtracts as much as it adds, and without it the skirt is a smooth ramp. The **city's own relief** rides on top as fine detail, two scales stacked. The last two are multiplied by the climb factor, which is 0 at the edge — which is why the seam stays exact no matter how much the outskirts deform.

**One number owns the limit.** `City.impassable_floors` (**13 floors ≈ 89 m**) is the ceiling every crest is a fraction of, and the height the barrier rises to; the city publishes it — with the floor height — into `WorldSettings`. `Ship` no longer carries a hand-typed ceiling: it stays `ceiling_margin_floors` (5) below the limit, which is the relation its old comment described in prose and that someone had to recompute by hand every time the wall moved (it once sat at 90 m and the ship flew straight over). The tallest buildings (15–22 floors) still rise above the crest on purpose — a limit taller than every tower makes the city read as a toy box.

Measured on the 1 425.6 m city: **1 064 triangles** for 14 rings over 38 nodes, plus 76 for the barrier (against the city's 22 596 collision shapes, nothing). Crests span **40 to 89 m** and the terrain **2 to 105 m**; sampled in 36 sectors of 10°, the skyline runs from **9 m in the lowest pass to 105 m on the highest ridge**, a 12× spread. Steepest slope 32 %, which is climbable on foot — you can walk up a ridge and look back at the city, and the barrier is what stops you, not the gradient. The ship's 54.6 m ceiling clears the low passes outright, which is precisely why the barrier exists. Planned: circular holes where cars fly in and out, to sell that the city continues beyond where the player can follow.

Like the old wall, the skirt carries **no distance range** — it is one mesh wrapping the whole city, so its origin is the centre and "distance to the outskirts" means nothing. What keeps its silhouette from shrinking the world is the fog. See [Meshes are built in world space](#meshes-are-built-in-world-space--mind-the-origin).

**Where the player starts.** The graph is generated in the **first quadrant**, not centred — the measured city runs from (6, 46) to (1395, 1422) — so the `(0, 0, 3)` the spawner used to carry landed *outside* the boundary. With the world ending in mid-air that went unnoticed, because the hidden 3 km plane caught the player. `City.start_point()` now returns the graph node nearest the centre of the boundary ring, lifted clear of the ground, and `CharacterSpawner` asks for it **at the moment it spawns** rather than reading a constant at load — the city fills it in during its own `_ready`, so the `city` node sits before `CharacterSpawner` in the scene.

### Meshes are built in world space — mind the origin

Almost every city mesh is built with **world-space vertices** and added with no transform, so its origin sits at `(0,0,0)` — the corner of the city — with the geometry hundreds of metres away. That is fine for drawing, and it is what lets separate pieces share one coordinate system.

It is **not** fine for anything Godot measures from the node's origin. `visibility_range_end` is exactly that: the distance it compares is *camera → node origin*, which for these meshes is *camera → corner of the city*, **the same for every building**. Move away from that corner and they all fade at once, including the ones right in front of you — and the symptom reads as a fog bug, not a culling one.

`_add_box_occluder` therefore centres its occluder on the mesh's own AABB. **Any future per-piece LOD, visibility range or distance-based logic has to do the same** — or be given a node whose origin means something. (`_fade_into_fog` did exactly that while pieces still had a visibility range; see below.)

There is a second half to that rule: **a mesh that spans the whole city cannot use a distance range at all**. The outskirts are one mesh wrapping the city, so their centred origin lands in the middle of it and "distance to the outskirts" is meaningless — given a 294 m range the old wall in that same position only drew while the camera was near the city centre, i.e. almost never. They therefore carry **no range**; what keeps their silhouette from shrinking the city is the fog.

### Superseded — the distance cutoff and the fade ring

Until the fog was decoupled from drawing, every piece got `visibility_range_end = render_distance + its AABB radius` and dissolved in across a ring scaled with distance — San Andreas' `CVisibilityPlugins::CalculateFadingAtomicAlpha` rule, 20 units near and `distance / 15 + 10` far. It measured well (largest channel difference against the sky across the ring: 0.227 at 400 m down to 0.059 at 500 — it dissolved, never stepped) and it is in git if a distance LOD ever wants it. It went because the fog distance and the draw distance being one number meant that bringing the fog in, to make the city feel larger, cut the distant silhouettes — the one thing strong fog needs. Two lessons survive it: the threshold must include the piece's own radius, because Godot measures to the origin while fog is per pixel; and a fade that dithers shows the inside of a mesh, so once doors and balconies are their own meshes any fade must sit where the fog is already thick.

### The weather: fog, sky, ambient, screen tint and clouds are one decision

`CityFog`, on the `WorldEnvironment`, applies all of them; the values are the defaults of `Weather` ([weather.gd](../../core/weather.gd)), a plain Resource. **The game ships one fixed weather** — there is no cycle and no changing state (see [world.md](../conceptual/world.md#climate) for the design that comes later). There used to be a table of nine presets converted from **GTA San Andreas' `timecyc.dat`** and an F5 list to alternate them; one was chosen and the rest is in git. What survived that reading are three structural decisions.

**1. Fog colour is not sky colour — unless you ask for it.** In the timecyc they are literally one column (`Sky bot`) used for both, which makes the silhouette problem impossible: a piece saturated with fog ends up painted exactly the colour of what is behind it. Elegant, but it ties the colour of the distant city to the sky, and that is what was not wanted. `Weather.fog_from_sky` is that argument turned into a switch — **off by default**, so fog has its own colour (a stock Godot sky with dark blue fog). Silhouettes are real there, which is exactly why the fade ring exists. Strong fog is wanted — without it the world reads monotonous — and the lesson from trying 800 m is that what keeps a city from feeling enclosed is the fog's *colour*, not its reach.

**2. Weather is colour, never range.** Across the nine timecyc rows read, `FarClp` is **2000 in every one**. So `Weather` carries no distances: they live in `WorldSettings`, because they also drive the city's distance cut and the car spawn radius. Changing the weather can never make the world smaller.

**3. The sun is two lights.** `DirectionalLight3D.light_angular_distance` defaults to **0**, and at 0 the disc `ProceduralSkyMaterial` draws is a point — invisible, which is why the world had no sun (measured: the pixel at the sun reads **1.000** brightness with a 3.2° disc against **0.384** without). But that same property is the sun's angular size for shadowing — the penumbra width, 0.53° in reality — so raising it to get a nice disc washes out the shadows buildings cast on each other. Two things sharing one property, so `CityFog` drives two lights: the one in the `sun` group lights and casts with `shadow_softness`, and a second in `SKY_MODE_SKY_ONLY` draws the disc with `sun_size` while contributing neither light nor shadow. At `sun_size` 0 there is no disc and still a sun — what San Andreas does in rain and sandstorm.

The **screen tint** is two full-screen colour-correction layers (`Alpha1 RGB1`, `Alpha2 RGB2`, at alpha 195/255 in every timecyc row seen), approximated in `Shaders/screen_tint.gdshader` as a multiply plus a wash. **It is an approximation, not a port** — Rockstar's own differs between PS2, PC and mobile. Both strengths default to 0: our tonemapping is not RenderWare's and at full strength it eats the contrast.

Two Environment flags stay pinned at **0** on purpose. `fog_sky_affect`, because the sky already carries the fog colour along its bottom edge and tinting it again just dirties it twice. And `fog_aerial_perspective`, which sounds like exactly what we want but is not: it blends the fog with the sky's *radiance cubemap* — the whole dome convolved, dominated by the zenith — not with the sky in that direction. Measured at 0.9, a saturated box rendered (0.54, 0.47, 0.49) against a sky of (0.83, 0.64, 0.46): grey-blue geometry on a warm sky, which is the very pop it was supposed to remove.

**Clouds** come from the **Sunshine Clouds 2** addon (`addons/SunshineClouds2/`, MIT): volumetric, rendered as a `CompositorEffect`. The settings live in [Scenes/clouds.tres](../../../../Scenes/clouds.tres), referenced twice from `Demo.tscn` — by the `WorldEnvironment`'s `Compositor` and by the `Clouds` node (`SunshineCloudsDriverGD`), which animates the wind and tracks the sun, so moving the sun relights the clouds. ⚠ **Both references are required**: the driver's setter only adds the resource to the Compositor when the node is already in the tree, which never happens while a scene loads. The compositor cannot see the `Environment`, so the clouds keep their own copy of the fog colour; `CityFog.apply()` writes it from the weather, which is why the tuner does not offer it. Needs Forward+ (compute shaders); invisible in headless.

⚠ **The shaders are compiled for one Godot version.** `addons/SunshineClouds2/CloudsInc.comp` defines `GODOT_VERSION_MAJOR`/`MINOR`, and with them the layout of the engine's scene-data block the shaders read (projection matrices, near/far). The addon ships set to 4.6; on 4.5 the block is read with the wrong offsets and **nothing renders**, with no error — the addon's tutorial blames the camera's 4 000 m far plane for that, but the shader treats sky pixels as infinitely far; the version was the cause here. The plugin's dock rewrites the number when the editor opens a scene, half a second in — a headless `--editor --quit` exits first, so it never ran here. It is set to **5** by hand. After changing it the six `.glsl` imports must be rebuilt (delete their `.godot/imported/SunshineClouds*.glsl-*` entries and reopen, or the resource's **Refresh Compute**). Updating the addon or Godot means checking this again.

⚠ **The addon's defaults are planet-scale**: noise patterns of 300, 85 and 20 km, a layer between 1.5 and 15 km, ray steps of 100–500 m. From a 1.8 km city under heavy fog, the whole visible sky falls inside a single sample of each pattern, so it is either one uniform veil or nothing — never separate clouds. `clouds.tres` is rescaled to the city across the board — layer and patterns come down by one to two orders of magnitude, ray steps with them, and the wind speeds follow the patterns. The numbers themselves are not repeated here: they are tuned by eye from F6 and the file is the only place they live.

All of it is tuned live from **F6** and pasted back by hand — see [ui.md](ui.md#layer-2--debug-panel-f1-tabbed). Nothing persists.

The old fullscreen `radial_fog.gdshader` — a depth pass with three hand-tuned colour bands copied off the sky gradient — **was deleted**, along with its wiring in `AreaInstantiator` and the `fog_color*` fields in `WorldSettings` that only it read. There is one fog system now. Its history is in git if it is ever needed.

---

## Streets — half a street per block

The ground is two meshes under one collider (`City._visualize_ground`): the **blocks** (every distorted-grid cell, `ground_color`) and the **streets** (`street_color`), one mesh for the whole city — a few thousand triangles, so no reason to split it. A street is not drawn between two blocks; **each block paves its own half** (`_ground_aprons`): the ring between its **kerb** — the outer edge of its grid, at the grid's heights, so it meets the block ground and the sidewalk without a step — and the **street axis** — the graph edge, at its nodes' heights: a trapezoid per side and a **corner patch** per corner, kerb corner → axis → node → axis. The two halves of a street meet on the axis at the same height, so there is no seam between blocks; nothing depends on the block across or on lane points, so the sandbox's single-block sample gets its half streets on its own, a `BOUNDARY` edge (offset 0) gets nothing, and changing sidewalk or street widths changes nothing here. The gaps every crossing used to have — corridors ran kerb to kerb and left the corners — cannot exist: the corner patch reaches the node. Inside the block, the **curved sidewalk corner** (`SidewalkProps.corner_unit`, a quarter disc of kerb) leaves the rest of its square as street: that region is drawn into the street mesh too (`SidewalkProps.curb_outside`, the exact complement of the arc, taken through the *same* bilinear the sidewalk was placed with, lifted `STREET_LIFT` over the block ground) — it used to show the block ground's colour. **UVs in metres**: `u` from the kerb, `v` along the edge in its canonical direction (lower node → higher), the same on both halves, so an asphalt shader runs continuous; corner patches use planar `(x, z)`. Lane volumes rest on the same node heights (see [traffic.md](traffic.md#relief--lane-volumes-follow-the-graph)).

## Building archetypes

Each `BuildingCluster` is assigned a **building archetype** + seed. A building works like a person: the archetype says what *class* of building it is, and the seed varies the individual within that class.

- **Base class** `BuildingArchetype` ([building_archetype.gd](../../building/building_archetype.gd)) defines the interface (`get_color`, `get_street_corner_chamfer_value`, future `generate_geometry`) and carries the **parameters that feed the rules** — `roof_pitch_height`, `flat_roof_chance`, and the `window_*` fields. The archetype holds no rules of its own: who decides a roof's shape is `RoofPlanner`, and who decides where windows go is `FacadePlanner`; both read these. Concrete archetypes live as **inner classes** while small; one can be promoted to its own file once its logic grows, with no caller changes.
- **Registry** `ArchetypeDefinitions.NEIGHBORHOOD_ARCHETYPES` ([archetype_definition.gd](../../building/archetype_definition.gd)) maps each **district** to its archetypes. `get_archetype_for_cluster()` seed-picks one and instantiates it — the pick stays even with one entry per district, so adding a second changes nothing else.
- **Colour**: each archetype owns a `base_color` — plaster and stone of the 1900s, never pure white — and the seed nudges hue, saturation and value per building. The saturated hue that makes a district readable at a glance is **debug-only** (`NeighborhoodTypes.debug_color`, drawn by the debug mesh; see [Two meshes per building](#two-meshes-per-building-the-semantic-one-and-the-skin)).

| District | Archetype | Windows (style trial) |
|---|---|---|
| `POOR` | `GenericPoor` | sparse — stacked columns, floors skip some at random; small |
| `RICH` | `GenericRich` | stacked, tall, tight rhythm |
| `INDUSTRIAL` | `GenericIndustrial` | stacked, wide and low, far apart |

**One generic archetype per district**, and the three are identical apart from hue and windows — deliberately. The layer exists so that changing a district's roof, windows or material is changing *data* here, not rules elsewhere.

**Superseded:** there used to be eight archetypes (`ShantyBasic`, `ShantyMakeshift`, `MixedUse`, `MansionClassic`, `MansionModern`, `OfficeTower`, `WarehouseBasic`, `FactoryModern`) that differed **only in hue** — a distinction that does not exist for the player. Named archetypes come back when there is something real to tell them apart with. There is no "Downtown" district either: density became its own axis when districts and heights were split in two (see `NeighborhoodTypes`).

---

## Facades — windows and doors

The same split as roofs, for walls ([facade_planner.gd](../../building/facade_planner.gd)): the **archetype** says which criterion a building uses and with what numbers; **`FacadePlanner`** has the rules and returns candidate regions in the cells of a wall's `RigidMatrix`; **`GridPlacer.place`** places, indexes, occupies and rejects whatever collides. The planner checks nothing against what is already there — the matrix does.

⚠ **Primitive on purpose.** Two window criteria exist to try out a style; doors (ground floor and upper floors) are meant to become further criteria of the same planner. The *pieces* are archetypes of their own — `WindowArchetype`, `DoorArchetype`, listed per building archetype and picked per building by seed — and where that is heading (one type per pseudo-category of window, per-window seed variation) is in [design-sandbox.md](design-sandbox.md#windows-and-doors-are-archetypes-now).

- **Where a wall is visible** — `has_wall(block, cluster, cell, module, side, floor)`: toward a street or alley, always; toward the world boundary, never; on an *attached* side, when the building across it has no floor at that height — a shorter neighbour (the floors that rise above it) or a block heart (walls facing a plaza are facades). Only against a cell of the same building is a side interior. The edge type alone is not enough.
- **`STACKED`** — columns of `window_width_m` separated by `window_gap_m`, as many as fit, centred, at `window_sill_m`. They depend only on the matrix width, which is the same on every floor, so a side's windows line up vertically with nothing stored.
- **`RANDOM`** — the same columns as `STACKED`, and each floor keeps each column with probability `window_fill`. The disorder is per floor, never per window: nothing is offset from the grid, so the wall stays cheap to build around the openings.
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
| **cupola** | the ochava cell of a corner building, **through whatever roof it has** | drum, dome, lantern, small dome, spire |

Pieces carry **numeric parameters** — heights at their edges, where a chamfer's cut falls — rather than existing in one variant per size. That is what lets a skirt that crosses three modules be placed as three skirts that meet exactly, and what keeps a gable's ridge at the same height whatever the building's width (if each band rose a fixed step, a four-cell-wide building would get a nine-metre roof). It is still a finite catalogue placed by rule; the pieces just know how to stretch.

### Everything is reasoned in whole building cells

The block's building grid is one integer lattice: cell `(cx, cz)` contributes its N×N cells from `cx·N` (N is the module's `columns`, the same across the city). Cores of two cells in one building touch on an exact shared edge (offset 0 on a `NORMAL` edge), so the footprint is a **union of integer rectangles**, and its outline always lies on cell lines. No polygons, no insets, no clipping:

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

### The cupola — through the roof, deformable with a limit

A corner building (a cell with a **street** chamfer) may carry a cupola on its ochava (`BuildingArchetype.cupola_chance`, seeded per cluster). `RoofPlanner.cupola` is the decider: a square region of `RoofProps.CUPOLA_DIAMETER_M` in the module's cells, pushed in from the corner vertex just enough for the drum to stay inside the diagonal of the cut, `CUPOLA_HEIGHT_M` tall, at roof level. Two things are new in how it is placed, both in `GridPlacer.place`:

- **It goes through the roof.** The roof pieces are already there; the cupola does not ask for a free region (`over_occupied`), only that it fits the grid — and it still occupies, so the tank placed after it keeps clear. This is the first of the objects that *come out of* a roof (chimneys will be another, as free placement).
- **It is a deformable with a limit.** It rides the module grid like every roof piece — it bends with the block — but a dome is round by definition, so it is accepted only if its region is nearly square: `PlacementGrid.LIMITED_SKEW_DEG` (10°) is the most any corner of the region's quad may depart from 90°. A limit of **angles, not size**, one value for every object of this class. Buildings whose cell is more skewed simply get no cupola; the generation log counts them (`sin lugar por torsión`), and the sandbox's X / Z distortion keys show the threshold at work. Measured on the Demo city, the skew of block-corner cells is spread almost evenly from 2° to 58° — it comes from the shape of the block itself, not from the wave distortion — so at 10° roughly one candidate in four or five passes: ~50 cupolas in 191 blocks.

### Superseded — three earlier designs, each easy to reintroduce

- **A piece per cell chosen from the cell's neighbourhood**: neighbouring pieces disagreed on the profile of the edge they share. *A cell cannot decide on its own.*
- **A height field on a half-cell lattice**: continuity, but at a resolution the grid does not have — a one-cell building had no room for a top and looked like a gable (651 of 929), and it ignored real chamfers.
- **A procedural outline (polygon union + inset)**: right shapes, but not the modular interface every other object uses — whoever placed something had to think in silhouettes.

### In the index

One record **per piece**: ids are `a` = building, `b` = piece (`RoofPlanner.Piece`, the cupola included), `c` = outline side or −1, `d` = style or −1. The inspector names them — "faldon de techo frances · edificio 16 · lado 3". Colour is per style, with French set apart in slate blue-grey — the real material of a mansard — and vertical walls in the side colour.

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

⚠ **There must be one definition of "where floor N is", and the mesh must ask for it.** There were two once: the mesh built floor N as floor 0 raised, while placement went through a taper that straightened the module toward the cluster's mean height over the first floors — a horizontal surface from floor 2 up, 1.35 m off the visible wall, chased for a while as a centimetre-scale bridge bug. The taper is gone, and the fix was made structural: `_visualize_buildings`, the colliders and every placed object **ask the grid for the faces they need** (`point_at_f`, `get_core_vertices`, `get_wall_quad` at both floor indices), and `BuildingShell` builds each floor from those walls and caps. If horizontal roofs are ever wanted again, change `point_at_f` and everything follows; changing the mesh or the placement alone is precisely the bug that was removed.

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

## Placing objects — three ways, in passes

There are three ways something ends up in the city, and the difference is **how much it may deform**:

| | What it is | What goes there | Deforms |
|---|---|---|---|
| **Module grid** (`BuildingModule`, the "deformable" grid) | the building's own cells, in plan and in depth | roof pieces, sidewalks, bridge extremes | fully — follows the block's distortion and relief |
| **Surface grid** (`RigidMatrix`, the "rigid" grid) | a re-subdivision of one surface (a wall, a roof) with its own normal | doors, windows | barely — the surface's own shear; on a saddle roof, the saddle |
| **Free placement** (`FreePlacement`, [free_placement.gd](../../block/free_placement.gd)) | a quad plus a list of footprints with margins — not a grid | parked cars, the roof water tank (`City._place_entity`: the unit mesh built whole, `UnitMesh.build_mesh`, in a transform, with its collider and its own index scope); next: containers, chimneys | never — an entity with a transform |

The first two share one mechanism: a **mesh authored in the unit cube** goes into a **region of cells of a grid**, and the grid's cells decide its geometry (`PlacementGrid`, [placement_grid.gd](../../block/placement_grid.gd); one call, `GridPlacer.place`, [grid_placer.gd](../../block/grid_placer.gd)). The third does not draw anything: it hands back a `Transform3D` for an entity, and remembers the footprint. It can also take occupancy projected from the grids (`block_points`, `block_span`), so a car never parks in front of a delivery door.

**Passes.** All three read what the earlier ones left and write their own; that order is the only thing that keeps the mutual occupancy from being circular, and it lives in one table, `City._passes()`: deformables first (bridges, sidewalks, roof pieces), then rigid (doors and windows, which also leave their **openings** behind), then free placement (parked cars, which read the doors), then the shell and skin (which need the openings to cut the walls), then the collider. Each pass prints its time. Expect the order to change often — that is why it is a table and not a chain of `if`s. What differs between the module grid and the surface grid is only **which grid** an object goes into, i.e. what its cells are:

- **Deformable** — can be stretched without looking wrong, *and* has to line up with its neighbours across modules: roof pieces, sidewalks, bridge extremes, columns, pipes, walkways. It goes into the **building module** (`BuildingModule extends PlacementGrid`): the distorted-grid cell with its relief, `axis_n` up, 80×80 cells of ~0.14 m and no ceiling. Its cells bend with the city, so what is placed in them bends the same way, and two pieces in neighbouring modules that share an edge coincide there — on a shared edge both bilinears reduce to the same line. No distortion threshold, ever — that is what deformable means.
- **Rigid** — should keep its proportions: windows, doors, water tanks, balconies. It goes into the **rigid grid of a surface** (`RigidMatrix extends PlacementGrid`, [rigid_matrix.gd](../../block/rigid_matrix.gd)): the surface's own quad, `axis_n` its outward normal, and cells **recomputed to be as close to cubes as possible** at `TARGET_CELL_M` (0.25 m). Because the surface is nearly flat and nearly a parallelogram, its bilinear is nearly affine, so what goes in is *barely* deformed — but it *is* the same mechanism, and that is the point.

### The grid

A `PlacementGrid` is four corners in the world, an outward axis, and a cell count per axis. A point in cells `(x, y, z)` goes to the world by **the bilinear of the corners in `(x, z)` plus `y` cells along the axis** (`cell_to_world`). That is the whole mechanism, and every vertex of everything placed in the city passes through it. **A piece cannot end up tilted against its grid, even on purpose**: there is no other source of position, the way a connector only fits one way round. (`BuildingModule.point_at_f(u, v, h)` is `cell_to_world` with normalised `(u, v)`; everything that samples a module still goes through it.)

⚠ Why this matters: the first rigid grid had its own **orthonormal frame** — `u` along the floor line, `v = u × n` — and mapped meshes affinely in it. A facade is a parallelogram (floors follow the terrain), so a rectangle cannot be parallel to both its floor line and its vertical edges; windows came out **rotated within the wall by 1.5° median, 7.4° worst (6–31 cm of lean over a 2.4 m window)**, visibly misaligned against the module's edge. That frame is gone. With the surface's own bilinear, a facade's cells are parallelograms with vertical sides and a tilted floor line — the building's own shear — and a window follows both. Along with it went the inscribed-rectangle logic, the per-object saddle lift (`surface_offset`) and its planar shortcut: a tank's base now sits *exactly* on the roof's saddle because the cells do.

The grid also owns:

- **Occupancy** — a list of boxes in cells, `is_free` (bounds included) and `occupy`. A list and not a 3D array: a module is N×N by 32 per floor — well over a hundred by a hundred — tens of millions of entries per city (the reason the old `SidewalkMatrix` never ran outside a debug view, and was deleted); objects are few.
- **Projection of one grid onto another** — `occupied_world_corners(index_from, index_to)` gives the eight world corners of every region occupied in a grid (filtered to a height range), and `mark_world_hexahedron` marks on the other grid the cells they cover, **column by column along `n`**: for each depth slice it clips the region's twelve edges against the slice and marks only what remains. Not the world envelope: a sidewalk that drops 12 % over its 3 m has an envelope ~40 cm tall and projected in one go it marked 40 cm of facade; sliced, next to the wall it marks its real thickness, which is what a door has to stand on. Conservative inside each slice, never under. `world_to_cell` (the inverse bilinear, by Newton — one step on a parallelogram) is what makes it possible.
- **Sizes in metres** — `cells_for(x_m, n_m, z_m)` per grid axis, rounded *up*: an object never shrinks to fit. What "height" means depends on the grid: `n` on a roof, `z` on a facade.
- **Standing on things** — `first_free_along_z(lo, size, max_rise)` slides a region up along `z` to the first free row: how a door rests on the sidewalk instead of going through it; above `max_rise` (`DOOR_MAX_STEP_M`, 0.5 m) the obstacle is not a kerb and the object is dropped. **Residual:** rows are ~0.25 m and the sidewalk 0.21 m thick, so a door on a sidewalk floats **4–4.7 cm** above the slab — the grid's granularity; closing it would mean fractional positions, a decision not made.

### The placer

```gdscript
placer.place(grid, lo, size, mesh, kind, id_a, id_b, id_c, id_d)  # -> bool
```

Whoever places something thinks about two things: the **region** (`lo` and `size`, in cells of that grid) and the **mesh** (`UnitMesh`, [unit_mesh.gd](../../props/unit_mesh.gd)): x, y, z from 0 to 1, a colour and an outward direction per triangle. Nothing else — never silhouettes, never neighbours, never slopes. Inside `place`: the region's bilinear is precomputed once (`PlacementGrid.region_frame`) and every vertex goes through it; face orientation is measured **in the world** with the bilinear's derivative, because a grid can mirror an axis; the piece is recorded in `CityIndex` with the placer's scope and object; the region is occupied. If it was not free or did not fit, `place` returns `false` and places nothing: two objects cannot overlap by oversight. Three optional tails: `sink_cells` (the piece starts that many cells below the surface — a window inside its reveals), `over_occupied` (no free check, only fit; still occupies — the cupola through the roof), `max_skew_deg` (reject a region whose quad is more skewed than this — see *The cupola*).

### Surfaces

A **surface** is one face able to host rigid objects: the side of **one module on one floor**, the flat roof of a cell, the diagonal face of a chamfer (not yet used). An object that would cross modules is, by definition, deformable.

- `RigidMatrix.from_quad(quad, depth_m, outward)`: `x` runs c0→c1, `z` runs c0→c3, depth along the normal up to what the surface type allows (`City.ROOF_SURFACE_DEPTH_M` 10 m, `FACADE_SURFACE_DEPTH_M` 2 m). A surface shorter than half a cell on a side yields no cells.
- **A unit mesh's `y` points out of the surface.** On a roof that is up; on a facade it is toward the street and `z` goes up (`get_facade_quad` runs bottom to top in `z`; the direction of `x` is irrelevant, faces are oriented in the world).
- **The wall surfaces** are `BuildingModule.get_walls()`: the four **facades** and the **chamfers**, through the same functions (`Wall.kind` says which). A facade is the core's face on that side, **shortened by the chamfers** at both ends (`get_facade_span`, the one definition of "where there is wall" on a side — `TraversalGenerator._door_span` draws door positions from it too, so a door cannot land on the ochava). A chamfer has no geometry of its own: it runs from the end of the previous facade to the start of the next, so nothing can gap or overlap between them, and it exists iff its two ends differ. `RigidMatrix.of_wall(module, wall, cells_per_floor)` is the one place a wall's grid is built, shared by whoever places on it and by `BuildingShell`, which draws it; `RigidMatrix.of_roof` is the same for the flat roof — nothing is placed on it any more (the tank moved to free placement, where a saddle cannot bend it), it remains as the roof's grid overlay in the debug view. One grid per `(module, wall, floor)` (`City._wall_surface_cached`), shared by everything on that face — doors and windows only see each other if they read the same grid. Only floor 0's is built from the quad; every other floor's is that one translated in Y (`RigidMatrix.translated`), with the occupancy of its own height range projected. Nothing is placed on chamfers yet; their grid exists and is drawn like any other.
- **There is no threshold.** A narrow surface just yields few cells and an object that needs more does not fit. ⚠ This also means a skewed surface no longer rejects: with the old inscribed rectangle, 40 of 147 tank roofs were dropped as too skewed; now all **147** tanks are placed and follow their roof's skew, like the roof pieces around them. Whether that reads well is judged in game.

### Order of generation

The order is `City._passes()` (see *Passes* above). The bug it exists to make impossible had already happened: **doors (rigid) placed straight through floating sidewalks (deformable)**, because nothing recorded that the sidewalk was there. Now the sidewalk occupies the module, the facade's grid reads it, and the door stands on it. The same reasoning put parked cars after doors, and the shell after everything that leaves an opening.

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

Building floors are `BuildingShell` (walls from `get_wall_quad`, caps as a fan over the walls' contour). `DebugUtil` still builds the boxes that are not placed pieces:

| Function | Input | Used for |
|---|---|---|
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
