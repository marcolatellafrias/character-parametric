# Ship Gameplay — The Company Ship

The in-ship half of the loop: players cooperate at the piloting dashboards to move the ship between delivery points, while dodging other flying vehicles. See [00-overview.md](00-overview.md) for how ship and on-foot gameplay alternate.

---

## The company ship

A **flying ship** the players use to move packages quickly across the city. Two hulls are being tried side by side — a **glass dome** and a **box** — around the same interior. Components:

- **Main door** — at the **back**, opened and closed with a button **inside and one outside**: in the dome, the lower panels of its three back segments **slide up along the dome**; in the box, a door that **shrinks upward**.
- **Dashboards** — collections of controllables ([interactables.md](interactables.md)) for either moving/controlling the ship or performing actions like repairs. Arranged as a **partial ring** against the hull, all round except by the main door. Partial because the main-door side has no dashboards, and there's a gap between the main door and the dashboards.
- **Cosmetic slots** — empty spaces on the dashboards or floor where players place cosmetic items (bought with money — see [run-setup.md](run-setup.md)).
- **Cargo zone** — where packages are loaded (below).
- **Ship manual** — a fixed, **non-movable** interactable at a set spot on the dashboards; players read it to know what to repair (see [Damage & repair](#damage--repair)).

### The four ships

A player's four ships (one per crew size — see [Ownership & persistence](#ownership--persistence)) are the **same size**. Two things differ between them:

- **Seats** — how many, and where.
- **Dashboards** — how many, and how they are laid out. Every control beyond the ones that fly the ship is a **repair** control.

### Measured in dashboard cells

The ship's unit is the **dashboard cell**, not the metre: a `0.04 m` square, with no gap. It is small on purpose — a control spans many cells (a button 2 × 2, a lever 6 × 12, the wheel 12 × 12), so controls can be as small as real ones and everything can be placed precisely. Finer would add nothing: 4 cm is about the smallest target the centre crosshair hits reliably at arm's length. Measuring the hull in the same unit keeps every side of the console ring holding a whole number of cells.

**The dome** is the **upper half of a UV sphere** on a flat floor of the same plan: 42 segments around — the floor has the same 42 sides, so their edges meet — and 8 rings from the floor to the pole, each face a flat plate. The **floor ring**, the **top cap**, the door and the row of faces just above it are opaque, a light, faintly reddish grey — the floor is a darker shade of it, to tell them apart —; everything else is **glass**, from 0.98 m up to the cap at 4.94 m — a window all round, so there are no window openings. Thin **frames** in the same reddish grey divide the glass, visual only: one horizontal all the way round at half height (45°, 3.84 m), and three vertical, evenly spaced every 120° and symmetric about the ship's axis — two at ±60° from the front, from the floor ring up to the middle frame, keeping the pilot's pane clear, and one on the axis at the back, from the middle frame up to the cap, continuing the line of the door and the opaque row above it. The vertical ones run along the middle of the faces: with 42 segments, one every 14. The opaque faces are drawn as whole plates — both skins and their edges — showing their 0.16 m thickness, with the outer skin flush with the floor's edge, so the dome is exactly as wide as the base. The glass is a flat pane at that outer skin, seen from both sides, with a shader after a Godot-forum recipe — the sun's specular highlights on top, and a strong gradient, clear at the bottom and dark and nearly opaque toward the cap, both sides lit with the pane's outer normal so it looks the same from inside and out —; its collider starts at the pane and goes outward, so from inside you touch the glass where you see it. The dome's faces — glass and opaque plates alike — are **shaded smooth**: every vertex takes the sphere's normal, so the light flows across faces without a seam even though each face is its own object. The plates' cut edges, the frames and the floor stay flat.

**The box** is a 252 × 126 × 252-cell room (10.08 × 5.04 × 10.08 m) — the dome's footprint and height — of opaque blocks, with the original cubic design's front window and back door (scaled up with the room, the window would sit above the pilot's eyes). Its walls, ceiling and door are drawn half-transparent by default, so the crew can be watched from outside (**Acciones → Nave: paredes traslúcidas**). Each face is its own object: Godot sorts transparency per object, so a single-mesh dome would draw back faces over front ones from inside. The faces and the door follow from the segments, so they don't land on whole cells.

The dashboards form a **partial ring against the hull**, facing the centre: consoles edge to edge in a regular polygon, as far out as their shelves allow, and every side carries a console except those that would cut into the cargo corridor from the door, which is the gap the ring leaves there. The ring doesn't follow the hull's segments; its shape suits the hull. In the round dome it is as many 32-column consoles as fit — **21 sides**, 4.25 m from the centre, **19 of them with modules**, about 325° of the way round. In the square box it is an **octagon** — four sides facing the walls, four cutting the corners, so little space is left in them — of 80-column sides: **7 sides**, 3.86 m from the centre.

**Modules.** Each side is a straight run of **modules**, each a type and a width in columns: the dome's sides are one 32-column module, the box's three — 24 + 32 + 24. The middle one is the **main** module: a lectern the seat faces, and on the front side the one with the flight panel. The types:

- **Lectern** — the common console described below.
- **Tall cabinet** — a 2 m block with its panel on the vertical front face, at a standing player's height (0.90–1.86 m).
- **Short cabinet** — waist-high (0.95 m at the front), its panel on top, tilted 15° toward the user; the front face is kept for later.
- **Overhead** — optional, above a module: a block on the wall over the seated player, whose lower inner edge is cut at the lectern's 45°, mirrored, into a panel facing down at them. Its lowest point is 1.45 m up, so the shortest archetype reaches it seated without it grazing their head.

Every module is built **against the wall**: the hull says how far out one can build at each height, and each module reaches it — straight in the box, sloping with the curve in the dome. For now the layout is hardcoded per hull (seats face lecterns with an overhead; the box puts short cabinets beside the walls and tall ones on the diagonals), and every panel except the flight one carries **dummy controls** — small and large buttons, small and large knobs (3 and 6 cells across; the wheel is 12), scattered with a cell of air between them — to see how it reads. Cabinets are worked **standing**, which in flight depends on standing aboard a moving ship (open — see below). Each console is a grid of **empty slots** that gets filled with controls, built from plates: the dashboard, as deep as the wheel and tilted 45° from vertical; a **lower plate** inclined back to the floor, leaving room for the knees so the seat sits close; and a flat **cosmetic shelf** from the dashboard's top edge to just short of the wall (at least 0.3 m, which is what limits how far out the ring goes).

Starting measurements, to be tuned by playing:

| | cells | metres |
|---|---|---|
| Dome radius (inside) | 126 | 5.04 — about twice the old cube's length across; its 0.16 m plates end flush with the floor |
| Dome door (three segments × 3 rings, at the floor) | — | 2.24 × 2.80 |
| Box interior (W × H × L) | 252 × 126 × 252 | 10.08 × 5.04 × 10.08 |
| Box door | 48 × 56 | 1.92 × 2.24 |
| Box front window (W × H), sill 24 cells up | 80 × 48 | 3.20 × 1.92 |
| Main module / box side module (columns) | 32 / 24 | 1.28 / 0.96 |
| Tall cabinet / short cabinet (height) | — | 2.00 / 0.95 |

The ring's apothem follows from its sides and the columns per side: `a = columns · 0.04 / (2 · tan(180° / sides))` — 4.25 m for the dome's 21 × 32, 3.86 m for the box's 8 × 80. The dome takes the most sides that fit.

## Cargo zone

The zone packages are loaded into. It acts as a **barrier**: when the ship moves suddenly and packages slide around, they stay constricted to this zone and never interfere with players at the dashboards. **Players can cross the barrier; packages cannot** — a sort of force field.

The cargo zone is the union of two zones of equal height:

- A **cylinder** at the center of the ship interior.
- A **cube** with the width of the main door, running from the main door to the cylinder's center.

The cylinder's diameter equals the main door's width (2.24 m in the dome, its three door segments at the floor; 1.92 m in the box).

Package physics and stats are defined in [objects.md](objects.md).

---

## Ownership & persistence

Ships are **host-owned and persistent**, like employees. Each player keeps a **roster of four ships** — one per host crew-size (**1 / 2 / 3 / 4 players**) — and a run uses the host's ship **for the current player count** ([people.md](people.md#player)). Each of the four has its **own seed, dashboard, cosmetics, and damage** — nothing shared between them. Because the ship is *selected* by crew size rather than reshaped by it, its **dashboard stays consistent** no matter who joins — which is what lets players actually learn their ship.

To close a shift the ship must be **parked in the branch's ship zone** ([run-setup.md](run-setup.md#match-lifecycle)). **Destroying the ship ends the run** — it is never respawned mid-run. On restart that roster slot regenerates a **brand-new ship** (new seed → **new dashboard**, no cosmetics, no damage). This is a real penalty: the crew loses their cosmetics, **every player takes penalty points**, the wreck is logged as **company property damage** ([people.md](people.md#penalty-system)), and they must **re-learn an unfamiliar dashboard and manual** together.

---

## Piloting

Players control the ship through the dashboard controllables ([interactables.md](interactables.md) → ship section). Multiple players can share piloting/repair duties.

### Movement controls

The ship flies with **four controls** — three behaving like a helicopter, plus acceleration:

- **Altitude** — one-axis lever; raises/lowers the ship.
- **Yaw** — steering wheel; rotates it left/right.
- **Pitch** — one-axis lever; tilts the nose up/down.
- **Acceleration** — one-axis lever; unlike the helicopter-style three, it just drives the ship **forward in the direction it faces**, faster or slower.

### Control layout

Each ship's **control layout** — which control sits where across the dashboards, plus its **seat count** — is **fixed**, generated from that **ship's seed**. It never shifts as players come and go: crew size instead **selects which of the host's four ships** is used ([Ownership & persistence](#ownership--persistence)), and each is a different, fixed dashboard. This asymmetry — who can reach what — drives the whole piloting flow, and its **consistency** is what lets a crew actually **learn their ship**. Damage is tracked **per function** (e.g. "yaw inverted"), so a breakage sticks to that ship's controls (see [Damage & repair](#damage--repair)).

**Control scheme (coded today):** a player looks at a dashboard control and holds **LMB** to engage it, releasing to let go. While engaged, **mouse drag** moves one-axis levers (along their axis) and two-axis joysticks; the **scroll wheel** rotates a valve/wheel or, for a free-held object, pushes/pulls it; **RMB** switches a grabbed object into free-rotate mode. Touch buttons fire on press (momentary) or flip on each engage (toggle). Levers and joysticks can auto-return to a rest value or snap to discrete positions, and each control exposes its normalised value through `state_changed` for downstream systems to read.

*(Wired in the [prototype](#prototype-coded-today): altitude, yaw and acceleration drive the ship. Pitch and the repair mini-mechanics don't exist in code yet.)*

### Flight model

The ship is a physics body that keeps itself level:

- **Altitude by target, not by force.** The altitude lever raises or lowers a **target altitude** and the ship eases toward it. The target is a **global** height, not a height above the ground: in a city of bridges and floating sidewalks, "above the ground" jumps every time the ship passes over something. Letting go of the lever holds the altitude — which is the idle the loop relies on: the ship **hovers in place** while part of the crew delivers on foot, with nobody at the controls.
- **Acceleration** pushes along the ship's facing; **yaw** turns it about the vertical.
- **Anti-drift** brakes sideways velocity, so it flies rather than skates.
- **Self-righting** keeps the floor level.

For now the ship **does not bank into turns or tilt when accelerating**: with an interior, tilting the ship tilts the floor, and the crew's capsules have zero friction. Tilt can come back later, on purpose, if cargo should shift in turns.

| Function | Control | Behaviour |
|---|---|---|
| Altitude | lever that springs back to centre | off-centre moves the target altitude; released holds it |
| Yaw | wheel that springs back to centre | turned = the ship turns |
| Acceleration | lever that stays where it is left | a cruise throttle: it sets the forward speed |
| Pitch | — | not in the prototype |

**Piloting is seated** for now.

### Standing aboard a moving ship — open

Not solved yet, which is why the prototype is flown seated. A character is a zero-friction rigid body whose movement is computed from its *world* velocity, so on a moving floor "standing still" means being left behind. Three ways out were weighed:

- **Velocity relative to the floor** *(preferred)* — the character reads the velocity of what it stands on (it already has a ground ray) and moves relative to it. One physics world, so the door, jumping out mid-flight, grabbing across the door and cargo sliding in a jolt all work without special cases. Two catches: impact detection must use relative velocity too, or every jolt knocks the crew down; and players must be synced in ship-local coordinates while aboard, or observers see them swim on the deck.
- **Carrying by transform while inside** — fastest to get working, but writing a dynamic body's transform fights Jolt (the launches documented in [multiplayer.md](multiplayer.md)), cargo stops sliding, and the in/out edge cases are the common case in this loop.
- **A separate, static interior world** — perfectly stable at any speed, but crossing the door means moving bodies between physics spaces, and crossing the door is the core of the loop.

---

## Interactable components

Everything a player operates at the dashboards is one of **four kinds** ([interactables.md](interactables.md)):

- **Control** — flies the ship: the steering wheel, the altitude / pitch / acceleration levers.
- **Information** — reports state without input: e.g. the **radar**.
- **Repair** — used to fix breakages *(specifics TBD)*.
- **Interactive information** — read or heard by a player, engaged with **E** ([interactables.md](interactables.md#information-interactables)): the **ship manual**, **phones** *(phones TBD)*.

---

## Damage & repair

The ship takes **damage** (breakages) from crashes and hits, and that damage is **persistent** (see above) — it stays until repaired. If integrity reaches **zero the ship is destroyed**, ending the run ([run-setup.md](run-setup.md#losing-the-run)).

A breakage degrades a specific system:

- **Altitude** — responds more slowly.
- **Yaw** — **inverted** (steering reversed).
- **Pitch** — less effective.
- **Acceleration** — less effective.
- **Integrity** — reduced durability, toward eventual **destruction** (run end).
- **Information systems** — e.g. the **radar** goes down.

Breakages are fixed **in flight, at the dashboards**: a repair is a sequence of dashboard-controllable actions ([interactables.md](interactables.md)). To know **what** to fix and **how**, players read the **ship manual** — a fixed interactable at a set place on the dashboards. Because the manual **cannot be moved**, only the player standing at it can read it, while others work the controls it describes. This deliberate **asymmetric information** forces the crew to talk and coordinate ("valve three, then the left lever") — a core co-op tension, by design, not an accident.

---

## Prototype (coded today)

A ship built from **primitive pieces** until the real model exists, each piece a different colour (except the dome: glass, and a reddish-grey structure and floor). `Ship` (`Scripts/ship/ship.gd`) is the body and the flight model; `ShipHull` is what every hull shares — the console ring, the seats and the door buttons — and `DomeHull` and `BoxHull` add each shape's shell, floor and door motion; `ShipDoor` opens and closes the main door from its buttons, moving it however the hull says. There is one working panel, the front main module, with altitude, yaw, acceleration and a **power button**; every other panel carries dummy controls. The ship starts **off**: off, it applies no force of its own and rests wherever it is (switched off in the air, it falls); switched on, it holds the height it is at. Buttons click and the ship hums while on — **test sounds**, generated in code (`TestSounds`), to be deleted when real audio arrives.

It comes in four versions from the debug panel — **Spawn → Nave domo** or **Nave cúbica**, each **(1 jugador)** or **(4 jugadores)**: one seat, the pilot's at the front console, or four — three more, at consoles −4, +4 and +7 in the dome and −2, +2 and +3 in the box (their consoles still empty; not symmetric on purpose). Each seat faces its console at the pilot's distance. Several ships can coexist — each new one lands clear of the others — and **Spawn → Limpiar spawns** removes them all. Spawned locally: `NetSpawner` attaches network sync and a grab handle to every rigid body it spawns, which would make the ship grabbable. **Not networked yet.**

---

## Special vehicles (flying obstacles)

Other vehicles fly through the city and act primarily as **obstacles to avoid while piloting** (they can also serve other roles on foot — e.g. cargo motorcycles you can ride through an alleyway, see [onfoot-gameplay.md](onfoot-gameplay.md)):

- Ambulance
- Police vehicle
- Cargo motorcycle
- Vending truck

> The ambient traffic simulation (the flying cars that populate the city) is a **technical** system documented in [traffic.md](../technical/traffic.md).
