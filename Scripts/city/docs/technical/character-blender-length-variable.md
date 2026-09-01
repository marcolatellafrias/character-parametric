# Authoring a length variable in Blender

The recipe for giving a bone chain a parametric length that Godot can drive — worked through on `arms_length`, but the same for `legs_length` and `torso_length`.

It produces exactly three things:

1. **One shape key** on the affected mesh, named after the variable.
2. **One number**: the factor the bone was scaled by. Godot measures the rest length itself, and pose
   scale is the one thing the `.glb` cannot carry.
3. Nothing else. Drivers and reference objects are authoring aids and never leave Blender.

---

## The one decision behind the whole recipe

A blend shape always runs from *base mesh* → *sculpted target*. So with a single shape key, **the base mesh has to be one of the two extremes**.

**The base is `0.0`** — the short version. The asset's neutral is the compact character and it grows from there; the shape key rises as the arm stretches, which is the direction the grab pushes. (Base at `1.0` works identically in the maths but leaves a long-armed character as the neutral asset, which is odd to look at.)

An earlier version of this plan put the base at `0.5` with two shape keys, so the middle could be authored too. That was dropped: one sculpt, one shape key and a plain lerp beat authoring the midpoint, which is only ever a blend of two shapes you already approved.

---

## Before you start

**`Inherit Scale = None` on `wrist.L/R`** — Properties → **Bone** tab (bone icon) → **Relations** → **Inherit Scale**. Without it the hand grows with the arm.

*Verify:* scale `upper.arm.L` and watch the hand. Same size, still attached to the wrist.

---

## 1. Shorten the base to the minimum

The arms as modelled become the **shortest arm any character will have**, so shorten them first.

Either route works — what matters is the end state (rest bones short, mesh matching, weights intact):

- **Pose Mode**: scale the bones → per mesh, duplicate the Armature modifier and **Apply** the copy → **Pose → Apply → Apply Pose as Rest Pose**.
- **Edit Mode**: edit the bone rest lengths and move the mesh vertices to match by hand.

> ⚠️ **If you take the Edit Mode route, check what hangs below.** Editing the armature's rest does **not** move meshes. Shortening `lower.arm` moves the head of `wrist`, but `hands_mesh` and `nails_mesh` stay put and end up floating where the long forearm used to end.

> ⚠️ **Applying a modifier fails on a mesh that already has shape keys.** If you take the Pose Mode route, it has to happen before step 3.

### Re-basing when the model is not an extreme

The arm was already the shortest arm, so step 1 was free. Usually it is not: the leg was authored at
what should be the *middle* of its range, and making the model the `0.0` means genuinely shrinking it.

**How much.** Take it from the band the code already uses, so no archetype changes meaning. The leg's
was `0.65 … 1.30` around the sculpt, so the new base is **65 %** of it and the factor is
`1.30 / 0.65 = `**`2.0`**.

**The archetype value that reproduces the original moves, and it is no longer `0.5`.** Solve
`1 + (F−1)·v` against the old length: for the leg, `1/0.65 = 1.5385` ⇒ **`v = 0.5385`**. Put it in the
generic archetype or the reference character silently gets shorter. This is also why the midpoint-bulge
fix is load-bearing here and not a nicety — the generic now *lives* at mid-range, where the error peaks.

**Only two meshes moved**, and knowing which saves the whole step: anything whose geometry sits above
the hip is untouched by a leg scale, so the shape-keyed arm meshes never enter the picture and the
"cannot apply a modifier with shape keys" wall never comes up. Check with the mesh's bounding box, not
by eye.

> ⚠️ **THE CHARACTER HAS TO END UP STANDING ON THE ORIGIN.** Scaling `higher.leg` pivots at the hip, so
> the feet rise — for the leg, by 0.319 m. Godot reads the sole-to-ankle distance as `foot.L`'s global
> rest height, so a model left floating tells it the character has 35 cm soles, and it stands them that
> far in the air. It is the float-and-never-step bug recorded in `character-animation.md`.
>
> Fix it in Object Mode — select everything, move down, **`Object → Apply → All Transforms`**. Applying
> is the part people skip: without it the offset ships as a node transform and the bone rests, which is
> what Godot actually reads, do not move at all. A pure translation is safe on shape-keyed meshes.
>
> Verify by measuring the exported `.glb`, not in the viewport: ankle back to its original height, chain
> at exactly `factor × new base`, thigh/calf fractions unchanged.

---

## 2. The ghost reference

A wireframe copy of the short arm, so you can see what you are moving away from.

1. Object Mode, pose cleared → select `arms_mesh` → `Shift+D` → **`Esc`** (stays in place).
2. Rename it `arms_ref`.
3. Properties → **Modifiers** (wrench) → on its **Armature** modifier, switch **Realtime** off. It now stays pinned at the short rest.
4. Properties → **Object** tab (orange square) → **Viewport Display** → **Display As: Wire**.
5. `M` → **New Collection** → `_ref`.

Bones are useful as reference too: select the armature → **Object Data** tab → **Viewport Display** → tick **In Front**, **Display As: Stick**.

---

## 3. Create the shape key

Select `arms_mesh` → Properties → **Object Data** tab (green triangle) → **Shape Keys** panel → `+` (creates **Basis**) → `+` again → rename the new key **`arms_length_max`** → set its **Value** to `1.0`.

> ⚠️ **Everything you edit in Edit Mode goes into whichever shape key is highlighted in the list.** With `Basis` selected you are silently editing the short arm instead. Check it every time you re-enter Edit Mode.

Only the mesh that actually deforms needs one. `body_mesh` does **not**: the scale pivots at the head of `upper.arm`, which *is* the shoulder joint, so those vertices have zero displacement by definition and the seam cannot open. `hands_mesh` and `nails_mesh` do not either — the hand only translates.

---

## 4. Pose the bones at the maximum

Pose Mode → select **only `upper.arm.L` and `upper.arm.R`** → Transform Pivot Point **Individual Origins** (header dropdown, or `.`) → `S` `Y` `Y` → type the factor.

The second `Y` switches to the bone's local axis. With one `Y` you scale along world Y and it comes out wrong.

> ⚠️ **Do not select the forearms.** `lower.arm` is a child and inherits its parent's scale, so scaling both compounds: 4 × 4 = **16**. The chain stretches uniformly from the upper arm alone. The same trap bites again at the driver stage.

**On picking the factor.** The job of the arm at `1.0` is *fully extended reaching*, not "a long-armed character" — those are different things. The gameplay reach is `resting arm × arm_stretch`, so a maximum near that keeps the hand touching what the game lets you grab.

A big factor used to be dangerous because of [the midpoint bulge](#the-midpoint-bulge), which grows with it and lands on the arm you look at almost all the time. With the corrected shape-key curve that is gone, and a large factor costs only sculpting resolution — which is why ×4 is fine.

---

## 5. The viewport setup — the part that matters

Two toggles on the **Armature** modifier do different jobs:

| Toggle | What it does |
|---|---|
| **Display in Edit Mode** | *shows* you the deformed result |
| **On Cage** | puts the vertices you *grab* at the deformed positions |

**Display in Edit Mode ON, On Cage OFF.** Also turn **Proportional Editing** off (`O`).

You then see the stretched arm updating live while grabbing handles drawn at the short positions. `G X` behaves normally, and you drag until the long arm looks right — **no arithmetic**. Sensitivity is the factor to one, so use small moves; `Shift` while dragging gives fine control.

> ⚠️ **Why not On Cage.** It back-solves your movement through the deformation, dividing the along-bone component by the factor and the across-bone component by one. Where every vertex shares one bone that is uniform and the loop translates cleanly — but at the elbow, and especially at the wrist where a bone scaled ×N blends with `wrist` scaled ×1, it differs per vertex and the loop **scales and skews instead of moving**. Those are exactly the loops you most want to move.

> ⚠️ **Both toggles off** leaves you editing blind: everything you move is multiplied by the factor afterwards, so you would have to pre-compensate by dividing. It works, but only for a purely numeric redistribution — and the rest arm looks wrong while you do it, because it is a pre-compensated shape rather than one you are meant to like.

---

## 6. Adjust the loops

`Tab` into Edit Mode and move loops until the long arm reads right — typically so the end caps and the elbow keep their size and the straight segments absorb the whole stretch.

Check by leaving Edit Mode; compare against the short version with **Pose → Clear Transform → All** and the shape key Value at `0`.

---

## 7. The driver

**Godot never reads it** — Blender drivers and custom properties do not survive the `.glb`. But it is not decoration either: it is the only way to preview an **intermediate** value, and an intermediate value is the one thing two authored extremes never show you. Wire it with the expressions below and the preview matches the game; wire the shape key with plain `var` and it lies, in exactly the way [The midpoint bulge](#the-midpoint-bulge) describes.

**The property.** Object Mode → armature → Properties → **Object** tab → **Custom Properties** → **New** → gear icon → name `arms_length`, Min `0`, Max `1`, Default `0`.

**The bones.** Pose Mode → select `upper.arm.L` → `N` panel → **Item** → right-click **Scale Y** → **Add Driver**. In the popup:

- Variable type: **Single Property** — the small dropdown left of `var`. It defaults to *Transform Channel*, which has no Path field at all; this is the usual place to get stuck.
- **Prop**: Object → the armature
- **Path**: `["arms_length"]` — brackets *and* double quotes, because it is a custom property
- **Expression**: `1 + (factor - 1) * var` — with the factor 4 from step 4, that is `1 + 3 * var`.

> ⚠ **Type the minus from your keyboard.** The expression is Python, so a typographic minus (−) pasted in from prose raises a SyntaxError and leaves the driver red without saying why.

Repeat for `upper.arm.R`. **The forearms get no driver** — they inherit, and driving them compounds the scale.

**The shape key.** Select `arms_mesh` → **Object Data** tab → **Shape Keys** → click `arms_length_max` → right-click its **Value** slider (below the list) → **Add Driver** → same Prop and Path, and:

- **Expression**: `4 * var / (1 + 3 * var)` — with factor 4. In general `F * var / (1 + (F-1) * var)`.

**Not `var`.** It is the same value at both ends and wrong everywhere between them; see
[The midpoint bulge](#the-midpoint-bulge) below for why. Godot drives it with the same curve.

*Sanity check:* with `arms_length` at 0 the bone's Driver Value reads `1.000`; at 1 it reads the factor.

---

## The midpoint bulge

**The single most important thing on this page.** Authoring two extremes and blending between them
does *not* give you the in-between you sculpted, and the error is largest exactly where the character
spends all its time.

### Why

The final mesh is **(bone scale) × (shape-key blend)**. Drive both from the same `0..1` and you are
multiplying two linear functions, which is **quadratic**: exact at `0.0` and `1.0` — the two places
you authored — and off everywhere between.

Work it through on the elbow, which you sculpted to *keep its size*. Keeping its size at `1.0` means
its rest size there is `1/F` of the short arm, because the bone multiplies it back by `F`. Halfway:

| | factor 4 |
|---|---|
| blended rest size | `(1 + 1/4) / 2` = **0.625** |
| bone scale | **2.5** |
| what you see | 0.625 × 2.5 = **1.5625** |

The elbow swells **56%** and nothing you sculpted asked for it. The peak error is `(1+F)²/(4F)`, so it
grows with the factor: **+56%** at ×4, +12.5% at ×2, +4% at ×1.5.

There is a second symptom that reads differently and is the same cause: at `arms_length` 0.5 the
corrective is applied at 0.18 when it should be at 0.47, so the result looks like the arm was
stretched by the bone alone and your sculpt barely counts.

### The fix

**The shape key does not have to sit at the same value as the length.** They are two drivers and
decoupling them cancels the quadratic exactly:

```
w  =  F * v / (1 + (F-1) * v)   =   F * v / s
```

where `v` is the length parameter and `s` the bone scale. It still gives 0 at 0 and 1 at 1, so both
authored extremes are untouched — it only changes the path between them.

It comes straight out of demanding that a constant-size feature stay constant: `s * (1 - w(1 - 1/F)) = 1`
for every `s`, which solves to `w = (1 - 1/s) / (1 - 1/F)`. So **everything you sculpted to keep its
size keeps it at every intermediate value**, not just at the ends. Verified in Godot: the elbow reads
`1.000×` across the whole range.

Features you sculpted to scale *proportionally* are unaffected — their rest size is the same in both
shapes, so no value of `w` moves them.

### What this means for the factor

The old warning here — *the bigger the factor, the less control over the middle* — was describing this
bulge without naming it. With the corrected curve the reason mostly evaporates, and a large factor
costs only sculpting resolution, not correctness. That is what makes ×4 fine.

### Applying it to legs and torso

This is a property of the technique, not of the arm. Every chain authored this way needs the same
curve, with its own `F`. In Godot it lives in `SkinnedBodyUtil._write_arm_shape`; a second chain gets
the same expression with its own factor.

---

## 8. Export

1. **Pose → Clear Transform → All**, shape key Value at `0`.
2. Hide the `_ref` collection (eye icon in the Outliner).
3. Confirm the character shows the short arms.
4. Export `.glb` over `Models/character.glb` with **Shape Keys** on and **Include → Limit to → Visible Objects** ticked.

---

## What ships to Godot

**The factor**, and nothing else — one per chain, in `ReferenceRig`: `ARM_MODEL_FACTOR = 4.0`,
`LEGS_MODEL_FACTOR = 2.0`. Godot's side is then two entries in `SkinnedBodyUtil.STRETCH_CHAINS` and a
call to `SkeletonSizesUtil.authored_chain`; there is no per-chain logic to write.

Everything else Godot measures from the `.glb` on load: every bone's rest length, and from those the chain, its internal proportions, and the mesh scale. Pose scale is the single quantity glTF does not carry, which is exactly why the factor has to be handed over by hand.

If you want the lengths anyway: armature Edit Mode → select the bone → `N` panel → **Item** → **Length**. Worked example: `0.153838 + 0.218627 = 0.372465` at `0.0`, factor 4 → `1.48986` at `1.0`.

---

## Changing the mesh after the shape key exists

You will. Adding a loop cut for a sleeve fold, tweaking the silhouette — normal iteration.

**Adding geometry is safe.** Blender propagates new vertices into *every* shape key, interpolating each one along the edge it was cut into, so the new loop lands at the proportional position in both the short and the long arm. Usually it is right first time.

The routine:

1. Clear the pose, shape key Value at `0`, and select **`Basis`** in the list — you are cutting on the base shape.
2. Edit Mode, make the change.
3. Select `arms_length_max` again, pose at the maximum, **Display in Edit Mode ON / On Cage OFF**.
4. Check where the new geometry landed on the long arm and adjust it there if needed.

**What does force a redo:** anything that changes *which vertex is which*, because a shape key is stored as "vertex N sits here" and the correspondence is simply gone. That means applying a modifier (Blender refuses outright while shape keys exist), Symmetrize, remeshing, retopology, or joining objects. Delete the shape keys, do the operation, sculpt the maximum again.

Hence the general rule: **close the topology before creating shape keys.** Adding detail afterwards is fine; restructuring is not.

---

## Before reaching for a shape key at all

Some of what a corrective would fix is a **weighting** problem, and weights cost nothing and work at every intermediate value automatically:

- The shoulder-end cap weighted to **`shoulder`** — a bone that does not scale with the variable — simply does not stretch.
- The wrist-end cap weighted to **`wrist`** (`Inherit Scale = None`) does not stretch either, and translates with the wrist.
- The straight segments, weighted to the scaling bones, absorb the whole stretch.

That leaves only the elbow, which on a low-poly cylinder is a couple of loops. Try the raw stretch with the caps re-weighted before assuming a sculpt is needed — it may already be enough.
