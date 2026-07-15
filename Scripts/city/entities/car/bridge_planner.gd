# BridgePlanner.gd — plans a car's vertical altitude profile over bridges.
#
# Bridges are static and fully known when a path is created, so instead of
# probing them reactively the planner computes, once per path segment, the
# exact arc intervals where the curve crosses a bridge's skewed box (the same
# corner/height math the renderer uses — one source of truth) and emits a
# **knot polyline** for PathController's profile layer: a short list of
# (arc, vertical offset) points with smoothstep easing between them.
#
# The rules are few and absolute:
#   1. Cars dodge UP or DOWN — whichever is the smaller move and stays clear.
#      A conflict means the path is inside a bridge's blocked band; the car
#      clears over the top or ducks under the bottom. The direction is decided
#      per fused GROUP (never per bridge, or the path would wiggle): the cheaper
#      feasible option wins, where "down" is feasible only if it stays within
#      MAX_DUCK of baseline and its ducked segment clips no other band. Up is
#      always available (open sky) and is the fallback; down is the shortcut
#      when the car already flies low, near a bridge's underside.
#   2. The slope is sacred and ramps STRETCH: every ramp fills its available
#      runway up to MAX_RAMP — CLIMB_SLOPE is the worst allowed, not the norm.
#      When a deadline is tight, holds and margins are eaten before a ramp
#      ever approaches the slope limit; below it, nothing may go.
#   3. One curve beats many, and when in doubt stay up: crossings that
#      (almost) touch fuse; crossings too close to descend between share one
#      level (the max). The car returns to baseline only when a COMFORTABLE
#      round trip fits, and a descent is only emitted if it completes before
#      the re-plan boundary — otherwise it holds and lets the next plan
#      (which sees a full street further) schedule it.
#   4. Ramps stay out of the queue zone before a street's traffic light (a
#      stopped car is never mid-tilt); the intersection's bezier turn is
#      preferred ramp space for climbs.
#   5. The plan is built against the *base* path, then re-scanned along the
#      path actually FLOWN; anything the offset path would hit (a climb ramp
#      or held plateau rising into a band the base cleared) becomes a new
#      crossing and the plan is rebuilt. One principle, iterated to a fixed
#      point — no separate repair pass, no special cases.
#
# All functions are static; the planner holds no state.
extends RefCounted
class_name BridgePlanner

const SAMPLE_STEP: float = 2.0        # max arc step when scanning the curve
const CLIMB_SLOPE: float = 0.22       # WORST allowed rise/run (~12.5 deg) — ramps stretch softer
const MIN_RAMP: float = 5.0           # minimum curve distance
const MAX_RAMP: float = 50.0          # maximum curve distance — ramps stretch toward this
const HOLD_AFTER: float = 8.0         # arc held at level past a crossing
const ARC_MARGIN: float = 3.0         # crossing inflation along the path
const RETURN_SLACK: float = 6.0       # extra gap required to bother returning to 0
const FUSE_GAP: float = 8.0           # crossings closer than this become one
const STOP_ZONE: float = 15.0         # queue arc before a street end kept ramp-free
const REPLAN_MARGIN: float = 4.0      # descents must complete this far before the re-plan boundary
const CLEAR_MARGIN: float = 0.25      # levels sit strictly clear of band edges, never exactly on them
const MAX_PLAN_ITERS: int = 8         # flown-path replan rounds before giving up
const MAX_DUCK: float = 15.0          # deepest a car will drop below baseline to pass UNDER a bridge

# ============================================================================
# PUBLIC API
# ============================================================================

## The whole-route Y-profile, computed once at spawn over the immutable curve.
## Every bridge on the route is gathered up front; the profile clears them all
## with bounded slope and can hold altitude across intersections. Zones and
## re-plan boundaries are disabled (INF) — there is no per-segment replanning.
static func plan_route(pc: PathController) -> PackedVector2Array:
	var car := pc.car_owner
	if car == null or car.generator == null or pc.curve == null:
		return PackedVector2Array()
	var geos := _collect_geos(pc, car)
	if geos.is_empty():
		return PackedVector2Array()
	var v_margin: float = car.height * 0.5 + car.dodge_clearance
	return _plan_knots(pc, 0.0, 0.0, geos, v_margin, INF, INF, INF)

## Shared with spawning: true if `point` sits inside any bridge box of the
## given lane (inflated by `v_margin` vertically and `xz_margin` in the
## footprint plane), so cars never materialize inside — or too close ahead
## of — a slab, now that bridges have no registry claims.
static func point_blocked(generator, face_idx: int, edge_idx: int,
		point: Vector3, v_margin: float, xz_margin: float = 0.0) -> bool:
	for placed in generator.get_bridges_for_lane(face_idx, edge_idx):
		var geo := _bridge_geometry(placed)
		var band := blocked_band(geo, point, v_margin, xz_margin)
		if band != Vector2.INF and point.y >= band.x and point.y <= band.y:
			return true
	return false

## The blocked vertical band [low, high] of one bridge geometry at `point`'s
## XZ position, inflated by `v_margin` vertically and `xz_margin` in the
## footprint plane (the car's half-width, so its sides count, not just its
## center); Vector2.INF when outside the footprint. Under the arc opening
## (mid-span) the band starts at the slab; near the facades it extends down to
## the arc bottom. Public because probe corridors (CollisionAvoidance) test
## against it too.
static func blocked_band(geo: Dictionary, point: Vector3, v_margin: float,
		xz_margin: float = 0.0) -> Vector2:
	var p := Vector2(point.x, point.z)
	# Invert the bilinear footprint patch by alternating projections: t along
	# the facade direction, s across the span. Two rounds are ample for the
	# mild skew these quads have.
	var m1: Vector2 = (geo["c_a1"] + geo["c_b1"]) * 0.5
	var m2: Vector2 = (geo["c_a2"] + geo["c_b2"]) * 0.5
	var t := _proj_fraction(p, m1, m2)
	var s := 0.5
	for _i in range(2):
		var a_t: Vector2 = geo["c_a1"].lerp(geo["c_a2"], t)
		var b_t: Vector2 = geo["c_b1"].lerp(geo["c_b2"], t)
		s = _proj_fraction(p, a_t, b_t)
		var e1: Vector2 = geo["c_a1"].lerp(geo["c_b1"], clampf(s, 0.0, 1.0))
		var e2: Vector2 = geo["c_a2"].lerp(geo["c_b2"], clampf(s, 0.0, 1.0))
		t = _proj_fraction(p, e1, e2)

	var m_t: float = xz_margin / maxf(geo["t_len"], 0.1)
	if t < geo["t_start"] - m_t or t > geo["t_end"] + m_t or s < 0.0 or s > 1.0:
		return Vector2.INF
	var low: float = geo["h_bot"]
	if geo["arc_frac"] > 0.0:
		var m_s: float = xz_margin / maxf(geo["span"], 0.1)
		if s < geo["arc_frac"] + m_s or s > 1.0 - geo["arc_frac"] - m_s:
			low = geo["h_arc_bot"]
	return Vector2(low - v_margin, geo["h_top"] + v_margin)

# ============================================================================
# GEOMETRY (exact skewed-box data, mirroring the renderer)
# ============================================================================

# Gather every bridge on the route and tag each with its ANALYTIC crossing:
# the bridge sits on one straight route segment, so projecting its footprint
# corners onto that segment line gives the crossing arc and exact along-path
# span directly — no per-sample geometry scan (which was O(route × bridges) and
# unplayable on bridge-dense arterials). `route_volumes[i]` aligns with
# `segments[i]` and curve points 2i / 2i+1.
static func _collect_geos(pc: PathController, car) -> Array:
	var geos: Array = []
	var v_margin: float = car.height * 0.5 + car.dodge_clearance
	var arc_pad: float = car.depth * 0.5 + ARC_MARGIN
	for i in range(pc.route_volumes.size()):
		if i >= pc.segments.size():
			break
		var vol: Dictionary = pc.route_volumes[i]
		if not vol.has("face_idx") or not vol.has("edge_idx"):
			continue
		var seg: Dictionary = pc.segments[i]
		var s: Vector3 = pc.curve.get_point_position(2 * i)
		var e: Vector3 = pc.curve.get_point_position(2 * i + 1)
		var s2 := Vector2(s.x, s.z)
		var seg_vec := Vector2(e.x, e.z) - s2
		var seg_len := seg_vec.length()
		var dir := seg_vec / seg_len if seg_len > 1e-6 else Vector2(1.0, 0.0)
		for placed in car.generator.get_bridges_for_lane(vol["face_idx"], vol["edge_idx"]):
			var geo := _bridge_geometry(placed)
			# EXACT along-path footprint span: project the four footprint corners
			# onto the drive direction and take the extent. This replaces a
			# 0.75×t_len fudge that under-covered skewed crossings, so the ramp
			# was scheduled to finish at the estimated edge while the car met the
			# real slab a fraction earlier, still mid-climb — the undershoot clips.
			var lo := INF
			var hi := -INF
			for c in [geo["c_a1"], geo["c_a2"], geo["c_b1"], geo["c_b2"]]:
				var pr: float = (c - s2).dot(dir)
				lo = minf(lo, pr)
				hi = maxf(hi, pr)
			var cross_arc: float = seg["arc_start"] + clampf((lo + hi) * 0.5, 0.0, seg_len)
			# Half the true extent, plus the car's body reach so the ramp finishes
			# before the nose enters the slab.
			var half: float = (hi - lo) * 0.5 + arc_pad
			geo["cross_arc"] = cross_arc
			geo["cross_half"] = half
			geo["base_y"] = pc.curve.sample_baked(cross_arc).y
			# Conservative full band (arc legs included): always clear to the top.
			geo["band_lo"] = geo["h_arc_bot"] - v_margin
			geo["band_hi"] = geo["h_top"] + v_margin
			geos.append(geo)
	return geos

# Corners are facade-line lerps, heights are building-cell counts times cell
# height — the same math as city.gd _draw_bridge.
static func _bridge_geometry(placed: Dictionary) -> Dictionary:
	var bridge = placed["bridge"]
	var cell_height: float = placed["cell_height"]
	var cells: int = placed["facade_building_cells"]
	var h_bot: float = (placed["floor_idx"] * placed["cells_per_floor"]
		- bridge.base_height) * cell_height
	var h_top: float = h_bot + (bridge.base_height + bridge.pathway_height
		+ bridge.railing_height) * cell_height

	var a_mid: Vector2 = placed["c_a1"].lerp(placed["c_a2"], 0.5)
	var b_mid: Vector2 = placed["c_b1"].lerp(placed["c_b2"], 0.5)
	var span := a_mid.distance_to(b_mid)
	var t_len: float = (placed["c_a1"].distance_to(placed["c_a2"])
		+ placed["c_b1"].distance_to(placed["c_b2"])) * 0.5
	# Footprint centre in XZ — projected onto the route segment to find the
	# crossing arc analytically (no per-sample scan).
	var center: Vector2 = (placed["c_a1"] + placed["c_a2"] + placed["c_b1"] + placed["c_b2"]) * 0.25
	var geo := {
		"c_a1": placed["c_a1"], "c_a2": placed["c_a2"],
		"c_b1": placed["c_b1"], "c_b2": placed["c_b2"],
		"t_start": float(placed["cell_start"]) / cells,
		"t_end": float(placed["cell_end"] + 1) / cells,
		"h_bot": h_bot, "h_top": h_top,
		"h_arc_bot": h_bot, "arc_frac": 0.0,
		"span": span, "t_len": t_len,
		"center": center,  # footprint centre, projected onto the segment line
	}
	if bridge.arc_height > 0 and bridge.arc_length > 0:
		geo["h_arc_bot"] = h_bot - bridge.arc_height * cell_height
		geo["arc_frac"] = clampf(bridge.arc_length * cell_height / span, 0.0, 0.45) \
			if span > 0.0 else 0.0
	return geo

static func _proj_fraction(p: Vector2, a: Vector2, b: Vector2) -> float:
	var d := b - a
	var len_sq := d.length_squared()
	return (p - a).dot(d) / len_sq if len_sq > 1e-8 else 0.0


# ============================================================================
# PLANNING PIPELINE (scan -> fuse -> unify -> build; iterate on the FLOWN path)
# ============================================================================

# The scan detects where the *base* path conflicts, but the car flies the
# *offset* path — a climb ramp or a held plateau can carry it up into a band
# the base path passed safely under. So after building the knots we re-scan
# the path actually flown; any conflict becomes a new crossing (cleared over
# its top, like every other) and we rebuild. One principle handles ramp-clips,
# held-plateau clips and near-band arc legs alike, and since we only ever raise
# levels (always up, bounded by the tallest bridge in range) it converges in a
# couple of rounds.
static func _plan_knots(pc: PathController, from_arc: float, start_y: float,
		geos: Array, v_margin: float, zone_a: float, zone_b: float,
		replan_boundary: float) -> PackedVector2Array:
	var crossings := _scan_conflicts(pc, from_arc, geos, v_margin, PackedVector2Array())
	var knots := PackedVector2Array()
	for _iter in range(MAX_PLAN_ITERS):
		_fuse_overlapping(crossings)
		var levels := _choose_levels(crossings, geos)
		knots = _build_knots(crossings, levels, from_arc, start_y, zone_a, zone_b, replan_boundary)
		var added := false
		for e in _scan_conflicts(pc, from_arc, geos, v_margin, knots):
			if not _already_cleared(crossings, e):
				crossings.append(e)
				added = true
		if not added:
			break
		crossings.sort_custom(func(a, b): return a["start"] < b["start"])
	return knots

# A promoted (up-only) conflict is redundant only if an existing crossing that
# is actually going UP already spans it and climbs at least as high. A DUCKED
# crossing (negative level) does NOT clear an up-conflict — so a duck that dips
# into another band still gets promoted, and next round its fused group (now
# holding a non-duckable member) is forced up. This keeps the escalation
# monotonic-up and terminating while never masking a real clip.
static func _already_cleared(crossings: Array, e: Dictionary) -> bool:
	for c in crossings:
		var lvl: float = c.get("level", 0.0)
		if lvl > 0.0 and lvl >= e["up_off"] - 0.01 \
				and c["start"] <= e["start"] + 0.01 and c["end"] >= e["end"] - 0.01:
			return true
	return false

# Analytic: for each bridge, test whether the flown path (base + `offset_knots`)
# at its crossing arc is inside its band. O(bridges) — a handful of ops each,
# no per-sample geometry scan. Returns the arc interval + climb for each hit.
static func _scan_conflicts(pc: PathController, from_arc: float,
		geos: Array, _v_margin: float, offset_knots: PackedVector2Array) -> Array:
	# Only the FIRST (base-path) scan lets a crossing be ducked. Conflicts found
	# on the flown path in later rounds (a ramp or held plateau clipping a band)
	# are always cleared UP — the monotonic direction that keeps the iteration
	# bounded and terminating (open sky above, floor below).
	var duckable := offset_knots.is_empty()
	var crossings: Array = []
	for geo in geos:
		var a: float = geo["cross_arc"]
		var half: float = geo["cross_half"]
		if a + half < from_arc:
			continue
		# The crossing is an INTERVAL, not a point: a climb ramp can graze the
		# band near the window's EDGES while its centre is clear (the shallow
		# 0-1m edge clips the reporter kept catching). Test the flown altitude
		# at both ends and the centre — knot offsets are smooth between knots,
		# so three samples bound the sweep. Still O(bridges).
		var conflict := false
		for arc in [maxf(a - half, from_arc), a, a + half]:
			var flown_y: float = geo["base_y"] + PathController.knot_offset(offset_knots, arc)
			if flown_y >= geo["band_lo"] and flown_y <= geo["band_hi"]:
				conflict = true
				break
		if conflict:
			crossings.append({
				"start": maxf(a - half, from_arc),
				"end": a + half,
				"up_off": geo["band_hi"] - geo["base_y"] + CLEAR_MARGIN,   # clear over the top (>0)
				"down_off": geo["band_lo"] - geo["base_y"] - CLEAR_MARGIN, # duck under the bottom (<0)
				"duckable": duckable,
			})
	crossings.sort_custom(func(x, y): return x["start"] < y["start"])
	return crossings

# Crossings that (almost) touch need one level clearing both — a transition
# between them would happen inside the bands. Wider gaps are handled by the
# knot builder's direct level-to-level transitions instead.
static func _fuse_overlapping(crossings: Array) -> void:
	var i := 0
	while i < crossings.size() - 1:
		var a: Dictionary = crossings[i]
		var b: Dictionary = crossings[i + 1]
		if b["start"] - a["end"] < FUSE_GAP:
			a["end"] = maxf(a["end"], b["end"])
			a["up_off"] = maxf(a["up_off"], b["up_off"])
			a["down_off"] = minf(a["down_off"], b["down_off"])  # duck below the deeper of the two
			a["duckable"] = a["duckable"] and b["duckable"]
			crossings.remove_at(i + 1)
		else:
			i += 1

# Assign each crossing a single SIGNED level, deciding direction per group.
# A group is a maximal run of crossings with no comfortable baseline return
# between them (they must share one level — you can't be up here and down there
# across a held span). Per group the cheaper feasible direction wins: UP clears
# above the tallest top and is always available; DOWN ducks below the deepest
# bottom, allowed only when the whole group is duckable, stays within MAX_DUCK,
# and the ducked segment clips no other bridge band. The chosen level is also
# stamped onto each crossing (for the up-only escalation guard).
static func _choose_levels(crossings: Array, geos: Array) -> Array:
	var n := crossings.size()
	var levels: Array = []
	levels.resize(n)
	var i := 0
	while i < n:
		var j := i
		while j + 1 < n and not _group_returns(crossings, j):
			j += 1
		# Group is crossings[i..j]: one direction, clearing every member.
		var up_level := 0.0
		var down_level := 0.0
		var all_duckable := true
		for k in range(i, j + 1):
			up_level = maxf(up_level, crossings[k]["up_off"])
			down_level = minf(down_level, crossings[k]["down_off"])
			if not crossings[k]["duckable"]:
				all_duckable = false
		var use_down: bool = all_duckable and absf(down_level) < up_level \
			and absf(down_level) <= MAX_DUCK \
			and _duck_clears(geos, crossings[i]["start"], crossings[j]["end"], down_level)
		var lvl: float = down_level if use_down else up_level
		for k in range(i, j + 1):
			levels[k] = lvl
			crossings[k]["level"] = lvl
		i = j + 1
	return levels

# Group boundary test, using the UP offsets (the largest possible level) as a
# conservative estimate: if even a full climb could round-trip to baseline in
# the gap, any lighter choice can too, so splitting the group is safe. Grouping
# only when up cannot return means those crossings would share a level anyway.
static func _group_returns(crossings: Array, j: int) -> bool:
	var gap: float = crossings[j + 1]["start"] - (crossings[j]["end"] + HOLD_AFTER)
	return gap >= _stretched(crossings[j]["up_off"]) + _stretched(crossings[j + 1]["up_off"]) + RETURN_SLACK

# True if a duck to `level` over [gstart, gend] leaves every bridge's band clear
# at its crossing arc. Members are cleared by construction (level is at or below
# their own duck target); this catches a NON-member slab the ducked path would
# drop into (e.g. a lower bridge under this one), so down is only taken when it
# is provably conflict-free and the iterative escalation stays up-only.
static func _duck_clears(geos: Array, gstart: float, gend: float, level: float) -> bool:
	for geo in geos:
		var a: float = geo["cross_arc"]
		if a < gstart or a > gend:
			continue
		var y: float = geo["base_y"] + level
		if y >= geo["band_lo"] and y <= geo["band_hi"]:
			return false
	return true

# Between crossings the car only comes back to baseline when a COMFORTABLE
# round trip fits the gap — measured with stretched ramps (twice as soft as
# the worst allowed slope), not minimum ones. When in doubt, stay up.
static func _returns_to_baseline(crossings: Array, levels: Array, i: int) -> bool:
	if absf(levels[i]) < 0.01:
		return true
	if i + 1 >= crossings.size():
		return true
	var gap: float = crossings[i + 1]["start"] - (crossings[i]["end"] + HOLD_AFTER)
	return gap >= _stretched(levels[i]) + _stretched(levels[i + 1]) + RETURN_SLACK

# Preferred (comfortable) ramp length for a level change: twice the slope
# minimum, capped at the maximum curve distance — but never below the slope
# minimum itself (very tall climbs legitimately exceed MAX_RAMP).
static func _stretched(delta: float) -> float:
	var minimum := maxf(absf(delta) / CLIMB_SLOPE, MIN_RAMP)
	return maxf(minf(minimum * 2.0, MAX_RAMP), minimum)

# ============================================================================
# KNOT CONSTRUCTION
# ============================================================================

static func _build_knots(crossings: Array, levels: Array, from_arc: float,
		start_y: float, zone_a: float, zone_b: float,
		replan_boundary: float) -> PackedVector2Array:
	var knots := PackedVector2Array()
	var end_limit := replan_boundary - REPLAN_MARGIN

	if crossings.is_empty():
		if absf(start_y) > 0.01:
			var min_down := maxf(absf(start_y) / CLIMB_SLOPE, MIN_RAMP)
			var dspan := _descend_span(from_arc, min_down, zone_a, zone_b, end_limit)
			if dspan.x >= 0.0:
				knots.append(Vector2(dspan.x, start_y))
				knots.append(Vector2(dspan.x + dspan.y, 0.0))
			else:
				knots.append(Vector2(from_arc, start_y))  # hold; the next plan descends
		return knots

	var prev_y := start_y
	var soft_from := from_arc   # earliest start honouring holds and margins
	var hard_from := from_arc   # absolute floor: previous transition/crossing end
	for i in range(crossings.size()):
		var c: Dictionary = crossings[i]
		var level: float = levels[i]
		if absf(level - prev_y) > 0.01:
			var min_ramp := maxf(absf(level - prev_y) / CLIMB_SLOPE, MIN_RAMP)
			var span := _place_ascend(c["start"], min_ramp, soft_from, hard_from, zone_a, zone_b)
			knots.append(Vector2(span.x, prev_y))
			knots.append(Vector2(span.x + span.y, level))
		prev_y = level
		hard_from = c["end"]
		if knots.size() > 0:
			hard_from = maxf(hard_from, knots[knots.size() - 1].x)
		soft_from = maxf(c["end"] + HOLD_AFTER, hard_from)
		if absf(prev_y) > 0.01 and _returns_to_baseline(crossings, levels, i):
			var min_down := maxf(absf(prev_y) / CLIMB_SLOPE, MIN_RAMP)
			# The descent may not eat the next crossing's comfortable run-up.
			var limit := end_limit
			if i + 1 < crossings.size():
				limit = minf(limit, crossings[i + 1]["start"] - _stretched(levels[i + 1]))
			var dspan := _descend_span(soft_from, min_down, zone_a, zone_b, limit)
			if dspan.x >= 0.0:
				knots.append(Vector2(dspan.x, prev_y))
				knots.append(Vector2(dspan.x + dspan.y, 0.0))
				prev_y = 0.0
				soft_from = dspan.x + dspan.y
				hard_from = soft_from
			# else: defer — hold the level; the next plan (which sees a full
			# street further) schedules the descent with complete knowledge.
	return knots

# A climb with a deadline (be at the target level by `target_arc`). Ramps
# STRETCH to fill their runway up to MAX_RAMP — the slope constant is the
# worst allowed, not the norm — and are never shortened below the slope
# minimum: when the comfortable start (`soft`, honouring holds) is too late,
# the hold is eaten down to the `hard` floor instead. Queue-zone overlaps
# prefer climbing just past the light, during the intersection's bezier turn.
# Returns (start_arc, ramp_len).
static func _place_ascend(target_arc: float, min_ramp: float, soft: float, hard: float,
		zone_a: float, zone_b: float) -> Vector2:
	# Stretch toward MAX_RAMP within the runway — but the slope minimum always
	# wins over the cap (very tall climbs legitimately need longer ramps).
	var ramp := maxf(minf(target_arc - soft, MAX_RAMP), min_ramp)
	var t0 := target_arc - ramp
	if t0 < soft:  # runway smaller than the slope minimum: eat the hold
		ramp = min_ramp
		t0 = maxf(target_arc - ramp, hard)
	if t0 + ramp <= zone_a or t0 >= zone_b:
		return Vector2(t0, ramp)
	# Late: climb after the light, in the turn, still meeting the deadline.
	var late_room := target_arc - maxf(zone_b, soft)
	if late_room >= min_ramp:
		var r := maxf(minf(late_room, MAX_RAMP), min_ramp)
		return Vector2(target_arc - r, r)
	# Early: finish before the queue zone.
	if zone_a - soft >= min_ramp:
		var r2 := maxf(minf(zone_a - soft, MAX_RAMP), min_ramp)
		return Vector2(zone_a - r2, r2)
	if zone_a - hard >= min_ramp:
		return Vector2(zone_a - min_ramp, min_ramp)
	# Squeezed: ramp through the zone (cosmetic) — never steeper than allowed.
	return Vector2(maxf(target_arc - min_ramp, hard), min_ramp)

# A descent (no deadline): stretched toward MAX_RAMP, kept out of the queue
# zone, and REQUIRED to complete before `end_limit` (the re-plan boundary and
# the next crossing's run-up). Returns (start_arc, ramp_len), or x = -1 to
# defer: hold the level and let the next plan schedule it.
static func _descend_span(earliest: float, min_ramp: float,
		zone_a: float, zone_b: float, end_limit: float) -> Vector2:
	# Before the queue zone (or past the whole street-end region already).
	var t0 := earliest
	var cap := end_limit
	if t0 < zone_b:
		cap = minf(cap, zone_a)
	if cap - t0 >= min_ramp:
		return Vector2(t0, maxf(minf(cap - t0, MAX_RAMP), min_ramp))
	# After the light: the turn and the next straight, before the boundary.
	t0 = maxf(earliest, zone_b)
	if end_limit - t0 >= min_ramp:
		return Vector2(t0, maxf(minf(end_limit - t0, MAX_RAMP), min_ramp))
	return Vector2(-1.0, 0.0)

