# Design sandbox

A second world, entered from the main menu, for iterating on one generated thing at a time without generating the city: a flat neutral plane with **rows of parcels** — one row per category (buildings, windows, doors, ships, controls, vehicles, the branch), one parcel per archetype — and a simple entity walking between them. No session, no debug menus, no HUD. Everything in it is the game's own code pointed at one element; nothing is a copy.

Files: [design_sandbox.gd](../../../sandbox/design_sandbox.gd) (the world and the rows), [sandbox_entity.gd](../../../sandbox/sandbox_entity.gd) (the walker), [sandbox_parcel.gd](../../../sandbox/sandbox_parcel.gd) (one parcel), [sandbox_panel.gd](../../../sandbox/sandbox_panel.gd) (the info panel), [seeded_archetype.gd](../../../sandbox/seeded_archetype.gd) (what a parcel can hold), [sample_wall.gd](../../../sandbox/sample_wall.gd) (a wall to hang a facade piece on), scene `Scenes/sandbox.tscn`.

## The entity

`SandboxEntity` is a `CharacterBody3D` with a camera: WASD without inertia, shift sprints, space jumps (no charge), **V** toggles creative flight (no gravity, space up / shift down, `FLY_SPEED` 6 m/s — half the game's, the sandbox is another scale). The only thing it shares with the game's character is **interaction with controllables**: the same `InteractionController` and `InteractionDetector`, set up with no arms, no animation and no entity stats — those classes now take any `CollisionObject3D` as the body and already tolerate the missing parts — so a ship's lever or door button behaves identically in both worlds. Grabbables and seats are not wired here.

## The seeded archetype

`SeededArchetype` is the contract every parcel needs and, by intention, the common ground for everything the world generates as *class + individual*: a **`display_name`** (mandatory — it forces every archetype to be nameable), **`max_footprint()`** (width × depth in metres, the most it can occupy under *any* seed), **`build(seed, parent)`** (the individual, centred on the parent's origin, standing on y = 0), **`describe(seed)`** (lines for the panel) and **`category_options()`** (the row's keys, below). Extended by `BuildingArchetype`, `WindowArchetype`, `DoorArchetype`, `ShipArchetype`, `ControlArchetype` and `VehicleArchetype`; as more shared criteria appear (seed derivation, sync, description) they belong here, not repeated per system.

## Parcels and zones

Three concentric zones per parcel, from `DesignSandbox`'s three global constants:

- the **parcel** — where the individual lives; as wide as its archetype's `max_footprint().x`, as deep as the deepest archetype of its **category** (a whole row shares its depth). Drawn as a plane slightly darker than the ground, lifted 1 cm. It is sized **once**: regenerating changes the individual, never the grid; an individual that spills over is reported in the console (`corregir max_footprint`).
- the **interaction zone** — `INTERACT_PAD` (2 m) around it, drawn as a frame, so you can walk around the object with the panel open.
- the **gap** — `ELEMENT_GAP` (3 m) between parcels of a row, `CATEGORY_GAP` (8 m) between rows. Not drawn.

While the entity stands in an interaction zone the **panel** on the right shows category · name, the seed, whatever the archetype says of itself, and the keys. **R** regenerates the individual with a random seed and flashes it white (an additive overlay that fades over 0.35 s); **C** copies the panel's text to the clipboard (a key, not a button: the mouse is captured). Initial seeds are a hash of category + name, so a parcel shows the same individual every session until you press R.

**Row options.** A row can have keys of its own — what in the game are menus — declared by its archetype class (`category_options()`): each is a key, a label (a string, or a callable that renders the current state) and an `apply(parcels)` callable that receives every parcel of the row. All archetypes of a row share one `options` dictionary, so what one key changes, every parcel's next `build` reads. Today: **Naves** — `T` toggles translucent walls (the game's own `Ship.toggle_translucent_walls`). **Edificios** — `X` / `Z` cycle the block's distortion per axis through fixed levels (0 · 0.05 · 0.1 · 0.2 of a cell, no randomness; regenerates the row with the same seeds), and the game's F3 view over every block of the row at once: `B` debug mesh, `G` grid (none / deformable / rigid), `K` placement boxes (the three colours at once).

## Categories today

| Row | Archetypes | What the parcel shows |
|---|---|---|
| **Edificios** | one per `BuildingArchetype` class (`ArchetypeDefinitions.all()`) | a whole block of that archetype's district, **no relief, at 1:25** (`City.generate_block_sample`): the largest building shown complete — roof, doors, windows with their openings — and every other one as a grey translucent **ghost** without accessories (`City.spotlight`). The block is a real `City` node with `auto_generate` off, scaled, colliders off; it comes from `GraphCityGenerator.generate_single_block`, one square face with medium streets on all four sides, then the normal `_generate_block_grids` and the same **passes** as the city — so it has sidewalks, its four **half streets** and corner intersections, and **parked cars** at the kerb, none of them sandbox code. `ArchetypeDefinitions.forced_archetype` makes every cluster of the sample use the parcel's archetype for that one generation. Regenerating takes ~200 ms. |
| **Ventanas** | every `WindowArchetype` some building archetype lists (`WindowArchetype.catalogue()`) | the piece placed on a `SampleWall`, a wall slab built as a `BuildingSkin` with the piece's **opening cut through it** — reveals, arch, the piece sunk in the wall — through the real `RigidMatrix` + `GridPlacer` + `add_opening` path. The piece itself is still the placeholder panel. |
| **Puertas** | same, `DoorArchetype.catalogue()` | same |
| **Naves** | one per `Ship.Shape` | the real `Ship`, **frozen** (`freeze = true`, static): its controls respond — door, levers — and the body does not move. No seed variation yet. |
| **Controles** | one per `ControlArchetype` style (`ControlArchetype.catalogue()`) | a lectern — post and tilted plate at hand height — with a one-control `ProceduralDashboard` on it, so the control is built, dressed and handled exactly as on the ship (see [interactables.md](../conceptual/interactables.md#control-archetypes-controlarchetype)). Grab it to press, drag or turn it. No seed variation yet. |
| **Vehículos** | one per `CarArchetypes.Type` | the same box the traffic draws for that type, on the ground at 1:1. The seed drives a car's route in the game; parked, nothing yet. |
| **Sucursal** | `BranchArchetype.catalogue()` (one, later one per company) | the branch **at 1:1**: a block of exactly its 2 × 2 modules (the city's module size) with medium half streets around, generated through the same `generate_block_sample` path as the Edificios row but with `distorted_grid_rows = 2`, no alleys and **colliders on** — so you walk in through the garage gate, press the button on either side to open or close it, and stand inside the hollow shell (see [city-generation.md](city-generation.md#two-meshes-per-building-the-semantic-one-and-the-skin), *Hollow buildings* and *Gates*). Shares the Edificios keys: X / Z distortion, B / G / K view. Nothing inside yet. |

**Nothing registers with the sandbox.** Every catalogue is derived from what the game already declares — the building registry, the window and door types buildings list, the ship shape enum, the car type enum — so an archetype added to the game appears here without knowing the sandbox exists. Adding a *category* is one entry in `DesignSandbox._categories()`.

## Windows and doors are archetypes now

A building archetype no longer carries window dimensions: it lists `window_archetypes` and `door_archetypes`, and each building picks one of each with its seed (`BuildingCluster.window` / `.door`). The window's size flows into `FacadePlanner.window_size`; the door's into `City._place_delivery_doors` (the door *span* is still drawn for the standard door width, `TraversalGenerator.DOOR_WIDTH_M`; a wider door slides along the facade until it fits). Placement rules — stacked or sparse, sill, gap — stay on the building archetype; the wall's thickness (`wall_thickness_m`) too, because it is the wall's, not the piece's. Each piece declares its **arch** (`arch_height_m`, `arch_segments`), which is a property of the opening it leaves in the wall (see [city-generation.md](city-generation.md#two-meshes-per-building-the-semantic-one-and-the-skin)); in the game scene window openings are off for cost (`City.window_openings`), in the sandbox they are on.

**Where this is going** (documented, not built): like a real building, one type per *pseudo-category* — street windows, alley windows, bathroom windows (smaller), ground-floor windows — chosen once and repeated, and within a type each window varying slightly with its own seed (flower pots, a broken shutter). That per-individual variation is what makes it believable, and it is what `WindowArchetype.build(seed)` will show in the sandbox. Today the piece is a panel and the seed changes nothing.

## Deliberate limits

- The sandbox `City` nodes join the `city_generator` group like the real one.
- Headless the sandbox generates and places everything (three blocks, ~90 ms each); at teardown it may segfault like the game does — Jolt RID leaks, not a code bug.
