# Character Animation — skeleton generation & procedural pose

How the **aesthetic skeleton** is built and posed. This is the visual layer that hangs off the physics capsule ([characters.md](characters.md) covers the capsule, ragdoll and grab). The skeleton is **generated from the seed** and **re-posed from scratch every physics frame** by a procedural pipeline — there are **no keyframed animations**. The whole pose is a function of a handful of **inputs** read mostly from the capsule.

It documents the pipeline explicitly — the per-frame inputs, and how a remote proxy replays the same pipeline from synced state (see [Multiplayer](#multiplayer-proxies)).

---

## Generation from the seed (build once)

`BoneInstantiator.initialize_skeleton()` builds everything, deterministically from `master_seed`:

1. **`EntityInstantiation.create(seed)`** → `arch_final` (an `EntityArchetype`: height, weight, reach, fatness, muscularity, proportions, slouch, arm/leg factors, step params…). This is the stat block.
2. **`SkeletonSizesUtil.create(inst)`** → every bone's **size / offset / rest data** as a pure function of the archetype stats (e.g. `middle_spine` radius `lerp(0.1, 0.55, fatness)`, arm segment lengths from `reach`, leg heights from proportions). Also derives the gait: `foot_reach`, `distance_from_ground`, `step_height`, `raycast_leg_lenght`, arm rest targets/poles, etc. — all of it out of the archetype's single `stride` knob (see [the gait model](#the-gait-model)).

**What the seed actually varies.** Only three things: the **archetype**, whether a **second archetype blends** in at 0.5, and the **specie** (today pinned to human by `EntityInstantiation.FORCE_HUMAN_SPECIE`). There is **no per-instance random roll on animation parameters** — `_resolve` computes each one as `archetype value × specie multiplier`. Two characters of the same archetype and specie animate identically; the variety is meant to come from the archetype set and the blends, not from jitter. (`age` and `skin_color` are still rolled, and neither feeds the pose.)
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

For the **active** player every frame; for **NPCs/proxies** (`is_active=false`) every *other* frame (`_npc_skip_frame`). This half-rate is a **performance** measure — the full procedural solve is expensive, and a crowd of NPCs/proxies doesn't need it every tick. Order in `BoneInstantiator._physics_process` → `_solve_frame`:

### The half-rate solve and the sync-before-snapshot rule

On NPCs/proxies the solve — and with it `sync_to_bones`, the foot targets and the IK — runs every other frame, while the **physics and the capsule keep moving every frame**. So on those characters the skeleton and the ragdoll bodies sit a frame or two behind the live physics. One rule follows from that: **anything that snapshots the skeleton or the bodies syncs them first.** The code enforces this at the one place it matters — `_build_joints()` runs `sync_to_bones()` as its first line, so a proxy's ragdoll joints are always built from the current pose, which is what keeps the limbs in their sockets (see [characters.md](characters.md)).

Two consequences of the half-rate are handled directly:

- **Recovery runs full-rate.** While a proxy is ragdolling or recovering, `BoneInstantiator` drops the skip (the heavy solve early-returns during ragdoll anyway, so full rate is cheap). Otherwise the recovery blend would take 2× real time and `_update_active` would lag.
- **Feet re-plant on recovery exit.** The leg step targets re-establish at half rate, so without help the feet trail after standing up; `reset_step_targets_to_ground` plants them under the body on the first standing frame, leaving only the inherent half-rate smoothing.

Anything new that reads current transforms on a proxy follows the same rule: sync first, or run it full-rate.


1. **`locomotion_signals.update(delta)`** — computes smoothed signals from the capsule + current foot targets:
   - `_update_velocity_signals`: `horizontal_velocity_smooth`, `speed_norm`, `vertical_velocity_smooth`, `impact_*_smooth` — read from **`char_rigidbody.get_motion_velocity()`** and `impact_xz/impact_y`.
   - `_update_step_signals`: `step_progress`, `step_length_norm`, `foot_spread_*` — read from the IK leg targets' current positions.
2. **`skel_sizes_util.update()`** → `_update_gait`: sets `current_excursion`, `current_duty` and `current_stride` from **speed**, then `ik_util.advance_gait` advances the gait phase.
3. **Leg IK** (`ik_util`), per leg:
   - `update_airborne_target`: how far the leg tucks up while off the ground (scales with vertical speed).
   - `update_ik_raycast`: **if `is_grounded` is false → foot goes to the *airborne* target** (tucked up), else casts down (several candidate origins) to find the ground, and places the foot according to the leg's **gait phase** — planted during stance, interpolated to the predicted landing point during swing. Then `solve_two_bone_ik` bends the leg to the foot target.
4. **`procedural_animator.update()`** (`ProceduralBoneAnimator`) — re-poses each registered bone/node from the locomotion signals. Registrations live in `BoneAnimations` (`register_all`): each entry maps a **signal** (step progress, h-velocity, foot spread…) to a **bone axis** (rot/pos) × weight × optional curve. This is the "walk/idle look" — spine sway, hip drive, arm swing, etc. All additive on top of rest.
5. **`anim_mod.apply(delta)`** (`AnimationModifiers`) — root offsets on `lower_spine` for **crouch** (`crouch_t`), **jump squat** (`jump_squat_t`) and **throw** tilt (`throw_t`/`throw_push_t`).
6. **Arm IK** — arm rest targets are placed relative to the chest, then **`arms_controller.apply_world_overrides`** blends in **grab** (arms reach the interactable's *handle points*, body/shoulder adjust) and **throw** poses; finally `solve_two_bone_ik` bends each arm to its target.
7. **Ragdoll sync** (`ragdoll_util.sync_to_bones`) when not ragdolling. During ragdoll the flow is bypassed and the capsule follows the bone-bodies ([characters.md](characters.md)).

`ProceduralBoneAnimator.update()` first **resets every registered bone to its rest** and then re-applies — so the pose is genuinely `f(inputs)` each frame, not accumulated.

### Seated is the same frame — only the root and the legs change

There is **one** solve path (`_solve_frame`), not a standing one and a seated one. Sitting down changes exactly two things:

1. **The root** (`_pose_root`) — standing, `lower_spine` rides the capsule; seated, it's **pinned to the seat** (and the capsule is pinned in XZ, and the seat mesh yaws with the occupant). It is idempotent and called **twice**, before and after the procedural layer, because the procedural moves the spine and it has to be re-anchored.
2. **The legs** — standing, the gait (`_pose_legs_standing`: airborne target → ground raycast → IK); seated, a fixed forward tuck (`_pose_legs_seated`).

Everything else — the procedural layer + `anim_mod`, the **arms** (rest targets, a proxy's synced grab via `drive_grab`, throw/grab world overrides, arm IK) and the ragdoll-body sync — is **shared and written once**. This is structural, not stylistic: the two paths used to be copy-pasted forks and drifted apart, so a **seated proxy operating a dashboard never got `drive_grab` and its arms stayed at rest** while everyone else saw them on the handles. If you add a step, it goes in the shared block; if you branch, it has to be root or legs.

**The one thing that legitimately differs is *when* the legs run**, and it is not negotiable in either direction:

- **Standing: legs run *before* the procedural.** The foot raycasts originate at the hips, and the procedural animates the hips from foot signals (`FOOT_SPREAD_*`). Solving the legs afterwards feeds hip swing back into foot placement.
- **Seated: legs run *after*.** They hang off a root that must already be anchored to the seat.

Seated also re-pins the legs **once more after the arms** (`_repin_legs_seated`), because the grab overrides tilt the spine. That re-pin reuses the **cached** foot/pole targets — recomputing them post-tilt would drag the feet along with the torso.

---

## The gait model

The legs are the one part with **state that persists between frames**, so they get their own map. Everything lives on `IkUtil` (per-frame placement) and `SkeletonSizesUtil` (the derivation). There is **one authored number**, `EntityArchetype.stride` ∈ 0..1 — "how much of its usable reach this character spends on each step". Everything else below is derived.

### The four foot nodes (per leg)

| Node | What it is |
|---|---|
| `neutral_local` | the foot raycast's **rest local origin** — `x = ±raycast_stance_offset` (stance width), `y = −raycast_start_y_offset` (up near the hip). The hip's ground projection. |
| `next_target` | the **live ground hit** this frame, at the probe position (below). |
| `current_target` | where the foot **actually is**. `solve_two_bone_ik(upper_leg, lower_leg, current_target, pole)` bends the leg to it. |
| `airborne_target` | foot **tucked up**; used instead of the ground when `is_grounded` is false. |
| `pole` | knee-bend direction — a node in front of the leg (offset by `pole_distance` + hip width). |

**Debug lines.** Three per leg, one per raycast candidate: **A** = the predicted-landing probe, **B** = plain neutral, **C** = the capsule's ground point. Blue = the candidate that resolved this frame, grey = the others. All three are children of the raycast, whose origin is always restored to neutral after probing, so each indicator must be offset by hand to the candidate it stands for — miss that on A and it sits on top of B and the lead becomes invisible.

**A moves per-leg and per-phase now, and that is expected.** It is not the old constant lead line. It answers "where will *this* foot land", a question that only has an answer while the foot is in flight:

- **Stance** — no prediction term, so A sits at `neutral + Â·A`. The planted foot drifts backwards away from it as the body advances.
- **Lift-off** — the prediction term `v⃗·t_remaining` appears at full size, so A **jumps forward** by about `(1−D)·S`. This is the one visible discontinuity and it is inherent: a foot that isn't moving has no landing point to predict.
- **Swing** — `t_remaining` decays to 0, so A sweeps back in and **converges on the foot** exactly at touchdown. No snap on landing; the convergence is what makes the plant seamless.

So "it snaps out at each step and then meets the foot" is the mechanism working. Watching A during swing is the way to see whether the prediction is aiming correctly.

### 1. Geometry: the pelvis height *is* the stride budget

The IK chain (upper + lower leg) is exactly `leg_height` (`0.45 + 0.55`), and the hip sits at `h = leg_height − distance_from_ground`. With the foot on the ground the chain has to span `h` vertically and `A` horizontally, so the reach is

```
A_max = √((e·L)² − h²)          e = MAX_EXTENSION = 0.95, L = leg_height
```

**The higher the pelvis, the shorter the possible step** — and it collapses fast. At `h = 0.95 L` (what all five archetypes used to author via `distance_from_ground_factor`) the leg is *already* at 95 % extension standing still: `A_max = 0`. Any step at all had to clamp in `solve_two_bone_ik`, locking the knee straight.

So the direction is inverted: **pick the stride, derive the pelvis height it needs.**

```
h      = L · lerp(HIP_HEIGHT_HIGH, HIP_HEIGHT_LOW, stride)     # 0.93 → 0.80
A_max  = √((e·L)² − h²)                                        # foot_reach
```

`distance_from_ground` is now an *output* (`L − h`), not an authored field. Raising `stride` lowers the hips and buys reach; that trade is the whole point and it is not optional — it is geometry.

### 2. Per frame: excursion, duty, stride

```
t   = speed / max_speed
D   = lerp(DUTY_WALK, DUTY_RUN, t)                 # 0.62 → 0.40, the duty factor
A   = A_max · √t                                   # foot excursion actually used
S   = 2A / D                                       # stride: body travel per full cycle
```

**`A` must reach zero at zero speed**, hence `√t` rather than a lerp off some idle floor. The step direction is a *normalised* vector, so a floor means the foot still aims a full excursion ahead at 0.001 m/s — the settling step then targets a point outside its own trigger threshold, lands, re-triggers, and mini-steps forever. `√t` also rises steeply off zero, so a slow walk gets real steps rather than a scurry; with a linear `t` the cadence `v/S` comes out *constant* at every speed, which is wrong.

**`S = 2A/D` is forced, not chosen.** The foot plants at `+A` and lifts at `−A`, so it travels `2A` backwards in the body frame; during stance it is world-fixed, so that travel equals `D·S`. Cadence then falls out as `f = v/S` — no cadence parameter exists, and it scales correctly with leg length and speed on its own.

`D` is the fraction of the cycle a foot is **planted**. `D > 0.5` ⇒ there is always a foot down and a double-support window (a walk). `D < 0.5` ⇒ a flight phase (a run). The old code had an *effective* `D = 0.2`: each foot airborne 80 % of the time, so two legs needed 1.6 cycles of swing per 1 cycle available — alternation was arithmetically impossible, steps queued behind each other, and the blocked leg kept drifting backwards. That is what "the legs lag behind" was.

### 3. Phase, not thresholds

One accumulator drives both feet — `gait_phase` advances by `rate·delta`, left leg at `phase`, right at `phase + 0.5`:

- `phase < D` → **stance**: the foot is world-planted and simply not touched.
- `phase ≥ D` → **swing**: `swing_t = (phase − D)/(1 − D)`, and the foot eases from its lift-off point to the landing point.

Alternation is exact by construction. There is no step radius, no cooldown, no "which leg is farther", no `_try_start_farther_leg`. When the character starts moving, `_sync_phase_to_feet` seeds the phase so the foot that is furthest *behind* swings first (otherwise the first step reads as a stumble).

**The rate is distance-driven, with a floor while a step is committed:**

```
rate = v / S                                  # cycles/s — stride locked to travel, no sliding
if either leg is swinging:
    rate = max(rate, MIN_SWING_RATE)
```

Distance-driven is what keeps the stride tied to how far the body actually moved. The one case it doesn't cover is **braking with a foot in the air**: at `v → 0` the phase stalls and the airborne foot would never land. The floor covers exactly that, and only that — it applies solely while a leg is mid-swing, so once the foot touches down nothing is swinging, the floor lapses, and the phase freezes. No marching in place.

Note the floor is *not* a captured duration. `rate` is re-derived from live speed every frame, so accelerating hard mid-step speeds that step up too; freezing a swing duration at lift-off would desync from travel exactly the way a frozen landing point does.

A leg that has started a step also **stays committed** until its phase leaves `[D, 1)`:

```gdscript
swinging = phase ≥ D and (moving or already_swinging)
```

Without the `already_swinging` term, releasing the stick mid-swing flips the leg out of swing that frame and the foot **teleports** to the ground. With it, the step plays out; and the `moving` term still stops a planted leg from starting a *new* step while stationary.

### 4. The landing prediction — the part that actually fixes the lag

The foot must land half a step ahead of where the hip **will be at touchdown**, not where it is now. So the ground probe is

```
probe = neutral + Â·A + v⃗ · t_remaining        t_remaining = (1 − swing_t)·(1 − D)/rate
```

(`t_remaining` comes off the **effective rate**, not `v/S` — the latter blows up as `v → 0`. Off the rate it stays finite everywhere, and `v⃗ · t_remaining` decays to zero on its own as you stop, so the landing point walks back under the hip instead of jumping.)

Without that `v⃗ · t_remaining` term the body advances during the swing by exactly as much as the foot was led forward, and the two cancel: **the foot lands directly under the hip every single step, and can never get in front of the body.** That was the old behaviour — and it was independent of the step radius, which is why re-tuning the radius never fixed it.

The term is also self-correcting: as `swing_t → 1`, `t_remaining → 0` and the probe converges on the exact plant point, so velocity noise mid-swing washes out by touchdown. That is why no smoothing filter is needed on the lead any more (the old `raycast_offset` lerp is gone).

Lateral/backward steps are shortened by `axis_weight_lateral` / `axis_weight_backward` on the placement term only — the prediction term is pure physics and is never weighted.

### 5. Edge cases

- **Idle** (`speed < GAIT_MIN_SPEED`): the phase freezes and feet stay planted.
- **The settling step.** Stopping cuts the cycle wherever it happened, so the feet are left asymmetric — one ahead, one behind. `_settle_step_if_needed` gives the more displaced foot one short step back under the hip once it passes `SETTLE_EXCURSION_FRACTION × foot_reach`. This is the little shuffle you get when you halt, and it also covers turning in place and being shoved. It's the **only** step not driven by phase (there's no cycle to advance at zero speed), and it's one foot at a time — the `_is_stepping` guard covers *both* feet, and the larger displacement wins the tie.
- **Airborne / no ground / ground out of reach**: the foot snaps to `airborne_target` (or a blend toward it near ledges) and the swing state clears, so landing re-plants cleanly instead of "flying" to the new spot.
- **Half-rate solve**: NPCs and proxies solve every other frame, so `BoneInstantiator` passes `solve_delta = delta · 2`. The gait phase and every smoothing filter are functions of delta; feeding them the raw physics delta makes them advance at half real-time speed while the capsule keeps moving every frame — feet trailing the body, on proxies only.

### Tuning

| Knob | Where | Effect |
|---|---|---|
| `stride` | `EntityArchetype` | the character's gait: hips lower, reach and step longer |
| `MAX_EXTENSION` | `SkeletonSizesUtil` | how straight the leg is allowed to get at the extremes |
| `HIP_HEIGHT_HIGH/LOW` | `SkeletonSizesUtil` | the pelvis range `stride` maps onto |
| `DUTY_WALK/RUN` | `SkeletonSizesUtil` | walk-vs-run character; below 0.5 gives a flight phase |
| `MIN_SWING_RATE` | `IkUtil` | how fast a step in progress finishes when you brake mid-stride |
| `SETTLE_EXCURSION_FRACTION` | `IkUtil` | how far off-centre a foot must be before the settling step fires |
| `SETTLE_DURATION` | `IkUtil` | how snappy that settling step is |

**Cadence is not tunable directly** — it is `v/S`. If the feet look like they are scurrying, the cause is that `EntityArchetype.speed` is high relative to what the legs can stride: with `speed = 0.3` (⇒ 3 m/s, `SPEED_SCALE = 10`) on `leg_height ≈ 0.88 m`, `f` lands around 3 Hz where a human would be near 1.5. Fix it by raising `stride` (longer steps) or lowering `speed` — not by adding a cadence multiplier, which would re-break the `S = 2A/D` identity and bring the foot-sliding back.

### The resting stance (why the foot clips)

The capsule holds the pelvis at `leg_height − distance_from_ground` above the ground (`y_offset` in `CharacterRigidBody3D.create`), so **idle legs are visibly bent** — more so now that the pelvis is derived from the stride. The foot IK targets the **raw ground point**, and the foot bone (`upper_feet`) is **rigidly ~90° to the shin** — foot roll is *not* animated. Net effect: the un-animated foot dips a little into the floor at rest. Known cosmetic quirk; harmless, and any leg animation must reproduce it (rather than fight it) to avoid a pop.

### Standing up from a ragdoll (recovery)

While `RagdollUtil.is_recovering`, `BoneInstantiator` sets `ik_util.recovery_targets_locked = true`, which **bypasses the placement block entirely**: the gait phase keeps running but nothing writes `current_target`. Consequence — and this is the trap — **`current_target` is frozen** at wherever it was when the fall began (stale; possibly meters away if the body slid). **`next_target` keeps updating** (its assignment sits *outside* the lock guard), so it's the live resting ground point under the now-grounded capsule.

`RagdollUtil._update_recovery` rebuilds the **visible ragdoll-body** pose (the skeleton is hidden; bodies are shown) as a deliberate "get up" motion — see [characters.md](characters.md) for the ragdoll/recovery lifecycle:

- **Upper body** (root and above) blends from the fallen pose toward the standing skeleton, as before.
- **Pelvis** rises from `floor + recovery_rise_start_height` to the standing Y over the recovery, instead of snapping.
- **Legs** are IK-solved (`_solve_recovery_leg`, same law-of-cosines + the same `leg.pole` as locomotion) with the hip on the rising pelvis and the foot planted at **`next_target`** — the live resting point, **not** the frozen `current_target`. With feet planted and hip rising, the knees straighten from a crouch → the "legs pushing up" look.
- **The foot is never interpolated on its own** — it's hung *rigidly off the shin* every frame (`foot_body = lower_body · foot_local`). Interpolating its world transform directly makes it **flip** at the start of recovery. What *does* ease is its **angle relative to the shin**: `foot_local` blends from the **fallen** ankle angle (`fallen_shin⁻¹ · fallen_foot`, from `_recovery_start_transforms`) to the **rest** angle (`lower_bone⁻¹ · foot_bone`, ~90°) over `recovery_plant_fraction`. So it starts at the angle it settled into on the ground (no snap) and rolls to the standing angle — landing on the standing pose exactly (same ~90°, same floor clip), no seam when locomotion resumes.

Tunables live at the top of `RagdollUtil`: `recovery_leg_ik` (toggle the whole effect), `recovery_rise_start_height` (how crouched the pelvis starts), `recovery_plant_fraction` (how fast feet + ankle angle commit), `recovery_duration` (overall speed). If a foot/knee issue ever reappears, the failure is almost always **wrong target** (using `current_target` instead of `next_target`) or **interpolating the foot's world transform** instead of its shin-relative angle.

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
| **head pitch** | `head_pitch` — camera pitch (local) / network (proxy) | head/neck/spine look up-down |
| **camera** | `player_camera` | first-person hiding (head look now goes through `head_pitch`) |
| **seat** | `is_seated`, `current_seat` | seated solve |
| per-foot **ground raycasts** | `ik_util` RayCast3Ds vs the world | exact foot placement (local, always) |

The pose reads these through an explicit **`AnimationInputs`** struct, not the live bodies directly: one **producer** (`BoneInstantiator._update_animation_inputs`) fills the struct from the sources above once per frame, and every module reads the struct. That single indirection is what lets a remote proxy run the *identical* pipeline from network-filled inputs (below). Two things still live outside the struct as flags rather than struct fields (the seated solve reads `is_seated`/`current_seat`; the local player's own grab is driven by its `InteractionController`), but both are already replicated to proxies — the producer derives the proxy's seated flags from the synced seat reference, and grab routes through `grab_target`.

---

## Multiplayer (proxies)

A remote **proxy** rebuilds the same skeleton from a **seed derived from the peer's id** (deterministic → identical on every machine, so only the seed + transform travel, never the mesh). It's driven by a **puppet** capsule whose `_physics_process` early-returns (no simulation); `CharacterNetSync` owns it — the owner broadcasts, the proxy interpolates. The proxy then runs the **same** per-frame pose pipeline as everyone else, which only works because the pose reads `AnimationInputs` — filled from the network on a proxy instead of from a live local capsule.

**What travels vs. what's rebuilt locally** (the reason the input struct exists):

- **Synced** (the proxy can't know these): transform (pos + yaw), velocity, impact, crouch / jump / throw, **head pitch** (mirar up-down — the yaw is already in the transform), the **grab reference** and the **seat reference** — just *which* interactable/seat (its node path); the arms-to-handles and the seated pose are rebuilt locally. All of it flows through `CharacterNetSync` into the proxy's pose. Both references resolve because spawned objects have stable names on every machine.
- **Derived locally** (never synced): foot placement / ground raycasts, `is_grounded` (the puppet still runs its own ground ray), and stepping — these fall out of the synced velocity plus the proxy's own raycasts against its own world. Per-foot heights are **not** synced.
- **Not done yet**: unifying the *local* player's grab onto the struct (cosmetic — the proxy already routes grab through it). *Late-join is handled*: on proxy creation `CharacterNetSync.request_state_if_proxy` asks the owner for its current seed **and** its seat/grab references, so a player who joins while someone is already seated/holding sees that pose. The reference path (`spawned_<id>/…`) is resolved **lazily** (`_resolve_pending`, retried each frame) because the referenced object may arrive later via the `NetSpawner` snapshot — the two joins are async.

**Two gotchas worth keeping in mind:**

- **The capsule transform must be applied before the pose solve.** The whole pose is built from it, so whatever sets it — player facing (local) or net interpolation (proxy) — has to run *before* `BoneInstantiator` solves the frame, or the IK targets (feet raycasts, arm poles) lag the body by a frame and look detached when turning. Both sources are applied at the start of the bone frame; don't add a transform source that runs after the solve.
- **Cross-machine references need explicit node names.** Syncing "which object" as a node path only resolves if the node is named the same on every machine — Godot's auto-generated names are per-instance. Spawned objects (`spawned_<id>`) and their `Grabbable` child are named explicitly for this reason.
