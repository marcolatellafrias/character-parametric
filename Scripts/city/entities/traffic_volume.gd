class_name TrafficPlane
extends Area3D

var lane_volume: LaneVolume
var traffic_index: int = -1
var collision_shape: CollisionShape3D
var adjusted_end_vertices: Array = []  # NUEVO: Vértices ajustados a block_height

# Global light phase — ONE source of truth (two scalars; trivially synced in
# multiplayer). `is_blocking` DERIVES from it on read, so a plane holds no
# per-plane light state that can go stale: the frozen-red-light class of bugs
# (the same ~20 lanes stuck red run after run, gridlocking their nodes) is
# impossible by construction.
static var global_active_index: int = 0
static var global_yellow_phase: bool = false

## true = semáforo en rojo (leído por TrafficClaimRegistry). During the yellow
## phase the green direction blocks too, so cars that can brake stop before the
## cross direction receives green.
var is_blocking: bool:
	get:
		if traffic_index == -1:
			return false
		return global_yellow_phase if traffic_index == global_active_index else true

const THICKNESS: float = 0.5

func _init(parent_lane: LaneVolume, initial_traffic_index: int) -> void:
	lane_volume = parent_lane
	traffic_index = initial_traffic_index
	_setup_area()

func _setup_area() -> void:
	monitoring = false
	monitorable = true
	
	collision_layer = 0
	collision_mask = 0
	
	add_to_group("traffic_planes")
	
	set_meta("lane_id", lane_volume.get_id())
	set_meta("traffic_index", traffic_index)

func setup_collision() -> void:
	if lane_volume.end_plane_vertices.size() != 4:
		push_error("[TrafficPlane] End plane vertices no tiene 4 vértices")
		return
	
	# Usar la altura de la manzana específica en lugar de la global
	var block_height = lane_volume.block_height
	
	# Obtener vértices base del end plane (altura global)
	var end_verts = lane_volume.end_plane_vertices
	
	# Crear nuevos vértices ajustados a la altura de la manzana
	var adjusted_front_verts = []
	for i in range(4):
		var vert = end_verts[i]
		# Los vértices inferiores (0,1) mantienen y=0, los superiores (2,3) usan block_height
		if i < 2:
			adjusted_front_verts.append(Vector3(vert.x, 0.0, vert.z))
		else:
			adjusted_front_verts.append(Vector3(vert.x, block_height, vert.z))
	
	# NUEVO: Guardar vértices ajustados para visualización
	adjusted_end_vertices = adjusted_front_verts.duplicate()
	
	# Calcular dirección hacia atrás
	var center_start = lane_volume.get_point_at_grid(0.5, 0.5, true)
	var center_end = lane_volume.get_point_at_grid(0.5, 0.5, false)
	var backward_dir = (center_start - center_end).normalized()
	
	# Crear vértices traseros desplazados
	var back_verts = []
	for v in adjusted_front_verts:
		back_verts.append(v + backward_dir * THICKNESS)
	
	collision_shape = DebugUtil.create_collision_shape_from_planes(
		adjusted_front_verts,
		back_verts
	)
	
	if collision_shape:
		add_child(collision_shape)

func get_end_vertices() -> Array:
	# Retornar vértices ajustados si existen, sino los originales
	if adjusted_end_vertices.size() == 4:
		return adjusted_end_vertices
	return lane_volume.end_plane_vertices
