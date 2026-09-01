# The character appearance system

Every knob that makes one character look different from another: what it changes, how it is authored,
and what it costs. The per-variable Blender recipe lives in
[character-blender-length-variable.md](character-blender-length-variable.md); the art direction in
[character-blender-authoring.md](character-blender-authoring.md). **This page is the map** — which
mechanism each parameter uses and why, and where the system would explode if built the obvious way.

---

## The three mechanisms

Every parameter uses exactly one of these. Knowing which one decides everything else about it.

| | **A — Length** | **B — Shape** | **C — Placement** |
|---|---|---|---|
| Changes | bone length **and** mesh | mesh only | nothing of its own |
| Authored as | bone scale + corrective shape key | one shape key | *nothing* — it follows |
| Godot drives | bone scale + shape key, on the `F·v/s` curve | shape key, linear | — |
| Examples | arms, legs, torso, frame, head | thickness, belly, neck width | face planes, accessories |

**The dividing line for A vs B** is the one already in the docs: *does the engine read this number?*
Reach, height and stride are gameplay, so they are bone lengths. A belly is not.

**C is the important one** and the least obvious. A face plane or a pair of glasses is never
positioned by code and never has its own shape key. It is *skinned*, and it inherits whatever the
thing it is attached to does. Getting C right is what stops this system from becoming a matrix.

---

## The rule that governs C

> **A shape key moves mesh. A bone moves everything attached to it.**

That asymmetry decides how every accessory and every face plane must be built:

- A parameter expressed as a **bone** (class A) propagates for free. Skin the beard to the jaw and it
  follows the jaw forever, no authoring, no code.
- A parameter expressed as a **shape key** (class B) propagates to **nothing**. A plane parented to a
  bone will not follow it. The only way to make it follow is to give that plane the *same shape key*,
  authored by hand.

So the cost of a class-B parameter is not one sculpt — it is one sculpt **per mesh that must react to
it**. With ~12 face planes and several parameters, that is the matrix that explodes.

### The consequence, stated as a rule

**If other things must move with it, make it a bone.**

`nose_length` is the case that forces this. It moves the nose *and* the jaw line, which moves the
mouth plane, the beard, and the chin-wrinkle plane. As a shape key that is four sculpts that must be
kept consistent forever. As a **bone** — a small `nose` bone, and a `jaw` bone — it is zero: the
planes are skinned to the jaw, the beard to the jaw, and they follow.

It also costs nothing conceptually, because it reuses machinery that already exists and is already
correct: bone-length parameters are measured from the model, corrected for the midpoint bulge, and
mirrored to the mesh automatically.

This does **not** contradict the plane-with-a-texture decision. Planes exist so that *appearance*
(which eyebrow, which wrinkle, which mouth) is a texture swap instead of a rig. Their *position* is a
different question, and skinning is the cheap answer to it.

---

## Catalogue

### Class A — length (bone + mesh)

| Parameter | Bone scaled | `Inherit Scale = None` on | Meshes | Assessment |
|---|---|---|---|---|
| `arms_length` | `upper.arm.L/R` | `wrist.L/R` | `arms_mesh` | **Done.** The only one that also varies at runtime. |
| `legs_length` | `higher.leg.L/R` | `foot.L/R` | `body_mesh` | **Done.** Factor ×2. See [re-basing](#re-basing-when-the-model-is-not-an-extreme). |
| `torso_length` | `lower.spine` | `shoulder.L/R` | `body_mesh` | Medium. No new mechanism. |
| `frame_width` | `shoulder.L/R` | `upper.arm.L/R` | `body_mesh`, `arms_mesh` (seam) | Cheaper than it looks — see below. |
| `head_height` | `head` | — (leaf bone) | `head_mesh` | Anchored at the jaw — see [the face](#the-whole-face-is-two-variables). |
| `nose_length` | `nose` *(to be added)* | — | `head_mesh` | Bone **on purpose**. With `head_height` it is the entire face. |

Only the **first** bone of a chain is ever scaled; the rest inherit. Scaling two bones of one chain
multiplies them (4 × 4 = 16), which is the trap the recipe warns about twice.

### Class B — shape (mesh only)

| Parameter | Meshes | Notes |
|---|---|---|
| `arms_thickness` | `arms_mesh`, `body_mesh` (shoulder junction) | Two meshes, one name, one value. |
| `legs_thickness` | `body_mesh` | |
| `belly` | `body_mesh` | |
| `neck_width` | `body_mesh` or `head_mesh`, wherever the neck lives | Trivial — nothing hangs off it. |

Class B keys are driven **linearly**. The midpoint-bulge correction exists only because a length key
is multiplied by a bone scale; with no bone in the loop there is nothing to correct, and applying the
curve anyway would be wrong.

### Class C — placement (follows, authored nowhere)

**Face planes** — mouth, eyes (×2), brows (×2), forehead, chin, cheeks, tear-trough. Quads (sometimes
bent) skinned to `head` / `jaw` / `nose`. Appearance is the texture; the mouth and eyes are driven by
Rive.

**Face meshes** — hair, beard, mouth accessory (cigarette, pipe), eye accessory (glasses, monocle,
patch). Skinned, not parented, for the reason below.

**Body** — back / chest / arm hair planes, hand rings, chest name card. Skinned to the nearest bone
(`chest`, `wrist`, finger bones).

---

## Per-chain notes

### Legs — done, and the trap was somewhere else

Shipped with factor **×2**: the model was shortened to 65 % in Blender so the `0.0` end is a real
extreme, and `generic.legs_length = 0.5385` puts the character back at the 0.9119 m it always had.

Both worries below turned out to be non-issues, as predicted. **The one that actually bit was neither
of them:** shortening the legs lifts the feet off the floor, and Godot reads the shoe's thickness as
`foot.L`'s global rest height — so a model left floating tells it the character has 35 cm soles and it
stands them in the air. See [re-basing](#re-basing-when-the-model-is-not-an-extreme).

### Legs — the worries that were already handled

**"It raises and lowers the whole character."** Already solved, and not by the leg code:
`standing_pelvis_height` is derived as `ankle_height + leg_chain × STAND_EXTENSION`, and
`total_height` is a **result** of the three lengths, not an input. The capsule, the camera, the
interaction origin and the HUD all read those. A longer leg makes a taller character with no extra
work.

**"The loop cuts are at an angle, not parallel like the arm."** Not a problem. The bone scales along
its own axis, so each vertex moves by its own along-axis coordinate: a slanted loop stays slanted and
translates. And you sculpt the extreme by hand in rest space anyway — the angle never enters any
formula.

**Legs are in fact easier than arms**, for a reason worth stating: **the leg shape key never changes
at runtime.** The grab stretches the arm every frame; nothing stretches a leg — when the ground is
uneven the *pelvis drops* and the leg keeps its length. So `legs_length` is set once at build and
never touched again.

That generalises: **`arms_length` is the only runtime-varying shape key in the whole system.**
Everything else is constant per character.

### Torso — four bones, one scale

Scale `lower.spine` only; `middle.spine`, `higher.spine` and `chest` inherit. `shoulder.L/R` need
`Inherit Scale = None` so the frame does not grow with the torso.

`hip.L/R` are **root bones** in the model, so they never inherit the spine's scale — which is what we
want, and it is safe because the spine chain grows *upward* from the pelvis. The hips sit at the
pelvis, which does not move.

### Frame width — cheaper than it looks

The fear is that it changes three things at once (torso silhouette, shoulder bone, arm position).
Two of the three are free:

- `upper.arm` is a **child** of `shoulder`, so lengthening the shoulder carries the whole arm outward
  by itself. Nothing to author.
- Godot needs no code change: `shoulder` joins `STRETCH_BONES` and `_detach_children_of_stretched`
  reparents `upper.arm` automatically, exactly as it already does for `lower.arm` and `wrist`.

What is left is genuinely a **sculpting** job — the torso silhouette and the shoulder seam — not a
systems one. `upper.arm` ends up carrying two scales at once (inherited from the frame, cancelled;
and its own, for arm length). Blender's `Inherit Scale = None` cancels only the parent's, so they stay
independent.

### Head — simplest, with one caveat

`head` is a **leaf bone**: nothing hangs off it, so there is no inherit-scale problem and no other
mesh is affected.

The caveat is the accessories. A hat or hair skinned 100% to `head` gets the full scale, so a longer
head gives a **stretched** hat. Either skin those to a non-scaling bone (a `head.socket` child with
`Inherit Scale = None`) or accept the stretch as characterful. Decide once, per accessory.

---

## Can a thickness key and a length key coexist?

**Yes, cleanly** — and it is worth knowing exactly why, because the reason is also the condition.

Shape keys are per-vertex deltas in rest space; they add. The final rest position is
`base + w_len·Δ_len + w_thick·Δ_thick`, and then the bone scale multiplies. The two do not fight
because they act in **orthogonal directions**: length displaces along the bone, thickness across it.

The condition is the one already in the recipe:

> **The bone must be scaled along its own axis only (`S Y Y`), never uniformly.**

A uniform scale would multiply the radial delta too, and thickness would become a function of length.
With axis-only scale, the radial delta passes through untouched at every length. This is also why the
midpoint-bulge curve is only ever applied to the length key.

Two authoring notes:

- Sculpt the thickness key with the length key at `0`. The stored delta is the same either way, but
  what you *see* is not, and you want to be looking at the shape you are editing.
- Check the result at length `1` before moving on. Adding geometry is safe; restructuring is not.

The same answer covers `legs_thickness` × `legs_length` and `belly` × `torso_length`.

---

## The face, in detail

### Two kinds of thing

**Planes** carry appearance in the texture. Swapping the texture swaps the eyebrow, the wrinkle, the
mouth — no rigging, no shape key, no new geometry. The mouth and the eyes are Rive surfaces, so they
blink and speak by animating that texture.

"Plane" is shorthand. In practice each one is a **small strip of several quads, loop-cut and bent** to
follow the surface it sits on and to give the texture some depth — a brow is three quads with the
middle one largest; the mouth, eyes and forehead are the same idea. That changes nothing about how
they are driven, and two details follow from it:

- **A strip has no single normal.** When a bone has to be aligned to one (only the brows need this),
  build the orientation from *all* the strip's faces selected, not one — Blender averages them.
- **A rigid strip on a curved surface lifts at the ends** if it is rotated far enough. Real, but only
  the brows rotate, and only by small angles. Float the strip a fraction off the skin if the range
  needs to be wide.

**Meshes** (hair, beard, glasses, cigarette) carry appearance in the geometry, and are picked from a
set rather than blended.

### The whole face is two variables

Not a simplification forced by the budget — a consequence of the head being low-poly, and it spans
more of the space than it looks.

| Variable | Anchored so that | Therefore controls |
|---|---|---|
| `head_height` | the **cranium keeps its size**; the added height lands in the **jaw** | total face length |
| `nose_length` | the **nose itself lengthens** — real geometry, its own corrective key — and in doing so **pushes the mouth plane and the face geometry below it down** | nose size, *and* where the mouth sits within that length |

`nose_length` is doing two jobs at once, and both are wanted. It is a full class-A parameter in its own
right — the `nose` bone scales, the nose mesh stretches with it, and a corrective key decides what
keeps its size (nostrils and tip are the natural "end caps"; the bridge absorbs the length, exactly as
the arm's straight segments do). The displacement of everything below it is not a side effect to be
tolerated but the second half of the point.

Stated the useful way: **one sets the length of the face, the other sets the nose and, with it, where
the mouth falls inside that length.** That is a genuine 2-D space, not two settings, and it is why so
few knobs go so far:

- long face, long jaw, short nose — mouth stays high, chin runs long
- long face, short jaw, long nose — mouth pushed down, little chin below it
- long face, everything mid — the neutral of that length
- short face with either extreme — a compressed version of the same two readings

The mechanism is **exactly the arm's**, with a different choice of what keeps its size. The arm's
corrective shape key is authored so the end caps and the elbow stay the same and the straight segments
absorb the stretch; the head's is authored so the **cranium** stays the same and the **jaw** absorbs
it. Same technique, same class A, different artistic decision about where the stretch goes.

Two things follow that are worth being explicit about:

- **This design depends on the midpoint-bulge fix.** "The cranium keeps its size" is precisely the
  property that the naive `w = v` pairing breaks in the middle — a skull that swells 56% at
  intermediate values would make the whole scheme unusable, and it would only show up on the faces
  nobody authored.
- **Both are bones, so everything on the face follows for free** — every plane, the beard, the hair,
  the glasses. This is the payoff of the "if other things must move with it, make it a bone" rule,
  and the face is the case that pays for it most.

Neither ships with the generic character. They are written down here because they decide how the head
is modelled *now*: the cranium and the jaw want to be separable loops, and the mouth plane wants to be
weighted to whatever will become the nose/jaw bone rather than rigidly to `head`.

### Planes that move but do not stretch

Decided while unwrapping: the cheekbone, tear-trough, mouth and chin planes **translate** with the face
variables but keep their size. Simpler to author, and the difference is not worth the complexity.

It is not automatic. A plane weighted to `jaw` scales when `jaw` scales; to translate only, weight it
to a **child bone with `Inherit Scale = None`**, placed where the plane sits.

That is the wrist pattern, and by now it is the rig's most reused idea:

| Plane / mesh | Hangs off | Result |
|---|---|---|
| hand + fingers | `lower.arm` | lands at the stretched arm's end, unstretched |
| mouth | `nose` | pushed down by a longer nose, same size |
| chin | `jaw` | follows a longer jaw, same size |
| cheekbone | `jaw` | same |

The tear-trough needs nothing: it hangs off `head`, which never scales.

For a plane that *does* stretch, the consequence is about **what is drawn**, not about UVs: the stretch
is single-axis, so lines running along it survive and circles become ovals.

### How anything on the face gets positioned

**By skinning, always.** Never by code and never by a per-plane shape key. The chain is:

```
head_length / nose_length   → bone           → skinned plane follows      (free)
neck_width / belly / …      → shape key      → skinned plane does NOT follow
```

Which is the whole argument for making the face variables that other things depend on into bones.
With `head`, `jaw` and `nose` as bones, every plane and every accessory on the face follows every
facial proportion automatically, and the authoring cost of adding the thirteenth plane is the same as
the first.

### What Godot has to do

Almost nothing, and that is the point — but one small generalisation is needed:

- ✅ **Drive shape keys by name across all meshes.** Done — `SkinnedBodyUtil` writes to **every** mesh
  carrying the key, not the first. Forced by `wrist_mesh` needing `arms_length_max` too.
- ✅ **`STRETCH_BONES` became `STRETCH_CHAINS`**, a table of `{shape, factor, bones}` — one factor per
  chain, because each is sculpted independently. Adding the torso is one entry and no logic.
- ✅ The `F·v/s` curve is `_write_shape(chain, scale)`, shared by every chain.

One difference from Blender worth knowing: the table lists **all** the chain's bones, not just the
root. Blender scales the root and lets the rest inherit; Godot cannot, because
`_detach_children_of_stretched` leaves those bones parentless. Each one scales itself from its own
`cb.length / _rest_len`, and since `_share` splits the chain by the model's proportions the result is
the same uniform stretch.

Selection (which eyebrow, which beard, which accessory) is a **seed → index** lookup plus
`visible = true` on one child of a set. No new mechanism.

---

## Plane standards — settled

Conventions agreed while building the generic character's face. Only the decided ones are here.

### One object per thing that varies independently

| Feature | Objects | Why |
|---|---|---|
| eyes | **two** (`eye_left_mesh`, `eye_right_mesh`) | must differ — one-eyed characters, mismatched eyes, a patch |
| brows | **one**, two halves | always identical; two bones skin one object fine |
| hand hair, tear-trough, cheekbones | **one**, two halves | static and symmetric |
| mouth, forehead, chest hair, back hair | **one** | single piece |

Splitting costs a draw call, not correctness. Face planes are subpixel at distance and are drop
candidates for far NPCs, so the count only matters up close, where there are at most four characters.

### Mirroring lives in the UVs, not in the art

Mirrored geometry with **identical UVs** shows the texture mirrored. So:

- **Pair should look identical** (brows, hand hair) → identical UVs. One texture, one artboard.
- **Pair must be independent** (eyes) → **flip the mirrored side's island** (`S X -1`). The two flips
  cancel, both sides read the same way up, and each can then carry its own texture.

Guarantee it by **order**: unwrap *one* half first, then `Mesh → Symmetrize` (same object) or
duplicate-and-mirror (separate objects). UVs travel with the copy, so the two sides are identical by
construction and there is nothing to keep in sync by hand.

Verify with an asymmetric placeholder texture (a letter `R`): brows should read mirrored, eyes should
read the same on both sides.

### Unwrapping

1. **`U → Unwrap Angle Based`** — conformal, so it unrolls the bend while keeping the perimeter's
   proportions. `Unwrap Minimum Stretch` is the fallback if the stretch overlay shows red.
2. *(quad strips only)* make the largest quad active, then **`U → Follow Active Quads`** with
   **Edge Length Mode: Length Average** — regularises the grid without touching proportions.
3. Verify: UV editor → **Overlays → Display Stretch → Area** → uniform blue.

> ⚠️ **Never `U → Reset` first.** Reset maps every face to the unit square, and Follow Active Quads
> keeps the active face's UVs — so the whole island inherits that square aspect. This is what produced
> a square brow island for a rectangular brow.

> ⚠️ **`UV → Pack Islands` rotates islands by default.** Turn Rotate off, or the UV layout stops
> matching the artboard layout.

### Artboards

- **The artboard's aspect ratio is the UV island's bounding box**, measured after unwrapping. Islands
  are never stretched to fill 0–1; wasted texture at this scale is irrelevant, distorted art is not.
- **The artboard is not a picture of the face.** Spacing between features in the atlas has nothing to
  do with spacing on the head — that comes from the mesh.
- **One `.riv` file, many artboards.** Rive's free tier caps *files* (3), not artboards, and gives 30
  days of revision history — so the `.riv` belongs in git like the `.blend`.

### Materials

- Static planes (forehead, wrinkles, body hair) use **shared** materials — one per feature for every
  character in the city.
- Rive planes (eyes, mouth) need **one material per character**, because the texture is live and
  unique. That is the whole per-character material budget; nothing else pays it.
- Cutout is **`ALPHA` + `ALPHA_SCISSOR_THRESHOLD`**, never alpha blend. See the shader warning.

## The visual-only bone layer

Not every bone in the model is driven by the mirror. `SkinnedBodyUtil` drives 20; the model has 52.
The other 32 — the five finger chains today, plus the brow / jaw / nose bones as they arrive — hold
whatever local pose the `Skeleton3D` has, and nothing in the logical rig, the IK, the ragdoll or the
netcode knows they exist.

That is not a gap, it is the right split, and it is worth naming because two of the next features live
entirely inside it: **hand poses** and **eyebrows**.

The rules of the layer:

- it writes **local** bone poses directly on the `Skeleton3D`, after the mirror sync
- it never touches a `CustomBone`, so it cannot affect reach, gait, ragdoll, or anything that is synced
- a proxy re-derives its own from its own state — nothing new goes on the wire

### Hand poses: authored in Blender, read as data

Author them in Blender — thirty finger bones is not something to type — as **one action per pose**, one
frame each: `hand.idle`, `hand.grab.box`, `hand.grab.lever`.

Godot should **not** play them with an `AnimationPlayer`. Read them once per session into a static
table of local bone transforms — exactly what `ReferenceRig` already does for rest poses — and blend
between them with a per-bone slerp. The reasons, in order of weight:

- the pose pipeline writes `set_bone_pose` every frame, and an `AnimationPlayer` on the same skeleton
  is a **second writer**; the ordering between two writers is one more thing to get wrong, and this
  project has already paid for that class of bug twice
- a table is one static allocation for the whole session, against an `AnimationPlayer` node per
  character
- blending "60% idle, 40% lever" is a slerp, not an `AnimationTree`
- and it keeps the property the rest of the rig has: **the model is the source of truth, read at
  runtime, nothing transcribed**

The driver already exists. `ArmsController` knows the per-side grab blend and what kind of
interactable is held — which is exactly *which pose* and *how much*.

> ⚠️ **Blender ships actions to glTF only if animation export is on and the actions are reachable** —
> pushed to the NLA, or **Export all actions** ticked. A pose-library entry is an action, so it works;
> but with that box unticked it exports nothing and says nothing, the same way the shape key did.

### The hand is its own mesh, split at the wrist

`hand_mesh` is separate from `wrist_mesh` (the cuff), and the split is deliberate: it lets the hand be
**posed and rotated freely** for grabbables and controllables without deforming anything. One mesh
spanning the wrist would tear at exactly the joint that moves most.

The four-way split, meshes against bones — they do not line up one to one:

| Bone | Mesh |
|---|---|
| `upper.arm` | `arms_mesh` |
| `lower.arm` | `arms_mesh` + `wrist_mesh` |
| `wrist` | `hand_mesh` |
| fingers | rest of `hand_mesh` |

Consequence for `arms_length`: **`wrist_mesh` needs its own `arms_length_max` shape key**, with the
same name and the same driver expression as `arms_mesh`. It straddles `lower.arm` (which scales) and
`wrist` (`Inherit Scale = None`, which does not), so it stretches between the two weight regions and
needs the same correction. `hand_mesh` needs none — the hand only translates.

> This is what forced `SkinnedBodyUtil` to drive the shape key on **every** mesh carrying that name
> rather than the first one it finds. With a single arm mesh the bug was invisible; the second mesh
> would have silently gone uncorrected, showing up as a seam opening at full stretch.

### The five hand poses

Authored by hand in Blender, one action each, read into the static table described above and blended
per bone. The set is driven by what the interaction system already distinguishes:

| Pose | When |
|---|---|
| `idle` | nothing held |
| `press` | pushing a button |
| `grab.lever` | lever or large rotatable |
| `grab.knob` | small rotatable / knob |
| `grab.object` | a grabbable |

`ArmsController` already knows which of these applies — it tracks the per-side grab blend and the kind
of interactable held — so the driver is a lookup, not new state.

---

## Phase: finishing the generic character

**Before** any of the length variables. The point is to find out whether the **style** works on one
finished character, which no amount of parametric plumbing can answer — and the answer changes what is
worth parameterising at all.

| Item | Mechanism | Notes |
|---|---|---|
| chest / arm / back hair planes | class C, skinned | alpha-scissor, not alpha-blend |
| hand poses | visual-only bone layer | idle / package / lever |
| eyes plane | class C + Rive | |
| mouth plane | class C + Rive | |
| eyebrow planes | visual-only bone layer | bones in Blender, rotated from Godot |
| forehead plane | class C, static texture | |
| character shader | material | plus seed-driven skin / suit / hair colour |

### The phases

Ordered by two rules: **de-risk the style before building plumbing for it**, and **batch the Blender
geometry**, because [topology lock](#where-this-actually-gets-expensive) makes a second pass over the
same mesh expensive in a way a second pass over code is not.

#### 0 — Shader and seed colour · *Godot only* — **plumbing landed, look deferred**

What exists: `Materials/character.gdshader` (banded toon, colour on an `instance uniform`),
`CharacterAppearance` (mesh → role table, four shared materials, applied at the end of
`initialize_skeleton`), and seed-driven skin / cloth / hair / leather palettes on the human specie.

**The look is explicitly not signed off.** The band count, edge hardness, rim and shadow tint are
placeholders that make the character read coherently, not an art direction. Revisit before phase 2,
because that is where textures start being drawn against this lighting and re-doing them afterwards is
the expensive version.

> ⚠️ **Never write `ALPHA` in the character shader.** Touching it once moves the whole material to the
> transparent pipeline, which does not write depth and sorts per object — the meshes then draw over
> each other depending on where the character is standing. Cutout (hair and face planes) uses
> `ALPHA` **plus** `ALPHA_SCISSOR_THRESHOLD`, which is alpha test and stays in the opaque pass.

Ships first, before any geometry. Two reasons, and the second is the real one:

- it is the cheapest test of the seed. Rolling skin / suit / hair on `P` says whether the seed
  produces variety while every character is still the generic archetype.
- **every texture authored afterwards is authored against this lighting.** Draw the face first and
  change the shading model later and the textures get re-done — contrast, line weight and how dark a
  wrinkle needs to be are all decisions about the final lighting.

Colours go in as `instance_uniform`s from the start.

#### 1 — All the geometry, in one Blender pass · *Blender only*

Face planes (eyes ×2, brows ×2, mouth, forehead), body-hair planes (chest, arms, back), and the brow
bones. One pass, one export.

Batched deliberately: adding a plane changes the mesh's vertex set, and shape keys do not survive
that. Everything that will ever be a plane should exist before the first shape key does — even planes
whose texture is still a placeholder.

Weight the mouth plane to what will become the nose/jaw bone, not rigidly to `head`. Costs nothing now
and is the difference between the two-variable face working later and needing a re-weight.

#### 2 — The static face · *Godot, materials only*

Textures and materials on what phase 1 produced. No animation, no bone driving, no Rive.

**This is the decision gate.** A still face already answers whether a low-poly head with drawn
features reads at gameplay distance, which is the question this whole phase exists to answer. If the
style does not work, it is cheaper to find out here than after the animation layers are built on top
of it.

#### 3 — The visual-only bone layer · *Godot*

The layer described above: local poses written on the `Skeleton3D` after the mirror sync, touching no
`CustomBone`.

Built once, serves brows now and hands next. Brows first because they are two bones and an obvious
right answer, so the layer gets exercised before the harder consumer arrives.

#### 4 — Hand poses · *Blender + Godot*

Actions in Blender, read once into a static table, blended per bone, driven by `ArmsController`'s
existing per-side grab state.

Comes after the layer exists rather than driving its design — the layer's contract is simpler if it is
not shaped around thirty finger bones on the first attempt.

#### 5 — Rive on eyes and mouth · *Godot*

Last on purpose. It is the highest-risk integration in the list and the **lowest** signal about
whether the style works: a face that reads well still reads well; a face that does not is not saved by
blinking. Doing it last also means the per-character-material question is answered against a finished
material rather than a placeholder.

### Shader notes

**Colour per character without a material per character.** Godot 4 has `instance_uniform`: a uniform
whose value lives on the `MeshInstance3D` instead of the material. Skin, suit and hair colour should
be instance uniforms, so every character in the city shares one material and one pipeline. This is
the mitigation for the per-character-material cost ranked below — free if done from the start, a
refactor if bolted on later.

**The face has to stay legible.** The Animal Crossing / PEAK look works because the drawn features are
not fighting the lighting: the face is close to unlit, and whatever shading survives is flat and
banded. Expect the face material to differ from the body material deliberately, not by accident.

**Planes on a surface z-fight.** Face and body-hair planes sit directly on the mesh they decorate.
Push them out along the normal by a fraction *or* give them a depth bias — not both, or they visibly
detach at grazing angles.

**Alpha-scissor for the hair planes, not alpha-blend.** Blended transparency has to be sorted per
object, and a dozen overlapping hair planes on a moving character is the textbook case where that
sorting pops. Scissor writes depth and sorts itself.

**Colour is also the cheapest test of the seed.** Rolling skin / suit / hair on `P` gives an immediate
read on whether the seed produces real variety — long before any proportion is parametric, and while
every character is still the generic archetype.

---

## Where this actually gets expensive

Ranked by how much it would hurt, not by how hard it looks.

**1. Topology lock — the real scheduling constraint.** A shape key stores "vertex N sits here". Any
operation that changes which vertex is which — applying a modifier, Symmetrize, remesh, retopology,
joining objects — destroys **every** shape key on that mesh. With one key per mesh that is annoying;
with five it is a day. **Close the topology of a mesh before starting its shape-key pass, and author
all of that mesh's extremes in one go.** This is the constraint most likely to cost real time, and it
is a scheduling decision, not a technical one.

**2. Per-character materials, if Rive runs per character.** Every face whose eyes and mouth animate
independently needs its **own** material instance — it cannot be shared. That is fine for four
players; for a street full of pedestrians it multiplies draw calls and texture memory. Worth deciding
early whether distant NPCs get a static face texture and only near ones get live Rive. This is the
only genuine **performance** risk in the whole appearance system; everything else is authoring time.

**3. The plane × parameter matrix — avoidable, and only if C is respected.** Twelve planes and six
parameters is seventy-two relationships if each is authored, and zero if each plane is skinned to a
bone that already moves. The entire cost of this item is decided by the bone-vs-shape-key choice for
the facial variables.

**4. Combination blindness.** Nine variables cannot be eyeballed pairwise, and the bad-looking
combinations (long torso + short arms, big belly + thin legs) are exactly the ones nobody
previews. Worth a debug action that rolls a random parameter set on the spot — the global debug view
already spawns and rebuilds characters, so it is small.

**5. Seams between chains that scale differently.** The shoulder seam between `body_mesh` and
`arms_mesh` is the one that tears, because two different parameters pull on its two sides. Only
identical vertex weights on both sides of the seam prevent it — masking cannot. Test at the extremes
of both parameters simultaneously.

---

## Gaps in the current list

Things that are not in the parameter set and probably should be, cheapest first:

- **Colour.** Skin, hair, eyes, clothing — material parameters, no geometry, no shape key, no
  topology risk. Pound for pound the cheapest variety in the whole system, and it is currently absent
  from the plan.
- **Asymmetry.** Everything here is mirrored, and mirrored faces read as synthetic. A small per-side
  offset on one or two facial planes buys a lot for very little.
- **Height is not a knob.** It is a *result* of `legs_length + torso_length + head_length`. Worth
  saying out loud, because "make a tall character" is a natural request and the answer is "make the
  legs long", not "set height".
- **Proportion coupling.** Nothing stops a seed rolling long legs with a short torso. Whether
  archetypes should constrain the combinations, or whether the ugly ones are the point, is a design
  decision that has not been made.
