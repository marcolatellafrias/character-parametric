# Stuck report — run 2026-07-14T21:50:54
# 19 permanently-stuck root(s) captured (cap 20, max 2 per node, first 90s ignored). Followers/queues excluded; normal light waits can't qualify.

## Stuck head 1  (t=+91s, unmoved 41.4s, 1 car)
where: node 100 (street 73→100)
why  : IGNORED GREEN — stopped at a light 41s (≥4 cycles) with NO other constraint ever seen: a governor bug, or the light never turned (cross-check light_watchdog.md)
  2280 GARBAGE_TRUCK  spawn 73→100 @(131,10,283) head W
     route 73→100→99→32  →exit 32
     now  at node 100, 0.0 m/s, unmoved 41.4s, waits→
     gov  state=STOPPED target=0.0 gap=1.72 ray=0.0
     diag (no blocker)

## Stuck head 2  (t=+91s, unmoved 17.6s, 1 car)
where: node 3 (street 49→3)
why  : IGNORED GREEN — stopped at a light 18s (≥1 cycles) with NO other constraint ever seen: a governor bug, or the light never turned (cross-check light_watchdog.md)
  1832 POOR_CAR  spawn 51→49 @(320,33,109) head NE
     route 51→49→3→58→7→…(15 more)→30  →exit 30
     now  at node 3, 0.0 m/s, unmoved 17.6s, waits→
     gov  state=STOPPED target=0.0 gap=5.13 ray=0.0
     diag (no blocker)

## Stuck head 3  (t=+91s, unmoved 19.6s, 1 car)
where: node 120 (street 119→120)
why  : IGNORED GREEN — stopped at a light 20s (≥1 cycles) with NO other constraint ever seen: a governor bug, or the light never turned (cross-check light_watchdog.md)
  2655 POOR_CAR  spawn 119→120 @(60,4,491) head NE
     route 119→120→93→94→92→…(2 more)→30  →exit 30
     now  at node 120, 0.0 m/s, unmoved 19.6s, waits→
     gov  state=STOPPED target=0.0 gap=5.11 ray=0.0
     diag (no blocker)

## Stuck head 4  (t=+91s, unmoved 17.6s, 1 car)
where: node 54 (street 2→54)
why  : IGNORED GREEN — stopped at a light 18s (≥1 cycles) with NO other constraint ever seen: a governor bug, or the light never turned (cross-check light_watchdog.md)
  7618 POOR_CAR  spawn 47→2 @(216,27,199) head W
     route 47→2→54→55→52  →exit 52
     now  at node 54, 0.0 m/s, unmoved 17.6s, waits→
     gov  state=STOPPED target=0.0 gap=5.11 ray=0.0
     diag (no blocker)

## Stuck head 5  (t=+91s, unmoved 19.6s, 1 car)
where: node 47 (street 74→47)
why  : IGNORED GREEN — stopped at a light 20s (≥1 cycles) with NO other constraint ever seen: a governor bug, or the light never turned (cross-check light_watchdog.md)
  6514 POOR_CAR  spawn 70→74 @(250,16,298) head W
     route 70→74→47→51→50→…(45 more)→129  →exit 129
     now  at node 47, 0.0 m/s, unmoved 19.6s, waits→
     gov  state=STOPPED target=0.0 gap=5.13 ray=0.0
     diag (no blocker)

## Stuck head 6  (t=+91s, unmoved 17.6s, 1 car)
where: node 51 (street 48→51)
why  : IGNORED GREEN — stopped at a light 18s (≥1 cycles) with NO other constraint ever seen: a governor bug, or the light never turned (cross-check light_watchdog.md)
  2913 POOR_CAR  spawn 1→48 @(342,4,207) head NE
     route 1→48→51→50→55→53  →exit 53
     now  at node 51, 0.0 m/s, unmoved 17.6s, waits→
     gov  state=STOPPED target=0.0 gap=5.13 ray=0.0
     diag (no blocker)

## Stuck head 7  (t=+97s, unmoved 18.9s, 1 car)
where: node 47 (street 51→47)
why  : NO CONSTRAINT — stopped with nothing blocking it (governor bug)
  9554 UTILITY_TRUCK  spawn 51→47 @(275,30,155) head SW
     route 51→47→74→72→94→…(2 more)→119  →exit 119
     now  at node 47, 2.1 m/s, unmoved 18.9s, waits→
     gov  state=CRUISING target=3.2 gap=inf ray=5.6
     diag (no blocker)

## Stuck head 8  (t=+97s, unmoved 20.4s, 1 car)
where: node 1 (street 70→1)
why  : NO CONSTRAINT — stopped with nothing blocking it (governor bug)
  9993 POOR_CAR  spawn 74→70 @(230,26,299) head E
     route 74→70→1→47→74→…(39 more)→34  →exit 34
     now  at node 1, 2.1 m/s, unmoved 20.4s, waits→
     gov  state=CRUISING target=8.1 gap=inf ray=5.6
     diag (no blocker)

## Stuck head 9  (t=+97s, unmoved 17.2s, 1 car)
where: node 94 (street 72→94)
why  : NO CONSTRAINT — stopped with nothing blocking it (governor bug)
  5305 MOTORCYCLE  spawn 74→72 @(213,0,314) head S
     route 74→72→94→89→91→…(19 more)→13  →exit 13
     now  at node 94, 2.1 m/s, unmoved 17.2s, waits→
     gov  state=CRUISING target=15.4 gap=inf ray=5.6
     diag (no blocker)

## Stuck head 10  (t=+97s, unmoved 18.9s, 1 car)
where: node 94 (street 72→94)
why  : NO CONSTRAINT — stopped with nothing blocking it (governor bug)
  _511 MOTORCYCLE  spawn 74→72 @(215,6,304) head S
     route 74→72→94→89→10→…(20 more)→131  →exit 131
     now  at node 94, 1.4 m/s, unmoved 18.9s, waits→
     gov  state=BRAKING target=0.0 gap=4.86 ray=5.6
     diag (no blocker)

## Stuck head 11  (t=+97s, unmoved 21.9s, 1 car)
where: node 51 (street 48→51)
why  : NO CONSTRAINT — stopped with nothing blocking it (governor bug)
  3089 POOR_CAR  spawn 3→48 @(378,7,147) head SW
     route 3→48→51→47→2→…(7 more)→23  →exit 23
     now  at node 51, 2.1 m/s, unmoved 21.9s, waits→
     gov  state=CRUISING target=7.6 gap=inf ray=5.6
     diag (no blocker)

## Stuck head 12  (t=+97s, unmoved 25.6s, 1 car)
where: node 69 (street 10→69)
why  : NO CONSTRAINT — stopped with nothing blocking it (governor bug)
  3887 POOR_CAR  spawn 70→10 @(261,31,348) head S
     route 70→10→69→9→68→…(11 more)→119  →exit 119
     now  at node 69, 2.1 m/s, unmoved 25.6s, waits→
     gov  state=CRUISING target=7.9 gap=inf ray=5.6
     diag (no blocker)

## Stuck head 13  (t=+398s, unmoved 15.5s, 1 car)
where: node 70 (street 10→70)
why  : LIGHT QUEUE NOT DRAINING — hasn't moved in 16s (≥1 light cycles); during green it was blocked by ghost:Car_35807_1830, so the real root is downstream (spillback)
  4699 RICH_CAR  spawn 58→7 @(503,0,188) head SE
     route 58→7→57→6→68→…(10 more)→5  →exit 5
     now  at node 70, 0.0 m/s, unmoved 15.5s, waits→
     gov  state=STOPPED target=0.0 gap=3.00 ray=0.0
     diag (no blocker)

## Stuck head 14  (t=+518s, unmoved 15.4s, 1 car)
where: node 77 (street 76→77)
why  : LIGHT QUEUE NOT DRAINING — hasn't moved in 15s (≥1 light cycles); during green it was blocked by body:Car_43115_9510, so the real root is downstream (spillback)
  4100 POOR_CAR  spawn 1→70 @(295,20,272) head SW
     route 1→70→71→68→9→…(15 more)→13  →exit 13
     now  at node 77, 0.0 m/s, unmoved 15.4s, waits→
     gov  state=STOPPED target=0.0 gap=5.48 ray=0.0
     diag (no blocker)

## Stuck head 15  (t=+842s, unmoved 61.1s, 1 car)
where: node 9 (street 76→9)
why  : LIGHT QUEUE NOT DRAINING — hasn't moved in 61s (≥6 light cycles); during green it was blocked by body:Car_42464_107, so the real root is downstream (spillback)
  8311 POOR_CAR  spawn 89→17 @(234,4,494) head S
     route 89→17→92→94→89→…(13 more)→119  →exit 119
     now  at node 9, 0.0 m/s, unmoved 61.1s, waits→
     gov  state=STOPPED target=0.0 gap=3.09 ray=0.0
     diag (no blocker)

## Stuck head 16  (t=+859s, unmoved 15.0s, 1 car)
where: node 89 (street 91→89)
why  : LIGHT QUEUE NOT DRAINING — hasn't moved in 15s (≥1 light cycles); during green it was blocked by body:Car_690238_7382, so the real root is downstream (spillback)
  5916 RICH_CAR  spawn 57→67 @(487,1,302) head SE
     route 57→67→66→77→76→…(8 more)→0  →exit 0
     now  at node 89, 0.0 m/s, unmoved 15.0s, waits→
     gov  state=STOPPED target=0.0 gap=3.78 ray=0.0
     diag (no blocker)

## Stuck head 17  (t=+878s, unmoved 20.8s, 1 car)
where: node 9 (street 68→9)
why  : LIGHT QUEUE NOT DRAINING — hasn't moved in 21s (≥2 light cycles); during green it was blocked by body:Car_247634_8311, so the real root is downstream (spillback)
  3473 POOR_CAR  spawn 120→93 @(110,11,454) head NE
     route 120→93→94→72→74→…(10 more)→119  →exit 119
     now  at node 9, 0.0 m/s, unmoved 20.8s, waits→
     gov  state=STOPPED target=0.0 gap=5.10 ray=0.0
     diag (no blocker)

## Stuck head 18  (t=+932s, unmoved 20.2s, 1 car)
where: node 8 (street 83→8)
why  : LIGHT QUEUE NOT DRAINING — hasn't moved in 20s (≥2 light cycles); during green it was blocked by ghost:Car_883252_3401, so the real root is downstream (spillback)
  3088 TAXI  spawn 83→8 @(604,11,375) head NW
     route 83→8→64→84→82→…(6 more)→13  →exit 13
     now  at node 8, 0.0 m/s, unmoved 20.2s, waits→
     gov  state=STOPPED target=0.0 gap=5.11 ray=0.0
     diag (no blocker)

## Deadlock 19  (t=+1563s, unmoved 28.1s, 2 cars)
where: node 7 (all cars entering it)
kind : ISOLATED (all at one node) — should be impossible; a rule regression
type : ONCOMING ~179°   apart 7.0m
why  : mutual block — each waits on the other (see per-car diag: body vs ghost)
  _412 TAXI  spawn 61→7 @(581,3,185) head SW
     route 61→7→80→14→82→…(7 more)→85  →exit 85
     now  at node 7, 0.0 m/s, unmoved 28.1s, waits→1634
     gov  state=STOPPED target=0.0 gap=3.00 ray=0.0
     diag ghost=false  blocker ahead(along +6.9)  d 7.0/r_sum 2.2 apart  same_dir=false
  1634 MOTORCYCLE  spawn 117→143 @(237,0,590) head E
     route 117→143→142→19→75→…(9 more)→161  →exit 161
     now  at node 7, 0.0 m/s, unmoved 9.2s, waits→_412
     gov  state=STOPPED target=0.0 gap=3.00 ray=0.0
     diag ghost=false  blocker ahead(along +6.9)  d 7.0/r_sum 2.2 apart  same_dir=false
