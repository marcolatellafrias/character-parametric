# Character Animation — skeleton generation & procedural pose

How the **aesthetic skeleton** is built and posed. This is the visual layer that hangs off the physics capsule ([characters.md](characters.md) covers the capsule, ragdoll and grab). The skeleton is **generated from the seed** and **re-posed from scratch every physics frame** by a procedural pipeline — there are **no keyframed animations**. The whole pose is a function of a handful of **inputs** read mostly from the capsule.

This doc exists to make the pipeline explicit before simplifying it (and before syncing it for remote players — see [Multiplayer implications](#multiplayer-implications)).

---

## Generation from the seed (build once)

`BoneInstantiator.initialize_skeleton()` builds everything, deterministically from `master_seed`:

1. **`EntityInstantiation.create(seed)`** → `arch_final` (an `EntityArchetype`: height, weight, reach, fatness, muscularity, proportions, slouch, arm/leg factors, step params…). This is the stat block.
2. **`SkeletonSizesUtil.create(inst)`** → every bone's **size / offset / rest data** as a pure function of the archetype stats (e.g. `middle_spine` radius `lerp(0.1, 0.55, fatness)`, arm segment lengths from `reach`, leg heights from proportions). Also derives locomotion params: `step_radius_min/max`, `step_height`, `distance_from_ground`, `raycast_leg_lenght`, arm rest targets/poles, etc.
3. **`CustomBonesUtil.create(sizes, inst)`** → builds the **bone hierarchy** of `CustomBone`s (parents, rest rotations, offsets) from those sizes.

Because all three are pure functions of the seed, **the same seed rebuilds the exact same skeleton on any machine** — this is what M3 leans on (a remote proxy uses a seed derived from the peer's Steam id).

### Bone hierarchy

```
lower_spine ─┬─ middle_spine ─ upper_spine ─ chest ─┬─ neck(optional) ─ head
             │                                       ├─ left_shoulder  ─ left_upper_arm  ─ left_lower_arm
             │                                       └─ right_shoulder ─ right_upper_arm ─ right_lower_arm
             ├─ left_hip  ─ left_upper_leg  ─ left_lower_leg  ─ left_upper_feet
             └─ right_hip ─ right_upper_leg ─ right_lower_leg ─ right_upper_feet
```

`lower_spine` is added as a child of the `CharacterRigidBody3D`, so **the whole skeleton follows the capsule**.

### `CustomBone`

A `Node3D` per bone with `capsule_dimensions` (x/z = radius, y = length) and a `rest_rotation`. Its mesh is a procedural `bone.glb` driven by **blend shapes** (height / top & bottom radius / dome heights) so a single mesh fits any proportions; `set_length()` re-stretches it. `pose_from_rest_to(dir, pole)` returns the basis that points the bone's rest axis along `dir` with a pole-resolved twist — the primitive the IK uses.

---

## Per-frame pose (rebuilt every physics tick)

For the **active** player every frame; for **NPCs/proxies** (`is_active=false`) every *other* frame (`_npc_skip_frame`). Order in `BoneInstantiator._physics_process` → `_solve_standing_frame`:

1. **`locomotion_signals.update(delta)`** — computes smoothed signals from the capsule + current foot targets:
   - `_update_velocity_signals`: `horizontal_velocity_smooth`, `speed_norm`, `vertical_velocity_smooth`, `impact_*_smooth` — read from **`char_rigidbody.get_motion_velocity()`** and `impact_xz/impact_y`.
   - `_update_step_signals`: `step_progress`, `step_length_norm`, `foot_spread_*` — read from the IK leg targets' current positions.
2. **`skel_sizes_util.update()`** → `_update_step_radius`: sets `ik_util.current_step_radius` by lerping min↔max on **speed** (bigger strides when faster).
3. **Leg IK** (`ik_util`), per leg:
   - `update_leg_raycast_offsets`: leads the foot raycast in the movement direction (from velocity) so steps land ahead.
   - `update_ik_raycast`: **if `char_rigidbody.is_grounded` is false → foot goes to the *airborne* target** (tucked up), else casts down (several candidate origins) to find the ground, decides whether the foot is out of its `step_radius` (→ **wants_step**), and `_try_start_farther_leg` tweens the farther foot to its new spot (`_tween_foot_to`, arced by `step_height`). Then `solve_two_bone_ik` bends the leg to the current foot target.
4. **`procedural_animator.update()`** (`ProceduralBoneAnimator`) — re-poses each registered bone/node from the locomotion signals. Registrations live in `BoneAnimations` (`register_all`): each entry maps a **signal** (step progress, h-velocity, foot spread…) to a **bone axis** (rot/pos) × weight × optional curve. This is the "walk/idle look" — spine sway, hip drive, arm swing, etc. All additive on top of rest.
5. **`anim_mod.apply(delta)`** (`AnimationModifiers`) — root offsets on `lower_spine` for **crouch** (`crouch_t`), **jump squat** (`jump_squat_t`) and **throw** tilt (`throw_t`/`throw_push_t`).
6. **Arm IK** — arm rest targets are placed relative to the chest, then **`arms_controller.apply_world_overrides`** blends in **grab** (arms reach the interactable's *handle points*, body/shoulder adjust) and **throw** poses; finally `solve_two_bone_ik` bends each arm to its target.
7. **Ragdoll sync** (`ragdoll_util.sync_to_bones`) when not ragdolling. During ragdoll the flow is bypassed and the capsule follows the bone-bodies ([characters.md](characters.md)).

`ProceduralBoneAnimator.update()` first **resets every registered bone to its rest** and then re-applies — so the pose is genuinely `f(inputs)` each frame, not accumulated.

---

## The inputs that determine the pose

Everything the pipeline reads to produce a pose:

| Input | Source | Drives |
|---|---|---|
| capsule **transform** (pos + yaw) | `char_rigidbody.global_transform` | where the whole skeleton is |
| **velocity** | `char_rigidbody.get_motion_velocity()` / `.linear_velocity` | step size/cadence, lean, arm swing |
| **is_grounded** | `char_rigidbody.is_grounded` | feet planted vs tucked (airborne) |
| **ground point** | `char_rigidbody.get_ground_collision_point()` | a foot-raycast candidate origin |
| **impact** (`impact_xz`, `impact_y`) | capsule impact PD | stagger/compress |
| **crouch / jump squat** | `crouch_t`, `jump_squat_t` (PlayerController) | root squat |
| **throw** (`throw_t`, `throw_push_t`, dir) | `AnimationModifiers` (set by grab/throw) | throw arms + tilt |
| **grab target** | interactable + grab point (via `ArmsController.start_grab/update_grab_handles`) | arms to handle points, body/shoulder adjust |
| **camera** | `player_camera` | head look, first-person hiding |
| **seat** | `is_seated`, `current_seat` | seated solve |
| per-foot **ground raycasts** | `ik_util` RayCast3Ds vs the world | exact foot placement (local, always) |

Note the coupling: the animation **reaches directly into the live physics body and the grab controller** for most of these. That implicit coupling is what makes the pipeline hard to reason about and hard to reproduce on a remote proxy.

---

## Multiplayer implications

A remote **proxy** (M3) rebuilds the same skeleton from the synced seed and is driven by a **puppet** capsule: `CharacterNetSync` writes its `global_position`/`yaw` and feeds `puppet_velocity`; the puppet's `_physics_process` **early-returns** (no simulation). Given that, the inputs split three ways:

**Re-derivable locally on the proxy (no sync needed):**
- **Foot placement / per-foot ground raycasts** — the proxy raycasts against its own world; feet find the floor locally. *(Answering the obvious question: no, you do not sync per-foot heights.)*
- **is_grounded** — could be re-derived from the capsule's own ground ray, **if the puppet ran it**.
- **Steps** — fall out of velocity (synced) + local raycasts.

**Must be synced (the proxy cannot know them):**
- ✅ **crouch / jump squat**, **throw** state, **impact/stagger** — now travel in the `CharacterNetSync` state (pos/yaw/vel + impact + crouch/jump/throw), interpolated and applied to the puppet.
- ⬜ **grab target** (which interactable + handles) — still pending (bug 3). It needs the grabbed object's reference resolved on the proxy so it can drive its own `ArmsController` to the handle points.
- ⬜ **head look** depends on the owner's camera — either sync a look direction or skip for proxies (minor).

**Remote-animation bugs:**
1. ✅ **Fixed (stage 2).** *Feet always airborne / "skeleton too high, no steps".* The puppet now updates its ground ray + `is_grounded` (it skips only movement/impact), and the leg IK reads `is_grounded` via `AnimationInputs.grounded`, so proxies plant their feet and step.
2. ✅ **Fixed (stage 2).** *Velocity read directly instead of the puppet velocity.* `SkeletonSizesUtil._update_step_radius`, `IkUtil.update_leg_raycast_offsets` and `get_step_duration` now read `AnimationInputs.velocity` (which is `get_motion_velocity()`, i.e. the puppet velocity on a proxy).
3. ✅ **Fixed.** *Arms don't reach handle points when a remote grabs.* `ArmsController.start_grab/update_grab_handles` are called by the **local** `InteractionController`; a proxy has none. *Fix:* only the grabbed **reference** is synced (`CharacterNetSync.set_grab_target` → `_receive_grab`, a node path). It lands in `AnimationInputs.grab_target`; the proxy's `ArmsController.drive_grab()` detects the start/stop and drives the arms, deriving origin / grab-point / handles **locally** (the object exists on every machine). The local player is unchanged (its IC still drives directly).
4. ✅ **Fixed.** *On a proxy the capsule + skeleton rotate but the IK targets (feet raycasts, arm poles) don't follow the yaw.* Root cause was **execution order**: `CharacterNetSync` is a *child* of the `BoneInstantiator`, so it applied the synced transform *after* the parent solved the pose that frame — the IK targets were built from the previous frame's yaw. *Fix:* the `BoneInstantiator` calls `net_sync.apply_to_puppet()` at the **start** of its `_physics_process`, before the solve. (The general lesson: whatever sets the capsule transform — player facing for the local player, net interpolation for a proxy — must run **before** the solve. `facing` should eventually become an explicit `AnimationInputs` field to make this impossible to get wrong.)
5. ✅ **Fixed.** *Reseed (respawn with `P`) changed the local skeleton but not the proxies.* The seed is normally derived from the steam id (deterministic, unsynced), which a local reseed breaks. *Fix:* the owner broadcasts its new seed (`CharacterNetSync.broadcast_seed()` on respawn); proxies rebuild via `_receive_seed` (and re-attach their name tag). Late joiners request the current seed on spawn (`request_seed_if_proxy`).

### Decoupling target

The structural fix is to stop the animation reaching into live physics/grab state and instead read an explicit **animation-input struct** — `{ velocity, facing, grounded, crouch_t, jump_t, throw_state, grab_target, impact }` — that fully determines the pose. Then:
- **single-player** builds the struct from the local capsule/controllers,
- a **proxy** receives the struct over the wire (only the non-derivable fields) and runs the **same** pipeline,

and questions like "why doesn't the proxy step?" disappear because the inputs are explicit and either synced or locally derived. Local-only inputs (foot raycasts, head-look) stay local.

**Progress:** `locomotion_signals`, `ik_util` and `skeleton_sizes_util` read the struct (stages 1–2). The **transform/facing** is now also consumed from it: `_update_animation_inputs()` (the producer) runs first each frame, then `_update_local_targets_positions()` reads `animation_inputs.origin`/`.basis` instead of the live capsule — so `local_targets` (feet raycasts, arm targets/poles) can't fall out of sync with the body regardless of who set the transform (see bug 4). **Grab** also flows through the struct now (`grab_target`, bug 3) — though the *local* player's arms are still driven directly by its `InteractionController` (only the proxy reads `grab_target`); unifying both onto the struct is the remaining polish. Still fully live: the seated solve.
