# Ship Gameplay — The Company Ship

The in-ship half of the loop: players cooperate at the piloting dashboards to move the ship between delivery points, while dodging other flying vehicles. See [00-overview.md](00-overview.md) for how ship and on-foot gameplay alternate.

---

## The company ship

A **cubical flying ship** the players use to move packages quickly across the city. Components:

- **Main door** — an elevating door at the **back** of the ship, opened/closed with a button.
- **Dashboards** — collections of controllables ([interactables.md](interactables.md)) for either moving/controlling the ship or performing actions like repairs. Arranged as a **partial octagon ring** around the interior perimeter. Partial because the main-door side has no dashboards, and there's a gap between the main door and the dashboards.
- **Cosmetic slots** — empty spaces on the dashboards or floor where players place cosmetic items (bought with money — see [run-setup.md](run-setup.md)).
- **Cargo zone** — where packages are loaded (below).
- **Ship manual** — a fixed, **non-movable** interactable at a set spot on the dashboards; players read it to know what to repair (see [Damage & repair](#damage--repair)).

## Cargo zone

The zone packages are loaded into. It acts as a **barrier**: when the ship moves suddenly and packages slide around, they stay constricted to this zone and never interfere with players at the dashboards. **Players can cross the barrier; packages cannot** — a sort of force field.

The cargo zone is the union of two zones of equal height:

- A **cylinder** at the center of the ship interior.
- A **cube** with the width of the main door, running from the main door to the cylinder's center.

The cylinder's diameter equals the main door's width.

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

*(Not yet wired: the binding from those control values to actual ship movement — thrust/steering — and the repair mini-mechanics don't exist in code yet. The dashboards currently drive only their own visuals and emit state.)*

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

## Special vehicles (flying obstacles)

Other vehicles fly through the city and act primarily as **obstacles to avoid while piloting** (they can also serve other roles on foot — e.g. cargo motorcycles you can ride through an alleyway, see [onfoot-gameplay.md](onfoot-gameplay.md)):

- Ambulance
- Police vehicle
- Cargo motorcycle
- Vending truck

> The ambient traffic simulation (the flying cars that populate the city) is a **technical** system documented in [traffic.md](../technical/traffic.md).
