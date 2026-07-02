# TrafficDebugDrawer.gd
# Visualizes the traffic claim system by reading data that already exists in
# the registry and each car's CollisionAvoidance — no extra queries, no
# per-car nodes. All lines go into one shared ImmediateMesh (one draw call);
# when the master toggle is off the cost is a single check per frame.
#
# Toggles live in the "Traffic Debug" export group of any AreaInstantiator;
# the first instantiator with show_traffic_debug enabled provides the config
# (and its cameras, for the inspect labels).
extends Node3D
class_name TrafficDebugDrawer

const MAX_LABELS: int = 24
const STATE_COLORS: Dictionary = {
	CollisionAvoidance.State.CRUISING: Color(0.2, 0.9, 0.2, 0.8),
	CollisionAvoidance.State.FOLLOWING: Color(0.2, 0.8, 0.95, 0.8),
	CollisionAvoidance.State.BRAKING: Color(1.0, 0.6, 0.1, 0.9),
	CollisionAvoidance.State.YIELDING: Color(0.9, 0.2, 0.9, 0.9),
	CollisionAvoidance.State.STOPPED: Color(1.0, 0.1, 0.1, 0.9),
	CollisionAvoidance.State.FOGGED: Color(0.5, 0.5, 0.5, 0.5),
	CollisionAvoidance.State.DODGING: Color(1.0, 1.0, 0.2, 0.9),
}
const BROADCAST_COLOR: Color = Color(0.2, 0.4, 1.0, 0.5)
const LINK_COLOR: Color = Color(1.0, 0.2, 0.6, 0.9)
const STOP_COLOR: Color = Color(1.0, 0.1, 0.1, 1.0)
const CELL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.12)

var registry: TrafficClaimRegistry

var _mesh: ImmediateMesh
var _mesh_instance: MeshInstance3D
var _labels: Array[Label3D] = []
var _tinted: bool = false
var _active: bool = false

var _line_points: PackedVector3Array = PackedVector3Array()
var _line_colors: PackedColorArray = PackedColorArray()

func _ready() -> void:
	# Draw after cars have moved and updated their state this frame.
	process_priority = 100

	_mesh = ImmediateMesh.new()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = _mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	_mesh_instance.material_override = mat
	_mesh_instance.custom_aabb = AABB(Vector3(-1e6, -1e6, -1e6), Vector3(2e6, 2e6, 2e6))
	add_child(_mesh_instance)

func _find_config():
	for node in get_tree().get_nodes_in_group("area_instantiator"):
		if node.show_traffic_debug:
			return node
	return null

func _process(_delta: float) -> void:
	var config = _find_config()
	if config == null or registry == null:
		if _active:
			_deactivate()
		return
	_active = true

	_line_points.clear()
	_line_colors.clear()

	for car in registry.cars:
		if not is_instance_valid(car):
			continue
		var ca: CollisionAvoidance = car.collision_avoidance
		if ca == null:
			continue
		var color: Color = STATE_COLORS.get(ca.state, Color.WHITE)

		if config.traffic_debug_tint:
			car.set_debug_tint(color)
			_tinted = true

		if ca.state == CollisionAvoidance.State.FOGGED:
			continue

		if config.traffic_debug_corridors:
			_draw_polyline(ca.corridor_points, color)
			_draw_broadcast(ca)

		if config.traffic_debug_links and ca.blocking_car_ref:
			var other = ca.blocking_car_ref.get_ref()
			if other:
				_line(car.global_position, other.global_position, LINK_COLOR)

		if config.traffic_debug_stop_points and ca.has_hit_point:
			_draw_marker(ca.hit_point, 1.0, STOP_COLOR)

	if not config.traffic_debug_tint and _tinted:
		_restore_tints()

	if config.traffic_debug_cells:
		_draw_cells()

	_mesh.clear_surfaces()
	if _line_points.size() >= 2:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(_line_points.size()):
			_mesh.surface_set_color(_line_colors[i])
			_mesh.surface_add_vertex(_line_points[i])
		_mesh.surface_end()

	_update_labels(config)

# ============================================================================
# LINE HELPERS
# ============================================================================

func _line(a: Vector3, b: Vector3, color: Color) -> void:
	_line_points.append(a)
	_line_points.append(b)
	_line_colors.append(color)
	_line_colors.append(color)

func _draw_polyline(points: PackedVector3Array, color: Color) -> void:
	for i in range(points.size() - 1):
		_line(points[i], points[i + 1], color)

func _draw_broadcast(ca: CollisionAvoidance) -> void:
	# The reserved corridor, drawn slightly raised so it reads over the
	# detection corridor.
	var points := ca.get_broadcast_points()
	var lift := Vector3(0.0, 0.25, 0.0)
	for i in range(points.size() - 1):
		_line(points[i] + lift, points[i + 1] + lift, BROADCAST_COLOR)

func _draw_marker(pos: Vector3, size: float, color: Color) -> void:
	_line(pos + Vector3(-size, 0, 0), pos + Vector3(size, 0, 0), color)
	_line(pos + Vector3(0, -size, 0), pos + Vector3(0, size, 0), color)
	_line(pos + Vector3(0, 0, -size), pos + Vector3(0, 0, size), color)

func _draw_cells() -> void:
	var s: float = registry.cell_size
	for key in registry._read_cells.keys():
		var base := Vector3(key) * s
		_draw_box_wire(base, Vector3(s, s, s), CELL_COLOR)

func _draw_box_wire(pos: Vector3, size: Vector3, color: Color) -> void:
	var x := Vector3(size.x, 0, 0)
	var y := Vector3(0, size.y, 0)
	var z := Vector3(0, 0, size.z)
	_line(pos, pos + x, color)
	_line(pos + z, pos + x + z, color)
	_line(pos, pos + z, color)
	_line(pos + x, pos + x + z, color)
	_line(pos + y, pos + y + x, color)
	_line(pos + y + z, pos + y + x + z, color)
	_line(pos + y, pos + y + z, color)
	_line(pos + y + x, pos + y + x + z, color)
	_line(pos, pos + y, color)
	_line(pos + x, pos + x + y, color)
	_line(pos + z, pos + z + y, color)
	_line(pos + x + z, pos + x + z + y, color)

# ============================================================================
# INSPECT LABELS (only cars near the camera)
# ============================================================================

func _update_labels(config) -> void:
	var used := 0
	if config.traffic_debug_labels:
		var max_dist: float = config.traffic_debug_label_distance
		for car in registry.cars:
			if used >= MAX_LABELS:
				break
			if not is_instance_valid(car):
				continue
			var near := false
			for camera in config.cameras:
				if camera and is_instance_valid(camera) \
						and camera.global_position.distance_to(car.global_position) <= max_dist:
					near = true
					break
			if not near:
				continue
			var label := _get_label(used)
			label.visible = true
			label.text = car.get_debug_info()
			label.global_position = car.global_position + Vector3(0.0, car.height * 0.5 + 1.5, 0.0)
			used += 1

	for i in range(used, _labels.size()):
		_labels[i].visible = false

func _get_label(index: int) -> Label3D:
	while _labels.size() <= index:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.005
		label.font_size = 28
		label.outline_size = 6
		label.visible = false
		add_child(label)
		_labels.append(label)
	return _labels[index]

# ============================================================================
# CLEANUP
# ============================================================================

func _deactivate() -> void:
	_active = false
	_mesh.clear_surfaces()
	for label in _labels:
		label.visible = false
	if _tinted:
		_restore_tints()

func _restore_tints() -> void:
	_tinted = false
	for car in registry.cars:
		if is_instance_valid(car):
			car.clear_debug_tint()
