# On-Foot Gameplay

The on-foot half of the loop: players leave the ship to carry packages through alleyways to delivery doors, traversing obstacles and barriers. See [00-overview.md](00-overview.md) for how it alternates with ship gameplay. Person movement stats (speed, acceleration, equilibrium, strength, reach) are defined in [people.md](people.md).

---

## Core systems

### Grab system

A player can grab either a **controllable** ([interactables.md](interactables.md)) or an **object/package** ([objects.md](objects.md)) — or **another player** (characters carry a `GrabbableInteractable` too). The grab ray latches onto a **grab point**; valid grab distance depends on the player's **reach**. The grip is lost as soon as the grab point leaves the **conical grip area**.

**Teammate interaction is intended play:** you can grab a teammate, **shove** one (empty-handed **R**), or **throw** a held package — and running into someone while carrying a big package should knock them over (emergent). Several of these are currently broken in multiplayer (proxies have no collision, the throw impulse is lost in the grab handoff) and the grab-force/knockdown magnitudes need tuning — tracked under [multiplayer.md → Pending: on-foot interaction gaps](multiplayer.md#pending--on-foot-interaction-gaps-grouped-by-root-cause).

The ray is cast from the camera each frame while the player is holding nothing, and highlights the nearest interactable in reach. Reach defines **three ascending distance bands** (fractions of the person's **reach** stat): **interact** (`0.85×`) to highlight and engage, **grab** (`0.9×`) where a held object floats (the scroll wheel slides it between `0.1×` and `0.9×`), and **grip** (`1.0×`), beyond which an already-established hold is dropped. The debug reach line colours these green → yellow → orange, and red once out of reach.

The **grip cone** is a cone of `120°` half-angle around the camera's forward axis, measured from the chest. A held object or engaged control whose direction leaves this cone — or exceeds the grip distance — is released. Holding an object out past `0.6` of the cone for more than `0.5 s` flags a **high-effort** state (used to drive strain feedback/animation). Grab strength itself scales with the person's **strength × weight**, so heavier/weaker holds are floppier.

### Fall system

A player can fall due to environmental static or dynamic obstacles. Balance is governed by the person's **equilibrium** stat, acting as a PD controller (see [people.md](people.md)). *(Note: equilibrium is currently frame-dependent — subject to change for online sync.)*

#### Standing up

While ragdolled a player runs a short recovery blend (`RagdollUtil.recovery_duration`) that lerps the loose bones back to the standing pose, then the capsule is grounded (feet snapped to the floor, no launch) and control returns. **You cannot re-ragdoll while standing up** — inputs to fall again are ignored during recovery (no spam). Interacting with, pushing or throwing at a downed/recovering player is also blocked ([multiplayer.md](multiplayer.md), Cause C).

*Planned:* standing up is currently a debug toggle (**G**). It will become **automatic on a timer keyed to the archetype** — `EntityArchetype.time_to_standup` (e.g. the old man is slow, ~longer; the kid pops up fast) — so heavier/frailer people are more punished by a knockdown. The recovery-lock above already models "you're committed to getting up once you start."

### Health system

A person spawns with **100 health**. Health is lost by:

- Falling
- Getting shot
- Getting hit by an object/wall

If an **employee's** health reaches 0, then depending on the cause of death they can be revived or marked **dead forever** in that player's roster ([people.md](people.md)). Pedestrians die when their health reaches 0.

---

## Traversal & parkour

Players climb the city vertically to skip ground obstacles or reach a delivery floor faster than the (deliberately slow) elevators.

### Parkouring

Players can gain height / avoid barriers by climbing facade features. *(Expand.)*

### Verticality contraptions

Physical objects/mechanisms players use to gain verticality — to clear a barrier or reach a delivery height faster than an elevator would.

### Building facade obstacles

Ways to traverse the city vertically on foot.

- **Static:** balconies, shop signs, pipes, air-duct bodies.
- **Dynamic:**
  - **Air vents** that blow in intervals — can unbalance and topple a player who is too light, but also work as parkour stepping stones.
  - **Antennas** — stepping stones, but if stood on too long they fall; heavier players make them fall faster.
  - **Windows** that open randomly and push the player.
  - **Doors** opened by pedestrians.
  - **Garage doors** opened by flying cargo motorcycles.

---

## Alleyways

### Block "laberinth"

Each block has a network of alleyways ([city-generation.md](../technical/city-generation.md)). When a delivery point sits inside an alleyway, some paths are blocked to make reaching it harder — **hard blocks** (e.g. chain-link fence) or **soft blocks** (barriers that take time to cross).

### Alleyway barriers

- **Soft barriers** (passable with a cost):
  - **Chain-link fence with guarded door** — wait a set time to pass the check (can bribe the guard with money).
  - **Steam-powered automatic door.**
- **Hard barriers** (impassable — reroute or parkour around):
  - **Chain-link fence** — cannot cross; take another route or climb over it.

### Alleyway floor-level obstacles

- **Pipe losing steam** — makes the alleyway impassable (pedestrians can still pass) until closed with the **valve**. Stronger employees turn the valve faster.
- **Oil stain** — stepping on it makes a player fall automatically (pedestrians don't).
- **Flying cargo motorcycles** — fly around and can knock you down from a height, but you can jump into their cargo compartment to ride through the alleyway.

### Dynamic alleyway obstacles

Specific ideas TBD — e.g. an air vent that blows in intervals across an alleyway, making players fall/ragdoll.

---

## Delivery

### Delivery points

When a city is generated, delivery points are scattered across it as **doors** ([DOORS](#doors)). Each unique generated package links to one delivery point. **Each block has 8 delivery points.** If a delivery point is at a height/floor, that building spawns with an **elevator** (elevators are very slow — this incentivizes parkour and other faster tactics). Package value depends partly on delivery height — see [objects.md](objects.md).

### Doors

Some floors of some buildings, at specific facade/alleyway-facing cell sides, have doors. Doors serve two purposes:

- **Delivery points** (above).
- **Pedestrian spawns/despawns** — pedestrians exit a spawn door to appear and enter one to disappear (see [people.md](people.md)).

---

## Vending machines & upgrades

- **Vending machines** are scattered across sidewalks. Players buy **upgrades** with money earned at end of shift ([run-setup.md](run-setup.md)).
- **Upgrades** temporarily increase strength, reach, or jumping strength.
