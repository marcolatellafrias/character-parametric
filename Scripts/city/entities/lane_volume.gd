extends Area3D
class_name LaneVolume

# ============================================================================
# LANE VOLUME
# ============================================================================
# Representa un volumen de carril de tráfico en 3D.
# Un lane volume es un prisma definido por:
# - Un plano de inicio (4 vértices)
# - Un plano final (4 vértices)
# - Coordenadas de grilla (width_cells x height_cells)
#
# Proporciona métodos para:
# - Interpolar puntos en coordenadas de grilla (u, v)
# - Validar si puntos están dentro del volumen
# - Obtener planos laterales para detección de colisiones
# - Visualización debug de grillas y volúmenes
# - Funcionalidad de Area3D con collision automático
# ============================================================================

var face_idx: int
var edge_idx: int
var start_plane_vertices: Array  # [bottom_left, bottom_right, top_right, top_left]
var end_plane_vertices: Array    # [bottom_left, bottom_right, top_right, top_left]
var width_cells: int
var height_cells: int
var street_type: int
var volume_height: float

# Datos originales del volumen (preservados por compatibilidad)
var raw_data: Dictionary

# CollisionShape3D generado
var collision_shape: CollisionShape3D

func _init(volume_data: Dictionary) -> void:
	raw_data = volume_data
	face_idx = volume_data.get("face_idx", -1)
	edge_idx = volume_data.get("edge_idx", -1)
	start_plane_vertices = volume_data.get("start_plane_vertices", [])
	end_plane_vertices = volume_data.get("end_plane_vertices", [])
	width_cells = volume_data.get("width_cells", 3)
	height_cells = volume_data.get("height_cells", 10)
	street_type = volume_data.get("street_type", 0)
	volume_height = volume_data.get("height", 0.0)
	
	_setup_area()
	_generate_collision()

func _setup_area() -> void:
	# Configuración básica del Area3D
	monitoring = true
	monitorable = true
	
	# CRÍTICO: Configurar collision layer para que otros Area3D nos detecten
	collision_layer = 2  # Ponemos los LaneVolume en el layer 2
	collision_mask = 0   # No necesitamos detectar nada
	
	# Agregar al grupo para fácil acceso
	add_to_group("lane_volumes")
	
	# Metadata útil
	set_meta("face_idx", face_idx)
	set_meta("edge_idx", edge_idx)
	set_meta("street_type", street_type)
	set_meta("lane_id", get_id())

func _generate_collision() -> void:
	collision_shape = DebugUtil.create_collision_shape_from_planes(
		start_plane_vertices,
		end_plane_vertices
	)
	
	if collision_shape:
		add_child(collision_shape)

# ============================================================================
# MÉTODOS DE GEOMETRÍA Y PATH
# ============================================================================

# Obtiene un punto interpolado en coordenadas de grilla (u, v)
# u: posición horizontal (0.0 = izquierda, 1.0 = derecha)
# v: posición vertical (0.0 = abajo, 1.0 = arriba)
# use_start_plane: si true usa el plano de inicio, si false usa el plano final
func get_point_at_grid(u: float, v: float, use_start_plane: bool = true) -> Vector3:
	var plane = start_plane_vertices if use_start_plane else end_plane_vertices
	
	# Interpolar horizontalmente en la base y en el tope
	var bottom = plane[0].lerp(plane[1], u)
	var top = plane[3].lerp(plane[2], u)
	
	# Interpolar verticalmente entre base y tope
	return bottom.lerp(top, v)

# Obtiene un segmento de path completo en coordenadas de grilla
# Retorna un diccionario con start y end points
func get_path_segment_at_grid(u: float, v: float) -> Dictionary:
	return {
		"start": get_point_at_grid(u, v, true),
		"end": get_point_at_grid(u, v, false)
	}

# Obtiene los 4 planos laterales que conectan start_plane con end_plane
# Retorna un diccionario con claves: "bottom", "right", "top", "left"
# Cada plano se representa como [normal: Vector3, point: Vector3]
func get_lateral_planes() -> Dictionary:
	return {
		"bottom": _plane_from_points(start_plane_vertices[0], start_plane_vertices[1], end_plane_vertices[1]),
		"right": _plane_from_points(start_plane_vertices[1], start_plane_vertices[2], end_plane_vertices[2]),
		"top": _plane_from_points(start_plane_vertices[2], start_plane_vertices[3], end_plane_vertices[3]),
		"left": _plane_from_points(start_plane_vertices[3], start_plane_vertices[0], end_plane_vertices[0])
	}

# Calcula la dirección del flujo de tráfico (normalizado)
func get_flow_direction() -> Vector3:
	var center_start = get_point_at_grid(0.5, 0.5, true)
	var center_end = get_point_at_grid(0.5, 0.5, false)
	return (center_end - center_start).normalized()

# Obtiene el centro del volumen
func get_center() -> Vector3:
	var center_start = get_point_at_grid(0.5, 0.5, true)
	var center_end = get_point_at_grid(0.5, 0.5, false)
	return (center_start + center_end) * 0.5

# Calcula la longitud del path en el centro del volumen
func get_path_length() -> float:
	var center_start = get_point_at_grid(0.5, 0.5, true)
	var center_end = get_point_at_grid(0.5, 0.5, false)
	return center_start.distance_to(center_end)

# Crea un plano a partir de 3 puntos
# Retorna [normal, point]
func _plane_from_points(p1: Vector3, p2: Vector3, p3: Vector3) -> Array:
	var v1 = p2 - p1
	var v2 = p3 - p1
	var normal = v1.cross(v2).normalized()
	return [normal, p1]

# Genera un identificador único para este volumen
func get_id() -> String:
	return "%d_%d" % [face_idx, edge_idx]

# Retorna el diccionario original (útil para compatibilidad)
func get_raw_data() -> Dictionary:
	return raw_data

# ============================================================================
# MÉTODOS DE VISUALIZACIÓN DEBUG
# ============================================================================

# Crea la visualización del volumen completo como un mesh
func create_volume_mesh(color: Color, transparency: float, container: Node3D) -> void:
	var mesh = DebugUtil.create_skewed_cube_from_planes(
		start_plane_vertices,
		end_plane_vertices,
		color,
		transparency
	)
	if mesh:
		container.add_child(mesh)

# Crea puntos de grilla para este lane volume
func create_grid_points(width_steps: int, height_steps: int, container: Node3D, 
						color: Color, size: float) -> void:
	for i in range(width_steps + 1):
		for j in range(height_steps + 1):
			var u = float(i) / float(width_steps)
			var v = float(j) / float(height_steps)
			
			# Punto en el plano de inicio
			var point_start = get_point_at_grid(u, v, true)
			var grid_coords = Vector2i(i, j)
			var sphere = DebugUtil.create_debug_sphere_print(grid_coords, color, size)
			sphere.set_meta("grid_coords", grid_coords)
			sphere.set_meta("world_position", point_start)
			container.add_child(sphere)
			sphere.global_position = point_start
			
			# Punto en el plano final
			var point_end = get_point_at_grid(u, v, false)
			var sphere_end = DebugUtil.create_debug_sphere_print(grid_coords, color, size)
			sphere_end.set_meta("grid_coords", grid_coords)
			sphere_end.set_meta("world_position", point_end)
			container.add_child(sphere_end)
			sphere_end.global_position = point_end

# Valida si una cara frontal proyectada a través del path cruza algún plano lateral
# face_vertices: Array de 4 Vector3 en orden [bottom-left, bottom-right, top-right, top-left]
#                Offsets relativos CENTRADOS respecto al punto del path (tanto horizontal como verticalmente)
# grid_u: coordenada horizontal (0.0 a 1.0)  
# grid_v: coordenada vertical (0.0 a 1.0)
# Retorna: {"valid": bool, "collision_plane": String}
func validate_face_projection(face_vertices: Array, grid_u: float, grid_v: float) -> Dictionary:
	var path_start = get_point_at_grid(grid_u, grid_v, true)
	var path_end = get_point_at_grid(grid_u, grid_v, false)
	
	var lateral_planes = get_lateral_planes()
	
	# Para cada plano lateral, verificar si la cara lo atraviesa
	for plane_name in lateral_planes.keys():
		var plane = lateral_planes[plane_name]
		var plane_normal = plane[0]
		var plane_point = plane[1]
		
		# Evaluar todos los vértices de la cara en start y end
		var has_positive_start = false
		var has_negative_start = false
		var has_positive_end = false
		var has_negative_end = false
		
		for vertex_offset in face_vertices:
			# Vértice en posición de inicio (offset centrado + punto del path)
			var vertex_at_start = path_start + vertex_offset
			var dist_start = plane_normal.dot(vertex_at_start - plane_point)
			if dist_start > 0.001:
				has_positive_start = true
			elif dist_start < -0.001:
				has_negative_start = true
			
			# Vértice en posición final (offset centrado + punto del path)
			var vertex_at_end = path_end + vertex_offset
			var dist_end = plane_normal.dot(vertex_at_end - plane_point)
			if dist_end > 0.001:
				has_positive_end = true
			elif dist_end < -0.001:
				has_negative_end = true
		
		# Si hay vértices en ambos lados del plano (en start o en end), la cara atraviesa el plano
		if (has_positive_start and has_negative_start) or (has_positive_end and has_negative_end):
			return {
				"valid": false,
				"collision_plane": plane_name
			}
	
	return {"valid": true, "collision_plane": ""}
