# Interactables

Cross-cutting system: things a player engages with **in place** — as opposed to [objects](objects.md), which you grab and carry off. Interactables appear both on the company ship (piloting/repair dashboards) and out in the world (levers, valves, buttons, manuals, seats).

Families so far, all sharing one engagement model:

- **Controllables** — drive a system's state: levers, valves, wheels, buttons. Held and dragged/scrolled.
- **Information interactables** — read or heard for information: manuals, phones. Engaged with **E**.
- **Seats** — sat in with **E**.

---

## Engaging an interactable — grab points & ranges

Every interactable shares this model, so ranges and release logic stay **uniform** across families — a controllable dropping and an information interactable releasing use the **same range model** (one code path, no redundancy). The grab ray and the reach stat come from the [grab system](onfoot-gameplay.md#grab-system).

- **Grab points** — the point the grab ray latches onto. Valid range derives from the player's **reach** stat, which sets three ascending thresholds (each a fraction of reach): **interact** (`0.85 × reach`) — the max range at which the interactable is highlighted and can be engaged; **grab** (`0.9 × reach`) — the range a held object is floated at (clamped between `0.1 × reach` and this, adjustable with the scroll wheel); **grip** (`1.0 × reach`) — the range at which an *already-established* hold is finally released once the target drifts past it. Grab points are **exclusive to one player** — no two share one simultaneously.
- **Handle points** — once a grab point is secured, these place the arms via IK for the visual of holding. Also **exclusive to one player**, shared only if that player has already occupied all other in-range points.
- **Cell dimensions** — 3D cells of constant size (height × depth × width in cells); determine the (always cubic) collider and drive grab/handle-point placement.

---

## Controllables

Controls that drive a system's state. Engaged by looking at one and holding to grab, then moving it.

### Primitives (abstract "archetypal controls")

Controllables are built from primitives, which are never placed directly — you place a concrete instantiation (a lever, a valve…), not "a one-axis component."

- **One-axis component** — a vertical or horizontal lever (more variations possible later). Interacted with by click-and-drag. Variations:
  - **Discrete** — snaps to discrete values even if released between them (like an automatic gear shift: park / drive / neutral).
  - **Continuous** — every position is valid.
  - **Snap-back** — a continuous lever that eases back to a rest value (e.g. neutral halfway), while its **whole trajectory is still recorded and synced**. Abstractly this is just a continuous lever that snaps back at one value but registers its full path — be careful architecting the class hierarchy around this.
- **Two-axis component** — an analog-joystick equivalent. Same variations as one-axis (discrete/continuous, snap-back or not).
- **Rotating component** — a valve, steering wheel, knob, etc. Differs in interaction: **press and hold, then rotate with the scroll wheel.** Can be discrete or continuous, and can register trajectory or not.
- **Touch component** — something you tap, or tap and hold. Depending on the button it registers hold time or just the press.

### Concrete controllables

Beyond the shared grab/handle points and cells (above), a placed controllable has:

- **Primary cosmetic** — usually the moving part (button, lever, valve…).
- **Secondary cosmetic** — usually the base (button base, lever base…); can be null.

Each instantiation has a **status** (its position/state) **synced across all players**. Sync is authoritative on the host, and a controllable can only be controlled by **one player at a time**.

In code each controllable holds a single float `_network_state` for its authoritative value; whenever it changes past a small epsilon the control emits `state_changed`, and any client that isn't the one driving it eases its `visual_value` toward `_network_state` each physics frame (`snap_lerp_speed`). The value is normalised per control type — lever position, accumulated rotation, or `0`/`1` for a button — and a two-axis component additionally emits its `Vector2` through `state_changed_2d`. *(The transport/authority layer that replicates `_network_state` between machines isn't wired yet — today the field is only updated locally — so the host-authoritative, one-driver-at-a-time model above is the intended design, not yet the running one.)*

### Dashboard

A **collection of components arranged in a grid** of a specific size. For example, the company ship has several dashboards for controlling/repairing the ship. Objects can also carry **nested dashboards** at a specific cell position (e.g. a package that is a TV with one touch component to turn it on/off) — see [objects.md](objects.md).

#### How dashboards are built (`ProceduralDashboard`)

A dashboard is generated procedurally onto a **grid of `grid_columns × grid_rows` cells**. Each cell is a fixed-size `cell_size` box separated by `cell_gap`; a control's world size and centre are computed from the cells it spans, and each control is placed as a `StaticBody3D` + box collider carrying the `ControllableInteractable`.

Two placement passes run:

1. **Preset (fixed) slots** — an optional `DashboardPreset` lists `DashboardSlot`s, each pinning a `ControlDefinition` to a grid cell. These are placed first; a slot that doesn't fit (out of bounds or overlapping) is skipped and its origin cell just marked occupied. A `null` definition marks a deliberately empty cell.
2. **Seeded random fill** — if the preset allows it (`fill_remaining_random`), leftover cells are filled from a weighted table of control archetypes (`_DEFS`: 1×1 / 2×1 / 1×2 / 2×2 variants of touch, lever, joystick, wheel) using a `RandomNumberGenerator` seeded with `seed_value`, so the same seed always yields the same dashboard.

A `ControlDefinition` chooses the control **type** (touch / one-axis / two-axis / rotating) and its per-type parameters — sensitivity, max angle, rotation axis, auto-return, toggle, custom mesh, etc. The built-in `PresetType.STEERING_WHEEL` layout, for example, places a 2×2 wheel at cell (1,1), a 1×2 lever at (3,1), and fills the rest with 1×1 buttons.

When `show_debug` is on, each control renders placeholder geometry (arm, joystick, wheel, or button face) plus its handle points; otherwise `build()` applies the control's `custom_mesh`.

---

## Information interactables

Read or heard for information — the **manual** and the **phone**. Unlike controllables, they are **not** taken with the grab mechanic; you engage them with **E**:

- Press **E** within the interactable's grab-point range → the object **detaches from where it sat and attaches to the player's model** (the book into the hands, the phone to the ear).
- While held: the **phone** plays its audio in your ear; the **manual** shows its pages, turned with the **scroll wheel**.
- **Release** — press **E** again, or move out of the interactable's grab-point range. This reuses the **same range model as a controllable's drop** (above), on purpose — one release path for both.
- Arm **IK** while an information interactable is held is *to be defined*.

Information interactables are fixed to their spot (e.g. the ship manual's set place on a dashboard — see [ship-gameplay.md](ship-gameplay.md#interactable-components)), which is what creates the **asymmetric information** between players. *(What the phone does exactly is still to define.)*

---

## Seats

An interactable a player sits in with **E**. *(Details TBD.)*

---

## Where interactables appear

### Ship

Dashboards arranged as a partial octagon ring around the ship interior — controllables that move the ship or perform repairs, plus information interactables (manual, phone) and seats. See [ship-gameplay.md](ship-gameplay.md).

### On foot

Standalone controllables on world obstacles and mechanisms — e.g. the **valve** that shuts a steaming pipe (faster for stronger employees), levers, and buttons. See [onfoot-gameplay.md](onfoot-gameplay.md).
