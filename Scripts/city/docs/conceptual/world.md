# World — Nuevos Aires

The alternate-reality Buenos Aires the game takes place in, during roughly the **1900–1920** years. Heavy Italian architecture, analog technology, flying cars, monuments, tango, ragtime, ornamentation, advertisements, occultism.

Nuevos Aires is shared by all players: it runs on a **universal day/night cycle** and a **changing climate**, both driven by seeds tied to the real Buenos Aires timezone.

---

## Day/night cycle

Universal for all players, based on the real Buenos Aires timezone. The whole player base experiences the same time of day simultaneously.

---

## Climate

One day has exactly **one climate at a time**, chosen by that day's seed and announced in the [daily bulletin](#daily-bulletin).

| Climate | Probability | Effect |
|---|---|---|
| Sunny | 70% | Normal, no debuffs. |
| Rainy | 20% | Reduced acceleration efficacy on people — longer to stop, longer to start moving. |
| Foggy | 10% | Reduced visibility. |

---

## Seeds

Two universal seeds drive world state. Both are the same for every player worldwide, on Buenos Aires time.

### Daily world seed

Changes every day, randomly. Same for all players for the whole day (Buenos Aires timezone). Determines:

- The **climate** of that day.
- Made-up world **events** (not implemented yet).
- The previous day's **bulletin events** that don't depend on player actions (e.g. misc leaves), which can affect employee rosters.
- The **packages** that will spawn that day to be delivered.
- Which **company headquarters** each company spawns at, for each run during that day.

### Weekly world seed

Changes every week, randomly. Same for all players for the whole week (Buenos Aires timezone). Determines:

- The **city spawn seed/parameters** (see [city-generation.md](../technical/city-generation.md) for how the city is generated from it).

---

## Daily bulletin

Every day a bulletin is hung on the bulletin board. It contains:

- The day's **climate forecast**.
- Randomly generated **misc leaves** (if any) across the current rosters of that company, for all players currently playing. See the employment lifecycle in [people.md](people.md).
