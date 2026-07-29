# Character Animation — skeleton generation & procedural pose

How the **aesthetic skeleton** is built and posed. This is the visual layer that hangs off the physics capsule ([characters.md](characters.md) covers the capsule, ragdoll and grab). The skeleton is **generated from the seed** and **re-posed from scratch every physics frame** by a procedural pipeline — there are **no keyframed animations**. The whole pose is a function of a handful of **inputs** read mostly from the capsule.

It documents the pipeline explicitly — the per-frame inputs, and how a remote proxy replays the same pipeline from synced state (see [Multiplayer](#multiplayer-proxies)).

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

The pose reads these through an explicit **`AnimationInputs`** struct, not the live bodies directly: one **producer** (`BoneInstantiator._update_animation_inputs`) fills the struct from the sources above once per frame, and every module reads the struct. That single indirection is what lets a remote proxy run the *identical* pipeline from network-filled inputs (below). A couple of spots aren't migrated yet and still read live state — the seated solve, and the local player's own grab (its `InteractionController` drives the arms directly).

---

## Multiplayer (proxies)

A remote **proxy** rebuilds the same skeleton from a **seed derived from the peer's id** (deterministic → identical on every machine, so only the seed + transform travel, never the mesh). It's driven by a **puppet** capsule whose `_physics_process` early-returns (no simulation); `CharacterNetSync` owns it — the owner broadcasts, the proxy interpolates. The proxy then runs the **same** per-frame pose pipeline as everyone else, which only works because the pose reads `AnimationInputs` — filled from the network on a proxy instead of from a live local capsule.

**What travels vs. what's rebuilt locally** (the reason the input struct exists):

- **Synced** (the proxy can't know these): transform (pos + yaw), velocity, impact, crouch / jump / throw, and the **grab reference** — just *which* interactable (its node path); the arms-to-handles is rebuilt locally. All of it flows through `CharacterNetSync` into `AnimationInputs`.
- **Derived locally** (never synced): foot placement / ground raycasts, `is_grounded` (the puppet still runs its own ground ray), and stepping — these fall out of the synced velocity plus the proxy's own raycasts against its own world. Per-foot heights are **not** synced.
- **Not done yet**: head look (a proxy has no camera → would need a synced look direction), the seated solve, and unifying the *local* player's grab onto the struct (cosmetic — the proxy already routes grab through it).

**Two gotchas worth keeping in mind:**

- **The capsule transform must be applied before the pose solve.** The whole pose is built from it, so whatever sets it — player facing (local) or net interpolation (proxy) — has to run *before* `BoneInstantiator` solves the frame, or the IK targets (feet raycasts, arm poles) lag the body by a frame and look detached when turning. Both sources are applied at the start of the bone frame; don't add a transform source that runs after the solve.
- **Cross-machine references need explicit node names.** Syncing "which object" as a node path only resolves if the node is named the same on every machine — Godot's auto-generated names are per-instance. Spawned objects (`spawned_<id>`) and their `Grabbable` child are named explicitly for this reason.
