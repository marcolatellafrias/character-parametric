# TrafficClaimRegistry.gd
# Mathematical replacement for the physics-based car detection system.
# Anything that occupies traffic space (car bodies, broadcast corridors,
# traffic lights, future generic obstacles) publishes a Claim into a spatial
# hash. Cars query their future-path corridor against the hash with pure
# segment math — no Area3D, no PhysicsShapeQueryParameters3D.
#
# Dynamic claims (cars) are double-buffered: every frame the registry swaps
# buffers, cars publish into the write buffer and query the completed read
# buffer from the previous frame. All cars therefore see the same complete
# claim set regardless of processing order (multiplayer-determinism friendly).
extends Node
class_name TrafficClaimRegistry

enum ClaimType { CAR_BODY, CAR_BROADCAST, TRAFFIC_LIGHT, OBSTACLE }

@export var cell_size: float = 32.0

class Claim:
	var type: int = ClaimType.OBSTACLE
	var owner_car: Node3D = null
	# Capsule chain shape (car bodies, broadcasts, generic obstacles)
	var points: PackedVector3Array = PackedVector3Array()
	var radius: float = 0.0
	# Quad shape (traffic light planes)
	var quad_verts: PackedVector3Array = PackedVector3Array()
	var quad_normal: Vector3 = Vector3.ZERO
	var lane_id: String = ""
	var plane_node: Area3D = null
	# Bookkeeping
	var cells: Array[Vector3i] = []
	var stamp: int = -1

## Registered cars, iterated by the debug drawer.
var cars: Array[Node3D] = []

var _read_cells: Dictionary = {}
var _write_cells: Dictionary = {}
var _static_cells: Dictionary = {}
var _light_claims: Dictionary = {}   # TrafficPlane -> Claim
var _light_refs: Dictionary = {}     # TrafficPlane -> refcount (multiple instantiators)
var _query_stamp: int = 0
var _parity: int = 0
# Query scratch buffers, reused across calls (single-threaded access).
var _scratch_candidates: Array[Claim] = []
var _scratch_hits: Array[Dictionary] = []

func _ready() -> void:
	add_to_group("traffic_claim_registry")
	# Swap buffers before any car publishes or queries this frame.
	process_priority = -100

func _process(_delta: float) -> void:
	# While paused with no manual step, freeze both buffers so a later stepped
	# frame still queries the last complete claim set.
	if DebugController.is_paused and DebugController.manual_delta == 0.0:
		return
	var tmp = _read_cells
	_read_cells = _write_cells
	_write_cells = tmp
	_write_cells.clear()
	_parity = 1 - _parity

# ============================================================================
# REGISTRATION / PUBLISHING
# ============================================================================

func register_car(car: Node3D) -> void:
	if not cars.has(car):
		cars.append(car)

func unregister_car(car: Node3D) -> void:
	cars.erase(car)

## Claims are ping-ponged so the read buffer keeps last frame's geometry
## untouched while this frame's is written.
func create_claim_pair(type: int, owner_car: Node3D) -> Array:
	var pair := []
	for i in 2:
		var claim := Claim.new()
		claim.type = type
		claim.owner_car = owner_car
		pair.append(claim)
	return pair

func publish_capsule(pair: Array, points: PackedVector3Array, radius: float) -> void:
	if points.size() < 2:
		return
	var claim: Claim = pair[_parity]
	# Copy into the claim's own buffer (packed arrays are shared by reference)
	# so callers can reuse scratch arrays without corrupting the read buffer.
	claim.points.clear()
	claim.points.append_array(points)
	claim.radius = radius
	_insert(_write_cells, claim, _capsule_aabb(claim.points, radius), false)

func register_traffic_light(plane: TrafficPlane) -> void:
	var count: int = _light_refs.get(plane, 0)
	_light_refs[plane] = count + 1
	if count > 0:
		return
	var claim := Claim.new()
	claim.type = ClaimType.TRAFFIC_LIGHT
	claim.plane_node = plane
	claim.lane_id = plane.get_meta("lane_id", "")
	var verts: Array = plane.get_end_vertices()
	claim.quad_verts = PackedVector3Array(verts)
	claim.quad_normal = (verts[1] - verts[0]).cross(verts[3] - verts[0]).normalized()
	_insert(_static_cells, claim, _quad_aabb(claim.quad_verts), true)
	_light_claims[plane] = claim

func unregister_traffic_light(plane: TrafficPlane) -> void:
	var count: int = _light_refs.get(plane, 0) - 1
	if count > 0:
		_light_refs[plane] = count
		return
	_light_refs.erase(plane)
	var claim: Claim = _light_claims.get(plane)
	if claim:
		_remove_static(claim)
		_light_claims.erase(plane)

## Generic static obstacle (debris, construction zone, ...). Cars adapt to it
## exactly like they do to other cars' bodies.
func register_obstacle(points: PackedVector3Array, radius: float) -> Claim:
	var claim := Claim.new()
	claim.type = ClaimType.OBSTACLE
	claim.points = points
	claim.radius = radius
	_insert(_static_cells, claim, _capsule_aabb(points, radius), true)
	return claim

func unregister_obstacle(claim: Claim) -> void:
	_remove_static(claim)

# ============================================================================
# QUERIES
# ============================================================================

## Query a future-path corridor (polyline capsule) against all claims.
## `arcs[i]` is the distance from the corridor start to `points[i]`.
## Returns hits: { claim, my_arc, other_arc, point } where my_arc is the
## distance along the corridor at which contact happens and other_arc the
## distance along the claim's own polyline (0 for quads/static shapes).
## The returned array is a reused buffer, only valid until the next query.
func query_corridor(points: PackedVector3Array, arcs: PackedFloat32Array,
					radius: float, exclude_car: Node3D) -> Array[Dictionary]:
	var hits := _scratch_hits
	hits.clear()
	if points.size() < 2:
		return hits
	var aabb := _capsule_aabb(points, radius)
	var candidates := _scratch_candidates
	candidates.clear()
	_query_stamp += 1
	_gather(_read_cells, aabb, candidates)
	_gather(_static_cells, aabb, candidates)
	for claim in candidates:
		# Note: a freed owner compares equal to null in GDScript, so validity
		# must be decided by claim type, not by a null check on the owner.
		if claim.type == ClaimType.CAR_BODY or claim.type == ClaimType.CAR_BROADCAST:
			if not is_instance_valid(claim.owner_car):
				continue
			if claim.owner_car == exclude_car:
				continue
		var hit := _test_claim(points, arcs, radius, claim)
		if not hit.is_empty():
			hits.append(hit)
	return hits

## Spawn check: is this capsule free of car bodies/broadcasts and obstacles?
## Checks both buffers so cars spawned earlier in the same tick are seen.
func is_capsule_free(a: Vector3, b: Vector3, radius: float) -> bool:
	var aabb := AABB(a, Vector3.ZERO).expand(b).grow(radius)
	var candidates := _scratch_candidates
	candidates.clear()
	_query_stamp += 1
	_gather(_read_cells, aabb, candidates)
	_gather(_write_cells, aabb, candidates)
	_gather(_static_cells, aabb, candidates)
	for claim in candidates:
		if claim.type == ClaimType.TRAFFIC_LIGHT:
			continue
		if claim.type != ClaimType.OBSTACLE and not is_instance_valid(claim.owner_car):
			continue
		var r_sum := radius + claim.radius
		var r_sum_sq := r_sum * r_sum
		for j in range(claim.points.size() - 1):
			var res := _seg_seg(a, b, claim.points[j], claim.points[j + 1])
			if res.z <= r_sum_sq:
				return false
	return true

# ============================================================================
# INTERNALS
# ============================================================================

func _insert(cells: Dictionary, claim: Claim, aabb: AABB, remember_cells: bool) -> void:
	var min_c := Vector3i((aabb.position / cell_size).floor())
	var max_c := Vector3i((aabb.end / cell_size).floor())
	for x in range(min_c.x, max_c.x + 1):
		for y in range(min_c.y, max_c.y + 1):
			for z in range(min_c.z, max_c.z + 1):
				var key := Vector3i(x, y, z)
				var arr = cells.get(key)
				if arr == null:
					arr = []
					cells[key] = arr
				arr.append(claim)
				if remember_cells:
					claim.cells.append(key)

func _remove_static(claim: Claim) -> void:
	for key in claim.cells:
		var arr = _static_cells.get(key)
		if arr:
			arr.erase(claim)
			if arr.is_empty():
				_static_cells.erase(key)
	claim.cells.clear()

func _gather(cells: Dictionary, aabb: AABB, out: Array[Claim]) -> void:
	var min_c := Vector3i((aabb.position / cell_size).floor())
	var max_c := Vector3i((aabb.end / cell_size).floor())
	for x in range(min_c.x, max_c.x + 1):
		for y in range(min_c.y, max_c.y + 1):
			for z in range(min_c.z, max_c.z + 1):
				var arr = cells.get(Vector3i(x, y, z))
				if arr == null:
					continue
				for claim in arr:
					if claim.stamp == _query_stamp:
						continue
					claim.stamp = _query_stamp
					out.append(claim)

func _test_claim(points: PackedVector3Array, arcs: PackedFloat32Array,
				 radius: float, claim: Claim) -> Dictionary:
	if claim.type == ClaimType.TRAFFIC_LIGHT:
		return _test_quad(points, arcs, claim)
	return _test_capsule_chain(points, arcs, radius, claim)

func _test_capsule_chain(points: PackedVector3Array, arcs: PackedFloat32Array,
						 radius: float, claim: Claim) -> Dictionary:
	var r_sum := radius + claim.radius
	var r_sum_sq := r_sum * r_sum
	var other := claim.points
	var best_my_arc := INF
	var best_other_arc := 0.0
	var best_point := Vector3.ZERO
	for i in range(points.size() - 1):
		var a1 := points[i]
		var b1 := points[i + 1]
		var seg_len := arcs[i + 1] - arcs[i]
		var other_arc_accum := 0.0
		var found := false
		for j in range(other.size() - 1):
			var a2 := other[j]
			var b2 := other[j + 1]
			var res := _seg_seg(a1, b1, a2, b2)
			if res.z <= r_sum_sq:
				var my_arc := arcs[i] + res.x * seg_len
				if my_arc < best_my_arc:
					best_my_arc = my_arc
					best_other_arc = other_arc_accum + res.y * a2.distance_to(b2)
					best_point = a1.lerp(b1, res.x)
				found = true
			other_arc_accum += a2.distance_to(b2)
		if found:
			# Corridor segments are ordered; nothing later can be closer.
			break
	if best_my_arc == INF:
		return {}
	return {"claim": claim, "my_arc": best_my_arc, "other_arc": best_other_arc, "point": best_point}

func _test_quad(points: PackedVector3Array, arcs: PackedFloat32Array, claim: Claim) -> Dictionary:
	for i in range(points.size() - 1):
		var t := _segment_quad_t(points[i], points[i + 1], claim.quad_verts, claim.quad_normal)
		if t >= 0.0:
			var my_arc: float = arcs[i] + t * (arcs[i + 1] - arcs[i])
			return {"claim": claim, "my_arc": my_arc, "other_arc": 0.0, "point": points[i].lerp(points[i + 1], t)}
	return {}

func _capsule_aabb(points: PackedVector3Array, radius: float) -> AABB:
	var aabb := AABB(points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		aabb = aabb.expand(points[i])
	return aabb.grow(radius)

func _quad_aabb(verts: PackedVector3Array) -> AABB:
	var aabb := AABB(verts[0], Vector3.ZERO)
	for i in range(1, verts.size()):
		aabb = aabb.expand(verts[i])
	return aabb.grow(1.0)

# ============================================================================
# GEOMETRY
# ============================================================================

## Closest approach between segments [p1,q1] and [p2,q2].
## Returns Vector3(s, t, dist_sq) with s/t the segment parameters in [0,1].
static func _seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Vector3:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-8 and e <= 1e-8:
		return Vector3(0.0, 0.0, r.dot(r))
	if a <= 1e-8:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-8:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom > 1e-8:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	var c1 := p1 + d1 * s
	var c2 := p2 + d2 * t
	return Vector3(s, t, c1.distance_squared_to(c2))

## Where segment [a,b] crosses a planar convex quad (perimeter-ordered verts,
## normal derived from that winding). Returns t in [0,1], or -1 for no hit.
static func _segment_quad_t(a: Vector3, b: Vector3, verts: PackedVector3Array, normal: Vector3) -> float:
	var ab := b - a
	var denom := normal.dot(ab)
	if absf(denom) < 1e-6:
		return -1.0
	var t := normal.dot(verts[0] - a) / denom
	if t < 0.0 or t > 1.0:
		return -1.0
	var p := a + ab * t
	for i in range(4):
		var v0 := verts[i]
		var v1 := verts[(i + 1) % 4]
		if (v1 - v0).cross(p - v0).dot(normal) < -0.001:
			return -1.0
	return t
