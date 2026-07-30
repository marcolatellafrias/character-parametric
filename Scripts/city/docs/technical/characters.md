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
- **Topple resistance (who falls in a collision).** An impact only *registers* when its Δv exceeds `impact_xz_threshold`, and that threshold is **per-archetype**: `BASE (1.5) × weight/REFERENCE_WEIGHT (60) × directional stability`. So the bar scales with **weight** — a heavy body needs a far bigger hit to fall — and the (previously unused) archetype **stability** stats (`foward/backwards/sideways_stability`) modulate it by hit direction (`_directional_stability`, blended from the local impact vector). The impact **vector stays raw** (fall direction + stagger remain physical); only the *bar* is scaled. Values ≥1 for a stability stat make that direction sturdier than the weight-only baseline; <1 (the current 0.5–0.7) make it easier.
- **Player-vs-player is a soft, non-blocking collision (`_resolve_player_collisions`).** Players **do not rigidly block each other** — every character pair gets a permanent `add_collision_exception_with`, so capsules pass *through* one another (they still collide with world + boxes). Rigid blocking can't give a "plow through and eject" feel and, worse, fights the netcode: a remote player is a **kinematic puppet** — *position*-driven, at its network-delayed (~100 ms) **stale** spot — so a rigid capsule would stop the mover dead at a phantom wall. Instead each frame we resolve the collision by **momentum**: for a character we're in contact with and **closing on**, apply `my_Δv = v_closing · other_mass/(mass+other_mass)` **directed away from them**, *once per contact* (a `_player_contacts` set; re-arms on separation — otherwise every overlap frame would re-brake the mover). It uses the **previous-frame velocity** and the other's `get_motion_velocity()` (network velocity for a puppet). This Δv is applied straight to `linear_velocity` **before** `_detect_external_impact`, so it's *measured* as an ordinary impact → the light one is flung and topples, the heavy one barely slows and plows on. Each machine resolves **its own local player**, so it's symmetric and immune to the stale-puppet problem: fat-into-kid → tiny Δv on the fat man (stays up, passes through), and on the kid's machine a large Δv (launched + toppled), which syncs back. Ragdolling players are skipped (disabled collider). **World and traffic keep the measured Δv** (genuine walls / heavy movers). *Trade-off:* no hard body-blocking between players (they can overlap when idle); accepted for the cartoon plow-through feel. This also subsumes the old spawn-overlap resolver — capsules that spawn inside each other simply never rigid-collide.
- **Crouch** shrinks the capsule and offsets the ground ray.

---

## Ragdoll — `RagdollUtil`

It's an **active ragdoll**: a pool of per-bone `RigidBody3D`s (one capsule each, sized from the bone's `capsule_dimensions`, on `RAGDOLL_LAYER=2` / `RAGDOLL_MASK=1`), built once. The bodies are wired parent→child by `Generic6DOFJoint3D`s whose **angular springs** (per-joint `stiffness`/`damping`, equilibrium = the bone's rest angle relative to its parent) act as **muscles** — they pull the body back toward a standing pose, so the ragdoll *settles* instead of going fully limp. `sync_to_bones` copies the animated bone transforms onto the bodies while **not** ragdolling, so activation starts from the current pose.

**States.** `is_active` (simulating) and `is_recovering` (blending back), mutually exclusive; `update(delta)` dispatches to `_update_active` / `_update_recovery`.

**`activate`:** capsule goes inert (`is_active=false`, collider disabled, frozen static); the skeleton is hidden and the bodies go dynamic; joints are built; the bodies are seeded with the capsule's velocity + **trip impulses** (upper body along the fall direction, legs opposite, a twist) — `activate_with_impact` sets that fall direction from the recorded impact (`_momentum_dir`). Bodies that start **overlapping** the world are held collision-less until they clear (`_pending_bodies`). While active, the **capsule follows the lower-spine body** (`_update_active`) so the capsule = pelvis position.

**`deactivate` → recovery:** joints cleared; the capsule is **grounded** at the pelvis's XZ (`snap_feet_to_ground`, a downward ray — *not* the old upward `_find_safe_spawn`, which is deleted) and **kept frozen** for the whole recovery. Over `recovery_duration` each body eases from where it fell toward the standing skeleton pose, with the **pelvis rising** and the **legs IK-solved** (feet planted) — the "getting up" motion; see [character-animation.md](character-animation.md). `_finish_recovery` snaps the bodies onto the skeleton, shows it, and **unfreezes** the capsule (local player only — a proxy stays a kinematic puppet).

Two robustness rules keep recovery from failing (the old "bones disjoint, press G again"):
- **The capsule stays frozen through recovery**, so even if the ground-snap ever misses, physics can't *eject* it mid-blend (an ejection would fling the skeleton the bodies are easing toward → disjoint). It only goes dynamic once recovery finishes.
- **`_on_fall_triggered` ignores impacts while `is_active` *or* `is_recovering`** — a spurious impact during getting-up can't restart the ragdoll halfway.
- On recovery exit the leg IK targets are **re-planted** under the body (`ik_util.reset_step_targets_to_ground`) so the feet don't lag while stepping to catch up — most visible on a proxy, whose solve runs at half rate.

### Replication (proxies) — root synced, ragdoll local

Only a `ragdoll` **flag**, the **capsule (= pelvis) position**, and the **pelvis rotation** (`ragdoll_rot`, a quaternion, in the per-tick state) travel — never per-bone state. On the flag edge each proxy runs its **own local active ragdoll** (`CharacterNetSync._drive_proxy_ragdoll` → `activate`/`deactivate`). The model:

- **The pelvis (root) is kinematic and network-driven; every other bone simulates locally.** Each frame while the proxy ragdoll is active, `drive_pelvis_to(pos, rot)` sets the lower-spine body's transform to the synced pose (`pos` = `s["pos"]`, `rot` = `s["ragdoll_rot"]`); `set_pelvis_kinematic(true)` (on activate) makes it a frozen **kinematic anchor**. Because it moves smoothly (interpolated), the joints **drag the hips/limbs along** without being slammed, and the limbs flail on their own gravity+springs. So the ragdoll is in the **right place** (no drift, authoritative) with the bones **in their sockets** — the pose is an approximation, the position is exact.
- **Why this is the model that works (after several that didn't):** driving the pelvis *dynamically* (velocity or force) makes it fight its own joints and separate the seams; teleporting *every* body spazzes the solver; a *pure* local sim looks right but drifts. A **kinematic root + local limbs** avoids all three — but it only works because the **joints are built from correct positions** (see below); before that fix the limbs looked detached no matter how the root was driven.
- **Seed + timing:** on activation the proxy seeds all bodies with the owner's `puppet_velocity` (the fall momentum, still held from just before the ragdoll) so the limbs start with the right energy.

> ### ⚠️ Joints must be built from a fresh pose
> `activate()` snapshots each bone's position to pin its joint, so **`sync_to_bones()` runs immediately before `_build_joints()`**. Without it, a proxy (half-rate solve → bodies a frame or two stale, see [character-animation.md](character-animation.md)) builds the joints from stale positions and **rigidly pins the arms/feet offset from their sockets** — attached (`maxgap≈0`) but visibly detached, worst on the fast-moving extremities. This was the "proxy ragdoll is dislocated" bug; the fix is that one sync.

> **Watch / open:** a **rare** joint separation on the **local** ragdoll (genuine sim instability under a hard landing) was reported but isn't reliably reproducible. `RagdollUtil` keeps diagnostic instrumentation behind `debug_log` (default off): it prints activate/deactivate/finish transitions with the peak joint gap (`_max_joint_gap`) and the worst joint. If it resurfaces, likely fixes: raise Jolt's position-solver iterations, add linear damping / velocity cap on the bodies, or soften the joints' linear limits.

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
