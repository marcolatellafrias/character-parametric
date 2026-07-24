# HUD — Patience Bar, Health, Sprint & Player States

The HUD is deliberately minimal: the crew's **patience bar**, the player's **health**, and a **sprint bar** shown only while sprinting. Delivery deadlines and money never appear on the HUD.

> **Shift vs run.** A **run** is the whole match (1–4 players, hosted) and spans **several shifts**; it is the unit that restarts. A **shift** is one work period inside a run — pick a batch at a branch, deliver, any player closes it at a branch, settle money & penalty points, **rest** (no clock), next shift. See [run-setup.md](run-setup.md).

---

## Patience bar

A HUD element **shared by the whole crew** — the company's patience with this crew in the **current shift**, not any single player's standing. It **resets to full at the start of every shift**.

- **Starts full.**
- **Does not drain while the crew keeps pace.** It only begins to wear down once they fall **well behind** expected delivery performance.
- **Delivering a package regenerates it** a little.
- **Empty → the whole match ends:** a **game-over screen** shows and the **run restarts**. Because the bar only drains on sustained underperformance and any delivery buys it back, emptying it is an *earned* loss, never a surprise.

It is the game's **soft clock**. A fully idle crew drains it in roughly **40 minutes**; an actively delivering crew can work indefinitely. This replaces the old fixed-length shift timer (see [run-setup.md](run-setup.md)).

---

## Health & sprint

Personal to the player's own character:

- **Health** — the character's current health. Drops from accidents; its value and cause decide the player state below.
- **Sprint bar** — shown **only while sprinting**; hidden otherwise.

Health and accidents come from the on-foot systems in [onfoot-gameplay.md](onfoot-gameplay.md).

---

## Not on the HUD

- **Delivery deadlines** — each package carries its own delivery window as a **diegetic label** on the package itself (see [objects.md](objects.md)). Past the window it can still be delivered, but is worth very little.
- **Money** — settled at the branch at end of shift ([run-setup.md](run-setup.md)), never shown mid-shift.

---

## Player states — going down mid-shift

Going down **takes you out for the rest of the current shift**, and you **spectate** the rest of the run. There is **no mid-shift revive and no healing a teammate** — this keeps the loop simple and, more importantly, keeps every employee meaningful: losing one has to sting. Scarcity is tuned through **difficulty** (how easily a hit is grave or fatal), not through a rescue mechanic.

Severity only decides **how, and whether, you come back**:

| State | Trigger | Return |
|---|---|---|
| **Injured** | Health hits the low threshold (~10) from an ordinary, non-lethal incident. | **Next shift, same employee.** No lasting cost. |
| **Gravely injured** | A severe but non-fatal trauma (a big survived fall, a gunshot, an explosion). | **Medical leave** — unavailable for a few in-world days. A substitute employee covers; this one returns when recovered (see [people.md](people.md)). |
| **Dead** | Health reaches **0** — fatal fall, headshot, crush. | **Never as this employee** — a brand-new employee joins next shift. |

A benched player only rejoins if their teammates **start another shift**. Death, medical leave, and substitute generation are all part of the employment lifecycle in [people.md](people.md). **Firing is not a mid-shift state** — penalty points get an employee fired *between days*, discovered later at the bulletin board (see below and [people.md](people.md#penalty-system)).

---

## Two ways to lose

- **Employee-level** (the table above): you are out for the **current shift**; the run continues for your teammates.
- **Run-level:** the crew's patience bar **empties → the whole match ends** (game over, run restarts).

Separately and far more slowly, a player's **penalty points** can get their employee **fired between days** (see [people.md](people.md#penalty-system)) — never mid-run, and only visible later on the bulletin board.

**Conceding equals losing.** If the host leaves once defeat is certain, the run simply ends and resets — exactly the outcome of the bar emptying. Penalty points from each shift are already banked at branch close, so there is nothing extra to dodge by quitting, and losing the run carries **no separate point penalty** of its own.
