# Run Setup — Companies, Branches, Shifts & the Run

Everything from creating a game to a run ending. See the full loop in [00-overview.md](../00-overview.md).

---

## Runs and shifts

- A **run** is the whole match: **1–4 players**, hosted by the game's creator/owner, who invites friends. A run **spans many shifts** and is the unit that ends and restarts.
- A **shift** is one work period inside a run: pick a batch at a branch, deliver it, close it at a branch. Between shifts the crew **rests** — dead time with no clock.
- A run **begins at creation**, with players spawning in a branch's **Lounge**. New players can keep **joining until the crew crosses into the garage** (opening the elevating door, which locks the crew). See the **Match lifecycle** below.

---

## Delivery companies

There are three delivery companies in Nuevos Aires:

| Company | Enum | Character |
|---|---|---|
| Despachos Generales | `despachos` | Government institution — inefficient, bureaucratic, decadent, old. |
| Monsetti & Hijos Encomiendas | `monsetti` | Family business, small; rumored to be a money-laundering scheme for the Monsetti mafia. |
| Voltera | `voltera` | Mysterious company, tied to cutting-edge inventions and technology. |

Each player has a **preferred company**, decided deterministically from their player seed and unchangeable — see [people.md](people.md). The host's preferred company is the company the run runs on.

---

## Company branch headquarters

Every city generation has **4 branch headquarters per company**, always spaced evenly from each other (spacing is per-company; different companies' branches may sit near each other). Which headquarters a company spawns at during a run is set by the [daily seed](world.md#daily-world-seed).

Each branch is one building module facing a street, split into **two rooms with no line of sight between them**:

- **The Lounge** — where players **spawn** at run start; the crew's **info hub** (bulletin, roster ledger, memorial, radio) with **no gameplay mechanics** — see [The Lounge](#the-lounge) below. Only ever entered at run start; once the ship first departs it is **sealed in every branch** for the rest of the run. Its separation from the garage is what lets the ship and batch (re)configure unseen while the crew is still forming.
- **The Garage** — the working room, joined to the Lounge by a one-time **elevating door**. Holds:
  - the **ship**, the **intake zone** (marked rectangle where the shift's **total batch** spawns, served by a **pneumatic tube**), and the **ship zone** (marked rectangle where the ship must be **parked** to close a shift);
  - **cosmetic vending machines** on the walls — **ship** and **person** cosmetics *(upgrades are separate, at city vending machines — see [onfoot-gameplay.md](onfoot-gameplay.md))*;
  - a **recall teleporter** — a fixed wall device (like the vending machines) that brings a **distant player** into the garage at shift close, so nobody spawns among other players or packages;
  - the **garage-door button** and the **garage door** to the street.

The **garage-door button** works the street door and drives both shift boundaries: in **loading** it **raises** the door → commit/departure; with the **ship parked back** it **lowers** it → close the shift. It is **global to the company** — it moves the doors of **all** that company's branches at once (other companies' branches keep theirs shut), so the crew can commit or close at whichever branch they are at.

---

## The Lounge

The Lounge carries no mechanics — it is where the crew **reads its standing** before heading out. Everything here is read-only and seen only at run start (the Lounge seals once the ship departs):

- **Bulletin board** — the daily bulletin: the climate forecast and the day's misc-leave / firing reports ([people.md](people.md#penalty-system), [world.md](world.md#daily-bulletin)).
- **Roster ledger** — a book on the table listing the player's **active** and **temporarily-inactive** employees ([people.md](people.md#rosters)).
- **Memorial** — a wall remembering the player's **dead** employees.
- **Radio** and **seating** — flavor.

The ledger shows who exists, but **not** which substitute the company will field after a death — that pick stays a mystery ([people.md](people.md#rosters)).

---

## Match lifecycle

The **garage-door button** drives every shift boundary — one button, no separate "start" and "close." What a press does depends only on the door's position, which is only ever one of two states:

- **Door down** (crew inside, loading) → the press **raises** it = **commit / departure**: the pneumatic tube clears the intake zone, the chosen batch locks, the ship flies out, the patience bar starts. Only works if at least one package has been pulled out of the intake zone (no empty manifest).
- **Door up** (ship back and parked in the ship zone, all players in the garage) → the press **lowers** it = **shift close**: undelivered chosen packages are lost, money & penalty points settle, and the next total batch spawns in the intake zone.

So **raising always means "we're heading out"** and **lowering always means "we're done — seal up and settle."** While the ship is out the button is inert (lowering is gated on ship-parked + all-in-garage). The only other stage trigger is the **elevating door** from the Lounge, opened once at run start.

1. **Run start (assembly).** The host creates the game; players spawn in the branch **Lounge** (branch = [daily seed](world.md#daily-world-seed) + host's preferred company), **join open**. The garage — ship and batch — is out of sight and still configuring itself to the forming crew.
2. **Crew lock — first shift only.** A player opens the **elevating door** to the garage: this **closes the join, locks the crew**, and **finalizes the garage** (dashboard laid out, total batch spawned with final prices). The crew crosses in.
3. **Loading — batch undefined (2a).** No clock yet — the patience bar isn't running. Players read labels, plan the route, and **choose packages by dragging them out of the intake zone** onto the ship. Nothing is locked.
4. **Commit / departure (2b).** A player presses the button; the **garage door rises**, the tube vacuums the intake zone, the chosen batch locks, the ship departs, the **patience bar resets full and starts**. *The very first departure is blocked until the Lounge is empty (everyone in the garage); on it, the Lounge is **sealed in every branch** for the rest of the run.*
5. **Shift (play).** The crew delivers the chosen batch; the patience bar governs.
6. **Shift close.** The crew flies back to **any** branch, **parks in the ship zone**, and with all players in the garage a player presses the button; the **garage door lowers**. It **settles** the shift (undelivered chosen packages lost, money & penalty points banked) and **spawns the next total batch** — back to stage 3 at **difficulty +1**.
7. **Run end.** The **patience bar empties**, the **ship is destroyed**, or the **host leaves** → the run ends (game over & restart on the first two).

**First shift vs later shifts:** only the first shift has the Lounge/assembly (stages 1–2) — its loading follows the crew crossing into the garage, where the join closes. Later shifts start straight at loading (stage 3), from the previous shift's close, with a locked crew.

---

## Choosing a batch

The **total batch** — every package on offer that shift — spawns in the garage's **intake zone**. A package becomes part of the **chosen batch** simply by being **outside the intake zone** when the garage door opens; the crew chooses by dragging packages out of the zone and loading them onto the ship ([grab system](onfoot-gameplay.md#grab-system), [cargo zone](ship-gameplay.md)). Package variety (transportability, fragility, size, priority, special effects) is the shift's first strategic decision; package definition lives in [objects.md](objects.md).

At commit (garage door up), the **pneumatic tube clears whatever is left inside the zone**, so nothing loose remains — you can't add to the batch after departing, and there's no fiddly per-package "is it loaded?" tracking. Only the zone is vacuumed: anything already **outside** the zone is kept even if not literally on the ship, so packages never vanish from odd spots. The chosen batch is recorded at that instant as the crew's **obligation** — dropping a chosen package mid-shift still counts as owed. The door **won't open with the zone untouched**: you must choose at least one package.

The **total batch is the same at every branch** (one universal list), fixed by:

- **The shift's seed** — advances **only when the shift is completed**. Leave and rejoin an unfinished shift and the packages are identical — no rerolling for a better batch.
- **The shift's number in the run** — a **difficulty modifier**: later shifts offer harder, more valuable packages, so a **long run** is worth more than several one-shift runs.
- **The crew factor** — a smaller or lower-stat crew is offered **more valuable** packages (a built-in handicap); see [objects.md](objects.md).

So the total batch = **shift seed + shift number**, with per-package value scaled by the **crew factor**. Undelivered chosen packages are lost at close, and the patience refill is normalized to the chosen batch's value ([objects.md](objects.md)).

---

## The shift & the patience bar

During a shift the crew delivers their **chosen batch**. Progress is governed by the crew's **patience bar** ([hud.md](hud.md)): it **resets full each shift**, drains only when the crew falls **behind**, and **refills on delivery**. If it **empties, the run is over** (game over, restart).

Each package carries its **delivery window** as a diegetic label on the package itself ([objects.md](objects.md)); past the window it can still be delivered, but for very little.

---

## Closing a shift

Any player can end the shift at **any branch the crew chooses** (usually the nearest). To close: the **ship is parked in the ship zone**, **all players are in the garage**, and a player presses the **garage-door button** (lowering the door). Requiring everyone in the garage is what keeps the crew from roaming the city freely between shifts. A distant or lost player is brought in by the garage's **recall teleporter** (a fixed wall device, like the vending machines), which spawns them **inside the garage** — never among other players or packages.

On close:

- **Undelivered packages from the chosen batch are lost** — they count against performance.
- **Money and penalty points settle** (below).
- The crew **rests**; the same press **spawns the next total batch** in the intake zone, beginning the next shift's loading — one difficulty step higher.

**Leaving mid-shift** (a player or the host quitting before closing) only **forfeits the un-banked progress** of that shift — nothing settles, so no penalty points are banked. Conceding a doomed run is therefore the same as losing it, with no extra cost. It is the **seed**, not a quit penalty, that prevents batch rerolling.

---

## End of shift — money, cosmetics & the bulletin

At the end of a shift, each player's **active employee earns or loses money** (never negative) based on performance. **Money belongs to the employee, not the player** ([people.md](people.md)): a player's different employees keep separate wallets, and an employee's savings are **lost when they die or are fired**. Money is spent on:

- **Ship cosmetics** — bought at the garage's **wall vending machines** for the **host's ship** ([ship-gameplay.md](ship-gameplay.md)). A run flies the host's ship, so everyone in it sees them; they are lost if the ship is destroyed.
- **Person cosmetics** (hats, etc.) — also at the garage's vending machines, but **owned by the individual employee**, like their money: they follow that employee and are lost when they die or are fired.
- **Upgrades** at vending machines scattered across the city ([onfoot-gameplay.md](onfoot-gameplay.md)).

This is the game's only persistent layer, and deliberately a small one — Nuevos Aires Delivery is not a progression game.

The **company ship** is part of this persistence. Each player keeps a **roster of four host-owned ships**, one per crew-size (1 / 2 / 3 / 4 players); a run uses the host's ship **for the current player count** ([people.md](people.md#player), [ship-gameplay.md](ship-gameplay.md#ownership--persistence)). Each keeps its **own seed, dashboard, cosmetics, and damage** — none shared — so its dashboard stays consistent as players come and go. **Destroying the ship ends the run** (see [Losing the run](#losing-the-run)): its cosmetics are lost, **every player takes penalty points**, the wreck is logged as **company property damage** ([people.md](people.md#penalty-system)), and that roster slot regenerates a **new-seed ship** — a fresh, unfamiliar **dashboard the crew must re-learn**. Ship damage is repaired **in flight, at the dashboards** — see [ship-gameplay.md](ship-gameplay.md#damage--repair).

Performance also feeds the **penalty system** (lost/damaged packages, hurt pedestrians → penalty points → firing), part of the employment lifecycle in [people.md](people.md#penalty-system). Penalty points never appear on the HUD; they surface **diegetically and delayed** — the **next day**, an employee's **observations**, and whether they were fired, appear on the **Lounge's bulletin board** — read at the start of a run (reports change between days, not shifts). You have to wait for the report to know where you stand.

---

## Losing the run

A run ends when:

- The crew's **patience bar empties** → **game over**, and the run **restarts**.
- The host's **ship is destroyed** → **game over**. It is the crew's only lifeline and is **never respawned mid-run**; the run restarts with that **ship-roster slot regenerated** (new seed → new dashboard, no cosmetics, no damage), and every player takes penalty points (see end-of-shift persistence above).
- The **host leaves** → the run ends for everyone. Conceding equals losing — there is no separate penalty for it.
