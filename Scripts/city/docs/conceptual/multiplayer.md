# Multiplayer & Sync

The game is co-op for **1–4 players** ([00-overview.md](../00-overview.md)). One player **hosts** and is authoritative; others join over Steam. This file is the technical outline: the transport, how a session is created/joined, how players are represented, and what has to stay in sync (and in what order we build it).

---

## Transport — GodotSteam

Networking runs on **[GodotSteam](https://godotsteam.com)**:

- The **`Steam` singleton** for Steamworks (identity, lobbies, rich presence, the overlay).
- **`SteamMultiplayerPeer`** plugged into Godot's high-level multiplayer (`multiplayer.multiplayer_peer`), so we get RPCs / `MultiplayerSynchronizer` over Steam's relayed sockets — no manual packet plumbing.

For now the game runs under **Spacewar (app id `480`)**, so Steam features work without our own app id.

Because everything is on Godot's **high-level** multiplayer, the transport is swappable: there's a **local ENet mode** (`SessionManager.host_local()` / `join_local()`, console `host_local`/`join_local`, or `--host-local`/`--join-local` args) for testing multiplayer with **several instances on one machine** — no Steam, no second account. Identity/seed fall back to the peer id, so the test characters look different. The whole sync stack (capsule, boxes, grab) runs unchanged.

---

## Session & joining — main menu (host / join by code)

On launch the game shows a **main menu** (a separate scene, no world loaded); from there the player **hosts** or **joins by a short code**. Friends can also join through the **Steam overlay → "Join Game"**, and if Steam launched us with `+connect_lobby <id>` we join that lobby directly, skipping the menu. The menu is a **temporary front-end**, later replaced by the diegetic **Lounge / assembly** flow ([run-setup.md](run-setup.md#match-lifecycle)). Full UI layering in [technical/ui.md](../technical/ui.md).

**Host (`SessionManager.host()`):** create a **public** Steam lobby, publish a **short code** as lobby data (+ `host_steam_id`), mark it joinable, set **rich presence** (so friends see "Join Game"), and start `SteamMultiplayerPeer` as **server** (peer `1`). Without Steam, `host()` starts a **local-only** session so dev iteration still works (play alone, nobody can join). On `session_ready` the menu loads the game scene.

**Join (`SessionManager.join_by_code(code)`, the overlay's join-requested callback, or `+connect_lobby`):** join-by-code runs a **lobby-list search filtered by the code** to resolve the lobby id, then joins; it reads the host's Steam id from lobby data and connects `SteamMultiplayerPeer` as **client**. On `connected_to_server` the assigned client id becomes the local id and the session is ready — the game scene loads and the `CharacterSpawner` spawns the local character under the right authority. Failures emit `session_failed` and the menu stays put.

Because the local character isn't spawned until the game scene loads (after the id is known), there's no launch-time re-key; `local_peer_id_changed` only matters for the rare mid-game overlay-join.

---

## Peers & players

Two distinct notions of "player":

- The persistent **Player** ([people.md](people.md#player)) — the Steam account: its seed, employee roster, ship roster, reputation. Identity, not runtime.
- A runtime **session player** — one connected peer this session: its **Godot peer id**, its **Steam id**, the persistent Player it maps to, and the **character** it drives. The host is peer `1`.

The host keeps a **registry**: `peer_id ↔ steam_id ↔ Player`, updated on connect/disconnect. Each session player spawns **one character** ([characters.md](../technical/characters.md)):

- On the **owning** machine the character is **active** (`is_active` — has the `PlayerController`, camera, input).
- On **every other** machine it is a **remote proxy** — driven by replication, no local input.

Movement is **owned by the controlling peer** and replicated out; genuinely shared or contested state (ship, objects, controllables, run) stays **host-authoritative** (below).

---

## Guiding principles

- **Host-authoritative for shared state.** The host owns the truth for anything contested; clients predict and reconcile. A player's own character is the exception — owned by its peer, replicated to others.
- **Seed-determined where possible.** Anything derived from a shared seed (the city, car trajectories, package sets, character generation) is reconstructed locally — only the seed and discrete events go on the wire.
- **Avoid frame-dependent logic.** Anything that reads per-frame deltas must become frame-rate-independent before the *same* simulation can run on two machines (see equilibrium). Replicating an owner-simulated transform sidesteps this for remote characters — they interpolate, they don't re-simulate.

---

## Physics sync — state replication over RPC

Physics is **not** made deterministic across machines (Jolt isn't). One authority simulates and replicates state; remotes interpolate. The transport choice (high-level `SteamMultiplayerPeer`) does **not** make this harder — it's the same problem with any transport, and we keep full control:

- Use `SteamMultiplayerPeer` **only as transport** (RPCs + channels). **Do not** use `MultiplayerSynchronizer` for physics bodies — it has no interpolation, sends coarse state, and jitters.
- The **authority** of a body (its owning peer for characters, the host for the ship/objects) sends `transform + linear/angular velocity` on an **unreliable** RPC each tick **while the body is awake**; remotes buffer and **interpolate**. Physics-body objects go **dormant** when they settle (see `NetBody` dormancy) and stop sending; characters never sleep (`can_sleep = false`).
- **Discrete events** (ragdoll on/off, grab/release, spawn/despawn) go on a **reliable** RPC.
- **Escape hatch:** if one hot path ever needs bit-packing/delta compression for bandwidth, open a **raw Steam channel** just for that stream and keep everything else high-level. Not expected at 1–4 players.

So the hard part of physics sync (authority + interpolation) is identical either way; high-level just hands us the plumbing (peers, channels, RPC routing) for free.

---

## What needs syncing

| Aspect | What's shared | How (roughly) |
|---|---|---|
| **Players** | Capsule transform, movement state, grabbed/controlled item | Per-player transform + input state; each player owns their own character. **Capsule only at first — no visuals.** |
| **Controllables** | Each control's status, one driver at a time | Host-authoritative value per control; non-drivers ease toward it. See [interactables.md](interactables.md). |
| **Ship** | Position, cargo-zone contents, dashboard states | Host-authoritative; driven by the shared controllables. See [ship-gameplay.md](ship-gameplay.md). |
| **Objects / packages** | Which package is where, who's holding it, durability | Ownership handoff on grab; damage/state on the host. See [objects.md](objects.md). |
| **People** | Pedestrians, employee rosters, health, equilibrium/falls | Seeded pedestrian spawns; equilibrium is **frame-dependent today and must change**. See [people.md](people.md). |
| **Ambient traffic** | Flying cars | Fully seed-determined — only spawn events on the wire. See [traffic.md](../technical/traffic.md). |
| **Run state** | Company, city seed, shift clock/patience, score/penalties | Set at run start from the host; clock and scoring host-authoritative. See [run-setup.md](run-setup.md). |

---

## Milestones

Built incrementally — networking first, fidelity later:

1. **Host + join + player registry.** ✅ *Implemented.* Host / join-by-code (or Steam overlay), and the **session-player registry** (`peer ↔ steam ↔ Player`) — including each peer's **Steam name**, exchanged on connect via a reliable `_register_identity` RPC. Each peer spawns a character. Proves the transport and identity end to end.
2. **Capsule sync.** ✅ *Implemented (pending live 2-player verification).* Replicate each player's **capsule** (transform + movement state). Remote players are just the **capsule + its debug ray** — no aesthetic skeleton yet.
3. **Aesthetic & animation.** ✅ *Implemented (pending live 2-player verification).* Remote players are now full seed-reconstructed skeletons, not capsules: the seed is **derived from each peer's Steam id** (same on every machine, no extra sync), so the proxy rebuilds the same character locally. Only the capsule transform + velocity travel; the walk animation is driven locally from that replicated velocity.
4. **Interaction.** Grab / controllables / ship (host-authoritative), objects, ownership handoff on grab. *In progress:* the **replicated debug spawner** (`NetSpawner`) + generic **`NetBody`** physics sync are in (spawn boxes/dashboards/seats on every machine; boxes sync host-authoritative). **Grab ownership handoff is in**: grabbing a synced box migrates its `NetBody` authority to the grabber (host-arbitrated), so whoever holds it simulates it locally and everyone interpolates; releasing hands it back to the host (velocity carried over so throws survive). Spawned boxes are made grabbable (a `GrabbableInteractable` is attached), in 4 debug variants (light/heavy × square/long).

**Grab model (all forces/torques — never sets the transform, so no exploits).** Every hand holding a body registers itself on that body's `GrabbableInteractable`, which **solves the whole grab once** rather than each grabber applying its own force. The model deliberately picks **stability over realism** (R.E.P.O. as reference) and is **two decoupled second-order systems, both critically damped**:

- **Position** — the force always goes to the body **centre** (`apply_central_force`), *never* to the grab point. Off-centre force couples translation and rotation into a feedback loop (the force rotates the body → the grab point moves → the force changes), and that loop is what made a long box ring forever. Each hand implies a body position (its aim target minus its rotated grab offset); the target is their **average**. So **two grabbers stop being a problem**: on position they are two springs pulling one *point*, and a point has no orientation to over-determine.
- **Orientation** — explicit, not emergent, and always the *same* constraint: align one body axis with an axis the hands define. With **2+ hands**, the axis between the two most-separated grab points aligns with the axis between their aim targets. With **one hand**, the centre→grab-point axis aligns pointing back at the grabber's chest — **what you grabbed is what faces you**, and the rest of the object extends away. Grab a long box by the end and it lines up along your view; grab it in the middle and it sits broadside. So the grab point matters with a single grabber too, and there is no special case (no yaw-follow, no network-conditional branch). Free mouse-rotate is dropped for the same reason: orientation is decided by *where you grab*, so there is no rotation target left for the mouse to move.
- The rotation each constraint leaves free (roll about that axis) is **damped, not loose**.
- Grabbing a specific part still matters — through **orientation** rather than emergent torque: where you grab is what sets the axis. Degenerate cases (a grab exactly at the centre, two hands on the same point) define no axis and simply leave orientation damped.

The two solves are coupled only one way (orientation feeds the position target, never the reverse), so there is no loop to oscillate.

**Derived gains, not tuned ones:** the only feel parameter is a **response time** (`RESPONSE_TIME`); stiffness and damping follow from it and the body's mass (`k = m·ω²`, `c = 2·m·ω`), so the system is critically damped for *every* object — no per-object gains, no overshoot. Because stiffness scales with mass, everything responds equally fast; what makes weight *felt* is the **force ceiling** (`FORCE_PER_STRENGTH · Σ strength`). Gravity is compensated **against that ceiling**, so a body too heavy for the hands on it sags — which is the readable "come help me" signal, and how "needs several players" ([objects.md](objects.md)) emerges from the model instead of being tuned in.

**Grab-point density** (`GRAB_DENSITY`) is one point per N object cells — lower means more points. It is not cosmetic: the grip is lost when *the latched point* leaves the cone or the grip distance, not when the object does, so denser points latch closer to where you actually aimed and the hold survives much more movement. It also sets how many hands an object can take: the extra-long debug box gets three points along its length, so three people can carry it.

**Co-grab netcode:** the host tracks the grabber set per body. The first grabber becomes the `NetBody` authority (simulates it locally, responsive); extra grabbers stay non-authority and stream their **hand** (grab-point offset + aim target + strength + desired orientation) to the authority, which registers it on the same `GrabbableInteractable` as its own — so the solver sees every hand, local or remote, and resolves them together. Releasing sends an explicit release (a hand also expires on its own if the stream dies). On release, if grabbers remain, authority is **promoted to the next grabber** (else back to host); velocity carries over so throws survive.

**Exclusive claims** (`ExclusiveClaim`): the recurring "one player owns this at a time, host-arbitrated" pattern lives in **one** small Node component (attached as a `Claim` child). It owns the request → grant/deny → broadcast flow — including the gotcha that `rpc_id(own_id)` doesn't self-invoke, so the host self-dispatches — and exposes it as `request()` / `release()` / `is_free()` / `is_mine()` + `granted` / `released` / `revoked` signals. Interactables consume it by signal and never re-implement arbitration. Ownership (the claim) and the **state** each interactable syncs are separate layers.

**Controllables** (dashboards): each control on a `ProceduralDashboard` is named deterministically (`ctrl_N/Control`) — the dashboard is seed-generated so the Nth control is at the same path on every machine — and carries a `Claim`. Only the owner may control it (`can_interact` blocks others; the loser of a race releases via `control_lost`). The confirmed owner **streams** its state (float / Vector2 / bool per component) each tick; others `apply_sync_state` and suppress their own auto-return/lerp via `_remote_controlled` until a reliable final state + release arrive. A joining client asks the host for each control's current value (`_request_control_states`) so a control someone left moved isn't reset to default. The owner's **arms** replicate through the same channel as grab: the controlled interactable travels as `CharacterNetSync.grab_target` (a player grabs *xor* controls, so one reference covers both) and each proxy drives its arms to the interactable's nearest handle/grab point locally.

**Seat occupancy** uses the same `Claim`: sitting requests it, granting `_sit`s the local player and releasing `_stand_up`s — two players can't share a seat. The seated *pose* replicates separately via `CharacterNetSync.seat_target`.

5. **Run.** Run state, the shift/patience clock, scoring — and the assembly/join flow moving onto the real Lounge front-end.

### Implementation (M1–M2)

- **`SessionManager`** (autoload) owns the session lifecycle: init Steam, then start **solo** (peer `1`) unless launched with `+connect_lobby`. `host()` / `join(lobby_id)` are called from the debug panel (and `join` from the overlay's join-requested callback). It emits **`session_ready(local_peer_id)`** for the initial spawn and **`local_peer_id_changed(new_id)`** when the local id changes (solo/host → client), plus `remote_player_joined/left`. Hosting keeps id `1` (no re-spawn); joining re-keys the local character to the assigned client id.
- **`CharacterSpawner`** (scene node) spawns every character by code: the local player (a full `BoneInstantiator`) and one **`RemoteCharacter`** proxy per remote peer. Each is named **`char_<peer_id>`** and its **`NetSync`** child's `multiplayer_authority` is that peer — so the RPC path matches on every machine and `is_multiplayer_authority()` decides who simulates.
- **`CharacterNetSync`** (child `NetSync`): the authority sends capsule **centre pos + yaw + linear velocity** (plus crouch/jump/throw/head-pitch pose) on an **unreliable_ordered** RPC each physics tick; remotes buffer with a local timestamp and **interpolate** (100 ms render delay, short velocity extrapolation on late packets). No `MultiplayerSynchronizer`, per the physics-sync rules above. **Seat/grab** travel as a synced **node reference** (path), resolved **lazily** so it survives the object arriving later; on join, `request_state_if_proxy` re-requests the owner's seed + current seat/grab so a late-joiner sees someone already seated/holding.
- **`NetBody`** (M4, generic physics sync): a child of any `RigidBody3D`. The **authority** simulates normally and sends transform + velocity (linear **and angular**) each tick; non-authorities **follow** it. `set_body_authority(peer)` migrates ownership (grab handoff). No prediction/rollback (chill co-op).
  - **A proxy body is never frozen — it stays dynamic and is driven by *velocity*, never by writing its transform** (`_follow_reference`). The velocity written is `reference_velocity + correction`: the first is genuine physical momentum (a thrown box really does travel fast and should hit like it), the second is the artificial part that closes drift and is **the only one clamped** — so following can never invent momentum. Gravity is off on a proxy (its fall is already contained in the reference pose it follows; applying it twice would make it sag).
  - **Why, not just how:** a teleported kinematic body has *infinite mass* and *unbounded implied velocity*. If it appears inside a capsule, Jolt ejects the capsule with whatever it takes — that was the "player launched into the air" when a second player grabbed a box someone was already holding. A velocity-driven **dynamic** proxy cannot pass through anyone: it pushes with real mass, so the contact resolves by **momentum** instead of depenetration, and rigid support contact (a carried box resting against your chest) is preserved. If something blocks it, the follow simply *loses* and recovers afterwards, instead of tunnelling. Only a drift beyond `SNAP_DIST` (a real desync, e.g. the box fell off a ledge on one machine) hard-snaps — and at that distance nobody is inside it.
  - This is the box-side counterpart of the reasoning that killed rigid player-vs-player blocking ([characters.md](../technical/characters.md)): a network-driven body must never be an infinite-mass wall at a stale position.
- **`NetSpawner`** (autoload): replicated debug/authoring spawn **with permanence**. A spawn request goes to the host, which assigns an incrementing id and broadcasts `_do_spawn(id, type, xform)`; every machine instantiates `spawned_<id>` under the current scene (matching path → sync routes). Physics bodies get a host-authority `NetBody`. The host also keeps a **registry** of what it spawned, and when a joining client's character enters the world (`CharacterSpawner._spawn_local`, after the scene-change `session_ready` triggers) it asks for a **snapshot** — the host re-spawns each object to the newcomer at its **current** transform *and* current **authority** (so a moved object arrives where it is, and an object being *held* at join arrives owned by its holder and accepts that stream). `_do_spawn` is idempotent (snapshot + live broadcast can overlap). Still a testing tool — production contraptions come from seeds, not this.
- **Dormancy** (`NetBody`): the authority streams every tick **only while the body is awake**; when the physics engine **sleeps** it (settled), it sends one final at-rest state (vel ~0, so remotes settle without extrapolating) and stops — 0 bytes until something wakes it (bump, push, grab; grabbing already forces `sleeping = false`). Taking authority (grab handoff) resets it to awake. A **proxy** sleeps on its own now that it is a normal dynamic body: once it is within `SETTLE_DIST`/`SETTLE_ANG` of the reference pose the follow stops writing its velocity and lets it settle (writing `linear_velocity` every frame would keep it awake forever); it is woken again the moment the reference moves. This is what scales to hundreds of objects: the 99.9% static cost nothing on the wire.
- **Remote proxy** (M3): a full **`BoneInstantiator`** (`is_active=false`, `is_puppet=true`) rebuilt from the peer's seed (`hash(steam_id)`). Its `CharacterRigidBody3D` runs in **puppet mode** — `_physics_process` early-returns (no simulation, no impact/fall, no collision, frozen kinematic); `CharacterNetSync` writes its `global_position`/`yaw` from interpolation and feeds `puppet_velocity`, which the animation reads via `get_motion_velocity()` to drive the walk cycle. All the puppet changes are guarded so single-player is untouched. A `NameTag` (billboarded `Label3D`) sits above it.

---

## Known open points

- **Equilibrium / falls** are frame-dependent ([people.md](people.md), [onfoot-gameplay.md](onfoot-gameplay.md)) — a *deterministic* form would be needed for the **same** fall to simulate identically on two machines. That's still open, but the **visual** is handled now (Cause C, done): each proxy runs its own approximate local ragdoll from a synced flag, so falls are *seen* everywhere even if not bit-identical.
- **Front-end / menu** intentionally absent for now — auto-host scaffolding until the Lounge join flow is built.

## Pending — on-foot interaction gaps (grouped by root cause)

Surfaced in 2-player play-testing (2026-07-29). Six reported symptoms, but they collapse to a few **root causes** — fix the root, not the symptom. Suggested order: **A → B → C**, then the tuning discussion. See [onfoot-gameplay.md](onfoot-gameplay.md) for the gameplay intent (carrying packages, shoving/grabbing teammates).

### Cause A — proxies have no collision presence ✅ *Done*
`CharacterRigidBody3D.setup_as_puppet()` sets `collision_layer = 0` / `collision_mask = 0`, so a remote player's capsule is invisible both to physics and to the interaction raycast (mask `1|2`). It was a deliberate simplification in the M2/M3 puppet work that over-shot. **One fix** — give the puppet a *kinematic* collision presence (a layer the local dynamic capsule and the detector ray hit) — unblocks three symptoms:
- **Characters don't collide with each other** — your dynamic capsule can't hit a layer-0 proxy.
- **Can't grab teammates** — the detector's ray misses the proxy, so it never reaches the character's `GrabbableInteractable` (which still exists — `_setup_char_grabbable`).
- **Can't push a teammate** — the empty-handed push (`_release_throw` with no held object) acts on the *hovered* interactable, and a layer-0 proxy can't be hovered.

**Update:** rigid capsule-vs-capsule blocking was later **removed entirely** in favour of a *soft, non-blocking* momentum collision (`_resolve_player_collisions`, see [characters.md](../technical/characters.md)). Players pass through each other and the collision is resolved by hand from momentum. This supersedes both loose ends that used to live here: **spawn-overlap** (capsules that spawn inside each other simply never rigid-collide, so nothing to fling) and the **push-jitter caveat** (a kinematic proxy no longer pushes the local capsule — the stale, network-delayed puppet position was exactly why rigid blocking felt wrong). The puppet still needs its **collision presence** (layer 1) for the interaction ray (grab/push targeting) and for `_resolve_player_collisions` to detect it — that part of Cause A stands.

### Cause B — the throw impulse is lost in the authority handoff ✅ *Done*
Holding **R** with a grabbed box threw it, but it dropped in place: `_release_throw` applied the impulse locally, then `_stop_grab` handed the box's `NetBody` authority back to the host, which retook it at rest (the velocity never made it across) → the box snapped back. **Fix:** the impulse is now applied by the **final authority** (`NetBody.throw_body` → the host, or the local peer offline), to the instance that everyone syncs from — not via the buffer, so it can't be lost. The client does **not** apply locally (that would snap back ~1 RTT when authority transfers); it sends the impulse to the host, which applies it after `end_grab` returns authority. *Trade-off:* a client's own thrown box starts moving ~1 RTT + render-delay late, but smoothly (no snap). Client-side prediction could hide that later if it bothers.

`_release_throw` now routes the launch (`_launch`) by target: a synced box → `throw_body`; a **teammate** → `CharacterNetSync.push` (the impulse is sent to the teammate's machine, where their capsule is dynamic and they're the authority, then replicated back — so the empty-handed **R push** shoves a teammate now, needing Cause A to have made them hoverable); anything else → a direct impulse. *Still open:* **grab-dragging** a teammate — grabbing latches (Cause A) but the grab PD hits their frozen proxy locally and does nothing; dragging them would need a continuous force-intent to their machine (like `NetBody`'s co-grab intent), a further mechanic.

### Cause C — ragdoll isn't replicated to proxies ✅ *Done*
Remote players used to freeze in their last standing pose when they fell. **Fix:** `CharacterNetSync` syncs a `ragdoll` flag plus the **pelvis position and rotation** in the per-tick state, and on the edge each proxy runs its **own local ragdoll** (`_drive_proxy_ragdoll` → `RagdollUtil.activate_as_proxy`/`deactivate_as_proxy`). The **pose** isn't re-simulated to match (physics isn't deterministic across machines) — it's an *approximation*: a limp body flailing believably. But the **pelvis position and facing are anchored to the owner's**: the proxy makes its pelvis body a **kinematic anchor** and each frame `apply_to_puppet` calls `RagdollUtil.drive_pelvis_to(s["pos"], s["ragdoll_rot"])` to place it at the owner's streamed pelvis pose (the owner's `_update_active` keeps its capsule = pelvis, so `s["pos"]` is the pelvis); the other bones simulate locally, hanging off it by the joints. So the *pose* is local, the *place and orientation* are authoritative — no drift and no yaw snap, however far the player ragdolls. On **recovery** the normal synced transform resumes; `deactivate_as_proxy` restores the puppet state (`setup_as_puppet` — `deactivate` un-freezes the capsule). This is the visible payoff of Cause A + B: shove a teammate → they fall → everyone sees it, in the right spot. *Known approximation:* only the limb pose differs across machines; the body's location and facing match.

### Grab rework (2026-07-31, in progress)

Two play-tested symptoms drove a rework of the grab system. The diagnosis matters more than the symptoms:

- **A player gets launched into the air when a second player grabs the box the first is holding.** *Root cause:* the proxy box was a **kinematic body moved by teleport** → infinite mass, unbounded implied velocity → Jolt ejects any capsule it materialises inside. **Fixed** — proxies are now velocity-driven dynamic bodies (see `NetBody` above).
- **A long box held by two players (one at each end) jiggles forever.** *Root cause:* three things, all removed by the solver in step 2 below. (1) The grab PD damped `linear_velocity` at the **centre of mass** while applying force at the **grab point**, so rotation about the centre is essentially undamped (ζ ≈ 0.09 for the long box) and rings for seconds. (2) The yaw-follow toggle depends on `has_cograbbers()` → `_intents`, fed by *unreliable* RPCs with a 200 ms timeout, so it **flickers** and fires torque pulses into that undamped mode. (3) Two grabbers run **independent springs toward geometrically incompatible targets** (nothing constrains `|target_A − target_B|` to equal `|grab_A − grab_B|`), so the system is over-determined and always carries a residual. Only shows up on long boxes because a cubic box's grab points nearly coincide.

**Direction agreed:** stop patching the seam between "the network dictates the transform" and "the local solver wants to resolve contacts" — there were two authorities on one body, and every candidate fix was a clamp on that seam. Instead, move toward **every machine genuinely simulating the box**: sync the *intent* (who grabs where, pulling where) rather than the pose, apply every grabber's spring on every machine, and reconcile drift with a soft correction. No rollback, no prediction.

Steps, in order:

1. ✅ **Proxies dynamic + velocity-driven** (`NetBody._follow_reference`). Play-tested: **the launches are gone**, which confirms the diagnosis.
2. ✅ **One solver per body, centre-of-mass hold** (`GrabbableInteractable`, see "Grab model" above). Collapses what were steps 3 and 5 into something simpler: holding at the centre removes the translation↔rotation loop, which makes two grabbers stable *by construction* rather than by tuning, and derived critical damping removes the gain knobs. Deliberately trades the "off-centre force gives emergent rotation" intent for stability — **stability over realism** was the call.
3. **Broadcast hands** so every machine solves the same grab locally instead of only the authority; gravity back on for proxies; the follow softens from "set velocity" to "nudge velocity". Removes the co-grabber's ~100 ms delayed feedback loop (they currently correct against a box they see late). This also lets **authority migration be deleted entirely** — `_grabbers`, `_grant_authority`, `set_body_authority`, the velocity carry-over and the `throw_body` routing all go, and the "throw impulse lost in the handoff" bug (Cause B) stops being *possible* rather than being fixed.
4. **A grabbed body never rigid-collides with its own grabbers** (collision exception, replicated) — but it still can with **bystanders**, which is the emergent knockdown the design wants.

### To design — grab-force vs knockdown magnitudes (NOT in the active plan)
Grabbing a box sometimes flings/ragdolls the grabber, and even a *light* box can send a nearby teammate flying. Likely a **tuning/magnitudes** problem, not architecture: `grab_strength` (~500) and the force needed to knock someone over are comparable, and the box masses (2 / 30 / 3 / 40 kg) may not read as "light vs heavy" against that. Intent to preserve: running into a teammate with a *big* package should knock them over (emergent fun); a *light* one shouldn't. Prefer calibrating magnitudes over making collision one-way (which would kill that emergent moment). **To be discussed before touching.**
