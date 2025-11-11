class_name GraphHelper

static func get_inscribed_square(quad: Array) -> Array:
	if quad.size() != 4:
		push_error("Quad must have exactly 4 vertices")
		return []
	
	# 1. Calcular centro de masa
	var center := Vector2.ZERO
	for vertex in quad:
		center += vertex
	center /= 4.0
	
	# 2. Trasladar vértices al origen (centro de masa en 0,0)
	var centered_quad : = []
	for vertex in quad:
		centered_quad.append(vertex - center)
	
	# 3. Ordenar vértices en sentido horario
	centered_quad = _sort_clockwise(centered_quad)
	
	# 4. Calcular r (radio del cuadrado = lado/√2)
	# Usamos la distancia promedio al centro multiplicada por un factor
	var avg_dist := 0.0
	for vertex in centered_quad:
		avg_dist += vertex.length()
	avg_dist /= 4.0
	var r := avg_dist * 0.7  # Factor ajustable para el tamaño del cuadrado
	
	# 5. Calcular el ángulo óptimo α
	var x1 :float= centered_quad[0].x
	var y1 :float= centered_quad[0].y
	var x2 :float= centered_quad[1].x
	var y2 :float= centered_quad[1].y
	var x3 :float= centered_quad[2].x
	var y3 :float= centered_quad[2].y
	var x4 :float= centered_quad[3].x
	var y4 :float= centered_quad[3].y
	
	# α = arctan((y1 + x2 - y3 - x4)/(x1 - y2 - x3 + y4)) + k·π
	var numerator := y1 + x2 - y3 - x4
	var denominator := x1 - y2 - x3 + y4
	
	var alpha_base := atan2(numerator, denominator)
	var alpha_candidates := [alpha_base, alpha_base + PI]
	
	# 6. Elegir el α que minimiza (segunda derivada positiva)
	var best_alpha := alpha_base
	var best_d2 := -INF
	
	for alpha in alpha_candidates:
		# D''(α) = 2r·cos(α)·(x1 - y2 - x3 + y4) + 2r·sin(α)·(y1 + x2 - y3 - x4)
		var d2 := 2 * r * cos(alpha) * denominator + 2 * r * sin(alpha) * numerator
		if d2 > best_d2:
			best_d2 = d2
			best_alpha = alpha
	
	# 7. Generar los vértices del cuadrado con el ángulo óptimo
	var square := []
	var alpha := best_alpha
	
	# Vértices en sentido horario
	square.append(Vector2(r * cos(alpha), r * sin(alpha)))
	square.append(Vector2(r * sin(alpha), -r * cos(alpha)))
	square.append(Vector2(-r * cos(alpha), -r * sin(alpha)))
	square.append(Vector2(-r * sin(alpha), r * cos(alpha)))
	
	# 8. Trasladar de vuelta al espacio original
	for i in range(4):
		square[i] += center
	
	return square


static func _sort_clockwise(vertices: Array) -> Array:
	# Calcular ángulo de cada vértice respecto al origen
	var angles := []
	for i in range(vertices.size()):
		var angle := atan2(vertices[i].y, vertices[i].x)
		angles.append({"index": i, "angle": angle})
	
	# Ordenar por ángulo (sentido horario = ángulo decreciente)
	angles.sort_custom(func(a, b): return a.angle > b.angle)
	
	var sorted := []
	for item in angles:
		sorted.append(vertices[item.index])
	
	return sorted
