# People — Persons, Pedestrians, Players & Employees

Every character in Nuevos Aires derives from a shared **Person** abstract class. Players control **Employees**; **Pedestrians** are the main on-foot obstacle. **Players** are the persistent accounts that own employee rosters.

Movement stats defined here feed the on-foot systems in [onfoot-gameplay.md](onfoot-gameplay.md).

---

## Person (abstract)

A persistent person in this world, with physical and visual stats. Can be an employee or a pedestrian — they share this abstract class.

### Physical stats

- **Equilibrium** — a radial threshold that, if overflowed, makes the person lose balance and fall, dropping whatever they're grabbing/controlling. Triggered by crashing into a wall while moving, getting hit by an object, falling far, or bumping another person. The base threshold is **derived from weight and height** — more **weight** (inertia) raises it, more **height** (higher centre of mass) lowers it — so a heavy, stocky worker resists knocks while a tall, light one topples easily; no separate stability stat is needed. How fast they *recover* is per-archetype (spring/damp). Implemented as a PD controller checking speed difference between frames. *(Frame-dependent today — must change for online sync.)*
- **Height** — cm, from `1.4` to `2.1`. Also feeds **equilibrium** (taller = easier to topple).
- **Reach** — normalized `0.5`–`1.5` (not cm; final cm value derives from this and height via a formula, TBD). Drives grab distance ([grab system](onfoot-gameplay.md#grab-system)).
- **Weight** — `30.0`–`150.0`. Double-edged: more weight raises **equilibrium** (harder to topple) but makes the person heavier to shove and to carry.
- **Strength** — how much weight the person can lift, `10.0`–`100.0`. Governs how easily they move heavy [objects](objects.md) and how fast they turn valves.
- **Speed** — max non-sprinting speed.
- **Sprint multiplier** — `speed × sprint_multiplier` = max sprint speed.
- **Acceleration** — how fast they gain speed (walking or sprinting).
- **Jump strength** — the peak jump impulse (scaled by the person's mass); higher jumps higher.
- **Time to max jump** — how long the jump must be charged to reach that peak; shorter means snappier jumps.

### Capability (derived)

A single normalised score of how good a person is **at the job** — carrying packages, moving through the city, staying upright. It blends the work-relevant physical stats: **strength** (heavier cargo, faster valves), **speed / sprint / acceleration** (traversal), **reach** (grab range), **jump strength & time-to-max-jump** (parkour), and **equilibrium/stability** (resisting falls). Roughly `0` = an old, weak, slow dreg; `1` = a fast, strong, sure-footed prime worker — **age biases it down**.

It is the shared currency of two systems: the **crew factor** that prices packages (a lower-capability crew is paid more — [objects.md](objects.md)), and the **reputation** clamp on new hires (see [Player](#player)).

### Visual stats

- **Hair** (string id)
- **Suit** (string id)
- *(More to come.)*

### Misc stats

- **Age** — decided *before* the physical attributes, because it biases their randomness (an old man is likelier slower, weaker, etc.).
- **Name** — real-life first name and surname.

---

## Pedestrian

Inherits from Person. The main on-foot moving obstacle to avoid. Bumping into a larger pedestrian means more pushback. They follow a **deterministic path** (like cars) that changes if they're pushed/fall/die. They have instances and **health** — at 0, they die.

Two spawn/despawn modes:

- **Door spawn/despawn** — outside the player's pedestrian radius and hidden from sight, they can instantly spawn at an alleyway/sidewalk.
- **Hidden spawn/despawn** — inside the player's pedestrian radius, they spawn/despawn by exiting/entering a [door](onfoot-gameplay.md#doors). Spawning right next to the player pushes him aside via the door's impact.

---

## Player

A player (the human account) has:

- **Id** — unique, never changes; used as the seed source (the Steam id — a number).
- **Player seed** — derived from the id; generates initial employees and the preferred company.
- **Employee list** — all employees ever connected to this player (see rosters below).
- **Preferred company** — the company a run defaults to when this player hosts. Defined deterministically from the player seed and **cannot change**. See [run-setup.md](run-setup.md).
- **Ship roster** — **four** host-owned company ships, one per host crew-size (**1, 2, 3, 4 players**): when this player **hosts**, the ship for that crew size is used. Each has its own **seed** (→ a fixed dashboard & seat count), **cosmetics**, and **damage** — **none shared**. A destroyed ship regenerates in its slot with a new seed. See [ship-gameplay.md](ship-gameplay.md#ownership--persistence).
- **Player reputation** — a hidden, slow player-level value: the company's goodwill toward this account. It **decays toward neutral over time** and only sinks on a *pattern* of abuse — employees dying or being fired on your watch, property damage. A low reputation **clamps the [capability](#capability-derived) of newly-generated employees toward the low end**: churn workers and the company hands you dregs. This is the disincentive against suiciding to reroll an employee — the reroll is never a fresh chance up, only down (and though a weak crew is *paid* more by the crew factor, being stuck with dregs, worse at the job, is the real cost). *(Name tentative.)*

### Spawn radii

- **Pedestrian spawn radius** — the smallest radius; inside it pedestrians can't hidden-spawn, only door-spawn.
- **Car spawn radii** — *(TBD; see the traffic/fog zone radii in [traffic.md](../technical/traffic.md#fog-and-zone-radii-areainstantiator).)*

### Rosters

On a player's first play, a roster of **6 active employees** is generated automatically — one per schedule of each company — from the player seed and a generation index, so it's fully deterministic and unique per player.

A player must keep **6 active employees at all times** to cover all 12 company-schedule combinations. If an employee becomes temporarily unavailable (suspension / medical leave / misc event), the system tries to reuse an already-generated employee who last worked for the same company (not dead, not employed elsewhere); if none exists, it generates a new one. When the original can work again, the substitute goes inactive.

**Which employee a player joins a game as** depends on:

- The host's preferred company.
- Which employee currently holds that shift at that company (by real Buenos Aires time at that moment).

The roster — **active** and **temporarily-inactive** employees — is legible in the branch **Lounge** (a ledger), and the **dead** are on its **memorial** ([run-setup.md](run-setup.md#the-lounge)). But which substitute the system fields after a death is **never shown**: if several are already generated, the pick stays a mystery, on purpose.

---

## Employee

Inherits from Person; playable, and works for one of the three companies. Extra variables:

- **Seed value** — the unchangeable initial seed used to generate the employee's stats. Derived from the generation index and the player id.
- **Generation index** — which "i-th" employee this is for the user.
- **Money** — the employee's persistent savings, earned/lost at end of shift ([run-setup.md](run-setup.md)). Tied to the **employee, not the player**: a player's different employees each keep their own money, and it is **lost when the employee dies or is fired**.
- **Person cosmetics** (hats, etc.) — bought with the employee's money and, like it, **owned by the employee**: they follow this employee and are lost when they die or are fired. (Ship cosmetics instead belong to the host's ship — see [ship-gameplay.md](ship-gameplay.md).)

### Current employment

- **Current company** — can be null (firing, death, etc.).
- **Schedule** (enum: night / day shift) — the defined shift for the current company; non-null only if employed or suspended. Two employees of the same player can never simultaneously hold the same company **and** schedule.
- **Wife** — null, or her full name.
- **Kids** — an int count.

### Company events timeline

For each company, a list of events:

- **Start** — day the event starts.
- **End** — day it ends (nullable; present only for durational events like suspension or medical leave).
- **Event enum** — started working, fired, death, suspension, medical leave, misc leave.
- **Misc leave info** (misc-leave only — random, not player-caused, hence separate):
  - **Cause** (enum): marital problems, paternity leave, depression. *(Will expand.)*
- **Death info** (death only):
  - **Cause** (enum): shot, fell, crushed.
  - **Entity**: crushed-by / shot-by object-or-entity enum.
- **Injury info** (medical-leave only):
  - **Area affected** (enum): left eye, right eye, head, right arm, left arm, left leg, right leg.
  - **Injury** (enum, by part): eye → cut / bullet; leg → broken bone / cut / bullet; arm → broken bone / cut / bullet; torso → bullet; head → concussion / bullet.
  - **Cause**: shot, fell, crushed.
  - **Entity**: crushed-by / shot-by object-or-entity enum.

---

## Penalty system

Ties day-to-day performance to the employment lifecycle above.

- Lost packages, damaged-but-delivered packages, and killed/damaged pedestrians in a day add **penalty points** to the player.
- **Destroying the company ship** adds penalty points to **every** player, loses all that ship's cosmetics, and is logged as **company property damage**; the ship's roster slot then regenerates with a new seed — a new dashboard to re-learn (see [run-setup.md](run-setup.md), [ship-gameplay.md](ship-gameplay.md#ownership--persistence)).
- Each passing day automatically **deducts** some penalty points, so they don't accumulate forever.
- Above a threshold: the employee is **fired the next day**. There is **no mid-run / instant firing** — the consequence always lands between days.
- Penalty points are never shown on the HUD ([hud.md](hud.md)). They surface **diegetically and delayed**: the **next day**, the employee's **observations** — and whether they were fired — appear on the branch **bulletin board**. You have to wait for the report to know where you stand.

Damage/kills are produced during [on-foot gameplay](onfoot-gameplay.md); money earned/lost is settled at end of shift in [run-setup.md](run-setup.md).
