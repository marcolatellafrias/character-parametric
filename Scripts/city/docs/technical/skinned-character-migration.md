# Skinned Character Migration — Plan

> **Status: PLAN. Nothing here is implemented yet.**
> Migrating the character from a collection of procedural capsule bones to a **skinned Blender model** driven by the same procedural animation system. This doc is the roadmap; [characters.md](characters.md) and [character-animation.md](character-animation.md) describe the system as it exists **today** and stay authoritative until each phase lands.

---

## The shape of the change

The two-layer split (physics capsule vs aesthetic skeleton) **does not change**. What changes is only what the aesthetic layer *draws*.

`CustomBone` draws nothing and is a **pure logical rig**; a real `Skeleton3D` mirrors it every frame and the skinned meshes hang off that. (It used to carry a `bone.glb` per bone — that, `bone.tscn` and `custom_bone.tscn` are deleted.)

```
CharacterRigidBody3D
├── lower_spine (CustomBone tree)   ← still the source of truth. No meshes.
└── SkinnedBody (Node3D)
    ├── Skeleton3D                  ← mirror, driven from the CustomBone tree
    │   ├── MeshInstance3D  legs+torso
    │   ├── MeshInstance3D  head+neck
    │   ├── MeshInstance3D  arms
    │   ├── MeshInstance3D  hands
    │   └── MeshInstance3D  feet
```

**This is deliberately additive.** The IK, the gait model, the procedural animator, `AnimationModifiers`, the seated solve, the ragdoll and the netcode all keep manipulating `CustomBone` as `Node3D`s exactly as they do now. The entire migration adds **one call** at the end of `BoneInstantiator._solve_frame`, next to `_sync_ragdoll_bodies()`:

```gdscript
skinned_body.sync_from_bones()
```

Rewriting the animation pipeline onto `Skeleton3D` indices and parent-relative poses was the alternative, and it would put every system in [character-animation.md](character-animation.md) at risk at once. The mirror costs one function and risks nothing.

---

## The dividing line: bone or shape key

The single rule that organises the whole model:

> **Bones only ever change along their own length (their Y axis). Everything that is thickness, silhouette or shape is sculpted.**

Note that `shoulders_width` obeys this too: the `shoulder.L` bone points outward, so its *width* is its *length*.

The split is not a matter of taste. The criterion is **does the engine read this number**:

| Variable | System that consumes it | Type |
|---|---|---|
| `legs_length` | pelvis height, foot reach, cadence, foot raycasts, physics capsule | **bone** |
| `arms_length` | interact/grab/grip thresholds, arm IK | **bone** |
| `torso_length` | interaction origin, grab cone, character handle points | **bone** |
| `head_length` | total height → capsule size and camera height | **bone** |
| `shoulders_width` | capsule width, grabbable handle points | **bone** |
| `belly_fatness` | nothing | shape key ×2 |
| `arms_thickness` | nothing | shape key |
| `legs_thickness` | nothing | shape key |
| `neck_thickness` | nothing | shape key |
| `nose_length` | nothing | shape key |
| `nose_width` | nothing | shape key |

**Every length variable is hand-modelled at both extremes** — legs, torso and arms alike. The bone still carries the length (the joint has to be where the engine thinks it is); the sculpts are correctives that say what that length *looks* like. See [Everything is authored](character-blender-authoring.md#everything-is-authored).

The bone ones are bones because gameplay reads them as numbers. If the leg mesh stretches without the bone knowing, Godot still believes the foot is where it was: the character walks sunk into the floor, the IK aims at the wrong place, and the capsule ends up the size of a different character. The others are read by nobody and are pure silhouette — sculpt them freely.

### A variable is not a shape key

A variable is a **number that Godot writes to several places at once**. It can drive a bone length, one or more shape keys, or both. `shoulders_width` is the clearest case:

| What changes | How |
|---|---|
| shoulder bone length | `set_bone_pose_scale` on `shoulder.L` / `shoulder.R` |
| torso silhouette (trapezius, upper back) | shape keys `shoulders_narrow` / `shoulders_wide` on legs+torso |
| deltoid silhouette | same two keys on the arms mesh *(only if needed)* |
| **arm position** | **nothing — comes free from the hierarchy** |

The last row matters: `upper.arm.L` is a child of `shoulder.L`, so lengthening the shoulder moves the whole arm outward on its own.

The same shape key name appearing on two meshes is still **one** variable — Godot writes the same value to both. If the two values ever disagree, the shoulder seam opens.

### Shape key naming convention

A blend shape always runs from **0 = base mesh** to **1 = the sculpted target**. The base mesh is the model at its *defaults*, so the sculpt is always the **other end** of the parameter's range. Hence the key is named after the shape that was sculpted, not after the variable that drives it:

| Shape key | Mesh(es) | Sculpted from default toward | Value Godot writes |
|---|---|---|---|
| `belly_thin` | legs+torso | `belly_fatness` 0.5 → 0.0 | `max(0, (0.5 − v)·2)` |
| `belly_fat` | legs+torso | `belly_fatness` 0.5 → 1.0 | `max(0, (v − 0.5)·2)` |
| `arms_thin` | arms | `arms_thickness` 1.0 → 0.0 | `1 − v` |
| `legs_thin` | legs+torso | `legs_thickness` 1.0 → 0.0 | `1 − v` |
| `neck_thick` | head+neck | `neck_thickness` 0.0 → 1.0 | `v` |
| `nose_long` | head+neck | `nose_length` 0.0 → 1.0 | `v` |
| `nose_narrow` | head+neck | `nose_width` 1.0 → 0.0 | `1 − v` |
| `shoulders_narrow` / `shoulders_wide` | legs+torso (+arms?) | `shoulders_width` 0.5 → 0 / → 1 | as `belly` |

Only the two parameters whose default is `1.0` end up inverted. If that inversion is a recurring source of confusion, the alternative is renaming the *parameter* so its default is 0 (`arms_thinness`, `nose_narrowness`) and the two numbers become identical — purely a readability choice.

---

## Phases

The migration is staged so that the **risky mechanical part is validated before any parametric work exists**. Each phase is independently shippable and playable.

### Phase 0 — Neutral export ✅ done

**Goal:** get the model into the project unchanged.

No new Blender work. Export the character exactly as it is today, every parameter at its default, Pose Mode clean, all shape keys at 0. Export `.glb` with the five meshes + the armature.

Then **measure and write down** the length of every bone in the rest pose, plus the character's total height. Those numbers are the input to Phase 1.

**Blender hierarchy rules to verify before exporting** (the mirror only works if both hierarchies agree on where each joint sits):

1. **`hip.L` / `hip.R` have their head at the head of `lower.spine`, not at its tail.** In code the hips are created with `use_father_end = false` → `position = Vector3.ZERO` relative to `lower_spine` ([custom_bones_util.gd:32-33](../../character/static/custom_bones_util.gd#L32-L33)). Parent them to the tail and the legs sit a hip too high.
2. **Every other child sits at its parent's tail** — `shoulder.L` at the tail of `chest`, `upper.arm.L` at the tail of `shoulder.L`, and so on.
3. **`hip.L/R` and `shoulder.L/R` are lateral bones** pointing outward; their length *is* the hip/shoulder width.
4. **Rest pose reasonably close to the procedural rest** — arms down, no slouch. The *pose* no longer has to match (the mirror aligns bone directions, see [`_fix`](#_fix-encodes-the-axis-convention-never-the-pose-difference)) — this model is a T-pose and works fine. It still matters for **skinning quality**: the further the rest, the more the deformation stretches at the extremes.

**Deliverable:** `.glb` + a table of rest bone lengths + total height in metres (1 Blender unit = 1 m).

#### The reference model — measured

`Models/character.glb`, 52 bones, 5 meshes (`arms`, `body`, `hands`, `head`, `shoes`), **0 blend shapes** (correct for Phase 1). Feet on the ground at y ≈ 0.

| Chain | Bone | Length (m) |
|---|---|---|
| **Torso — 0.7617** | `lower.spine` | 0.1981 |
| | `middle.spine` | 0.1985 |
| | `higher.spine` | 0.1987 |
| | `chest` | 0.1664 |
| **Head** | `neck` | 0.0768 |
| | `head` | *leaf* (≈0.225 visual) |
| **Arm — 1.1060** | `shoulder.L/R` | 0.2860 |
| | `upper.arm.L/R` | 0.6284 |
| | `lower.arm.L/R` | 0.4776 |
| | `wrist.L/R` (hand) | 0.1623 |
| **Leg — 1.2494** | `hip.L/R` | 0.1689 |
| | `higher.leg.L/R` | 0.5590 |
| | `lower.leg.L/R` | 0.6904 |
| | `foot.L/R` | *leaf* |

Key rest heights: pelvis (`lower.spine` head) **1.2352**, shoulders/neck **1.9832**, head base **2.0587**, ankle **0.0310**. **Total height 2.2833 m.**

Three things this tells us:

- **The reference character is 2.28 m** — taller than every current archetype (1.45–1.95). Phase 1 adopts these proportions wholesale, so the whole game gets noticeably bigger characters until Phase 2 remaps the archetypes.
- **The arm chain is 1.106 m**, ~1.5× the longest archetype's `reach` (0.75). This is the deliberate long-arm decision and it does most of the work on [the arm reach problem](#the-arm-reach-problem).
- **`hip.L` / `hip.R` are root bones**, not children of `lower.spine`. Their heads sit at exactly `lower.spine`'s head, so the geometry is right, and because the mirror drives *every* mapped bone's global pose the parenting is irrelevant to correctness. **No re-export needed** — parent them only if it makes posing easier in Blender.

---

### Phase 1 — The mirror (zero deformation) — implemented, pending playtest

**Goal:** prove the plumbing works, with **no parametric variation at all**. Every character in the game is the same default model — "a mid-heavy, tallish guy". All five archetypes render identically.

The point of this phase is isolation: **in Phase 1 the mesh must never deform.** Every bone pose scale is exactly 1 and every blend shape is exactly 0. So if anything looks distorted, torn or misplaced, it is a bug in the mirror — not a proportion that needs tuning. That distinction is impossible to make once lengths are in play, which is why lengths come later.

**Godot work — all landed:**

1. ✅ **`SkinnedBodyUtil`** — the name map, the per-bone axis correction, and the per-frame sync (see [The mirror](#the-mirror) below).
2. ✅ **`SkeletonSizesUtil.USE_REFERENCE_MODEL`** — the `REF_*` constants measured in Phase 0 replace the archetype-derived bone lengths, for every archetype. Aggregates are overridden early (everything derived — gait, raycasts, poles, capsule — reads them) and the per-bone lengths after the fraction split, because the fractions don't match the model: the code makes the forearm longer than the upper arm (0.45/0.55) and the model is the reverse (0.57/0.43).
3. ✅ **`EntityArchetype.generic` + `EntityInstantiation.FORCE_ARCHETYPE`** — one neutral archetype for everyone: no slouch, no dropped shoulders, no crippled legs, narrow stance, arms barely bent. It exists to *look at the model*, not to be a game character, and it is excluded from the population roll (`archetype_frequency = 0`).
4. ✅ `CustomBone` meshes hidden when the skinned model exists; ragdoll bodies permanently invisible with the mirror reading them instead; first-person hides the head mesh.

**Blender work:** none.

**Why the freeze matters — the mesh was being crushed.** Without it the logical rig asks the mesh for proportions it was never sculpted at: the arm chain is `arch.reach` (0.38–0.75 m) against the sculpted **1.106 m** — **34–68 %**. The torso lands at 72 %, the leg at 82 %. The arm is by far the worst, which is why the arms were the visibly broken part. That compression is the mirror working *correctly* — it faithfully reproduces whatever the logical rig asks for. The freeze makes the ask match the sculpt.

**The legs stay somewhat bent, and that is not a bug — it is the one knob with a hard floor.** The pelvis height comes from `stride`, not from the model's rest (`h = L · lerp(0.93, 0.80, stride)`), because [the pelvis height *is* the stride budget](character-animation.md#1-geometry-the-pelvis-height-is-the-stride-budget):

| `stride` | pelvis | `foot_reach` | |
|---|---|---|---|
| 0.50 | 1.081 | 0.491 | clearly bent, longest stride |
| **0.25** | **1.121** | **0.389** | **`generic` uses this** |
| 0.00 | 1.162 | 0.242 | nearly straight, tiny steps |
| — | 1.224 | **0.000** | the sculpted rest: cannot step at all |

Straightening the legs all the way to the sculpted rest means giving up walking entirely. `stride` is the only lever, and it trades leg extension against step length directly.

**Exit criteria** — all of these, in a played session, not headless:

- [ ] Walk and run: no seams open, feet plant, no swimming
- [ ] Ragdoll (**G**) and stand back up — the skinned mesh is what's visible in both states
- [ ] Sit on a seat, and operate a dashboard while seated
- [ ] Grab an object at close range (no arm stretch involved yet)
- [ ] First person hides what it should
- [ ] A remote proxy looks right (half-rate solve, see [character-animation.md](character-animation.md))
- [ ] 20+ NPCs on screen without a frame-time regression vs. the capsule bones

Note that the character's size, camera height and gait all change in this phase to the Blender model's actual proportions. Phase 1 is also the first read on whether the game *feels* right at this character's scale.

---

### Phase 2 — Limb and torso lengths — implemented, ranges provisional

**Goal:** the first intentional deformation. `legs_length`, `arms_length`, `torso_length` become real, and archetypes start looking different from each other again.

**Blender work:** for each of the three, scale the relevant bones in Pose Mode until the extreme looks right artistically, and **write down the scale factor**. That number, not the mesh, is the deliverable.

| Variable | Bones to scale |
|---|---|
| `legs_length` | `higher.leg.L/R`, `lower.leg.L/R` |
| `arms_length` | `upper.arm.L/R`, `lower.arm.L/R` |
| `torso_length` | `lower.spine`, `middle.spine`, `higher.spine`, `chest` |

**Rig setup required first:** by default a bone inherits its parent's scale, so scaling `upper.arm.L` also grows the hand. Set **Inherit Scale = None** on `wrist.L/R` (hands don't grow with the arm), `foot.L/R` (feet don't grow with the leg) and `neck`. Verification: scale `higher.leg.L` to double and check the foot — same size, still attached at the ankle. If the foot detaches, use **Aligned** instead of None on that bone.

**Godot work:** remap the archetypes onto the measured ranges (see [Archetypes adapt](#archetypes-adapt-to-the-blender-ranges)), apply the lengths as pose scale.

**Blocked on:** [The arm reach problem](#the-arm-reach-problem) must be resolved before `arms_length` ships.

**Watch for:** the seams. The wrist, ankle, shoulder and neck seams are what tear when limbs stretch, and masking can't help — only identical vertex weights on both sides of the seam can. Test with `legs_length` and `arms_length` at their minimum simultaneously.

---

#### What landed

- `EntityArchetype` gained **`legs_length` / `arms_length` / `torso_length`** (0..1, default 1.0 = the sculpted length), wired into `blend_with`.
- `SkeletonSizesUtil` converts them to metres over `MIN_*`/`MAX_*`, and splits each chain by the **model's** internal fractions — not the code's old ones, which had the forearm longer than the upper arm (0.45/0.55) where the model is the reverse (0.57/0.43).
- **`height` is now an output**, `SkeletonSizesUtil.total_height`. `EntityArchetype.height` and the four `*_proportion` fields are vestigial (kept as author reference; hips/shoulders/neck/head stay pinned to the sculpt until Phase 3).
- **`reach` and `reach_multiplier` are gone from the archetype.** The arm chain is `arm_reach`, and the interaction range is derived: `interaction_reach = arm_reach × MAX_ARM_STRETCH × 0.97`. One source of truth, and the arm can never be asked to stretch past the cap. `EntitySpecie.reach_multiplier` was already dead and stays unused.
- **`EntityInstantiation.FORCE_ARCHETYPE`** replaced the old boolean. It is an archetype *or* `-1`, so the Phase 1 view is one value among many rather than a special case. It stays `const` on purpose: a mutable global would make a proxy resolve a different character from the same seed.
- **Per-spawn archetype choice** lives in the debug panel (tab *Arquetipos*) and works by **encoding the archetype in the seed** (`DEBUG_SEED_BASE`, band `900000+`). The seed is the only thing that crosses the wire, so this needs no protocol change and every machine lands on the same character. It replaced an older hack that mapped seeds `0..4` to archetypes — those could be rolled naturally and did not cover every archetype.

Resulting characters (head fixed at 0.302 m until Phase 3):

| Archetype | legs / arms / torso | leg | torso | **height** | arm | grab range |
|---|---|---|---|---|---|---|
| `kid` | 0.00 / 0.00 / 0.05 | 0.750 | 0.472 | **1.52** | 0.664 | 0.81 |
| `old` | 0.35 / 0.30 / 0.25 | 0.925 | 0.533 | **1.76** | 0.796 | 0.97 |
| `fat_man` | 0.45 / 0.50 / 0.75 | 0.975 | 0.686 | **1.96** | 0.885 | 1.07 |
| `giga` | 0.60 / 0.75 / 0.90 | 1.050 | 0.731 | **2.08** | 0.995 | 1.21 |
| `tall_lanky` | 1.00 / 0.95 / 0.60 | 1.249 | 0.640 | **2.19** | 1.084 | 1.31 |
| `generic` | 1.00 / 1.00 / 1.00 | 1.249 | 0.762 | **2.31** | 1.106 | 1.34 |

**Two things to judge in play, not on paper:**

1. **Everyone got bigger** — the range is 1.52–2.31 m against the old 1.45–1.95. That follows directly from the sculpt being the *maximum* (`legs_length` default 1.0 in Blender), so every character is a scaled-down version of it. If the world now feels small, the fix is the `MIN_*` values, not the archetypes.
2. **Grab range dropped ~30–40 %** (e.g. `fat_man` 1.56 → 1.07 m). This is [option 1](#the-arm-reach-problem) — cutting the multiplier to whatever keeps the mesh under `MAX_ARM_STRETCH`. If reaching now feels too short, the upgrade is **option 3**: keep a long acquisition range and clamp only the *held* distance, so the grab PD pulls the object to the hand instead of stretching the arm to the object.

**Superseded by the restructure.** Both of those numbers assume the sculpt is the *maximum*. It isn't any more: the model is being re-authored so the sculpt sits at **0.5**, at **1.7 m**, with both extremes hand-modelled. So the ranges, the archetype values and the grab distances above are all placeholders now — the mechanism stands, the constants don't. They get replaced in Phase 4a from measured Blender numbers, and each variable will carry **three** (0.0 / 0.5 / 1.0) rather than two.

---

### Phase 3 — Vertical slice: the generic character ← **next**

**Goal: one character, finished.** Not one variable more. The plan was restructured here: instead of adding parametric variables on top of a base that doesn't look right yet, the generic character gets taken all the way to "this is the game's art style" first, and archetype variation comes after.

The reasoning is the ordering, not the scope: **drivers, correctives and range tables are all investments in a system that varies the character. There is no point paying for them before knowing whether the character is worth varying.** And because the generic sits at 0.5 on every axis — its base mesh, deformation zero — this is also the cleanest possible view for judging the art.

What Godot owes this phase:

1. **Bone scale for length — currently missing.** The mirror drives bone *positions* but leaves every pose scale at 1, so a bone's flesh never lengthens: only the blend region around the joint stretches, like pulling a sock by the ankle. This is the real reason the mesh "doesn't adapt well". The fix is `set_bone_pose_scale(idx, Vector3(1, actual_length / rest_length, 1))` per driven bone. It has to land before anything else here, because the next two items only matter once it exists.
2. **Arm stretch rides `arms_length`, clamped at 1.0.** The arm is authored at both extremes, so instead of scaling the bone past whatever was sculpted, a grab **solves for the `arms_length` value** that produces the arm length it needs, and clamps there. Every arm state is then a blend between two sculpted shapes — including mid-grab. Past 1.0 the hand stops short of the object and the IK just points at it; that's an accepted cost, not a bug to fix.

   The inverse is two-segment, because 0.5 is authored and off-centre:

   ```gdscript
   # given the arm length L a grab needs, and the three authored lengths L0 / L05 / L1
   var v := 0.5 * (L - L0) / (L05 - L0) if L <= L05 else 0.5 + 0.5 * (L - L05) / (L1 - L05)
   arms_length = clampf(v, resting_value, 1.0)
   ```

3. **Gameplay reach stays proportional** to *this character's* resting arm (`arm_reach × MAX_ARM_STRETCH`), never a jump to a shared ceiling — otherwise every character would reach the same absolute distance and arm length would stop mattering. The clamp is on the **mesh**, not on the reach.

   **No `deltoid` bone.** An earlier version added one per side to keep the shoulder socket from stretching. Authoring the arm extremes removes the need: the socket stretching at `arms_length = 1.0` is a shape you modelled, not a defect to prevent, so the socket hangs off `upper.arm` directly and swings with it. See [why there is no deltoid bone](character-blender-authoring.md#why-there-is-no-deltoid-bone).
4. **Twist / hand orientation.** The open problem from [twist](#twist-was-never-meaningful-in-the-capsule-rig--and-the-skinned-mesh-exposes-it): the forearm takes its twist from the elbow pole, so the palm rotates with the elbow. A sculpted hand makes that unmissable. Needs a real twist input rather than a by-product of the pole.
5. **Attachments — a third category.** The eight Rive planes plus hair, hats and the cigarette are neither bones nor shape keys: they don't deform, they're *placed*, and their placement follows the parameters. They need anchor points the parametric system moves, and `Inherit Scale = None` so a future `head_length` never stretches a mouth.
6. **Re-measure after the 1.7 m rescale** — every `REF_*` / `MIN_*` / `MAX_*` constant is in metres and all of them shift.

**Exit:** the generic character walks, runs, grabs, ragdolls, sits and reads as finished art. Arms stretch cleanly when reaching — socket holds, hands keep their size, palms face the right way.

---

### Phase 4 — Archetype expansion

Everything parametric, once the character is worth varying. Split by what the Blender side has to deliver, and ordered by how much each one changes the read of a character.

| Step | Variables | Godot work |
|---|---|---|
| 4a | `legs_length`, `torso_length`, `arms_length` | replace the provisional `MIN_*`/`MAX_*` with measured values; **two-segment interpolation** (below); wire the length correctives |
| 4b | `arms_thickness`, `legs_thickness` | blend shape writes only |
| 4c | `belly_fatness`, `head_length`, `neck_length`, `neck_thickness`, `nose_length`, `nose_width` | blend shapes + two leaf-bone scales |
| 4d | `shoulders_width`, `hips_width` | bone + correctives; the trickiest and the least urgent |

**Two-segment interpolation is the one structural change.** Every variable now defaults to **0.5**, and 0.5 is the *authored* generic — deliberately **not** the arithmetic midpoint of the two extremes. So a single `lerp(MIN, MAX, v)` is wrong; each variable carries three numbers and interpolates in halves:

```gdscript
var length := lerp_range(MIN, MID, v * 2.0) if v < 0.5 else lerp_range(MID, MAX, (v - 0.5) * 2.0)
```

The shape keys follow the same split — `min_key = max(0, (0.5 − v) · 2)`, `max_key = max(0, (v − 0.5) · 2)` — which makes every variable uniform. The inverted cases from the old scheme (`1 − v` for anything whose default was 1.0) disappear entirely.

**Arms are no longer an exception** — they get two hand-modelled extremes like every other chain (and they land in Phase 3, not here, because the generic character can't grab anything without them). What makes arms special is only the **clamp**: a grab solves for the `arms_length` that reaches and stops at 1.0, so the mesh never leaves authored territory even mid-grab. See [Everything is authored](character-blender-authoring.md#everything-is-authored).

**Archetype resting values stay in the lower part of the arm range**, so every character keeps stretch headroom. A character resting at the top of its range could not reach at all.

Phase 4c also deletes the last of the magic radius formulas in `SkeletonSizesUtil` (`lerp(0.16, 0.45, muscularity)` and its eight siblings) — sculpted silhouette replaces them.

---

### Corrective sculpting — the workflow note

Worth recording once, because it's the fiddliest part and it applies to every corrective in Phase 4: a corrective is sculpted **on top of the already-applied deformation**. Put the bone at its extreme in Pose Mode, then sculpt while seeing the deformed result — in the Armature modifier, enable Edit Mode display + **On Cage** so Blender back-solves the sculpt into rest space.

---

### Deferred — hands and fingers

**`wrist.L/R` and the 30 finger bones ride rigid.** They are in the rig and in the skin, they follow the forearm, and nothing animates them. That is the intended state through every phase above.

The procedural system has no concept of a hand today — grab poses the *arm* so the forearm tip reaches the handle point, and there is no finger closing, no grip shaping, no per-object hand pose. Adding that is its own feature with its own design, not part of this migration. When it happens it will most likely want its own controller alongside `ArmsController`, reading the grabbed interactable's shape.

The only thing the migration owes it: **keep the finger bones in the exported rig and skinned**, so the feature doesn't require a re-export later.

---

## The mirror

Both hierarchies describe the same standing pose, but their local axis conventions will not match — `CustomBone.rest_rotation` uses `createFromToDown` (180° about X), `createFromToLeft` (+90° about Z) and so on, while Blender assigns its own roll per bone. **Don't try to reconcile the conventions analytically.** Compute a per-bone correction once at build time and drive the delta from rest:

```gdscript
# build (once, after the skeleton is created):
#   _fix[i] = custom_rest_basis_global.inverse() * skel_rest_basis_global

func sync_from_bones() -> void:
    var root_inv := skel.global_transform.affine_inverse()
    for i in _order:                                   # topological, parents first
        var cb: CustomBone = _bones[i]
        var g := root_inv * cb.global_transform         # CustomBone in skeleton space
        var desired := Transform3D(g.basis * _fix[i], g.origin)
        var p := skel.get_bone_parent(i)
        var parent_g: Transform3D = _parent_global[p] if p >= 0 else Transform3D()
        skel.set_bone_pose(i, parent_g.affine_inverse() * desired)
        _parent_global[i] = desired
```

### `_fix` encodes the axis convention, never the pose difference

The two rigs are in **different rest poses**: the Blender model is modelled with the arms nearly horizontal (T-pose — `upper.arm.L` drops only 0.089 m over a 0.628 m bone), while the `CustomBone` rest hangs the arms down. A naive `_fix = custom_rest⁻¹ · skel_rest` maps rest → rest, so it bakes that **pose** difference in alongside the axis convention: the arm bone renders horizontal while the chain of driven positions goes downward, and the arm mesh comes out crossed and broken.

So `_fix` carries a direction-alignment term — the minimal rotation taking the Blender bone's rest direction onto the CustomBone's rest direction:

```gdscript
var align := _align_axis(skel_rest.y.normalized(), custom_rest.y.normalized())
_fix[k] = custom_rest.inverse() * (align * skel_rest)
```

With it, `_fix` holds **only the roll/axis convention**, and the identity `desired.basis.y == cb.global_basis.y` holds for every bone every frame: the model's bone points exactly where the `CustomBone` points, whatever rest pose the model was authored in. That makes the mirror immune to rest-pose differences instead of merely tolerant of them — the Blender rest no longer has to imitate the procedural rest for the *pose* to be right. (It still pays to keep them close, but now only for **skinning quality**: the further the rest, the more the deformation stretches.)

### Twist was never meaningful in the capsule rig — and the skinned mesh exposes it

This is the deepest structural issue in the migration, and it is worth stating plainly: **a capsule is a solid of revolution.** Spin it about its own axis and it looks identical. So for the whole life of the procedural system, the **twist** of every bone — its rotation about its own length — has been *free*: nothing read it, nothing looked wrong when it was arbitrary, and nothing was ever tuned to make it right.

Look at what the arm IK actually does ([ik_util.gd:203-204](../../character/animation/ik_util.gd#L203-L204)):

```gdscript
upper_bone.global_transform.basis = upper_bone.pose_from_rest_to((knee_pos - root_pos).normalized(), pole_on_plane)
lower_bone.global_transform.basis = upper_bone.pose_from_rest_to((target_pos - knee_pos).normalized(), pole_on_plane)
```

Both segments take their twist from `pole_on_plane` — the **elbow direction**. That is the right input for *where the elbow points* and says nothing about *where the palm faces*. With capsules that was fine. With a skinned hand it means **the palm rotates with the elbow**, which reads immediately as "the hands are inverted".

Two consequences follow, and they are different problems:

**1. Calibration (fixed).** `_fix` used to be computed at the *construction* rest — arms straight down, twist from `createFromToDown`. But the character never holds that pose: the first arm IK solve immediately moves to the archetype's A-pose (`arm_openness` / `arm_bentness`) with a pole-derived twist. So the twist offset was measured in a pose abandoned on the same frame. `SkinnedBodyUtil.create` is now called **after** the initial arm IK solve in `initialize_skeleton`, so the calibration happens against the pose that is actually held.

**2. Twist tracking (open).** Even calibrated, the forearm's twist follows the elbow pole as the arm moves, so the palm still rotates with the elbow. Fixing this properly means giving the arm a real twist input — a hand-orientation target rather than a by-product of the pole — which is the same feature as [hand posing](#deferred--hands-and-fingers) and belongs there, not here.

The general rule the migration surfaces: **anything the capsule rig left arbitrary because capsules are symmetric now has to become deliberate.** Twist is the first and biggest instance; expect others in the same family (foot roll is the likely next one, since `upper_feet` is rigidly ~90° to the shin and foot roll is not animated — see [character-animation.md](character-animation.md#the-resting-stance-why-the-foot-clips)).

**If the arms point correctly but stay twisted after the calibration fix**, the remaining options are a per-bone twist constant (cheap, approximate) or matching the two rest poses exactly by re-authoring the Blender rest with the arms down (exact, removes the `align` heuristic entirely, costs a re-pose + re-bind in Blender).

Two rules that are not negotiable:

- **The `Skin` bind poses are baked from the Blender rest and never touched.** The temptation is to recompute the bind when proportions change — do that and the mesh stops deforming and you get the neutral model forever. The per-archetype deformation *is* the difference between the current pose and the original bind.
- **Parents before children** (hence the cached `_parent_global`). Walking the chain upward per bone is O(n²) per frame per character.

This mirrors Blender exactly: editing a bone's length in Edit Mode doesn't deform the mesh there either (rest and pose move together), which is why all the length work happens in Pose Mode. **What you preview in Pose Mode is literally the operation Godot performs at runtime** — not an approximation of it.

---

## Forward axis — the project convention

> **The front of anything in this project is −Z.** Not negotiable per model, per character or per system. Anything that arrives facing another way is corrected **once, at the boundary where it enters**.

This is Godot's own convention — `Node3D.basis.z` points *backwards*, `look_at` aims at −Z — and it is already what the entire codebase assumes: the capsule, the camera, the seated pose (`-char_rigidbody.global_transform.basis.z`), the interactables and the traffic system all read forward as −Z. Changing it would be a far larger edit than correcting any one asset.

**The Blender model is authored facing +Z**, i.e. 180° the wrong way. That was measured, not assumed:

| | Blender rest | CustomBone rest | |
|---|---|---|---|
| `foot.L` direction (toes) | **+Z** | **−Z** | opposite |
| `hip.L` / `shoulder.L` direction | **+X** | **−X** | opposite |
| `higher.leg.L` direction | −Y | −Y | same |

A 180° yaw about Y maps +Z→−Z, +X→−X and leaves −Y alone — it explains all three at once. Two things it rules out: it is **not** a per-bone roll difference (`_fix` already absorbs those, which is exactly why the spine bases matched while the model still rendered backwards), and it is **not** an L/R swap (`shoulder.L` really is the character's left in both rigs; the yaw is what makes the two agree).

**Where the correction lives:** `ReferenceRig.MODEL_FORWARD_YAW`. One constant, one place, applied once when the model is read — both the logical rig and the mirror take their rest from there already corrected.

Do **not** "fix" this by rotating the model root or the `Skeleton3D` node instead. `_fix` is derived from *both* rest poses, so a rotation inserted between them gets partly re-absorbed into the correction and has to be reasoned about twice. Keep it in the one constant.

If the model is ever re-exported already facing −Z (rotate 180° about Blender's Z axis, then apply the rotation), set `MODEL_FORWARD_YAW` to `0.0` and nothing else changes.

---

## The arm reach problem

> **Resolved — kept for the reasoning.** The answer is [authored extremes with a clamp](#phase-3--vertical-slice-the-generic-character): the arm is modelled at 0.0 and 1.0, a grab solves for the `arms_length` that reaches, and stops there. The numbers below are from the capsule-era rig and no longer describe the model, but the constraint they expose is exactly why the clamp exists.

### Length and stretch are two independent variables

Reach is **not** one number, and collapsing it into one is what the old `reach` / `reach_multiplier`
pair got right and is worth keeping:

| Archetype field | What it means | Where it lands |
|---|---|---|
| `arms_length` (0..1) | **Body proportion.** What arm the character has standing still, doing nothing. | `SkeletonSizesUtil.arm_reach`, in metres |
| `arm_stretch` (×) | **How far out of that proportion they go to reach something.** | `interaction_reach = arm_reach × arm_stretch × 0.97` |

They are independent on purpose: a short-armed character can have a huge stretch and a long-armed one
a small one. Those are different characters, and one number cannot say both.

`arms_length` maps into a *band* of the Blender range (`ARM_EXT_MIN`..`ARM_EXT_MAX`), not the whole
0..1 — the top of the range is reserved for reaching, which is exactly what `arm_stretch` spends. The
only global constant left is `SkeletonSizesUtil.MAX_ARM_STRETCH`, and it is a safety net rather than
a knob: it stops an archetype asking for an arm past the sculpted extreme, where the shape key has
nothing left to correct the silhouette with and the mesh really does go rubbery.

Consequence worth stating: **stretching is not a cheat here.** Inside the authored range the stretched
arm is a shape somebody sculpted and approved, so `arm_stretch` is free to be generous. On the current
model the generic sits at `2.0` — a 1.11 m reach, using 0.69 of the sculpted range.

**This blocks `arms_length` in Phase 2 and it is the hardest constraint in the migration.**

`ArmsController._apply_arm_grab` **physically lengthens the arm bones at runtime** so the hand reaches a grabbed object ([arms_controller.gd:255-269](../../character/animation/arms_controller.gd#L255-L269)):

```gdscript
var target_total : float = max(nat_total, dist / GRAB_MIN_BEND_FACTOR)   # 0.97
upper.set_length(new_upper_l)
lower.position = Vector3(0.0, new_upper_l, 0.0)
lower.set_length(new_lower_l)
```

With capsule bones this is invisible — a capsule just gets longer. With a skinned mesh it becomes a stretch of the arm geometry, and the current numbers are extreme. The natural arm chain is exactly `arch.reach`, and the grip threshold is `reach × reach_multiplier`, so the maximum stretch is `reach_multiplier / 0.97`:

| Archetype | arm chain (m) | `reach_multiplier` | max grip dist (m) | **max stretch** |
|---|---|---|---|---|
| `fat_man` | 0.65 | 2.4 | 1.56 | **2.5×** |
| `kid` | 0.38 | 3.6 | 1.37 | **3.7×** |
| `tall_lanky` | 0.75 | 2.5 | 1.88 | **2.6×** |
| `giga` | 0.75 | 2.3 | 1.73 | **2.4×** |
| `old` | 0.50 | 3.0 | 1.50 | **3.1×** |

A skinned arm stretched 3.7× is chewing gum. **This is why the Blender character is modelled with deliberately long arms** — the longer the natural arm, the smaller the multiplier needed to cover the same interaction range.

**And the measurements say it largely worked.** The reference model's arm chain is **1.106 m**. Feeding the *same* grip distances through it:

| Grip distance | Stretch with old arms | **Stretch with the Blender arm (1.106 m)** |
|---|---|---|
| 1.37 m (`kid`) | 3.7× | **1.28×** |
| 1.56 m (`fat_man`) | 2.5× | **1.45×** |
| 1.88 m (`tall_lanky`) | 2.6× | **1.75×** |

That moves the problem from "impossible" to "a tuning decision". At `MAX_ARM_STRETCH = 1.25` the grip range comes out at `1.106 × 1.25 × 0.97 =` **1.34 m** — only ~14 % shorter than what a similarly-sized archetype has today. A far smaller gameplay change than the raw multipliers suggested.

The constraint has to be expressed as a **ratio, not a distance**, because Phase 2 shrinks the arm for smaller archetypes and the ratio is what stays invariant:

```
reach_multiplier = MAX_ARM_STRETCH × GRAB_MIN_BEND_FACTOR    # ≈ 1.25 × 0.97 ≈ 1.21
```

So `reach_multiplier` stops being a per-archetype authored number (2.3–3.6 today) and becomes a single global constant. The options for what to do at the boundary:

1. **Cut `reach_multiplier` to what the mesh tolerates.** Pick a `MAX_ARM_STRETCH` (≈1.25× is where stretched skinning usually still reads as an arm) and derive `reach_multiplier ≤ MAX_ARM_STRETCH × 0.97`. Honest and simple, but it shrinks the interaction range by roughly half — a real gameplay change that needs playtesting.
2. **Cap the stretch, let the hand fall short.** Gameplay reach unchanged; the arm extends to its cap and points at the object without touching it. Cheapest, but the grab stops reading as a grab at distance.
3. **Cap the stretch and pull the object in.** Keep the current reach for *acquiring* a grab, but clamp the held `grab_distance` to `arm_natural × MAX_ARM_STRETCH`. The grab PD already pulls the object to `origin + camera_forward × grab_distance`, so the object comes to the hand rather than the arm going to the object. Preserves the long-range grab *and* the silhouette; costs a clamp on the scroll-wheel distance.

**Recommendation: option 3**, with option 1 as the fallback if the clamped hold distance feels bad. Whichever wins, `MAX_ARM_STRETCH` becomes a constant next to `GRAB_MIN_BEND_FACTOR` and `arms_length`'s Blender range has to be chosen with it in mind.

**Decision pending.**

---

## Archetypes adapt to the Blender ranges

The direction of authority inverts. Today `SkeletonSizesUtil` computes bone lengths freely from `height` and a set of proportions, and the mesh would have to follow wherever that lands. After the migration, **the Blender file defines the possible range and the archetypes are remapped into it.** If an archetype wants a length outside the range, the archetype gives way — the range was approved artistically, the formula wasn't.

Concretely:

- Each of the 5 bone variables gets a `min`/`max` in metres, measured in Blender (Phase 2/3).
- The archetype stores a normalised `0..1` per variable; `SkeletonSizesUtil` converts to metres via that range.
- **`height` stops being an input and becomes an output** — it falls out of `legs_length + torso_length + head_length`. Everything that currently reads `arch.height` (capsule size, camera height, hip/shoulder widths derived as `proportion × height`) has to read the derived total instead.
- The gait model is unaffected in structure: it still needs `leg_height` in metres, and it still gets it — just from the range instead of from a proportion. `stride` stays exactly as it is.

**Two gaps in the current variable list**, both needed before Phase 2 can fully replace the old fields:

- **`neck_length`** — `head_neck_ratio` currently splits the head allowance between the neck and head bones. The Blender list has `neck_thickness` but no neck length. Either add it, or fold the neck into `torso_length`.
- **Hip width — resolved by removal.** `hips_width_proportion` used to vary from 0.05 (`old`) to 0.08 (`fat_man`). It is **not** becoming a variable: every character now has the same hip width, pinned to the sculpted value. The field is deleted from `EntityArchetype`. One variable, two sculpts and one more extreme to check, dropped for a difference nobody would read.

**Fields that are unaffected and stay as they are:** everything that is behaviour or pose rather than proportion — `strength`, `weight`, `speed`, the stability set, the jump set, `stride`, `step_height`, `slouch`, `shoulders_height`, `shoulders_back`, `arm_openness`, `arm_bentness`, `arm_elbow_openness`, `stance_width`. Note that `shoulders_height` / `shoulders_back` are *rotations* of the shoulder bone, so the shoulder will be rotated as well as scaled — worth remembering when judging the `shoulders_width` extremes in Blender.

---

## Name unification

### Bones — Godot follows Blender ✅ done

The Godot-side bone names were renamed to match the Blender rig, which is the newer and more accurate naming. Three renames, applied across `CustomBonesUtil`, `SkeletonSizesUtil`, `IkUtil`, `RagdollUtil`, `BoneAnimations`, `BoneInstantiator` and `PlayerController`:

| Was | Now | Blender |
|---|---|---|
| `upper_spine` | `higher_spine` | `higher.spine` |
| `left/right_upper_leg` | `left/right_higher_leg` | `higher.leg.L/R` |
| `left/right_upper_feet` | `left/right_foot` | `foot.L/R` |

The `SkeletonSizesUtil` size/offset fields followed too (`higher_spine_size`, `higher_leg_offset`, `foot_size`, …).

**What still needs a map** is only the side convention: Blender uses the `.L`/`.R` *suffix* because it drives X-mirror and Flip Names there, and GDScript can't have dots in an identifier. So `BONE_MAP` in `SkinnedBodyUtil` is now a pure `left_x` ↔ `x.L` translation.

`wrist.L/R` and the finger bones are deliberately absent — nothing on the Godot side drives them (see [Deferred](#deferred--hands-and-fingers)).

**Name collision — fixed.** Godot requires unique names across every node imported from a `.glb`, and bones compete with meshes. The mesh named `head` won, so the **bone** `head` came in as `head_2`. Renaming the meshes in Blender to `arms_mesh` / `body_mesh` / `hands_mesh` / `head_mesh` / `shoes_mesh` resolved it — all 20 mapped bones now bind by their real name. `SkinnedBodyUtil._find_bone` keeps the `_2` fallback (with a warning) so a future collision degrades instead of breaking.

### Variables — one canonical set

The 11 canonical names, used identically in the Blender custom properties, the shape key names, and `EntityArchetype`:

`legs_length` · `arms_length` · `torso_length` · `head_length` · `shoulders_width` · `belly_fatness` · `arms_thickness` · `legs_thickness` · `neck_thickness` · `nose_length` · `nose_width`

(+ `neck_length` and `hips_width` if the two gaps above are filled → 13.)

Note `arms_thickness` / `legs_thickness` split what the Blender file currently calls `extremities_thickness`. The split costs one extra shape key and recovers a distinction the current system has and would otherwise lose: `giga` is muscular on top (`muscularity` 1.0, `fatness` 0.5) while `fat_man` is heavy on the bottom (0.9 / 1.0). One control can't express both.

These replace: `height`, `chest_to_low_spine_proportion`, `legs_to_feet_proportion`, `hips_width_proportion` (deleted), `shoulder_width_proportion`, `head_neck_ratio`, `fatness`, `muscularity`, `reach`, `has_neck`.

**`has_neck` cannot survive** as a bool — the head+neck mesh always exists and can't drop a bone. It becomes `neck_length → 0` with a high `neck_thickness`, or it goes away.

Anything added to `EntityArchetype` must also be added to **`blend_with()`** ([archetypes.gd:369](../../character/abstract/archetypes.gd#L369)) — two archetypes blend at 0.5, and a field missing there silently keeps archetype A's value.

### Typo cleanup (optional, separate commit)

Pre-existing misspellings worth fixing while names are being touched — but as their own mechanical commit, **not** mixed into the migration:

| Current | Should be |
|---|---|
| `strenght`, `throw_strenght` | `strength`, `throw_strength` |
| `foward_stability` | `forward_stability` |
| `uncompatible_archetypes` | `incompatible_archetypes` |
| `left_foot` / `right_foot` | `left_foot` / `right_foot` |
| `raycast_leg_lenght` | `raycast_leg_length` |

`lower_feet_size` / `lower_feet_offset` in `SkeletonSizesUtil` are computed and never used — delete.

---

## What breaks

**Ragdoll — the visual inverts.** Today `RagdollUtil` **hides the skeleton and shows the per-bone rigid bodies**, which are boxes ([ragdoll_util.gd:246](../../character/animation/ragdoll_util.gd#L246)). Left alone, ragdolling would turn the character into a pile of boxes. The fix fits the architecture: **the ragdoll bodies stay invisible permanently, and during ragdoll the same mirror reads the `RigidBody3D`s instead of the `CustomBone`s.** The body≡bone convention already exists in that file. The skinned mesh becomes the only visible thing in both states, and recovery — which already eases the bodies toward the standing pose — keeps working untouched. Must land in **Phase 1**.

**First person loses per-bone granularity.** `set_first_person_visibility` hides individual bones ([bone_instantiator.gd:459](../../character/bone_instantiator.gd#L459)). With five stitched meshes that's gone — but the piece split happens to cover the real case: hide the **head+neck** mesh. What's lost is "show only forearms and feet"; recovering it would need per-bone visibility in the shader (bone index → mask). Phase 1 decision: accept the coarser version.

**Blend shape mode.** Verify the imported `Mesh` ends up in **`BLEND_SHAPE_MODE_RELATIVE`**. In `NORMALIZED` the keys share weight instead of summing, so `belly_fat` + `legs_thin` together give half of each. Bites in Phase 4.

**Species.** `Species` multipliers exist and robot/alien would need their own meshes. `EntityInstantiation.FORCE_HUMAN_SPECIE` pins everything to human today, so this is out of scope — but the five-mesh split is the natural seam for it later.

**Networking and determinism: no impact.** The mesh doesn't travel; it's rebuilt from the seed like the skeleton, and the shape key values are a pure function of the archetype, so every machine computes the same ones.

**Performance: improves.** ~20 `MeshInstance3D`s with blend shapes per character become 5 + one `Skeleton3D`. The `Mesh` resource is shared across instances; blend shape values live per-`MeshInstance3D`.

---

## Open decisions

### Settled

| Decision | Resolution |
|---|---|
| Arm stretch strategy | **Authored and clamped.** Arms get hand-modelled extremes like every other chain; a grab solves for the `arms_length` that reaches, and clamps at 1.0. Past that the hand stops short — accepted. Gameplay reach stays proportional to each character's own arm, so arm length still matters; only the mesh clamps. |
| `deltoid` bone | **Dropped.** It existed to stop the socket stretching under unbounded arm scale. With the arm authored at both extremes that stretch is a modelled shape, so the socket rides `upper.arm` directly. One bone and one rule fewer. |
| Mechanical vs authored chains | **All authored.** The earlier split (arms mechanical, everything else sculpted) is gone; every length variable has two hand-modelled extremes. |
| `neck_length` | **Added** as a variable (Phase 4c). |
| `hips_width` | **Dropped.** Same hip width for every character; the archetype field is deleted. |
| `arms_thickness` / `legs_thickness` split | **Kept split** — a muscular upper body and a heavy lower body have to stay separable. |
| First-person hiding | **Coarse accepted.** `head_mesh` and `body_mesh` hide; arms, hands and shoes stay. The five-piece cut happens to make this exactly right, so no shader masking. |
| Where 0.5 sits | **Authored, not the midpoint.** Hence two-segment interpolation (Phase 4a). |
| Model scale | **1.7 m** for the generic. Every metre constant re-measures after the rescale. |

### Still open

| # | Decision | Blocks |
|---|---|---|
| 1 | How twist / hand orientation gets a real input instead of falling out of the elbow pole | Phase 3 |
| 2 | How attachments (Rive planes, hair, hats, cigarette) anchor and follow the parameters | Phase 3 |
| 3 | The measured `MIN`/`MID`/`MAX` per bone-driven variable — the Blender deliverable | Phase 4a |
