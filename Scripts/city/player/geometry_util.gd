extends RefCounted
class_name GeometryUtils

# Calcula intersecciones de una línea con un cilindro infinito en el plano XZ
# Retorna array con los valores t [0-1] donde ocurren las intersecciones
static func intersect_cylinder(origin: Vector3, direction: Vector3, radius: float) -> Array:
	var a = direction.x * direction.x + direction.z * direction.z
	var b = 2.0 * (origin.x * direction.x + origin.z * direction.z)
	var c = origin.x * origin.x + origin.z * origin.z - radius * radius
	
	# Línea vertical
	if abs(a) < 0.0001:
		return []
	
	var discriminant = b * b - 4.0 * a * c
	
	if discriminant < 0:
		return []
	
	if abs(discriminant) < 0.0001:
		# Una intersección (tangente)
		return [(-b) / (2.0 * a)]
	
	# Dos intersecciones
	var sqrt_disc = sqrt(discriminant)
	return [
		(-b - sqrt_disc) / (2.0 * a),
		(-b + sqrt_disc) / (2.0 * a)
	]

# Versión normalizada que retorna valores t en el rango [0-1] relativo al path total
# Útil para calcular posiciones interpoladas a lo largo de un camino
static func intersect_cylinder_normalized(origin: Vector3, direction: Vector3, radius: float, total_length: float) -> Array:
	var a = direction.x * direction.x + direction.z * direction.z
	var b = 2.0 * (origin.x * direction.x + origin.z * direction.z)
	var c = origin.x * origin.x + origin.z * origin.z - radius * radius
	
	# Línea vertical
	if abs(a) < 0.0001:
		return []
	
	var discriminant = b * b - 4.0 * a * c
	
	if discriminant < 0:
		return []
	
	if abs(discriminant) < 0.0001:
		# Una intersección (tangente)
		var t = (-b) / (2.0 * a)
		return [t / total_length]
	
	# Dos intersecciones
	var sqrt_disc = sqrt(discriminant)
	var t1 = (-b - sqrt_disc) / (2.0 * a)
	var t2 = (-b + sqrt_disc) / (2.0 * a)
	
	return [
		t1 / total_length,
		t2 / total_length
	]

# Verifica si un punto (en coordenadas locales) está dentro del volumen de anillo cilíndrico 3D
static func is_point_in_ring_volume(local_point: Vector3, inner_radius: float, outer_radius: float, height: float) -> bool:
	var half_height = height / 2.0
	var r = sqrt(local_point.x * local_point.x + local_point.z * local_point.z)
	return r >= inner_radius and r <= outer_radius and local_point.y >= -half_height and local_point.y <= half_height

# Verifica si un punto está dentro de un lane volume definido por dos planos
static func is_point_inside_lane_volume(point: Vector3, plane1_verts: Array, plane2_verts: Array) -> bool:
	if not check_point_plane_side(point, plane1_verts[0], plane1_verts[1], plane1_verts[2], true):
		return false
	
	if not check_point_plane_side(point, plane2_verts[3], plane2_verts[2], plane2_verts[1], true):
		return false
	
	if not check_point_plane_side(point, plane1_verts[0], plane2_verts[0], plane2_verts[1], true):
		return false
	
	if not check_point_plane_side(point, plane1_verts[3], plane1_verts[2], plane2_verts[2], true):
		return false
	
	if not check_point_plane_side(point, plane1_verts[0], plane1_verts[3], plane2_verts[3], true):
		return false
	
	if not check_point_plane_side(point, plane1_verts[1], plane2_verts[1], plane2_verts[2], true):
		return false
	
	return true

# Verifica si un punto está del lado especificado de un plano definido por 3 vértices
# inside=true: verifica que esté del lado positivo de la normal
# inside=false: verifica que esté del lado negativo de la normal
static func check_point_plane_side(point: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, inside: bool) -> bool:
	var normal = (v2 - v1).cross(v3 - v1).normalized()
	var to_point = point - v1
	var dot = normal.dot(to_point)
	
	return dot >= 0 if inside else dot <= 0

# Recorta una línea 3D al volumen de anillo cilíndrico, retornando los segmentos visibles
# Retorna array de pares [start_point, end_point] en coordenadas globales
static func clip_line_to_ring_volume(line_start: Vector3, line_end: Vector3, transform: Transform3D, inner_radius: float, outer_radius: float, height: float) -> Array:
	# Convertir a coordenadas locales
	var local_start = transform.affine_inverse() * line_start
	var local_end = transform.affine_inverse() * line_end
	
	var half_height = height / 2.0
	var direction = local_end - local_start
	
	# Calcular intersecciones con cilindro exterior
	var t_outer = intersect_cylinder(local_start, direction, outer_radius)
	
	# Calcular intersecciones con cilindro interior
	var t_inner = intersect_cylinder(local_start, direction, inner_radius)
	
	# Recopilar todos los puntos de intersección relevantes
	var intersections = []
	
	# Añadir intersecciones con cilindro exterior
	for t in t_outer:
		if t >= 0.0 and t <= 1.0:
			var point = local_start + t * direction
			if point.y >= -half_height and point.y <= half_height:
				intersections.append({"t": t, "type": "outer"})
	
	# Añadir intersecciones con cilindro interior
	for t in t_inner:
		if t >= 0.0 and t <= 1.0:
			var point = local_start + t * direction
			if point.y >= -half_height and point.y <= half_height:
				intersections.append({"t": t, "type": "inner"})
	
	# Añadir extremos de la línea si están dentro del anillo
	if is_point_in_ring_volume(local_start, inner_radius, outer_radius, height):
		intersections.append({"t": 0.0, "type": "start"})
	if is_point_in_ring_volume(local_end, inner_radius, outer_radius, height):
		intersections.append({"t": 1.0, "type": "end"})
	
	# Ordenar por t
	intersections.sort_custom(func(a, b): return a["t"] < b["t"])
	
	# Construir segmentos que están dentro del anillo
	var segments_result = []
	var i = 0
	while i < intersections.size():
		var t1 = intersections[i]["t"]
		
		# Buscar el siguiente punto de intersección
		if i + 1 < intersections.size():
			var t2 = intersections[i + 1]["t"]
			var mid_t = (t1 + t2) / 2.0
			var mid_point = local_start + mid_t * direction
			
			# Verificar si el punto medio está en el anillo
			if is_point_in_ring_volume(mid_point, inner_radius, outer_radius, height):
				var global_p1 = transform * (local_start + t1 * direction)
				var global_p2 = transform * (local_start + t2 * direction)
				segments_result.append([global_p1, global_p2])
		
		i += 1
	
	return segments_result
