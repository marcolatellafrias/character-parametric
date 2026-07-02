# PathController.gd — node-free path following.
# Holds a Curve3D resource directly instead of Path3D/PathFollow3D/Timer nodes:
# progress is a float advanced by the car, transforms are sampled from the
# baked curve, and transition/end checks happen inline in advance().
extends RefCounted
class_name PathController

signal segment_transition_completed(old_volume_id: String, new_volume_id: String)
signal path_ended

# Cars don't need the default 0.2u bake precision; a coarser bake makes
# sampling, length and rotation lookups an order of magnitude cheaper.
const BAKE_INTERVAL: float = 2.0

var curve: Curve3D
var progress: float = 0.0
var transition_point: float = -1.0
var is_transitioning: bool = false

# Dodge offset layer: a world-space offset applied on top of the base curve,
# shaped by a smoothstep envelope over arc distance (ease out -> hold -> ease
# in). The base curve is never modified, so segment transitions and
# continuations are untouched and the car always returns to its ideal path.
# `dodge_merge_arc == INF` means the hold phase is open-ended: the merge point
# is decided later by CollisionAvoidance (condition-based exit).
var dodge_active: bool = false
var dodge_dir: Vector3 = Vector3.ZERO
var dodge_magnitude: float = 0.0
var dodge_start_arc: float = 0.0
var dodge_ramp_len: float = 6.0
var dodge_merge_arc: float = INF

var first_segment_volume: Dictionary = {}
var second_segment_volume: Dictionary = {}

var world_node: Node3D
var car_owner: FlyingCar

var _length: float = 0.0
var _ended: bool = false

# Debug
var path_debug_mesh: MeshInstance3D
var continuation_debug_meshes: Array[MeshInstance3D] = []
var show_debug: bool = false
var debug_color: Color = Color.YELLOW
var debug_width: float = 0.05
var debug_segments: int = 30

func initialize(owner_car: FlyingCar, world: Node3D) -> void:
	car_owner = owner_car
	world_node = world

func create_path(start: Vector3, end: Vector3, initial_progress: float,
				 volume: Dictionary, next_segment: Dictionary) -> void:

	first_segment_volume = volume

	if next_segment.is_empty():
		_create_simple_path(start, end, initial_progress)
		second_segment_volume = {}
	else:
		_create_double_segment_path(start, end, next_segment, initial_progress)
		second_segment_volume = next_segment["volume_data"]

	is_transitioning = false
	cancel_dodge()

func get_current_transform() -> Transform3D:
	if not curve:
		return Transform3D()
	var xf := curve.sample_baked_with_rotation(progress)
	if not dodge_active:
		return xf
	var e := _envelope(progress)
	var de := _envelope_derivative(progress)
	if e <= 0.0 and de == 0.0:
		return xf
	xf.origin += dodge_dir * (dodge_magnitude * e)
	# Orient along the offset path's tangent (base tangent + envelope slope):
	# the car pitches into vertical dodges and yaws into lateral ones.
	var h := 0.5
	var base_tangent := curve.sample_baked(minf(progress + h, _length)) \
		- curve.sample_baked(maxf(progress - h, 0.0))
	if base_tangent.length_squared() < 1e-8:
		return xf
	base_tangent = base_tangent.normalized()
	var tangent := (base_tangent + dodge_dir * (dodge_magnitude * de)).normalized()
	# Keep the sampled rotation's forward-axis sign so the basis never flips
	# when the envelope fades in or out.
	var z_axis := tangent * (1.0 if xf.basis.z.dot(base_tangent) >= 0.0 else -1.0)
	var y_axis := xf.basis.y - z_axis * xf.basis.y.dot(z_axis)
	if y_axis.length_squared() < 1e-8:
		y_axis = Vector3.UP - z_axis * Vector3.UP.dot(z_axis)
	y_axis = y_axis.normalized()
	xf.basis = Basis(y_axis.cross(z_axis), y_axis, z_axis)
	return xf

func advance(delta: float, speed: float) -> void:
	if not curve:
		return

	progress += delta * speed

	if dodge_active and dodge_merge_arc != INF \
			and progress >= dodge_merge_arc + dodge_ramp_len:
		cancel_dodge()

	if transition_point > 0.0 and progress >= transition_point and not is_transitioning:
		is_transitioning = true
		# The handler swaps in the next segment's curve and progress.
		_notify_transition()
		return

	if progress >= _length:
		progress = _length
		if not _ended:
			_ended = true
			path_ended.emit()

func get_progress() -> float:
	return progress

func get_curve_length() -> float:
	return _length

func sample_baked(p_progress: float) -> Vector3:
	if curve:
		return curve.sample_baked(p_progress)
	return Vector3.ZERO

## Base curve sample plus the active dodge offset. Corridor building uses this
## so detection, broadcasts and claims all follow the path actually flown.
func sample_dodged(p_progress: float) -> Vector3:
	var p := sample_baked(p_progress)
	if dodge_active:
		p += dodge_dir * (dodge_magnitude * _envelope(p_progress))
	return p

# ============================================================================
# DODGE ENVELOPE
# ============================================================================

func start_dodge(dir: Vector3, magnitude: float, start_arc: float, ramp_len: float) -> void:
	dodge_active = true
	dodge_dir = dir
	dodge_magnitude = magnitude
	dodge_start_arc = start_arc
	dodge_ramp_len = maxf(ramp_len, 0.1)
	dodge_merge_arc = INF

## Close the open-ended hold: the ease-in back to the base path begins at
## `merge_arc`. The dodge self-clears once the ramp completes (see advance()).
func request_merge(merge_arc: float) -> void:
	if dodge_active and dodge_merge_arc == INF:
		dodge_merge_arc = maxf(merge_arc, dodge_start_arc + dodge_ramp_len)

func cancel_dodge() -> void:
	dodge_active = false
	dodge_dir = Vector3.ZERO
	dodge_magnitude = 0.0
	dodge_merge_arc = INF

func _envelope(arc: float) -> float:
	return envelope(arc, dodge_start_arc, dodge_ramp_len, dodge_merge_arc)

## Envelope value in [0,1] at `arc`. Static so CollisionAvoidance can evaluate
## hypothetical dodges (probes, merge checks) with the same math.
static func envelope(arc: float, start_arc: float, ramp_len: float, merge_arc: float) -> float:
	var t_out := clampf((arc - start_arc) / ramp_len, 0.0, 1.0)
	var e := t_out * t_out * (3.0 - 2.0 * t_out)
	if merge_arc != INF:
		var t_in := clampf((arc - merge_arc) / ramp_len, 0.0, 1.0)
		e = minf(e, 1.0 - t_in * t_in * (3.0 - 2.0 * t_in))
	return e

# Closed-form slope of the active ramp (smoothstep derivative), used to tilt
# the car's basis into the dodge.
func _envelope_derivative(arc: float) -> float:
	var d := 0.0
	var t_out := (arc - dodge_start_arc) / dodge_ramp_len
	if t_out > 0.0 and t_out < 1.0:
		d += (6.0 * t_out - 6.0 * t_out * t_out) / dodge_ramp_len
	if dodge_merge_arc != INF:
		var t_in := (arc - dodge_merge_arc) / dodge_ramp_len
		if t_in > 0.0 and t_in < 1.0:
			d -= (6.0 * t_in - 6.0 * t_in * t_in) / dodge_ramp_len
	return d

func _create_simple_path(start: Vector3, end: Vector3, initial_progress: float) -> void:
	curve = Curve3D.new()
	curve.bake_interval = BAKE_INTERVAL
	curve.add_point(start, Vector3.ZERO, Vector3.ZERO)
	curve.add_point(end, Vector3.ZERO, Vector3.ZERO)

	_length = curve.get_baked_length()
	transition_point = -1.0
	progress = initial_progress * _length
	_ended = false

	if show_debug:
		_create_path_debug()

func _create_double_segment_path(start: Vector3, end: Vector3,
								 next_segment: Dictionary, initial_progress: float) -> void:
	curve = Curve3D.new()
	curve.bake_interval = BAKE_INTERVAL

	var first_direction = (end - start).normalized()
	var next_start = next_segment["path"]["start"]
	var next_end = next_segment["path"]["end"]
	var next_direction = (next_end - next_start).normalized()

	var connection_distance = (next_start - end).length()
	var handle_length = connection_distance * 0.4

	var out_handle = first_direction * handle_length
	var in_handle = -next_direction * handle_length

	curve.add_point(start, Vector3.ZERO, Vector3.ZERO)
	curve.add_point(end, Vector3.ZERO, out_handle)
	curve.add_point(next_start, in_handle, Vector3.ZERO)
	curve.add_point(next_end, Vector3.ZERO, Vector3.ZERO)

	_length = curve.get_baked_length()
	# The final segment (next_start → next_end) is a straight line, so its
	# baked arc length equals its euclidean length — no offset search needed.
	transition_point = _length - next_start.distance_to(next_end)
	progress = initial_progress * _length
	_ended = false

	if show_debug:
		_create_path_debug()

func _notify_transition() -> void:
	var old_id = _get_volume_id(first_segment_volume)
	var new_id = _get_volume_id(second_segment_volume)

	segment_transition_completed.emit(old_id, new_id)

func advance_to_next_segment(new_segment: Dictionary) -> void:
	first_segment_volume = second_segment_volume

	var current_start = curve.get_point_position(2)
	var current_end = curve.get_point_position(3)
	# The car sits on the old curve's straight last segment, which becomes the
	# new curve's straight first segment — the offset carries over directly.
	var carried_progress = progress - transition_point

	# An active dodge survives the transition: its arcs live in progress space,
	# so they shift by the same amount the progress does.
	if dodge_active:
		dodge_start_arc -= transition_point
		if dodge_merge_arc != INF:
			dodge_merge_arc -= transition_point

	_clear_debug_meshes()

	if new_segment.is_empty():
		_create_simple_path(current_start, current_end, 0.0)
		second_segment_volume = {}
	else:
		_create_double_segment_path(current_start, current_end, new_segment, 0.0)
		second_segment_volume = new_segment["volume_data"]

	progress = clampf(carried_progress, 0.0, _length)
	is_transitioning = false

func _create_path_debug() -> void:
	var points = []
	for i in range(curve.point_count):
		points.append({
			"pos": curve.get_point_position(i),
			"in": curve.get_point_in(i),
			"out": curve.get_point_out(i)
		})

	path_debug_mesh = DebugUtil.create_debug_path3d(
		points, debug_segments, debug_color, debug_width
	)
	world_node.add_child(path_debug_mesh)

func _clear_debug_meshes() -> void:
	if path_debug_mesh and is_instance_valid(path_debug_mesh):
		path_debug_mesh.queue_free()

	for mesh in continuation_debug_meshes:
		if mesh and is_instance_valid(mesh):
			mesh.queue_free()
	continuation_debug_meshes.clear()

func _get_volume_id(volume: Dictionary) -> String:
	if volume.has("face_idx") and volume.has("edge_idx"):
		return str(volume["face_idx"]) + "_" + str(volume["edge_idx"])
	return ""

func cleanup() -> void:
	_clear_debug_meshes()
