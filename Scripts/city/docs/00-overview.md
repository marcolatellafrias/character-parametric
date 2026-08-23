# Nuevos Aires Delivery — Overview

A co-op delivery game for **1–4 players**, set in **Nuevos Aires**: a 1900–1920 retrofuturistic alternate-reality Buenos Aires of Italian architecture, analog technology, flying cars, tango, ragtime, occultism, and endless advertisements.

Players work for one of three delivery companies, piloting a cubical flying ship across the city and going out on foot into alleyways to hand-deliver packages before the company's patience runs out.

---

## The gameplay loop

1. **Host & join.** One player hosts. The run uses the host's *preferred company* (see [people.md](conceptual/people.md)). The host invites friends; new players can keep joining until the crew crosses from the Lounge into the garage, which locks the crew (see [run-setup.md](conceptual/run-setup.md)).
2. **Spawn at headquarters.** Players spawn inside one branch of the delivery company, with the company ship in the garage and a set of choosable packages laid out with their delivery instructions (street, building, floor/apartment) and prices.
3. **Plan the load.** Players decide *together* which packages to take. Packages vary — heavier, more fragile, bigger/smaller, time-constrained, or with special effects (some move on their own). This is the first strategy tension. They grab the chosen packages ([objects.md](conceptual/objects.md), grab system in [onfoot-gameplay.md](conceptual/onfoot-gameplay.md)) and load them into the ship's **cargo zone** — a limited cube at the ship's center ([ship-gameplay.md](conceptual/ship-gameplay.md)).
4. **Fly.** Inside the ship, players cooperate on the piloting dashboards ([interactables.md](conceptual/interactables.md)) to move toward delivery points.
5. **Go on foot.** Most delivery points sit inside alleyways the ship can't enter. Here's the core tension: who leaves the ship to carry the package? Do all park and walk (heavy/large package)? Does one player keep the ship idling while others deliver, ready for a fast takeoff? Do they drop a player with a package, move the ship to the next point, and swing back to collect them?
6. **Deliver, then close the shift.** Players alternate between in-ship and on-foot gameplay while the crew's **patience bar** holds — it drains only when they fall behind, and any delivery refills it ([hud.md](conceptual/hud.md)). Any player can **close the shift** at any branch: undelivered packages are lost, money and penalty points settle, and after a rest the next shift begins — harder. A **run** spans many shifts and ends only when the bar empties (game over) or the host leaves. See [run-setup.md](conceptual/run-setup.md).

This is **not a progression game.** The only persistence is money and cosmetics — a small side layer. The draw is the moment-to-moment cooperation and the disposable-workforce simulation, not character growth.

---

## Document index

The docs are split into **conceptual** (game design — the `conceptual/` folder) and **technical** (code-level generation systems — the `technical/` folder).

### Conceptual

| File | What's in it |
|---|---|
| [00-overview.md](00-overview.md) | This file — pitch, gameplay loop, and the index. |
| [conceptual/world.md](conceptual/world.md) | Nuevos Aires setting, day/night cycle, climates, daily & weekly seeds, daily bulletin. |
| [conceptual/run-setup.md](conceptual/run-setup.md) | The three companies, branch headquarters (Lounge + garage), the match lifecycle, package selection, the shift, and end-of-shift money/cosmetics. |
| [conceptual/ship-gameplay.md](conceptual/ship-gameplay.md) | The company ship (doors, dashboards, cargo zone, cosmetic slots), host ownership & persistence, damage & repair (the manual + asymmetric info), piloting, and special vehicles as flying obstacles. |
| [conceptual/onfoot-gameplay.md](conceptual/onfoot-gameplay.md) | On-foot movement, grab/fall/health systems, parkour, facade & alleyway obstacles, barriers, delivery points, doors, vending machines & upgrades. |
| [conceptual/interactables.md](conceptual/interactables.md) | Interactables: controllables (levers/valves/wheels/buttons + dashboards), information interactables (manuals, phones), and seats — one shared engagement model, on ship and on foot. |
| [conceptual/hud.md](conceptual/hud.md) | The HUD: the crew's patience bar (the soft shift clock), player states (injured/dead), and the spectator view. |
| [conceptual/objects.md](conceptual/objects.md) | Objects & packages: nature, durability, value, grab/handle points — shared by ship (cargo) and on-foot (delivery). |
| [conceptual/people.md](conceptual/people.md) | Person stats, pedestrians, players, employees, roster/employment lifecycle, and the penalty→firing system. |
| [conceptual/multiplayer.md](conceptual/multiplayer.md) | The GodotSteam transport, the menuless auto-host/join-over-Steam session model, peers vs persistent players, what needs syncing, and the build milestones. |

### Technical (code-level city generation)

| File | What's in it |
|---|---|
| [technical/city-generation.md](technical/city-generation.md) | Procedural city-generation breakdown: street graph, grids, offsets, building archetypes, chamfers, block hearts, mesh generation, object placement. |
| [technical/sidewalks.md](technical/sidewalks.md) | Sidewalk zones & instances, the sidewalk 3D matrix, delivery doors, and traversal infrastructure (stairs + floating sidewalks). |
| [technical/bridges.md](technical/bridges.md) | Bridge ownership, count, structure, archetypes, and the placement algorithm. |
| [technical/traffic.md](technical/traffic.md) | The ambient flying-car simulation: lane volumes, movement, spawning, collision avoidance, and bridge navigation. |
| [technical/characters.md](technical/characters.md) | The character's two layers (physics capsule vs aesthetic skeleton), the impact→fall model, the ragdoll, the grab/interaction system, the visual-height vs gameplay-height rule, and the decoupling loose ends. |
| [technical/character-animation.md](technical/character-animation.md) | The aesthetic skeleton: seed-driven generation (sizes→bones), the per-frame procedural pose pipeline (locomotion signals, leg IK/steps, procedural animator, arm IK), the full list of pose inputs, and the multiplayer/decoupling analysis (what a proxy re-derives vs must sync, + the known remote-animation bugs). |
| [technical/character-blender-length-variable.md](technical/character-blender-length-variable.md) | **Recipe.** How to author one parametric length variable in Blender end to end (worked on `arms_length`): why the base mesh is the `0.0` extreme, the viewport setup that lets you edit the short arm while watching the stretched one, the driver wiring, what actually ships to Godot, **the midpoint bulge** (why blending two authored extremes does not give the in-between you sculpted, and the curve that fixes it), and the traps — scale inheritance compounding, the On Cage back-solve, the wrong-shape-key mistake. |
| [technical/character-blender-authoring.md](technical/character-blender-authoring.md) | **Plan.** The Blender half of the character: the art style (low-poly silhouette + baked normals, five meshes, gradient textures, Rive facial planes, accessories), the bone-vs-sculpt rule, the seam-weighting invariant, the base-is-minimum convention, and the authoring phases (generic character → lengths → thickness → face → shoulders). |
| [technical/skinned-character-migration.md](technical/skinned-character-migration.md) | **Plan.** Migrating the character from procedural capsule bones to a skinned Blender model: the `Skeleton3D` mirror, the bone-vs-shape-key dividing line, the phased rollout (neutral → lengths → shoulders/head → body → face), the arm-stretch constraint, and name unification. |
| [technical/ui.md](technical/ui.md) | **Plan.** UI layering: the player-facing shell (main menu, pause, options), the tabbed F1 debug panel, a global Valve-style console, the UI-state/mouse owner, and in-match player names. |




