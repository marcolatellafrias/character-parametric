# Ship Gameplay — The Company Ship

The in-ship half of the loop: players cooperate at the piloting dashboards to move the ship between delivery points, while dodging other flying vehicles. See [00-overview.md](00-overview.md) for how ship and on-foot gameplay alternate.

---

## The company ship

A **glass-domed flying ship** the players use to move packages quickly across the city. Components:

- **Main door** — the lower part of the dome's three **back** segments: its panels **slide up along the dome** to open, from a button **inside and one outside**.
- **Dashboards** — collections of controllables ([interactables.md](interactables.md)) for either moving/controlling the ship or performing actions like repairs. Arranged as a **partial ring** against the glass, all round except by the main door. Partial because the main-door side has no dashboards, and there's a gap between the main door and the dashboards.
- **Cosmetic slots** — empty spaces on the dashboards or floor where players place cosmetic items (bought with money — see [run-setup.md](run-setup.md)).
- **Cargo zone** — where packages are loaded (below).
- **Ship manual** — a fixed, **non-movable** interactable at a set spot on the dashboards; players read it to know what to repair (see [Damage & repair](#damage--repair)).

### The four ships

A player's four ships (one per crew size — see [Ownership & persistence](#ownership--persistence)) are the **same size**. Two things differ between them:

- **Seats** — how many, and where.
- **Dashboards** — how many, and how they are laid out. Every control beyond the ones that fly the ship is a **repair** control.

### Measured in dashboard cells

The ship's unit is the **dashboard cell**, not the metre: a `0.04 m` square, with no gap. It is small on purpose — a control spans many cells (a button 2 × 2, a lever 6 × 12, the wheel 12 × 12), so controls can be as small as real ones and everything can be placed precisely. Finer would add nothing: 4 cm is about the smallest target the centre crosshair hits reliably at arm's length. Measuring the hull in the same unit keeps every side of the console ring holding a whole number of cells.

The hull is the **upper half of a UV sphere** on a flat floor of the same plan: 32 segments around — the floor has the same 32 sides, so their edges meet — and 8 rings from the floor to the pole, each face a flat plate. The **floor ring**, the **top cap** and the door are opaque, one dark colour; everything between is clear **glass**, from 0.90 m up to the cap at 4.51 m — a window all round, so there are no window openings. The opaque faces are drawn as whole plates — both skins and their edges — showing their 0.16 m thickness, with the outer skin flush with the floor's edge, so the dome is exactly as wide as the base. The glass is a flat pane at that outer skin, seen from both sides; its collider starts at the pane and goes outward, so from inside you touch the glass where you see it. Each face is its own object: Godot sorts transparency per object, so a single-mesh dome would draw back faces over front ones from inside. The faces and the door follow from the segments, so they don't land on whole cells.

The dashboards form a **partial ring against the glass**, facing the centre. It doesn't follow the dome's segments: it is as many 32-column consoles edge to edge as fit with their shelves clear of the glass — **19 sides**, 3.84 m from the centre — and every side carries a console except those that would cut into the cargo corridor from the door, which is the gap the ring leaves there: **15 consoles**, about 285° of the way round. Each console is a grid of **empty slots** that gets filled with controls, built from plates: the dashboard, as deep as the wheel and tilted 45° from vertical; a **lower plate** inclined back to the floor, leaving room for the knees so the seat sits close; and a flat **cosmetic shelf** from the dashboard's top edge to just short of the glass (at least 0.3 m, which is what limits how far out the ring goes).

Starting measurements, to be tuned by playing:

| | cells | metres |
|---|---|---|
| Dome radius (inside) | 115 | 4.60 — a tenth under twice the old cube's length across; its 0.16 m plates end flush with the floor |
| Main door (three segments × 3 rings, at the floor) | — | 2.67 × 2.56 |
| Console panel (columns × rows) | 32 × 12 | 1.28 × 0.48 |

The ring's apothem follows from each side holding exactly thirty-two columns: `a = 32 · 0.04 / (2 · tan(180° / 19)) ≈ 3.84 m`. Nineteen is the most sides that fit: one more and the ring grows past the glass.

## Cargo zone

The zone packages are loaded into. It acts as a **barrier**: when the ship moves suddenly and packages slide around, they stay constricted to this zone and never interfere with players at the dashboards. **Players can cross the barrier; packages cannot** — a sort of force field.

The cargo zone is the union of two zones of equal height:

- A **cylinder** at the center of the ship interior.
- A **cube** with the width of the main door, running from the main door to the cylinder's center.

The cylinder's diameter equals the main door's width (2.67 m, the door's three segments at the floor).

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

A one-player ship built from **primitive pieces** until the real model exists: a glass dome of flat faces over a round floor, and consoles made of plates, each piece a different colour except the dome, whose glass is clear and whose opaque shell is one dark colour. `Ship` (`Scripts/ship/ship.gd`) is the body and the flight model; `ShipHull` builds the dome, the console ring and the door buttons; `ShipDoor` is the main door — the lower faces of the three back segments, which slide up along the dome to open, from a button inside and one outside. There is one working console, the front one, with altitude, yaw, acceleration and a **power button**; the other fourteen consoles are empty slots. The ship starts **off**: off, it applies no force of its own and rests wherever it is (switched off in the air, it falls); switched on, it holds the height it is at. Buttons click and the ship hums while on — **test sounds**, generated in code (`TestSounds`), to be deleted when real audio arrives.

It comes in two versions, spawned from the debug panel: **Spawn → Nave (1 jugador)**, with the pilot's seat at the front console, and **Nave (4 jugadores)**, the same ship with three more seats, at consoles −4, +4 and +7 (their consoles still empty; not symmetric on purpose). Each seat faces its console at the pilot's distance. Spawned locally: `NetSpawner` attaches network sync and a grab handle to every rigid body it spawns, which would make the ship grabbable. **Not networked yet.**

---

## Special vehicles (flying obstacles)

Other vehicles fly through the city and act primarily as **obstacles to avoid while piloting** (they can also serve other roles on foot — e.g. cargo motorcycles you can ride through an alleyway, see [onfoot-gameplay.md](onfoot-gameplay.md)):

- Ambulance
- Police vehicle
- Cargo motorcycle
- Vending truck

> The ambient traffic simulation (the flying cars that populate the city) is a **technical** system documented in [traffic.md](../technical/traffic.md).
