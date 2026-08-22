# Character — Blender Authoring Plan

> **Status: PLAN.** The authoring side of the skinned-character migration. What gets modelled, in what order, and the rules the rig has to obey for the Godot side ([skinned-character-migration.md](skinned-character-migration.md)) to work. That doc is the code half; this one is the Blender half.

---

## The style

- **Low-poly silhouette with baked high-poly normals.** The outline stays faceted (Team Fortress family); the normal map carries the smooth shading so smooth-shaded surfaces don't produce the usual low-poly artefacts.
- **Five separate meshes**, all skinned to one armature: `arms_mesh`, `hands_mesh`, `head_mesh` (head + neck), `shoes_mesh` (feet), `body_mesh` (torso + legs).
- **Soft gradient textures**, little fine detail. This is deliberate and load-bearing: the mesh gets stretched and squashed by the parametric system, and gradients survive distortion where detail work would smear visibly.
- **Facial detail lives on planes**, not in the mesh — flat quads carrying adaptive textures animated in **Rive** (validated as working). Their *placement* is the parametric system's job; what happens *inside* each plane (mouth talking, brows furrowing) is Rive's.
- **Accessories** — hats, hair, beard, cigarette, pipe — are attachments whose placement also follows the parameters.

### The eight planes

| Plane | Count |
|---|---|
| Mouth + lip corners | 1 |
| Chin | 1 |
| Eye + brow + wrinkles | 2 (one per side) |
| Nostrils | 1 |
| Forehead (wrinkles) | 1 |
| Cheekbones (wrinkles) | 2 |

---

## The one rule that organises everything

> **Bones only ever change along their own length. Anything that is thickness, silhouette or shape is sculpted.**

And a second rule that follows from how the character is cut into pieces:

> **Every seam ring is weighted, identically in both meshes, to a bone that does not scale relative to that seam.**

Coincident vertices on either side of a seam must carry **identical weights**. If they differ even slightly, the seam opens the moment anything stretches. This is the single most common way this kind of rig fails.

---

## Everything is authored

**Every length variable is hand-modelled at both extremes** — mesh *and* bone position, at 0.0 and at 1.0. Legs, torso, arms: no exceptions, no mechanical-only chain. The system never invents a shape; it only interpolates between shapes you approved.

This replaces an earlier split where arms were going to be bone-scale-only (no sculpts) because they stretch at runtime and therefore had "no maximum to author". The decision was reversed in favour of artistic control, and it pays for itself immediately — see [why there is no deltoid bone](#why-there-is-no-deltoid-bone).

### The one thing arms give up

The arm **can** be asked to stretch past its authored maximum: reaching for a distant object is gameplay, and gameplay doesn't know about your sculpts. When that happens the arm stops at 1.0 and **the hand simply doesn't reach the object** — the IK points at it without touching it.

That is an accepted cost, deliberately. In practice arms rarely need to go much past their modelled maximum, and the alternative (unbounded stretching with no authored shape behind it) means the mesh leaves artist-approved territory exactly when it's most visible.

**Gameplay reach stays proportional to each character's own arm**, so a long-armed character still reaches further than a short-armed one. The clamp is on the *mesh*, not on the reach. A character whose resting arm sits near the top of the range has less headroom and will show the not-quite-touching hand more often — that's the shape of the trade.

---

## The seam rule

Four seams, four rings. The requirement is the same at every one, and it is the single most common way this kind of rig fails:

> **Coincident vertices on either side of a seam must carry identical weights, and be moved identically by every shape key.**

If they differ even slightly, the seam opens the moment anything stretches.

| Seam | Meshes | Ring weighted to |
|---|---|---|
| Shoulder | `arms_mesh` ↔ `body_mesh` | `upper.arm.L/R` |
| Wrist | `arms_mesh` ↔ `hands_mesh` | `wrist.L/R` |
| Ankle | `body_mesh` ↔ `shoes_mesh` | `foot.L/R` |
| Neck | `body_mesh` ↔ `head_mesh` | `neck` |

Note the shoulder row: the ring is weighted to `upper.arm` **in both meshes**, which means a band of the torso mesh follows the arm bone. That is intentional — it's what makes the deltoid cap swing with the arm instead of sitting rigid.

### Why there is no deltoid bone

An earlier version of this plan added a dedicated `deltoid` bone per side. It is no longer needed, and the reason is worth keeping because the problem it solved is real.

The shoulder is the only seam whose natural far-side bone (`shoulder`) is **lateral** — it does not swing with the arm. So weighting the socket there closes the seam but freezes the shoulder into a plastic doll joint, while weighting it to `upper.arm` deforms nicely but *stretches* when the arm lengthens. One bone cannot both follow the rotation and ignore the scale, so the fix was a second bone that copied the rotation and refused the scale.

**Authoring the arm extremes dissolves that.** Once every arm state is a blend between two sculpted shapes, the socket stretching at `arms_length = 1.0` is not a defect to prevent — it's a shape you modelled. So the socket can hang off `upper.arm` directly: it swings with the arm, it stretches with the arm, and your sculpt says what that stretch looks like.

One bone fewer, one rule fewer. What remains is the seam rule above, which was always required anyway.

*(The same lateral-bone problem exists at the hip. You don't have it because legs and torso are one mesh, so there is no hip seam. Keep it that way.)*

---

## The 0.5 convention

Every parameter defaults to **0.5**, and that default **is** the generic character. Both extremes (0.0 and 1.0) are hand-modelled — mesh *and* bone length.

**0.5 is not the arithmetic midpoint**, and it is not supposed to be. If `legs_length` runs 0.3 → 0.9, the value at 0.5 can be 0.6, or 0.55, or 0.7 — whatever looks right. The curve is asymmetric on purpose; that asymmetry is the artistic control.

Two consequences:

- **Two shape keys per variable**, one per extreme, driven by the half-ranges: `min_key = max(0, (0.5 − v) · 2)`, `max_key = max(0, (v − 0.5) · 2)`. Uniform for every variable, no inverted cases, nothing to remember.
- **Interpolation happens in two segments** on the Godot side (`0 → 0.5` and `0.5 → 1`), which is what lets 0.5 sit off-centre.

### Keep archetypes low in the arm range

Gameplay reach is proportional to a character's own resting arm, and the *mesh* clamps at 1.0. So an archetype resting near the top of the arm range has almost no room left to reach into, and will show the not-quite-touching hand often. Keep archetype resting values in the lower part of the range and the top stays available for reaching.

---

## Phases

Each phase is a stopping point where the character is complete and testable.

### Phase A — The generic character, with arm length

**Goal: one character, aesthetically finished, in the game — plus the one variable it can't do without.**

The generic sits at 0.5 on everything, so almost no parametric work is needed. The exception is **`arms_length`**: the character has to reach for objects from day one, so the arm needs its two authored extremes and its driver. Everything else waits.

That is the whole point of the vertical slice: find out whether you like the style before investing in the system that varies it.

**Mesh and skeleton**

1. **Scale the model to 1.7 m** and apply the scale. Do this first — it is a one-minute operation now and a nuisance after anything is baked or sculpted.
2. **Re-proportion from "fat and tall" to generic.** To change bone lengths without breaking the skinning, don't edit the armature in Edit Mode (the mesh won't follow). Instead: pose the bones in **Pose Mode** → per mesh, **duplicate the Armature modifier and apply the copy** (this bakes the deformation into the mesh) → **Pose → Apply → Apply Pose as Rest Pose**. New proportions, mesh follows, weights intact.
   - Use the same operation to bring the arms down from the current T-pose into an **A-pose, ~30–40° from vertical**. Closer to the procedural rest, better armpit skinning, and the best shot at the hand-twist problem.
3. **Fix the four seam rings** — see [the seam rule](#the-seam-rule). Identical weights on both sides, in both meshes.

**Arm length**

4. **Set `Inherit Scale = None` on `wrist.L/R`** so hands keep their size at any arm extension. (Do the same on `foot.L/R` and `neck` while you're here — they'll be needed in Phase B and it costs nothing now.)
5. **Model the arm at 0.0 and at 1.0** — mesh *and* bone positions. Two sculpts: `arms_length_min`, `arms_length_max`.
6. **Build the driver** for `arms_length`: 4 bone scales + 2 shape keys.
7. **Write down three arm lengths** — at 0.0, at 0.5, at 1.0. Those three numbers are what Godot needs to map gameplay reach onto the parameter.

**Surface and face**

8. **Topology final**, then **UVs**, then the **normal bake**. See [the bake](#the-normal-bake) — it closes the mesh stage, not the project, and shape keys are safe to add afterwards.
9. **Textures** — gradients, low detail.
10. **The eight planes**, placed. Each parented to a head bone with **Inherit Scale = None** so a future `head_length` never stretches a mouth.
11. **Accessories** for the generic: hair, cigarette. Same attachment rules.
12. **Export.**

**Exit:** the generic character walks, grabs, ragdolls and reads as finished art. Reaching for an object stretches the arm through your authored range; past 1.0 the hand stops short, as agreed.

> **Checkpoint after step 7.** Export before the surface work and playtest the deformation. If the arm or the shoulder is wrong, it is far cheaper to fix before UVs and a baked normal map exist.

---

### Phase B — Legs and torso length

- **`legs_length`** — bones `higher.leg.L/R`, `lower.leg.L/R`. Two sculpts.
- **`torso_length`** — bones `lower.spine`, `middle.spine`, `higher.spine`, `chest`. Two sculpts.

Verify the `Inherit Scale = None` from Phase A step 4 by doubling `higher.leg.L`: the foot must stay the same size and stay attached. If it detaches, use **Aligned** instead of **None** on that bone.

**Build drivers for both** — 4 bone scales + 2 shape keys each. Well past the point where moving sliders by hand desynchronises and you sculpt a corrective against the wrong bone length.

---

### Phase C — Extremities thickness

`arms_thickness` and `legs_thickness`, two sculpts each. Pure silhouette, no bones. This is what stops a short-legged character from reading as stubby: the length comes from the bone, the *shape* comes from here.

Sculpt with the seam vertices masked (a `seam` vertex group per mesh, locked while sculpting).

---

### Phase D — Fatness, head, face, neck

`belly_fatness`, `head_length`, `neck_length`, `neck_thickness`, `nose_length`, `nose_width`. Two sculpts each.

`head_length` and `neck_length` are the two that also move bones. `head` is a **leaf** — nothing below it to displace — so its length has to be an explicit bone scale, and the eight planes must not inherit it.

---

### Phase E — Shoulders

`shoulders_width`, last because it is the most complex and the least urgent. It is a lateral bone whose length *is* the width, and it needs correctives: moving the joint outward and letting linear skinning resolve the trapezius and upper back is exactly the case where the mechanical result looks worst.

**Hip width is deliberately not a variable.** Every character has the same hip width. It was in the old capsule archetypes and has been removed rather than carried over — one variable, two sculpts and one more thing to check at every extreme, bought for a difference nobody would read.

---

## The full variable list

| Variable | Default | Bones | Sculpts | Phase |
|---|---|---|---|---|
| `arms_length` | 0.5 | `upper.arm.L/R`, `lower.arm.L/R` | 2 | **A** |
| `legs_length` | 0.5 | `higher.leg.L/R`, `lower.leg.L/R` | 2 | B |
| `torso_length` | 0.5 | `lower/middle/higher.spine`, `chest` | 2 | B |
| `arms_thickness` | 0.5 | — | 2 | C |
| `legs_thickness` | 0.5 | — | 2 | C |
| `belly_fatness` | 0.5 | — | 2 | D |
| `head_length` | 0.5 | `head` (leaf → scale) | 2 | D |
| `neck_length` | 0.5 | `neck` | 2 | D |
| `neck_thickness` | 0.5 | — | 2 | D |
| `nose_length` | 0.5 | — | 2 | D |
| `nose_width` | 0.5 | — | 2 | D |
| `shoulders_width` | 0.5 | `shoulder.L/R` | 2 | E |

Twelve variables. `neck_length` is new — it was a gap in the earlier list. `extremities_thickness` was split into `arms_thickness` / `legs_thickness` so a muscular upper body and a heavy lower body stay separable. **Hip width is not a variable** — same for every character, by decision.

---

## The normal bake

One bake, on the **base mesh at rest** — generic proportions, no pose, every shape key at 0. High-poly duplicate → project onto the low-poly. bueno pero entonceThere is no need for a bake per shape key or per extreme.

**It survives the deformations**, and the reason is worth knowing: a **tangent-space** normal map is stored *relative to the surface*, not to the world. When bones bend or stretch the mesh, the surface's tangent frame moves and the map rides along with it. (This is exactly why tangent space, not object space, is the right choice for a skinned character — object space would break the moment a limb rotated.) The only limit is the same one the textures have: stretch far enough and the detail reads as stretched. With soft organic forms that is negligible — the same bet the gradient textures already make.

**The order that matters:**

```
shape → final topology → UVs → BAKE → shape keys
```

The bake is stored against the **UVs**, so changing topology or UVs afterwards means re-baking. **Shape keys change neither**, so they are safe to add after the bake — you do *not* need the twelve variables resolved before baking. The bake closes the mesh stage (Phase A), not the project.

One small caveat: baked detail stays where it was in UV space, so a wrinkle baked onto a flat cheek is still there when a shape key inflates that cheek. For soft forms this doesn't read.

---

## Driver recipes

A custom property on the armature object, then one driver per output. For a variable `v` with bone scale range `lo → hi`:

```
bone scale Y        →  lo + (hi - lo) * v          # but see the two-segment note
shape key "…_min"   →  max(0, (0.5 - v) * 2)
shape key "…_max"   →  max(0, (v - 0.5) * 2)
```

Because 0.5 is off-centre, the bone scale is also two-segment in Godot. For **preview purposes in Blender** a single linear driver is close enough; what matters is that the sculpts are made at the true extremes. Record the three lengths (at 0.0, 0.5, 1.0) and hand those to the Godot side — those numbers, not the driver, are what ships.

**Build drivers only for variables with 3+ outputs.** A pure-sculpt variable like `nose_length` has one output; its own shape key slider is already the control.

---

## Combination previews

Save presets as **keyframes**, not as a rig feature: frame 1 neutral, frame 10 "short legs + thin arms", frame 20 "long torso + fat belly", and so on. A keyframe captures bone scales *and* shape key values, so scrubbing the timeline browses your presets, and you can read exact numbers off any frame.

Check at least the combinations that will actually exist, and specifically the ones that stress the seams: both length variables at minimum simultaneously, and any thickness at an extreme combined with a length at an extreme.

---

## What ships to Godot

1. The `.glb` — five meshes, the armature, shape keys, at 1.7 m.
2. **Three lengths per bone-driven variable**: the value at 0.0, at 0.5, and at 1.0. Three, not two — because 0.5 is authored and deliberately off-centre, so Godot interpolates (and inverts) in two segments:

   ```
   L ≤ L₀.₅ :  v = 0.5 · (L − L₀)   / (L₀.₅ − L₀)
   L > L₀.₅ :  v = 0.5 + 0.5 · (L − L₀.₅) / (L₁ − L₀.₅)
   ```

   That inverse is what lets Godot answer "the grab needs an arm this long — what `arms_length` is that?" and clamp at 1.0.
3. Shape key names, matching exactly between meshes where a variable drives more than one.
