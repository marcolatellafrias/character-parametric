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

func get_current_transform() -> Transform3D:
	if curve:
		return curve.sample_baked_with_rotation(progress)
	return Transform3D()

func advance(delta: float, speed: float) -> void:
	if not curve:
		return

	progress += delta * speed

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
