# Characters — Physics, Ragdoll & Grab

How a playable/pedestrian character is built and driven: a **physics capsule** decoupled from an **aesthetic skeleton**, with a ragdoll that bridges them and a grab/interaction system on top. Person stats and archetypes are in [people.md](../conceptual/people.md); the grab-point/range model this shares with world controls is in [interactables.md](../conceptual/interactables.md).

---

## Two layers

A character is two decoupled layers under one **`BoneInstantiator`** (the aesthetic root):

- **Physics** — a **`CharacterRigidBody3D`** (a `RigidBody3D`), child of the BoneInstantiator. Its collider is a **capsule** sized from the character's root box — **never** the bones. All movement, collision, and the camera hang off this body.
- **Aesthetic** — the **skeleton** of `CustomBone`s (the visible, animated model), driven by the procedural animator + `ArmsController`. Purely visual in normal play.

The head bone drives the camera height; yaw is written onto the capsule (`char_rb.rotation.y = camera_yaw`), which stays upright (all three angular axes locked). The split is deliberate: **the bones must never feed the capsule's physics** — see [Decoupling & loose ends](#decoupling--loose-ends).

---

## Physics body — `CharacterRigidBody3D`

- **Capsule** collider + a debug capsule mesh (`show_mesh`) + a downward **ground ray** (`is_grounded`). Frictionless, bounceless, non-sleeping, upright.
- **Movement** is **force-based** (`_apply_movement_force` / `_apply_braking_force`): per-direction max-speed / acceleration / braking, derived at `create()` from the archetype (weight, speed, acceleration, sprint, directional factors) × species multipliers × scale constants. Mass = archetype **weight**.
- **Impact → fall.** `_detect_external_impact` each frame compares the **actual** velocity change to the **expected** one (own forces + gravity); the leftover is an external **impact**. Horizontal impact accumulates into `impact_xz`, a PD-smoothed "stagger"; when it crosses **`ragdoll_threshold` (0.85)** it emits **`fall_triggered`**. Vertical impact tracks separately (`impact_y`). *(Frame-dependent today — flagged for online sync in [multiplayer.md](../conceptual/multiplayer.md).)*
- **Crouch** shrinks the capsule and offsets the ground ray.

---

## Ragdoll — `RagdollUtil`

A pool of per-bone `RigidBody3D`s (one capsule each, sized from the bone's `capsule_dimensions`), built once and kept in sync with the animated bones (`sync_to_bones`). On **`activate`**:

- the capsule goes **inert** — `is_active = false`, collider **disabled**, frozen **static**;
- the skeleton is hidden and the **bone-bodies go dynamic**, seeded with the capsule's velocity + **trip impulses** (upper body forward, legs back, a twist);
- bodies that spawn **overlapping** something are held collision-less until they clear (`_pending_bodies`);
- while active, the **capsule follows** the ragdoll's lower spine (`char_rb.global_position = lower_spine_body.global_position`).

`activate_with_impact` adds momentum from the recorded impact direction. **`deactivate` → recovery**: joints cleared, each bone-body eased back toward its animated bone transform over `recovery_duration`, the capsule teleported to a **collision-free `_find_safe_spawn`** above the lower spine and re-enabled; the skeleton reappears.

---

## Grab & interaction — `InteractionController`

Drives the shared interactable model ([interactables.md](../conceptual/interactables.md)) for this character. Reach thresholds come from the archetype's reach × multiplier: **interact `0.85`**, **grab `0.9`**, **grip `1.0`** (min `0.1`).

- **Grab** (`GrabbableInteractable`): a PD **force** pulls the grab point to `origin + camera_forward × grab_distance`; a PD **torque** matches a target rotation; scroll adjusts distance, RMB free-rotates, **R** charges a throw. Grab strength = archetype **strength × weight × g**. Dropped when the target leaves the **grip** range or the interaction **cone**.
- **Control** (`ControllableInteractable`): `_start_control` binds to the nearest handle point and hands off to the [controllable](../conceptual/interactables.md#controllables) logic; dropped the same way.
- **Effort zone**: holding a grabbed object off-centre past a time threshold flips a **high-effort** state (feeds animation).
- `stop_all()` clears grab/control/throw — called whenever the character **ragdolls, is switched, or respawns**.

---

## Debug affordances (already in code)

`PlayerController` already carries test tools: **G** toggles ragdoll, **P** respawns (regenerating the character from a new seed), numpad keys orbit **debug cameras**, `show_mesh` reveals the physics capsule, and `set_first_person_visibility` hides the aesthetic. These are the seeds of the planned **creative/debug mode** (own doc, TBD).

---

## Decoupling & loose ends

The **intent**: physics is the capsule, aesthetics is the skeleton, and **bone shapes must never affect the capsule's physics**. In normal play this holds. Where it currently leaks:

1. **Ragdoll bodies carry collision at all times.** The per-bone bodies are built on their own layer/mask and kept following the animation even when *not* ragdolling, so bone-shaped colliders exist and can interact with layer-1 physics (the capsule, the world, grabbed objects). **Fix direction:** clean collision-layer isolation — capsule, world, and ragdoll on separated layers, and the bone-bodies **fully inert unless the ragdoll is active**.
2. **During ragdoll the capsule's position is bone-derived** — it follows the lower-spine body and respawns via `_find_safe_spawn` (built from bone positions). That coupling is what makes "the physical part interfere with the aesthetic."

Edge cases to define (for the creative/debug mode and beyond):

- **Creative/fly while ragdolled** — the capsule is frozen static during ragdoll, so entering fly must first **force-deactivate the ragdoll** (or be blocked).
- **Interacting while ragdolled** — `try_interact` still fires on click during ragdoll, but grab forces run in an update that is skipped while ragdolled, leaving a half-started grab. Interaction should be **blocked while ragdolled**.
- **Show/hide the aesthetic on demand** — the machinery exists (bone visibility + the capsule's `show_mesh`), so a debug action can cleanly **swap to "show capsule, hide bones."** A clean decoupling is exactly what makes this trivial.
