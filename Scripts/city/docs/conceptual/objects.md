# Objects & Packages

Cross-cutting system: objects are loaded as **cargo in the ship** and carried/delivered **on foot**. This file defines the object model; the ship and on-foot sections at the bottom note where they show up.

Objects are moved with the [grab system](onfoot-gameplay.md#grab-system).

---

## Object

Something you can grab and move with the grab mechanic.

- **Cell dimensions** — 3D cells of constant size, specified as height × depth × width in cells. Determines the (always cubic) collider, and drives grab-point and handle-point placement.
- **Grab points** — the point the grab ray latches onto. Valid distance depends on the player's **reach** (see code for the 3 grab-ray distance stages). **Exclusive to one player.**
- **Handle points** — once a grab point is secured, these place the arms via IK. **Exclusive to one player**, shared only when all other in-range points are already taken by that player.
- **Cosmetic** — the 3D model, fitted to the bounding box from the cell dimensions. (Model with the grid in mind, but still fit the mesh to the bounding box exactly via code.)
- **Weight** — how hard it is to move while grabbed, relative to the **strength** of the grabbing player(s). See [people.md](people.md).
- **Nested dashboards** — a package can contain a [dashboard](interactables.md#dashboard) at a specific cell position (e.g. a TV with one touch component to turn it on/off).

---

## Nature

An enum for what the object is:

- **Deliverable** — part of a delivery; inherently has a delivery point, value, priority, durability, and fragility (see below).
- **Ship cosmetic** — has only weight (and its cosmetic); placed in the ship's cosmetic slots.
- **World prop.**

---

## Deliverable package stats

Only **deliverable** objects have these:

- **Durability** — starts at `1.0`. Lowered by each impact above a threshold (small hits are ignored so mini-bumps don't frustrate). At `0.0` the package is destroyed and despawned. Intermediate values scale its **value**.
- **Fragility** — the more fragile, the more durability is subtracted per qualifying hit.
- **Priority** — one of three tiers, shown on the package label as a single **word**: **entrega flexible**, **entrega rápida**, or **entrega urgente**. No clock is shown — the delivery window is understood to run from the **start of the shift**. Under the hood the tier is just a delivery window `T` (a double); a shorter window is more urgent. Drives payout decay and patience (below).
- **Delivery point** — the target door ([onfoot-gameplay.md](onfoot-gameplay.md#delivery-points)).
- **Deliverable flag** — marks the object as part of a delivery (which gives it a delivery door).

### Value & payout

**Base value** is computed at generation time from:

- **Transportability** — how **heavy** and **large** the package is (harder to carry → worth more).
- **Distance** — from the branch HQ to the delivery point.
- **Delivery height** — how high up the delivery door is.

Priority bumps it too: more urgent packages are generated worth more.

It is also scaled by the **crew factor** — a run-wide multiplier from the **number of players** and their **stats**. A smaller and/or lower-capability crew (old, slow, weak employees — see [people.md](people.md)) is paid **more** per package:

```
crew_factor = ref_capability / Σ_players(capabilityₚ)
```

where `capabilityₚ` is each player's employee **capability score** ([people.md](people.md#capability-derived)). Fewer or weaker players → higher factor → more valuable packages. It's a **handicap**: it doesn't make the crew stronger, only better paid, so a short-handed or unlucky-roster crew still earns. Fixed once the crew locks at **first departure** ([run-setup.md](run-setup.md)).

During the first shift's join window (players still arriving) the factor — and so the **prices shown on the package labels** — is **provisional**, re-settling as the crew fills; it locks at first departure and never moves again.

The base value is then **modified at the moment of delivery** by two things — **condition** (durability) and **time** (lateness against the priority window):

```
late   = max(0, now − (shift_start + T))
payout = base_value · durability · max(floor, 1 − late / (k · T))
```

On time and pristine → full base value. Damaged → scaled by durability (`0.0` = destroyed). Past the window → decays toward a small **floor** (~`0.1`): still deliverable, worth very little.

### Patience refill

Delivering refills the crew's [patience bar](hud.md) by an amount **proportional to payout**, normalized to the **chosen batch**:

```
refill_i = a · (payout_i / total value of the chosen batch)
```

Tuned so delivering the whole chosen batch on time restores about **1.2–1.5×** a full bar (`a ≈ 1.3`). Falling behind — overdue packages draining, late deliveries paying little — sinks it.

### Tentative tuning

Windows are best thought of relative to **τ = the time to reach a typical delivery point** (fly + walk):

| Priority | Window `T` | Base-value × |
|---|---|---|
| Flexible | ~4–6 τ (lots of slack) | ×1.0 |
| Rápida | ~2 τ | ×1.3 |
| Urgente | ~1 τ (go almost straight there) | ×1.8 |

- Decay: **floor ≈ 0.1**, `k` set so a package reaches the floor ~2 τ past its window.
- Patience: **a ≈ 1.3** (refill); drain `c` tuned so a fully-overdue chosen batch empties the bar in a couple of minutes.
- Keep **most of a batch flexible** and urgents **rare**, so route planning stays the main puzzle and urgency is the occasional disruptor (see [run-setup.md](run-setup.md)).

### Special effects *(enum — do not implement yet)*

Effects that change package stats dynamically, e.g.:

- Weight changes on time intervals (some magnetic experiment).
- Stat changes on falls / durability changes.
- The package exerting its own forces and moving on its own.
- A literal **bomb** — a rare, one-off package that dramatically raises the stakes. A special case, not one of the normal priority tiers.

---

## Where objects appear

### Ship

Packages are loaded into the **cargo zone**, constrained there by its force-field barrier so they never interfere with players at the dashboards. Ship cosmetics fill cosmetic slots. See [ship-gameplay.md](ship-gameplay.md).

### On foot

Players grab and carry packages (heavy/large ones may need several players) from the ship to the delivery door, protecting durability along the way. See [onfoot-gameplay.md](onfoot-gameplay.md). Package selection at run start is in [run-setup.md](run-setup.md).
