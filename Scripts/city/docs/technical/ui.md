# UI — Menus, Console & Debug

How the game's UI is layered: the **player-facing shell** (main menu, pause, options), the **debug panel** (F1), and a **global console** — plus in-match player identity (names in the pause list and above capsules).

**Status: plan (not built yet).** Locked decisions from design:

- The main menu is a **separate scene**; on launch the game goes straight to it (no more launch-time solo spawn).
- **No solo mode** — you only **Host** or **Join**.
- The main menu is a **temporary front-end**, later replaced by the diegetic **Lounge / assembly** flow ([run-setup.md](../conceptual/run-setup.md#match-lifecycle)).
- The console is **always available** (power-user), in menu and in-game — not stripped from release.

---

## The three layers

Keep these as separate systems. Mixing them — networking living inside the debug panel today — is the current mess. **The rule that untangles it: Host/Join is a player action → it belongs in the menu, not the debug panel.**

| Layer | What it is | For whom | Lives… |
|---|---|---|---|
| **Game shell** | Main menu, pause, options | Player | Always (menu and/or in-game) |
| **Debug panel (F1)** | Info + actions + spawn | Dev | Only when a player/session exists |
| **Console** | Valve-style terminal | Dev / power-user | Global, always |

---

## Layer 1 — Game shell (player-facing)

**Scenes & flow.** A `main_menu` scene is the initial scene and does **not** load the world. Heavy city generation only happens once a role is chosen and the game scene loads:

`launch → main_menu → Host or Join → SessionManager sets the role → load game scene → CharacterSpawner spawns`

This removes the current "solo session at launch" bootstrap: `SessionManager` no longer auto-starts a session; `host()` / `join()` are called from the menu.

- **Main menu:** Host · Join (code field) · Options · Quit.
- **Pause menu (Escape, in-game):** Resume · **Players in match** (name list) · Options · Quit to menu · Quit game.
- **Options:** one screen shared by menu and pause. Placeholder for now — the button exists, does nothing.

**The "join code" — decided: a short code.** Instead of the raw 64-bit lobby id, the host publishes a **short alphanumeric code** as **lobby data**; the joiner runs a **lobby-list request filtered by that code** to resolve the real lobby id, then joins. No backend needed — Steam matchmaking does the lookup. The Steam overlay "Join Game" stays the frictionless path for friends; the code is for sharing outside the friends list.

---

## Layer 2 — Debug panel (F1), tabbed

Split the single F1 list into tabs, in a panel as tall as the screen so they barely scroll:

- **Info** — unify here: the generated-character info, seeds/date, and session state (solo/host/client + peer list).
- **Actions** — creative, ragdoll, respawn, go-to-start, etc. Among them **Neblina y corte por distancia** (`CityDebugView`), to look at the whole city at once: it turns off the Environment's fog (`CityFog`, found through the `city_fog` group) — and the old shader quad, if it were ever switched back on — *and* lifts the `visibility_range_end` that buildings, floating sidewalks and bridges are born with (`render_distance` plus their own radius) — without the second half the city would still be cut at that distance. It is reversible: each mesh remembers its original range in a meta, so nothing that never had a range gets one. It draws the entire city, so it is for looking, not for measuring performance.
- **Arquetipos** — become, or spawn beside you, a character of a given archetype.
- **Spawn** — gmod-style list (characters, boxes, ships, …).
- **Apuntar para identificar** — a toggle in *Acciones* that arms `CityInspector` ([city_inspector.gd](../../debug/city_inspector.gd)): a crosshair at screen centre, a finite 50 m ray, and whatever it hits gets a dot at its centre, an in-world `Label3D` naming it, and what it hit drawn in **three layers**, which is what makes local and global readable at once: the **whole object** as a very dark translucent fill, the **piece** aimed at one step lighter over it, and the piece's **x-ray wireframe** on top — every triangle edge, deduplicated. The dark fills exist so the wireframe has something to read against.

  All three ignore depth, and their order is fixed by `render_priority` rather than by the depth buffer: they are copies of the city's own geometry sitting exactly on top of it, so depth testing would make them fight the original and each other. Deliberately *not* the grabbable outline: that one is a pure silhouette meant to lift a held object off the background, whereas inspecting wants all the angles, visible even when occluded. It exists to close the "I can see something wrong but I cannot say *which* one" loop — the reason it is worth building early is that every system added later (pipes, stairs, windows) joins it for free. Like the F2 map it does **not** register in `UIState`, and here that is a requirement rather than a preference: the panel frees the mouse, and without a captured mouse there is no aiming, so F1 only *arms* the mode and the mode is used with the panel **closed**.

  The inspector **knows nothing about buildings, roofs or bridges**. It casts a ray, reads the scope stamped on the body that stopped it, and asks `CityIndex` what the piece is — see "Identity of a piece" in [city-generation.md](city-generation.md). The outline is built by copying that piece's triangle range out of the city mesh, which is what allows outlining one cell of a merged block mesh; applying the grabbable outline path directly would light up the whole block, since it works per `MeshInstance3D`.
- **Clima** — one entry per `WeatherPresets` entry, each jumping straight to it (`CityFog.apply_to_tree`). Two overlays do the same job without the panel, and the difference between them is deliberate. **F5** (`WeatherOverlay`) lists the weathers and picks one with the number keys; like the F2 map it does **not** register in `UIState`, so the mouse stays captured and you keep flying — judging light means alternating two weathers from the same spot, looking at the same thing, which a panel that freezes the mouse cannot do. **F6** (`WeatherTuner`) edits the active weather by hand — fog diameter and colour, the two filter colours, the sky's zenith and horizon, and the sun's contrast, strength, disc size and shadow hardness — and this one *does* register in `UIState`, because dragging sliders and opening colour pickers needs the mouse free. Its edits are overrides layered on the preset and are cleared by picking any weather; nothing is written to disk, so whatever works gets copied by hand into `WeatherPresets`. See [city-generation.md](city-generation.md) for where the presets come from.
- **Mapa** — the city from above, live (`CityMap`): blocks coloured by neighbourhood, streets at their **real width** (the footprint of their lane volume, already in metres; boundary streets have none, so they are drawn as thin lines), a mark across the street for each bridge, and, read every frame while the tab is open, cars, ships, other characters, you as an arrow, and the ring around you where cars exist (`WorldSettings.spawn_radius`). The static part is baked once and re-baked if the city is regenerated. It opens showing the whole city; the wheel zooms towards the mouse, dragging pans, **a click teleports you there** (straight down from above onto the first thing below — debug only), and **Centrar en mí** re-centres on you. The same map also rides in the bottom-left corner **while you play**: **F2** toggles a small copy (`CityMapOverlay`) that is deliberately not registered in `UIState`, so the mouse stays captured and you keep moving — which is also why it has no click or drag: it stays centred on you and zooms with **+** and **−**.
- **Performance** — turns parts of the game off to see what each costs (`PerformanceToggles`): the ships' filler controls (the working ones stay, so you can still fly), cars, buildings, and NPCs (characters no player drives — not yours, not remote players'). Each has separate **draw** and **logic** switches, to tell GPU from CPU cost: they act on the part's root nodes — hidden, and `PROCESS_MODE_DISABLED`, which stops all processing below and takes its bodies out of physics (buildings lose their colliders; cars freeze in place and their spawner stops). Live numbers on top: FPS, frame/process/physics-step ms, draw calls, nodes, and how many of each part (Jolt leaves the physics-body monitors at 0, so they're left out). The state is static: it survives respawns and applies to whatever spawns later.

The console is **not** a tab here (see below).

---

## Layer 3 — Console (global)

Your instinct ("always there, in menu and in-game") is right, and it's actually *simpler* this way, not harder:

- A standalone **autoload overlay** above everything, toggled by `~`, working in the menu and in-game. Independent of any player or scene — that's exactly why it can live in the menu too. Docking it inside F1 would be *more* tangled (F1 only exists with a player).
- A **command registry** is the single source of truth for dev actions. The F1 Actions/Spawn buttons become **shortcuts that invoke registered commands** (`spawn box`, `host`, `join <code>`), so the console and the panel share one backend instead of duplicating logic.

---

## Cross-cutting — UI state & mouse/input owner

The real trap once several overlays exist (menu, pause, console, F1): each wants to show the cursor and eat input, and they fight. **Centralize a single UI state** (playing / paused / menu / console / debug) that owns `Input.mouse_mode` and decides who receives input. Build this first — everything else leans on it, and skipping it is how you get "the console is open but I'm still walking" bugs.

---

## Player identity & names

**Steam name handshake — ✅ done.** On `peer_connected`, each peer sends its `steam_id + name` to the new peer via a **reliable** RPC on the `SessionManager` autoload (`_register_identity`); since `peer_connected` fires for every pair, everyone learns everyone. The local player is now also registered in `players`. Names update through `players_changed`.

- **Pause-menu player list — ✅ done.** The pause menu lists everyone in `SessionManager.players` (name or `Jugador <id>` fallback, "(vos)" for the local one), refreshed on `players_changed`.
- **Nametags above capsules — ✅ done.** A billboarded `Label3D` above each **`RemoteCharacter`** proxy, showing that peer's name (updates on `players_changed`). Skipped for the local player — in first person you don't see your own capsule.

---

## Suggested build order

1. **UI state + mouse/input owner** — the foundation. ✅ *`UIState` autoload (`Scripts/ui/ui_state.gd`): owns `mouse_mode`, tracks open overlays (pause/menu/console/debug), exposes `gameplay_active()`. `player_controller` and `CharacterRigidBody3D` gate input on it; `DebugPanel` routes its toggle through it.*
2. **Pause menu** (Escape) — simplest, no networking. ✅ *`PauseMenu` (`Scripts/ui/pause_menu.gd`), a CanvasLayer in the game scene: Resume / Options (placeholder) / Quit. Overlay only — does not pause the tree (co-op keeps simulating).*
3. **Main menu + move Host/Join out of the debug panel** — the session starts from the menu; drop the launch-time solo spawn. ✅ *`main_menu.tscn`/`main_menu.gd` is now the initial scene (Host · Join-by-code · Options · Quit). `SessionManager` no longer auto-starts: `host()` creates a **public** lobby with a short code (or a local-only session if Steam is off); `join_by_code()` resolves the code via a filtered lobby-list search. On `session_ready` the menu loads the game scene; on `session_failed` it stays and shows the error. Debug panel's Net buttons are gone — role/code now shows as an Info line. **Untested with real Steam matchmaking** (the lobby-list-filter API names and the host→game transition need a live check).*
4. **Steam-name handshake** — replicate each peer's name (unblocks the identity features). ✅ *`_register_identity` reliable RPC on `SessionManager`; local player registered in `players`.*
5. **Pause player list + capsule nametags.** ✅ *Pause menu lists `players`; `RemoteCharacter` shows a billboarded `Label3D`. Also: pause now has **"Salir de la partida"** (`SessionManager.return_to_menu()`) alongside "Salir del juego".*
6. **Global console + command registry.** ✅ *`DevConsole` autoload (`Scripts/ui/dev_console.gd`): overlay toggled by the key left of `1` (physical `KEY_QUOTELEFT` → `º`/`~`), works in menu and in-game. `register(name, callable, help)` command registry; built-ins: `help`, `clear`, `quit`, `host`, `join <code>`.*
7. **Restructure F1 into tabs**, with Actions/Spawn calling console commands. ✅ *`DebugPanel` is now a `TabContainer` with **Info / Acciones / Spawn** tabs; the character stats (seed/archetype/height/weight/…) moved from the gameplay HUD into the **Info** tab. Panel is rebuilt on respawn. **Partial:** the Action/Spawn buttons still call `PlayerController` methods directly rather than routing through console commands — the registry exists for that later.*
