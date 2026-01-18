# PathController.gd
extends Node
class_name PathController

signal segment_transition_completed(old_volume_id: String, new_volume_id: String)
signal path_ended

var path_3d: Path3D
var path_follow: PathFollow3D
var transition_point: float = -1.0
var is_transitioning: bool = false

var first_segment_volume: Dictionary = {}
var second_segment_volume: Dictionary = {}

var world_node: Node3D
var car_owner: FlyingCar

# Debug
var path_debug_mesh: MeshInstance3D
var continuation_debug_meshes: Array[MeshInstance3D] = []
var show_debug: bool = false
var debug_color: Color = Color.YELLOW
var debug_width: float = 0.05
var debug_segments: int = 30

func _ready() -> void:
	var timer = Timer.new()
	timer.wait_time = 0.1
	timer.timeout.connect(_check_transition)
	add_child(timer)
	timer.start()

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
	if path_follow:
		return path_follow.global_transform
	return Transform3D()

func get_current_position() -> Vector3:
	if path_follow:
		return path_follow.global_position
	return Vector3.ZERO

func advance(delta: float, speed: float) -> void:
	if not path_follow:
		return
	
	path_follow.progress += delta * speed

func get_progress() -> float:
	return path_follow.progress if path_follow else 0.0

func get_curve_length() -> float:
	return path_3d.curve.get_baked_length() if path_3d else 0.0

func sample_baked(progress: float) -> Vector3:
	if path_3d:
		return path_3d.curve.sample_baked(progress)
	return Vector3.ZERO

func sample_baked_with_rotation(progress: float) -> Transform3D:
	if path_3d:
		return path_3d.curve.sample_baked_with_rotation(progress)
	return Transform3D()

func _create_simple_path(start: Vector3, end: Vector3, initial_progress: float) -> void:
	path_3d = Path3D.new()
	var curve = Curve3D.new()
	curve.add_point(start, Vector3.ZERO, Vector3.ZERO)
	curve.add_point(end, Vector3.ZERO, Vector3.ZERO)
	path_3d.curve = curve
	
	transition_point = -1.0
	
	world_node.add_child(path_3d)
	
	path_follow = PathFollow3D.new()
	path_follow.loop = false
	path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_3d.add_child(path_follow)
	
	path_follow.progress = initial_progress * curve.get_baked_length()
	
	if show_debug:
		_create_path_debug()

func _create_double_segment_path(start: Vector3, end: Vector3, 
								 next_segment: Dictionary, initial_progress: float) -> void:
	path_3d = Path3D.new()
	var curve = Curve3D.new()
	
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
	
	path_3d.curve = curve
	transition_point = curve.get_closest_offset(next_start)
	
	world_node.add_child(path_3d)
	
	path_follow = PathFollow3D.new()
	path_follow.loop = false
	path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_3d.add_child(path_follow)
	
	path_follow.progress = initial_progress * curve.get_baked_length()
	
	if show_debug:
		_create_path_debug()

func _check_transition() -> void:
	if not path_follow or not path_3d:
		return
	
	var current_progress = path_follow.progress
	var curve_length = path_3d.curve.get_baked_length()
	
	if current_progress >= curve_length:
		path_ended.emit()
		return
	
	if transition_point > 0 and current_progress >= transition_point and not is_transitioning:
		is_transitioning = true
		_notify_transition()

func _notify_transition() -> void:
	var old_id = _get_volume_id(first_segment_volume)
	var new_id = _get_volume_id(second_segment_volume)
	
	segment_transition_completed.emit(old_id, new_id)

func advance_to_next_segment(new_segment: Dictionary) -> void:
	first_segment_volume = second_segment_volume
	
	var current_end = path_3d.curve.get_point_position(3)
	
	if new_segment.is_empty():
		var current_start = path_3d.curve.get_point_position(2)
		_regenerate_simple_path(current_start, current_end)
		second_segment_volume = {}
	else:
		var current_start = path_3d.curve.get_point_position(2)
		_regenerate_double_path(current_start, current_end, new_segment)
		second_segment_volume = new_segment["volume_data"]
	
	is_transitioning = false

func _regenerate_simple_path(start: Vector3, end: Vector3) -> void:
	_clear_debug_meshes()
	
	var current_position = path_follow.global_position
	var old_path = path_3d
	
	_create_simple_path(start, end, 0.0)
	
	var closest_offset = path_3d.curve.get_closest_offset(current_position)
	path_follow.progress = closest_offset
	
	if old_path and is_instance_valid(old_path):
		old_path.queue_free()

func _regenerate_double_path(start: Vector3, end: Vector3, next_segment: Dictionary) -> void:
	_clear_debug_meshes()
	
	var current_position = path_follow.global_position
	var old_path = path_3d
	
	_create_double_segment_path(start, end, next_segment, 0.0)
	
	var closest_offset = path_3d.curve.get_closest_offset(current_position)
	path_follow.progress = closest_offset
	
	if old_path and is_instance_valid(old_path):
		old_path.queue_free()

func _create_path_debug() -> void:
	var points = []
	for i in range(path_3d.curve.point_count):
		points.append({
			"pos": path_3d.curve.get_point_position(i),
			"in": path_3d.curve.get_point_in(i),
			"out": path_3d.curve.get_point_out(i)
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
	
	if path_3d and is_instance_valid(path_3d):
		path_3d.queue_free()
