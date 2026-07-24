# Nuevos Aires Delivery

Juego co-op de delivery (1–4 jugadores) en **Nuevos Aires**, una Buenos Aires retrofuturista alternativa de 1900–1920. Hecho en **Godot 4.5** (GDScript), física con **Jolt**, red con **GodotSteam**.

## Antes de modificar código: leé el diseño

El juego está documentado en `Scripts/city/docs/`, separado en **conceptual/** (diseño de juego) y **technical/** (sistemas de generación a nivel código).

**Antes de escribir o modificar código de una feature, leé primero el/los documento(s) relevante(s)** para entender la intención de diseño y no romper supuestos. Solo los relevantes al cambio en cuestión — no todos.

- Empezá por el índice: [Scripts/city/docs/00-overview.md](Scripts/city/docs/00-overview.md) (pitch, loop de juego y tabla con qué hay en cada doc).
- Elegí desde ahí el/los doc(s) que tocan tu cambio. Guía rápida:
  - Multiplayer / red / sync / sesiones → `conceptual/multiplayer.md`
  - Personaje, cápsula vs esqueleto, ragdoll, grab → `technical/characters.md` + `conceptual/onfoot-gameplay.md`
  - Tráfico / autos voladores / spawn de autos → `technical/traffic.md`
  - Ciudad / calles / edificios / veredas / puentes → `technical/city-generation.md`, `technical/sidewalks.md`, `technical/bridges.md`
  - Nave, dashboards, carga → `conceptual/ship-gameplay.md`, `conceptual/interactables.md`
  - Objetos / paquetes → `conceptual/objects.md`
  - Personas, jugadores, empleados, pedestres → `conceptual/people.md`
  - HUD / barra de paciencia / espectador → `conceptual/hud.md`
  - Run, compañías, turnos, headquarters → `conceptual/run-setup.md`
  - Mundo, ciclo día/noche, seeds → `conceptual/world.md`

Si un cambio contradice lo que dice el doc, avisá antes de proceder (puede que el doc esté desactualizado o que el cambio necesite repensarse).

## Verificación

- Headless (`--headless`) sirve solo para chequear que compila/parsea. La escena completa puede segfaultear en el *teardown* headless (fugas de RID de Jolt) — eso no indica un bug del código.
- El veredicto real de gameplay (tráfico, personaje, spawns) se da en una partida jugada, no en headless.
