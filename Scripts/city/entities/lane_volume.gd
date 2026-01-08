extends RefCounted
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
# - Visualización debug de grillas, volúmenes y flechas de flujo
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

# Verifica si un punto está dentro del lane volume
func contains_point(point: Vector3) -> bool:
	return GeometryUtils.is_point_inside_lane_volume(
		point, 
		start_plane_vertices, 
		end_plane_vertices
	)

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

# Crea flechas de flujo para este lane volume, retornando segmentos válidos
# Los segmentos se recortan al área cilíndrica especificada
func create_flow_arrows(width_steps: int, height_steps: int, container: Node3D,
						arrow_color: Color, arrow_width: float,
						area_transform: Transform3D, inner_radius: float, 
						outer_radius: float, area_height: float) -> Array:
	var valid_segments = []
	
	for i in range(width_steps + 1):
		for j in range(height_steps + 1):
			var u = float(i) / float(width_steps)
			var v = float(j) / float(height_steps)
			
			# Obtener el segmento de path en estas coordenadas
			var path_segment = get_path_segment_at_grid(u, v)
			
			# Recortar al anillo cilíndrico
			var segments_array = GeometryUtils.clip_line_to_ring_volume(
				path_segment["start"], 
				path_segment["end"], 
				area_transform, 
				inner_radius, 
				outer_radius, 
				area_height
			)
			
			for segment in segments_array:
				var arrow = DebugUtil.create_debug_arrow_to_from(
					segment[0], segment[1], arrow_color, arrow_width
				)
				container.add_child(arrow)
				
				# Guardar información del segmento para spawn
				valid_segments.append({
					"start": segment[0],
					"end": segment[1],
					"lane_volume": self,
					"grid_u": u,
					"grid_v": v,
					"width_cells": width_steps,
					"height_cells": height_steps
				})
	
	return valid_segments
