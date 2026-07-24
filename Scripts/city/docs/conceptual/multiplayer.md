# Multiplayer & Sync

The game is co-op for **1–4 players** ([00-overview.md](../00-overview.md)). One player **hosts** and is authoritative; others join over Steam. This file is the technical outline: the transport, how a session is created/joined, how players are represented, and what has to stay in sync (and in what order we build it).

---

## Transport — GodotSteam

Networking runs on **[GodotSteam](https://godotsteam.com)**:

- The **`Steam` singleton** for Steamworks (identity, lobbies, rich presence, the overlay).
- **`SteamMultiplayerPeer`** plugged into Godot's high-level multiplayer (`multiplayer.multiplayer_peer`), so we get RPCs / `MultiplayerSynchronizer` over Steam's relayed sockets — no manual packet plumbing.

For now the game runs under **Spacewar (app id `480`)**, so Steam features work without our own app id.

---

## Session & joining — no menu (for now)

**Deliberately menuless while we build.** On launch the game **auto-creates a session as host** — no title screen, no lobby UI. The only way a friend joins is the **Steam overlay → "Join Game"**.

Why: a menu means clicking through UI on every run, and we relaunch constantly to test. Auto-host keeps the iteration loop tight. A real front-end — and the diegetic **Lounge / assembly** join flow from [run-setup.md](run-setup.md#match-lifecycle) — comes later; this is scaffolding.

**Host, on launch:**
1. Init Steam, create a **Steam lobby** (friends-only), mark it joinable.
2. Set **rich presence** so friends see **"Join Game"** on your profile.
3. Start `SteamMultiplayerPeer` as **server** (peer `1`).

**Client, on "Join Game":**
1. GodotSteam fires the **join-requested / lobby-join-requested** callback with the lobby id.
2. Join the lobby, read the host's Steam id from lobby data.
3. Connect `SteamMultiplayerPeer` to the host → Godot's high-level multiplayer takes over.

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
- The **authority** of a body (its owning peer for characters, the host for the ship/objects) sends `transform + linear/angular velocity` on an **unreliable** RPC each tick; remotes buffer and **interpolate**.
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

1. **Host + join + player registry.** ✅ *Implemented.* Auto-host, join via the Steam overlay, and the **session-player registry** (`peer ↔ steam ↔ Player`); each peer spawns a character. Proves the transport and identity end to end.
2. **Capsule sync.** ✅ *Implemented (pending live 2-player verification).* Replicate each player's **capsule** (transform + movement state). Remote players are just the **capsule + its debug ray** — no aesthetic skeleton yet.
3. **Aesthetic & animation.** Reconstruct/replicate the skeleton so remote players look like characters (mostly seed-reconstructed + a little state).
4. **Interaction.** Grab / controllables / ship (host-authoritative), objects, ownership handoff on grab.
5. **Run.** Run state, the shift/patience clock, scoring — and the assembly/join flow moving onto the real Lounge front-end.

### Implementation (M1–M2)

- **`SessionManager`** (autoload) owns the session lifecycle: init Steam, host/join, and — the key timing fix — it emits **`session_ready(local_peer_id)`** only once the local id is definitive (offline/host → `1`; client → its unique id, on `connected_to_server`), plus `remote_player_joined/left`. Nothing spawns before the id is known (a client spawning early would collide on peer `1`).
- **`CharacterSpawner`** (scene node) spawns every character by code: the local player (a full `BoneInstantiator`) and one **`RemoteCharacter`** proxy per remote peer. Each is named **`char_<peer_id>`** and its **`NetSync`** child's `multiplayer_authority` is that peer — so the RPC path matches on every machine and `is_multiplayer_authority()` decides who simulates.
- **`CharacterNetSync`** (child `NetSync`): the authority sends capsule **centre pos + yaw + linear velocity** on an **unreliable_ordered** RPC each physics tick; remotes buffer with a local timestamp and **interpolate** (100 ms render delay, short velocity extrapolation on late packets). No `MultiplayerSynchronizer`, per the physics-sync rules above.
- **`RemoteCharacter`**: lightweight capsule + local ground ray only. No skeleton (M3), no physics sim — it just follows the interpolated transform.

---

## Known open points

- **Equilibrium / falls** are frame-dependent ([people.md](people.md), [onfoot-gameplay.md](onfoot-gameplay.md)) — need a deterministic form before the *same* fall simulates identically on two machines. Milestone 2 dodges this by replicating the owner's transform rather than re-simulating.
- **Controllable sync transport** (the layer that replicates control state) isn't wired yet ([interactables.md](interactables.md)).
- **Front-end / menu** intentionally absent for now — auto-host scaffolding until the Lounge join flow is built.
