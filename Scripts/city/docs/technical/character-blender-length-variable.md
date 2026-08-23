# Authoring a length variable in Blender

The recipe for giving a bone chain a parametric length that Godot can drive — worked through on `arms_length`, but the same for `legs_length` and `torso_length`.

It produces exactly three things:

1. **One shape key** on the affected mesh, named after the variable.
2. **Two numbers**: the chain length at `0.0` and at `1.0`.
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

**On picking the factor.** The job of the arm at `1.0` is *fully extended reaching*, not "a long-armed character" — those are different things. The gameplay reach is `resting arm × MAX_ARM_STRETCH`, so a maximum near that keeps the hand touching what the game lets you grab. The bigger the factor, the further apart the two authored shapes and the less control you have over the middle — which is the arm you look at almost all the time.

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

## 7. The driver *(optional)*

Only so you can preview with one slider. **Godot never reads it** — Blender drivers and custom properties do not survive the `.glb`.

**The property.** Object Mode → armature → Properties → **Object** tab → **Custom Properties** → **New** → gear icon → name `arms_length`, Min `0`, Max `1`, Default `0`.

**The bones.** Pose Mode → select `upper.arm.L` → `N` panel → **Item** → right-click **Scale Y** → **Add Driver**. In the popup:

- Variable type: **Single Property** — the small dropdown left of `var`. It defaults to *Transform Channel*, which has no Path field at all; this is the usual place to get stuck.
- **Prop**: Object → the armature
- **Path**: `["arms_length"]` — brackets *and* double quotes, because it is a custom property
- **Expression**: `1 + (factor − 1) * var`

Repeat for `upper.arm.R`. **The forearms get no driver** — they inherit, and driving them compounds the scale.

**The shape key.** Select `arms_mesh` → **Object Data** tab → **Shape Keys** → click `arms_length_max` → right-click its **Value** slider (below the list) → **Add Driver** → same Prop and Path, **Expression: `var`**.

*Sanity check:* with `arms_length` at 0 the bone's Driver Value reads `1.000`; at 1 it reads the factor.

---

## 8. Export

1. **Pose → Clear Transform → All**, shape key Value at `0`.
2. Hide the `_ref` collection (eye icon in the Outliner).
3. Confirm the character shows the short arms.
4. Export `.glb` over `Models/character.glb` with **Shape Keys** on and **Include → Limit to → Visible Objects** ticked.

---

## What ships to Godot

**The two chain lengths**, and nothing else.

Read them in the armature's Edit Mode: select the bone → `N` panel → **Item** → **Length**. Sum `upper.arm` + `lower.arm` for the `0.0` value; multiply by the factor for `1.0`.

Godot re-measures the `0.0` length from the `.glb` itself, so in practice **the factor alone is enough** — pose scale is not exported, which is the one thing the file cannot tell us.

Worked example: `0.153838 + 0.218627 = 0.372465` at `0.0`, factor 4 → `1.48986` at `1.0`.

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
