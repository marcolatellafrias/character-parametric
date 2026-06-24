# res://utils/debug_utils.gd
class_name DebugUtil


static func create_debug_cone(color: Color, length: float, radius: float, segments: int = 32) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in segments:
		var a0 := TAU * float(i)     / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, length)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, length)
		st.set_color(color); st.add_vertex(Vector3.ZERO)
		st.set_color(color); st.add_vertex(p0)
		st.set_color(color); st.add_vertex(p1)

	var center := Vector3(0, 0, length)
	for i in segments:
		var a0 := TAU * float(i)     / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, length)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, length)
		st.set_color(color); st.add_vertex(center)
		st.set_color(color); st.add_vertex(p1)
		st.set_color(color); st.add_vertex(p0)

	mesh_instance.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = mat
	return mesh_instance

static func create_debug_line(color: Color, length: float, on_top: bool = false, to_down: bool = true) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.01, length, 0.01)
	mesh_instance.mesh = cube
	mesh_instance.position = Vector3(0.0, (-length * 0.5) if to_down else (length * 0.5), 0.0)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	
	if on_top:
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS 
	mesh_instance.material_override = material
	return mesh_instance

static func update_debug_line_mesh(mesh_instance: MeshInstance3D,length: float, to_down: bool = true) -> MeshInstance3D:
	if mesh_instance == null:
		return mesh_instance
	var cube := BoxMesh.new()
	cube.size = Vector3(0.01, length, 0.01)
	mesh_instance.mesh = cube
	mesh_instance.position = Vector3(0.0, (-length * 0.5) if to_down else (length * 0.5), 0.0)
	return mesh_instance
	
static func create_debug_sphere(color: Color, size: float = 0.1, on_top: bool = false, radial_segments: int = 8, rings: int = 8) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = radial_segments
	sphere.rings = rings
	mesh_instance.mesh = sphere
	mesh_instance.scale = Vector3(size, size, size)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if on_top:
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS 
	mesh_instance.material_override = material
	return mesh_instance

static func create_debug_cube(color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cube := BoxMesh.new()
	mesh_instance.mesh = cube
	mesh_instance.scale = Vector3(0.05,0.05,0.05)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh_instance.material_override = material
	return mesh_instance

static func create_debug_capsule(radius: float, height: float, y_offset: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	
	# Crear una cápsula con los parámetros dados
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = height
	mesh_instance.mesh = capsule

	# Crear un material blanco semitransparente
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1, 1, 1, 0.2) # Blanco con opacidad 0.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.flags_transparent = true

	mesh_instance.material_override = material
	mesh_instance.position= Vector3(0,y_offset,0)
	
	return mesh_instance

static func create_debug_ring(color: Color, radius: float, segments: int = 64) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)

	for i in range(segments + 1):
		var angle := TAU * float(i) / float(segments)
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		st.set_color(color)
		st.add_vertex(Vector3(x, 0, z))

	var mesh := st.commit()
	mesh_instance.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.flags_transparent = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material
	return mesh_instance


static func create_debug_ring_mesh(radius: float, segments: int = 64) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINE_STRIP)

	for i in range(segments + 1):
		var angle := TAU * float(i) / float(segments)
		var x := cos(angle) * radius
		var z := sin(angle) * radius
		st.add_vertex(Vector3(x, 0, z))

	var mesh := st.commit()
	return mesh

static func create_debug_disc(color: Color, radius: float, segments: int = 64) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)

		var x1 := cos(angle1) * radius
		var z1 := sin(angle1) * radius
		var x2 := cos(angle2) * radius
		var z2 := sin(angle2) * radius

		st.set_color(color)
		st.add_vertex(Vector3(0, 0, 0)) # centro
		st.set_color(color)
		st.add_vertex(Vector3(x1, 0, z1))
		st.set_color(color)
		st.add_vertex(Vector3(x2, 0, z2))

	var mesh := st.commit()
	mesh_instance.mesh = mesh

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.material_override = material

	return mesh_instance


# Creates a MeshInstance3D cube with axis-colored faces:
#  +X: light red,  -X: dark red
#  +Y: light green,-Y: dark green
#  +Z: light blue, -Z: dark blue
# size can be a float (uniform) or Vector3.
static func create_debug_colored_cube(size, light_amount: float = 0.35) -> MeshInstance3D:
	var s: Vector3 = size if typeof(size) == TYPE_VECTOR3 else Vector3(size, size, size)
	var hx := s.x * 0.5
	var hy := s.y * 0.5
	var hz := s.z * 0.5

	var mesh := ArrayMesh.new()
	var mesh_instance := MeshInstance3D.new()

	# Base colors + shades
	light_amount = clamp(light_amount, 0.0, 0.9)
	var red_pos   := Color(1, 0, 0).lightened(light_amount)
	var red_neg   := Color(1, 0, 0).darkened(light_amount)
	var green_pos := Color(0, 1, 0).lightened(light_amount)
	var green_neg := Color(0, 1, 0).darkened(light_amount)
	var blue_pos  := Color(0, 0, 1).lightened(light_amount)
	var blue_neg  := Color(0, 0, 1).darkened(light_amount)

	# Faces (CCW from outside). Order: +X, -X, +Y, -Y, +Z, -Z
	var faces = [
		{ "n": Vector3( 1, 0, 0), "v": [Vector3( hx,-hy,-hz), Vector3( hx, hy,-hz), Vector3( hx, hy, hz), Vector3( hx,-hy, hz)], "c": red_pos   }, # +X
		{ "n": Vector3(-1, 0, 0), "v": [Vector3(-hx,-hy, hz), Vector3(-hx, hy, hz), Vector3(-hx, hy,-hz), Vector3(-hx,-hy,-hz)], "c": red_neg   }, # -X
		{ "n": Vector3( 0, 1, 0), "v": [Vector3(-hx, hy,-hz), Vector3(-hx, hy, hz), Vector3( hx, hy, hz), Vector3( hx, hy,-hz)], "c": green_pos }, # +Y
		{ "n": Vector3( 0,-1, 0), "v": [Vector3(-hx,-hy, hz), Vector3(-hx,-hy,-hz), Vector3( hx,-hy,-hz), Vector3( hx,-hy, hz)], "c": green_neg }, # -Y
		{ "n": Vector3( 0, 0, 1), "v": [Vector3(-hx,-hy, hz), Vector3( hx,-hy, hz), Vector3( hx, hy, hz), Vector3(-hx, hy, hz)], "c": blue_pos  }, # +Z
		{ "n": Vector3( 0, 0,-1), "v": [Vector3( hx,-hy,-hz), Vector3(-hx,-hy,-hz), Vector3(-hx, hy,-hz), Vector3( hx, hy,-hz)], "c": blue_neg  }  # -Z
	]

	for i in faces.size():
		var f = faces[i]
		var verts: PackedVector3Array = PackedVector3Array(f["v"])
		var norms: PackedVector3Array = PackedVector3Array([f["n"], f["n"], f["n"], f["n"]])
		var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])

		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_INDEX] = indices

		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = f["c"]
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

	mesh_instance.mesh = mesh
	return mesh_instance


static func create_debug_line_to_from(from: Vector3, to: Vector3, color: Color, width: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var cube := BoxMesh.new()
	
	var distance := from.distance_to(to)
	cube.size = Vector3(width, distance, width)
	mesh_instance.mesh = cube
	
	var midpoint := (from + to) / 2.0
	mesh_instance.position = midpoint
	
	# Construir la base manualmente para alinear el eje Y con la dirección
	var direction := (to - from).normalized()
	if direction.length() > 0.001:
		var y_axis = direction
		var x_axis = y_axis.cross(Vector3.UP)
		
		# Si la línea está vertical, usar otro vector de referencia
		if x_axis.length() < 0.001:
			x_axis = y_axis.cross(Vector3.RIGHT)
		
		x_axis = x_axis.normalized()
		var z_axis = x_axis.cross(y_axis).normalized()
		
		# Aplicar la base personalizada
		mesh_instance.basis = Basis(x_axis, y_axis, z_axis)
	
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color

	mesh_instance.material_override = material
	mesh_instance.visibility_range_end = WorldSettings.spawn_radius
	return mesh_instance

static func create_debug_polygon(points: PackedVector3Array, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	
	# Validar que hay al menos 3 puntos
	if points.size() < 3:
		push_error("Se necesitan al menos 3 puntos para crear un polígono")
		return mesh_instance
	
	# Proyectar los puntos 3D al plano XZ (2D) para triangulación
	var points_2d := PackedVector2Array()
	var height := points[0].y  # Todos los puntos deberían tener la misma altura Y
	
	for point in points:
		points_2d.append(Vector2(point.x, point.z))
	
	# Triangular el polígono 2D usando el algoritmo de Godot (maneja polígonos cóncavos)
	var indices := Geometry2D.triangulate_polygon(points_2d)
	
	if indices.is_empty():
		push_error("No se pudo triangular el polígono")
		return mesh_instance
	
	# Crear los arrays para el mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	
	# Los vértices son los puntos 3D originales
	var vertices := points
	
	# Verificar el winding order del primer triángulo para determinar la normal correcta
	var normal := Vector3(0, 1, 0)  # Por defecto, apuntando hacia arriba
	
	if indices.size() >= 3:
		var v0 := points[indices[0]]
		var v1 := points[indices[1]]
		var v2 := points[indices[2]]
		
		var edge1 := v1 - v0
		var edge2 := v2 - v0
		var tri_normal := edge1.cross(edge2)
		
		# Si la normal del primer triángulo apunta hacia abajo, invertir todos los triángulos
		if tri_normal.y < 0:
			# Invertir el orden de los vértices en cada triángulo (swap segundo y tercer índice)
			for i in range(0, indices.size(), 3):
				var temp := indices[i + 1]
				indices[i + 1] = indices[i + 2]
				indices[i + 2] = temp
	
	# Crear las normales (todas apuntando hacia arriba)
	var normals := PackedVector3Array()
	normals.resize(points.size())
	for i in range(points.size()):
		normals[i] = normal
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	mesh_instance.mesh = array_mesh
	
	# Crear y aplicar el material
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Renderizar ambos lados por seguridad
	
	mesh_instance.material_override = material
	
	return mesh_instance
	
static func create_debug_plane(corner1: Vector3, corner2: Vector3, corner3: Vector3, corner4: Vector3, color: Color, transparency: float = 0.0) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	
	# Crear un ArrayMesh personalizado
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	
	# Definir los vértices (4 esquinas)
	var vertices := PackedVector3Array([
		corner1, corner2, corner3, corner4
	])
	
	# Definir los índices para formar dos triángulos
	# Triángulo 1: corner1 -> corner2 -> corner3
	# Triángulo 2: corner1 -> corner3 -> corner4
	var indices := PackedInt32Array([
		0, 1, 2,
		0, 2, 3
	])
	
	# Calcular la normal del plano
	var edge1 := corner2 - corner1
	var edge2 := corner3 - corner1
	var normal := edge1.cross(edge2).normalized()
	
	# Aplicar la misma normal a todos los vértices
	var normals := PackedVector3Array([
		normal, normal, normal, normal
	])
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	mesh_instance.mesh = array_mesh
	
	# Crear y aplicar el material
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	# Aplicar transparencia al color
	var final_color = color
	final_color.a = clamp(1.0 - transparency, 0.0, 1.0)
	material.albedo_color = final_color
	
	# Configurar transparencia si es necesario
	if transparency > 0.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible desde ambos lados

	mesh_instance.material_override = material
	mesh_instance.visibility_range_end = WorldSettings.spawn_radius
	return mesh_instance

static func create_skewed_cube(base_vertices: Array, height: float, color: Color, use_transparency: bool = false) -> MeshInstance3D:
	if base_vertices.size() != 4:
		push_error("Se requieren exactamente 4 vértices para la base")
		return null
	
	var mesh_instance = MeshInstance3D.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var bottom_verts = base_vertices
	var top_verts = []
	
	for i in range(4):
		top_verts.append(bottom_verts[i] + Vector3(0, height, 0))
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()
	
	var add_triangle_with_normal = func(v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3):
		var start_idx = vertices.size()
		vertices.append(v1)
		vertices.append(v2)
		vertices.append(v3)
		normals.append(normal)
		normals.append(normal)
		normals.append(normal)
		indices.append(start_idx)
		indices.append(start_idx + 1)
		indices.append(start_idx + 2)
	
	# Cara inferior (normal hacia abajo)
	var bottom_normal = Vector3(0, -1, 0)
	add_triangle_with_normal.call(bottom_verts[0], bottom_verts[2], bottom_verts[1], bottom_normal)
	add_triangle_with_normal.call(bottom_verts[0], bottom_verts[3], bottom_verts[2], bottom_normal)
	
	# Cara superior (normal hacia arriba)
	var top_normal = Vector3(0, 1, 0)
	add_triangle_with_normal.call(top_verts[0], top_verts[1], top_verts[2], top_normal)
	add_triangle_with_normal.call(top_verts[0], top_verts[2], top_verts[3], top_normal)
	
	# Caras laterales
	for i in range(4):
		var next_i = (i + 1) % 4
		
		# Calcular normal usando los 3 vértices del primer triángulo
		var v1 = bottom_verts[i]
		var v2 = top_verts[next_i]
		var v3 = top_verts[i]
		
		var edge1 = v2 - v1
		var edge2 = v3 - v1
		var face_normal = edge1.cross(edge2).normalized()
		
		# Asegurar que la normal apunte hacia afuera
		var center = (bottom_verts[0] + bottom_verts[1] + bottom_verts[2] + bottom_verts[3]) / 4.0
		var face_center = (v1 + v2 + v3) / 3.0
		var to_outside = (face_center - center).normalized()
		
		if face_normal.dot(to_outside) < 0:
			face_normal = -face_normal
		
		add_triangle_with_normal.call(bottom_verts[i], top_verts[next_i], top_verts[i], face_normal)
		add_triangle_with_normal.call(bottom_verts[i], bottom_verts[next_i], top_verts[next_i], face_normal)
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	st.create_from_arrays(arrays)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	
	if use_transparency:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	st.set_material(material)
	
	mesh_instance.mesh = st.commit()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh_instance.visibility_range_end = WorldSettings.spawn_radius
	return mesh_instance

# Crea un cubo skewed con chamfers en sus edges verticales, especificados en unidades reales.
# 
# base_vertices: Array[Vector3] con 4 vértices del quad base en orden clockwise [BL, BR, TR, TL]
#                (Bottom-Left, Bottom-Right, Top-Right, Top-Left)
# 
# chamfers: Diccionario donde la clave es el índice del vértice (0-3) en orden clockwise
#           y el valor es [c1, c2] expresado en UNIDADES REALES (distancia en el espacio 3D).
#           c1: distancia chamfereada hacia el edge que conecta con el vértice anterior (sentido anti-clockwise)
#           c2: distancia chamfereada hacia el edge que conecta con el vértice siguiente (sentido clockwise)
# 
# NOTA: Acepta vértices en orden clockwise. Internamente invierte el winding order de los
#       triángulos para generar normales correctas que apunten hacia afuera.
# 
# Ejemplo: Si chamfers={0: [0.5, 1.0]}, el edge vertical en el vértice 0 será chamfereado
#          0.5 unidades hacia el vértice 3, y 1.0 unidades hacia el vértice 1.
# 
# Las caras superior e inferior se adaptan automáticamente al contorno resultante (de cuadrado a octágono).
# Si chamfers está vacío o todos los valores son [0, 0], se comporta igual que create_skewed_cube.
static func create_skewed_cube_advanced(base_vertices: Array, height: float, color: Color, chamfers: Dictionary, use_transparency: bool = false) -> MeshInstance3D:
	if base_vertices.size() != 4:
		push_error("Se requieren exactamente 4 vértices para la base")
		return null
	
	var mesh_instance = MeshInstance3D.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var indices = PackedInt32Array()
	
	var add_triangle_with_normal = func(v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3):
		var start_idx = vertices.size()
		vertices.append(v1)
		vertices.append(v2)
		vertices.append(v3)
		normals.append(normal)
		normals.append(normal)
		normals.append(normal)
		indices.append(start_idx)
		indices.append(start_idx + 1)
		indices.append(start_idx + 2)
	
	# Construir vértices del contorno inferior y superior
	var bottom_contour = []
	var top_contour = []
	
	for i in range(4):
		var chamfer = chamfers.get(i, [0, 0])
		var c1 = chamfer[0] if chamfer.size() > 0 else 0
		var c2 = chamfer[1] if chamfer.size() > 1 else 0
		
		var to_prev = (base_vertices[(i - 1 + 4) % 4] - base_vertices[i]).normalized()
		var to_next = (base_vertices[(i + 1) % 4] - base_vertices[i]).normalized()
		
		bottom_contour.append(base_vertices[i] + to_prev * c1)
		top_contour.append(base_vertices[i] + Vector3(0, height, 0) + to_prev * c1)
		
		bottom_contour.append(base_vertices[i] + to_next * c2)
		top_contour.append(base_vertices[i] + Vector3(0, height, 0) + to_next * c2)
	
	# Calcular centros
	var bottom_center = Vector3.ZERO
	for v in bottom_contour:
		bottom_center += v
	bottom_center /= bottom_contour.size()
	
	var top_center = Vector3.ZERO
	for v in top_contour:
		top_center += v
	top_center /= top_contour.size()
	
	# Cara inferior (normal hacia abajo) - INVERTIDO EL WINDING ORDER
	var bottom_normal = Vector3(0, -1, 0)
	for i in range(bottom_contour.size()):
		var next_i = (i + 1) % bottom_contour.size()
		add_triangle_with_normal.call(bottom_center, bottom_contour[i], bottom_contour[next_i], bottom_normal)
	
	# Cara superior (normal hacia arriba) - INVERTIDO EL WINDING ORDER
	var top_normal = Vector3(0, 1, 0)
	for i in range(top_contour.size()):
		var next_i = (i + 1) % top_contour.size()
		add_triangle_with_normal.call(top_center, top_contour[next_i], top_contour[i], top_normal)
	
	# Caras laterales
	var center = Vector3.ZERO
	for v in base_vertices:
		center += v
	center /= 4.0
	
	for i in range(bottom_contour.size()):
		var next_i = (i + 1) % bottom_contour.size()
		
		var v1 = bottom_contour[i]
		var v2 = bottom_contour[next_i]
		var v3 = top_contour[i]
		var v4 = top_contour[next_i]
		
		var edge1 = v2 - v1
		var edge2 = v3 - v1
		var face_normal = edge1.cross(edge2).normalized()
		
		var face_center = (v1 + v2 + v3 + v4) / 4.0
		var to_outside = (face_center - center).normalized()
		
		if face_normal.dot(to_outside) < 0:
			face_normal = -face_normal
		
		# INVERTIDO EL WINDING ORDER
		add_triangle_with_normal.call(v1, v3, v2, face_normal)
		add_triangle_with_normal.call(v2, v3, v4, face_normal)
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	
	st.create_from_arrays(arrays)
	
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	
	if use_transparency:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	st.set_material(material)
	
	mesh_instance.mesh = st.commit()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh_instance.visibility_range_end = WorldSettings.spawn_radius
	return mesh_instance

# Crea un cubo skewed con chamfers en sus edges verticales, especificados en unidades de grid.
# 
# base_vertices: Array[Vector3] con 4 vértices del quad base en orden clockwise [BL, BR, TR, TL]
#                (Bottom-Left, Bottom-Right, Top-Right, Top-Left)
# 
# rows: Número de divisiones para los edges impares (1 y 3 - east/west) en orden clockwise.
# columns: Número de divisiones para los edges pares (0 y 2 - north/south) en orden clockwise.
# 
# chamfers: Diccionario donde la clave es el índice del vértice (0-3) en orden clockwise
#           y el valor es [c1, c2] expresado en NÚMERO DE CELDAS del grid, no en unidades reales.
#           c1: celdas chamfereadas hacia el edge que conecta con el vértice anterior
#           c2: celdas chamfereadas hacia el edge que conecta con el vértice siguiente
#           Los edges pares (0, 2) usan 'columns' para calcular el tamaño de celda.
#           Los edges impares (1, 3) usan 'rows' para calcular el tamaño de celda.
# 
# NOTA: Acepta vértices en orden clockwise. Internamente convierte chamfers de unidades de grid
#       a unidades reales y delega a create_skewed_cube_advanced para la generación del mesh.
# 
# Ejemplo: Si rows=6, columns=4, y chamfers={0: [1, 2]}, el edge vertical en v0
#          será chamfereado 1/6 del edge 3 hacia v3, y 2/4 del edge 0 hacia v1.
# 
# Si chamfers está vacío o todos los valores son [0, 0], se comporta igual que create_skewed_cube.
static func create_skewed_cube_advanced_grid(base_vertices: Array, height: float, color: Color, chamfers: Dictionary, rows: int, columns: int, use_transparency: bool = false) -> MeshInstance3D:
	if base_vertices.size() != 4:
		push_error("Se requieren exactamente 4 vértices para la base")
		return null
	
	if rows <= 0 or columns <= 0:
		push_error("rows y columns deben ser mayores que 0")
		return null
	
	# Convertir chamfers de celdas a unidades reales
	var real_chamfers = {}
	
	for i in range(4):
		if chamfers.has(i):
			var chamfer_cells = chamfers[i]
			var c1_cells = chamfer_cells[0] if chamfer_cells.size() > 0 else 0
			var c2_cells = chamfer_cells[1] if chamfer_cells.size() > 1 else 0
			
			var prev_i = (i - 1 + 4) % 4
			var edge_prev_length = base_vertices[i].distance_to(base_vertices[prev_i])
			var divisions_prev = rows if prev_i % 2 == 1 else columns
			var cell_size_prev = edge_prev_length / float(divisions_prev)
			
			var next_i = (i + 1) % 4
			var edge_next_length = base_vertices[i].distance_to(base_vertices[next_i])
			var divisions_next = rows if i % 2 == 1 else columns
			var cell_size_next = edge_next_length / float(divisions_next)
			
			var c1_real = c1_cells * cell_size_prev
			var c2_real = c2_cells * cell_size_next
			
			real_chamfers[i] = [c1_real, c2_real]
	
	return create_skewed_cube_advanced(base_vertices, height, color, real_chamfers, use_transparency)

# Crea un StaticBody3D con collider que coincide con la forma de create_skewed_cube_advanced_grid.
# 
# base_vertices: Array[Vector3] con 4 vértices del quad base en orden clockwise [BL, BR, TR, TL]
#                (Bottom-Left, Bottom-Right, Top-Right, Top-Left)
# 
# rows: Número de divisiones para los edges impares (1 y 3 - east/west) en orden clockwise.
# columns: Número de divisiones para los edges pares (0 y 2 - north/south) en orden clockwise.
# 
# chamfers: Mismo formato que en create_skewed_cube_advanced_grid. Diccionario donde la clave
#           es el índice del vértice (0-3) en orden clockwise y el valor es [c1, c2] en celdas.
# 
# NOTA: Acepta vértices en orden clockwise. Genera un ConvexPolygonShape3D que coincide exactamente
#       con la geometría visual producida por create_skewed_cube_advanced_grid.
# 
# Retorna un StaticBody3D con el CollisionShape3D ya configurado.
static func create_skewed_cube_advanced_grid_collider(base_vertices: Array, height: float, chamfers: Dictionary, rows: int, columns: int) -> StaticBody3D:
	if base_vertices.size() != 4:
		push_error("Se requieren exactamente 4 vértices para la base")
		return null
	
	if rows <= 0 or columns <= 0:
		push_error("rows y columns deben ser mayores que 0")
		return null
	
	# Convertir chamfers de celdas a unidades reales
	var real_chamfers = {}
	
	for i in range(4):
		if chamfers.has(i):
			var chamfer_cells = chamfers[i]
			var c1_cells = chamfer_cells[0] if chamfer_cells.size() > 0 else 0
			var c2_cells = chamfer_cells[1] if chamfer_cells.size() > 1 else 0
			
			var prev_i = (i - 1 + 4) % 4
			var edge_prev_length = base_vertices[i].distance_to(base_vertices[prev_i])
			var divisions_prev = rows if prev_i % 2 == 1 else columns
			var cell_size_prev = edge_prev_length / float(divisions_prev)
			
			var next_i = (i + 1) % 4
			var edge_next_length = base_vertices[i].distance_to(base_vertices[next_i])
			var divisions_next = rows if i % 2 == 1 else columns
			var cell_size_next = edge_next_length / float(divisions_next)
			
			var c1_real = c1_cells * cell_size_prev
			var c2_real = c2_cells * cell_size_next
			
			real_chamfers[i] = [c1_real, c2_real]
	
	# Construir vértices del contorno
	var bottom_contour = []
	var top_contour = []
	
	for i in range(4):
		var chamfer = real_chamfers.get(i, [0, 0])
		var c1 = chamfer[0] if chamfer.size() > 0 else 0
		var c2 = chamfer[1] if chamfer.size() > 1 else 0
		
		var to_prev = (base_vertices[(i - 1 + 4) % 4] - base_vertices[i]).normalized()
		var to_next = (base_vertices[(i + 1) % 4] - base_vertices[i]).normalized()
		
		bottom_contour.append(base_vertices[i] + to_prev * c1)
		top_contour.append(base_vertices[i] + Vector3(0, height, 0) + to_prev * c1)
		
		bottom_contour.append(base_vertices[i] + to_next * c2)
		top_contour.append(base_vertices[i] + Vector3(0, height, 0) + to_next * c2)
	
	# Crear array de puntos para ConvexPolygonShape3D
	var points = PackedVector3Array()
	
	for v in bottom_contour:
		points.append(v)
	for v in top_contour:
		points.append(v)
	
	# Crear el shape convexo
	var shape = ConvexPolygonShape3D.new()
	shape.points = points
	
	# Crear collision shape
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = shape
	
	# Crear static body
	var static_body = StaticBody3D.new()
	static_body.add_child(collision_shape)
	
	return static_body

static func create_debug_arrow_to_from(from: Vector3, to: Vector3, color: Color, width: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var array_mesh := ArrayMesh.new()
	
	var distance := from.distance_to(to)
	var cone_height := width * 4.0
	var line_length := distance - cone_height
	
	# Crear la línea (cilindro)
	var cylinder := BoxMesh.new()
	cylinder.size = Vector3(width, line_length, width)
	
	# Crear el cono
	var cone := ArrayMesh.new()
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	
	var cone_base_radius := width * 2.0
	var segments := 16
	
	# Vértice superior del cono (en la punta)
	vertices.append(Vector3(0, cone_height, 0))
	
	# Vértices de la base del cono
	for i in range(segments):
		var angle := (float(i) / segments) * TAU
		var x := cos(angle) * cone_base_radius
		var z := sin(angle) * cone_base_radius
		vertices.append(Vector3(x, 0, z))
	
	# Triángulos del cono
	for i in range(segments):
		var next := (i + 1) % segments
		indices.append(0)
		indices.append(i + 1)
		indices.append(next + 1)
	
	# Base del cono
	for i in range(1, segments - 1):
		indices.append(1)
		indices.append(i + 1)
		indices.append(i + 2)
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	
	cone.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	# Combinar meshes con offset correcto
	var st := SurfaceTool.new()
	# Cilindro centrado en -cone_height/2 para que vaya de -distance/2 a distance/2 - cone_height
	st.append_from(cylinder, 0, Transform3D(Basis.IDENTITY, Vector3(0, -cone_height / 2.0, 0)))
	# Cono desde distance/2 - cone_height hasta distance/2
	st.append_from(cone, 0, Transform3D(Basis.IDENTITY, Vector3(0, distance / 2.0 - cone_height, 0)))
	array_mesh = st.commit()
	
	mesh_instance.mesh = array_mesh
	
	var midpoint := (from + to) / 2.0
	mesh_instance.position = midpoint
	
	var direction := (to - from).normalized()
	if direction.length() > 0.001:
		var y_axis = direction
		var x_axis = y_axis.cross(Vector3.UP)
		
		if x_axis.length() < 0.001:
			x_axis = y_axis.cross(Vector3.RIGHT)
		
		x_axis = x_axis.normalized()
		var z_axis = x_axis.cross(y_axis).normalized()
		
		mesh_instance.basis = Basis(x_axis, y_axis, z_axis)
	
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	
	mesh_instance.material_override = material
	return mesh_instance


static func create_skewed_cube_collider(base_vertices: Array, height: float) -> StaticBody3D:
	if base_vertices.size() != 4:
		push_error("Se requieren exactamente 4 vértices para la base")
		return null
	
	var static_body = StaticBody3D.new()
	var collision_shape = CollisionShape3D.new()
	
	var bottom_verts = base_vertices
	var top_verts = []
	
	for i in range(4):
		top_verts.append(bottom_verts[i] + Vector3(0, height, 0))
	
	# Crear array de vértices para ConvexPolygonShape3D
	var points = PackedVector3Array()
	
	# Agregar vértices inferiores
	for v in bottom_verts:
		points.append(v)
	
	# Agregar vértices superiores
	for v in top_verts:
		points.append(v)
	
	# Crear el shape convexo
	var convex_shape = ConvexPolygonShape3D.new()
	convex_shape.points = points
	
	collision_shape.shape = convex_shape
	static_body.add_child(collision_shape)
	
	return static_body

static func create_skewed_cube_debug(base_vertices: Array, height: float, color: Color, face_index: int) -> MeshInstance3D:
	if base_vertices.size() != 4:
		push_error("Se requieren exactamente 4 vértices para la base")
		return null
	
	if face_index < 0 or face_index > 5:
		push_error("face_index debe estar entre 0 y 5")
		return null
	
	var mesh_instance = MeshInstance3D.new()
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var bottom_verts = base_vertices
	var top_verts = []
	
	for i in range(4):
		top_verts.append(bottom_verts[i] + Vector3(0, height, 0))
	
	# Calcular cara opuesta
	var opposite_face = 1 - face_index if face_index < 2 else 6 - face_index
	
	# Colores transparentes
	var transparent_color = Color(color.r, color.g, color.b, 0.5)
	var transparent_green = Color(0.0, 1.0, 0.0, 0.5)
	var transparent_red = Color(1.0, 0.0, 0.0, 0.5)
	
	var current_face = 0
	
	var add_triangle = func(v1: Vector3, v2: Vector3, v3: Vector3, normal: Vector3, face_color: Color):
		st.set_normal(normal)
		st.set_color(face_color)
		st.add_vertex(v1)
		st.set_normal(normal)
		st.set_color(face_color)
		st.add_vertex(v2)
		st.set_normal(normal)
		st.set_color(face_color)
		st.add_vertex(v3)
	
	# Cara inferior (face 0)
	var bottom_normal = Vector3(0, -1, 0)
	var bottom_color = transparent_green if current_face == face_index else (transparent_red if current_face == opposite_face else transparent_color)
	add_triangle.call(bottom_verts[0], bottom_verts[2], bottom_verts[1], bottom_normal, bottom_color)
	add_triangle.call(bottom_verts[0], bottom_verts[3], bottom_verts[2], bottom_normal, bottom_color)
	current_face += 1
	
	# Cara superior (face 1)
	var top_normal = Vector3(0, 1, 0)
	var top_color = transparent_green if current_face == face_index else (transparent_red if current_face == opposite_face else transparent_color)
	add_triangle.call(top_verts[0], top_verts[1], top_verts[2], top_normal, top_color)
	add_triangle.call(top_verts[0], top_verts[2], top_verts[3], top_normal, top_color)
	current_face += 1
	
	# Caras laterales (faces 2-5)
	for i in range(4):
		var next_i = (i + 1) % 4
		
		var v1 = bottom_verts[i]
		var v2 = top_verts[next_i]
		var v3 = top_verts[i]
		
		var edge1 = v2 - v1
		var edge2 = v3 - v1
		var face_normal = edge1.cross(edge2).normalized()
		
		var center = (bottom_verts[0] + bottom_verts[1] + bottom_verts[2] + bottom_verts[3]) / 4.0
		var face_center = (v1 + v2 + v3) / 3.0
		var to_outside = (face_center - center).normalized()
		
		if face_normal.dot(to_outside) < 0:
			face_normal = -face_normal
		
		var side_color = transparent_green if current_face == face_index else (transparent_red if current_face == opposite_face else transparent_color)
		add_triangle.call(bottom_verts[i], top_verts[next_i], top_verts[i], face_normal, side_color)
		add_triangle.call(bottom_verts[i], bottom_verts[next_i], top_verts[next_i], face_normal, side_color)
		current_face += 1
	
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	
	# Configuración de transparencia
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	
	st.set_material(material)
	
	mesh_instance.mesh = st.commit()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	return mesh_instance


static func create_debug_cylinder(color: Color, radius: float, height: float, segments: int = 16) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Caras laterales
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)
		
		var x1 := cos(angle1) * radius
		var z1 := sin(angle1) * radius
		var x2 := cos(angle2) * radius
		var z2 := sin(angle2) * radius
		
		# Quad lateral (2 triángulos)
		st.set_color(color)
		st.add_vertex(Vector3(x1, 0, z1))
		st.set_color(color)
		st.add_vertex(Vector3(x1, height, z1))
		st.set_color(color)
		st.add_vertex(Vector3(x2, height, z2))
		
		st.set_color(color)
		st.add_vertex(Vector3(x1, 0, z1))
		st.set_color(color)
		st.add_vertex(Vector3(x2, height, z2))
		st.set_color(color)
		st.add_vertex(Vector3(x2, 0, z2))
	
	var mesh := st.commit()
	mesh_instance.mesh = mesh
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	
	return mesh_instance
	
# DebugUtil - Función para agregar

static func create_debug_ring_volume(color: Color, outer_radius: float, inner_radius: float, height: float, segments: int = 16) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Cara exterior del anillo
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)
		
		var x1 := cos(angle1) * outer_radius
		var z1 := sin(angle1) * outer_radius
		var x2 := cos(angle2) * outer_radius
		var z2 := sin(angle2) * outer_radius
		
		# Quad lateral exterior (2 triángulos)
		st.set_color(color)
		st.add_vertex(Vector3(x1, 0, z1))
		st.set_color(color)
		st.add_vertex(Vector3(x1, height, z1))
		st.set_color(color)
		st.add_vertex(Vector3(x2, height, z2))
		
		st.set_color(color)
		st.add_vertex(Vector3(x1, 0, z1))
		st.set_color(color)
		st.add_vertex(Vector3(x2, height, z2))
		st.set_color(color)
		st.add_vertex(Vector3(x2, 0, z2))
	
	# Cara interior del anillo (invertida)
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)
		
		var x1 := cos(angle1) * inner_radius
		var z1 := sin(angle1) * inner_radius
		var x2 := cos(angle2) * inner_radius
		var z2 := sin(angle2) * inner_radius
		
		# Quad lateral interior invertido (2 triángulos)
		st.set_color(color)
		st.add_vertex(Vector3(x1, 0, z1))
		st.set_color(color)
		st.add_vertex(Vector3(x2, height, z2))
		st.set_color(color)
		st.add_vertex(Vector3(x1, height, z1))
		
		st.set_color(color)
		st.add_vertex(Vector3(x1, 0, z1))
		st.set_color(color)
		st.add_vertex(Vector3(x2, 0, z2))
		st.set_color(color)
		st.add_vertex(Vector3(x2, height, z2))
	
	# Tapa inferior del anillo
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)
		
		var x1_outer := cos(angle1) * outer_radius
		var z1_outer := sin(angle1) * outer_radius
		var x2_outer := cos(angle2) * outer_radius
		var z2_outer := sin(angle2) * outer_radius
		
		var x1_inner := cos(angle1) * inner_radius
		var z1_inner := sin(angle1) * inner_radius
		var x2_inner := cos(angle2) * inner_radius
		var z2_inner := sin(angle2) * inner_radius
		
		# Quad de tapa inferior (2 triángulos)
		st.set_color(color)
		st.add_vertex(Vector3(x1_outer, 0, z1_outer))
		st.set_color(color)
		st.add_vertex(Vector3(x2_outer, 0, z2_outer))
		st.set_color(color)
		st.add_vertex(Vector3(x1_inner, 0, z1_inner))
		
		st.set_color(color)
		st.add_vertex(Vector3(x2_outer, 0, z2_outer))
		st.set_color(color)
		st.add_vertex(Vector3(x2_inner, 0, z2_inner))
		st.set_color(color)
		st.add_vertex(Vector3(x1_inner, 0, z1_inner))
	
	# Tapa superior del anillo
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)
		
		var x1_outer := cos(angle1) * outer_radius
		var z1_outer := sin(angle1) * outer_radius
		var x2_outer := cos(angle2) * outer_radius
		var z2_outer := sin(angle2) * outer_radius
		
		var x1_inner := cos(angle1) * inner_radius
		var z1_inner := sin(angle1) * inner_radius
		var x2_inner := cos(angle2) * inner_radius
		var z2_inner := sin(angle2) * inner_radius
		
		# Quad de tapa superior (2 triángulos)
		st.set_color(color)
		st.add_vertex(Vector3(x1_outer, height, z1_outer))
		st.set_color(color)
		st.add_vertex(Vector3(x1_inner, height, z1_inner))
		st.set_color(color)
		st.add_vertex(Vector3(x2_outer, height, z2_outer))
		
		st.set_color(color)
		st.add_vertex(Vector3(x2_outer, height, z2_outer))
		st.set_color(color)
		st.add_vertex(Vector3(x1_inner, height, z1_inner))
		st.set_color(color)
		st.add_vertex(Vector3(x2_inner, height, z2_inner))
	
	var mesh := st.commit()
	mesh_instance.mesh = mesh
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	
	return mesh_instance


static func create_cylinder_colliders(radius: float, height: float, segments: int = 16) -> Array[CollisionShape3D]:
	var colliders: Array[CollisionShape3D] = []
	
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)
		
		var x1 := cos(angle1) * radius
		var z1 := sin(angle1) * radius
		var x2 := cos(angle2) * radius
		var z2 := sin(angle2) * radius
		
		# Centro del segmento
		var center_x := (x1 + x2) / 2.0
		var center_z := (z1 + z2) / 2.0
		
		# Dimensiones del box
		var segment_width := Vector2(x1, z1).distance_to(Vector2(x2, z2))
		var segment_depth := radius * 0.15  # Profundidad aproximada
		
		var collision_shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(segment_width, height, segment_depth)
		collision_shape.shape = box_shape
		
		# Posicionar y rotar
		var angle_mid := (angle1 + angle2) / 2.0
		collision_shape.position = Vector3(center_x, height / 2.0, center_z)
		collision_shape.rotation.y = angle_mid
		
		colliders.append(collision_shape)
	
	return colliders

static func create_ring_volume_colliders(outer_radius: float, inner_radius: float, height: float, segments: int = 16) -> Array[CollisionShape3D]:
	var colliders: Array[CollisionShape3D] = []
	var ring_thickness := outer_radius - inner_radius
	var ring_mid_radius := (outer_radius + inner_radius) / 2.0
	
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)
		var angle_mid := (angle1 + angle2) / 2.0
		
		# Posición en el radio medio del anillo
		var x := cos(angle_mid) * ring_mid_radius
		var z := sin(angle_mid) * ring_mid_radius
		
		# Ancho del segmento en el arco
		var segment_width := ring_mid_radius * TAU / float(segments)
		
		var collision_shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(segment_width, height, ring_thickness)
		collision_shape.shape = box_shape
		
		collision_shape.position = Vector3(x, height / 2.0, z)
		collision_shape.rotation.y = angle_mid
		
		colliders.append(collision_shape)
	
	return colliders

static func _quad_outward_normal(a: Vector3, b: Vector3, c: Vector3, d: Vector3, mesh_center: Vector3) -> Vector3:
	var n = (b - a).cross(c - a).normalized()
	var face_center = (a + b + c + d) * 0.25
	if n.dot(face_center - mesh_center) < 0:
		n = -n
	return n

static func _add_quad_normals(normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, mesh_center: Vector3) -> void:
	var n = _quad_outward_normal(a, b, c, d, mesh_center)
	normals.append(n)
	normals.append(n)
	normals.append(n)
	normals.append(n)

static func _add_quad(
	verts: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array,
	a: Vector3, b: Vector3, c: Vector3, d: Vector3,
	mesh_center: Vector3
) -> void:
	var n = (b - a).cross(c - a)
	var face_center = (a + b + c + d) * 0.25
	if n.dot(face_center - mesh_center) > 0.0:
		var tmp = b; b = d; d = tmp
	_add_quad_to_arrays(verts, indices, a, b, c, d)
	_add_quad_normals(normals, a, b, c, d, mesh_center)

# Construye un cubo deformado a partir de dos quads (plano frontal y trasero).
#
# Orden de vértices esperado para cada plano:
#
#   [3] top-left ---- [2] top-right
#        |                  |
#   [0] bot-left ---- [1] bot-right
#
# El winding y las normales se auto-corrigen contra el centroide del mesh,
# por lo que el orden de vértices puede ser CW o CCW — no importa.
static func create_skewed_cube_from_planes(
	plane1_vertices: Array,
	plane2_vertices: Array,
	color: Color,
	alpha: float
) -> MeshInstance3D:
	if plane1_vertices.size() != 4 or plane2_vertices.size() != 4:
		push_error("create_skewed_cube_from_planes requiere 4 vértices por plano")
		return null
	var p1 := plane1_vertices
	var p2 := plane2_vertices
	var mesh_center = Vector3.ZERO
	for v in p1: mesh_center += v
	for v in p2: mesh_center += v
	mesh_center /= 8.0
	var mesh_instance = MeshInstance3D.new()
	var array_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	var mesh_vertices = PackedVector3Array()
	var mesh_normals  = PackedVector3Array()
	var mesh_indices  = PackedInt32Array()
	# Plane 1 (cara frontal)
	_add_quad(mesh_vertices, mesh_indices, mesh_normals,
		p1[0], p1[1], p1[2], p1[3], mesh_center)
	# Plane 2 (cara trasera)
	_add_quad(mesh_vertices, mesh_indices, mesh_normals,
		p2[3], p2[2], p2[1], p2[0], mesh_center)
	# Bottom face
	_add_quad(mesh_vertices, mesh_indices, mesh_normals,
		p1[0], p2[0], p2[1], p1[1], mesh_center)
	# Top face
	_add_quad(mesh_vertices, mesh_indices, mesh_normals,
		p1[3], p1[2], p2[2], p2[3], mesh_center)
	# Left face
	_add_quad(mesh_vertices, mesh_indices, mesh_normals,
		p1[0], p1[3], p2[3], p2[0], mesh_center)
	# Right face
	_add_quad(mesh_vertices, mesh_indices, mesh_normals,
		p1[1], p2[1], p2[2], p1[2], mesh_center)
	arrays[Mesh.ARRAY_VERTEX] = mesh_vertices
	arrays[Mesh.ARRAY_NORMAL] = mesh_normals
	arrays[Mesh.ARRAY_INDEX]  = mesh_indices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = array_mesh
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh_instance.material_override = material
	mesh_instance.visibility_range_end = WorldSettings.spawn_radius
	return mesh_instance

# Función helper para agregar un quad a los arrays de mesh
static func _add_quad_to_arrays(
	vertices: PackedVector3Array, 
	indices: PackedInt32Array,
	v1: Vector3, v2: Vector3, v3: Vector3, v4: Vector3
) -> void:
	var start_idx = vertices.size()
	
	vertices.append(v1)
	vertices.append(v2)
	vertices.append(v3)
	vertices.append(v4)
	
	# Primer triángulo
	indices.append(start_idx + 0)
	indices.append(start_idx + 1)
	indices.append(start_idx + 2)
	
	# Segundo triángulo
	indices.append(start_idx + 0)
	indices.append(start_idx + 2)
	indices.append(start_idx + 3)

# DebugUtil.gd - Agregar este método estático

static func create_collision_shape_from_plane(plane_vertices: Array) -> CollisionShape3D:
	if plane_vertices.size() != 4:
		push_error("create_collision_shape_from_plane requiere exactamente 4 vértices")
		return null
	
	# Calcular la normal del plano
	var v1 = plane_vertices[1] - plane_vertices[0]
	var v2 = plane_vertices[3] - plane_vertices[0]
	var normal = v1.cross(v2).normalized()
	
	# Crear un grosor pequeño para que tenga colisión en ambas direcciones
	var thickness = 0.5
	var half_thickness = thickness * 0.5
	
	var points = PackedVector3Array()
	
	# Cara frontal (offset positivo)
	for vertex in plane_vertices:
		points.append(vertex + normal * half_thickness)
	
	# Cara trasera (offset negativo)
	for vertex in plane_vertices:
		points.append(vertex - normal * half_thickness)
	
	# Crear el ConvexPolygonShape3D con 8 puntos (plano con grosor)
	var convex_shape = ConvexPolygonShape3D.new()
	convex_shape.points = points
	
	# Crear el CollisionShape3D
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = convex_shape
	
	return collision_shape

# Crea un CollisionShape3D (convex) a partir de dos planos paralelos
# plane1_vertices: Array de 4 Vector3 representando el primer plano [v1_base, v2_base, v3_top, v4_top]
# plane2_vertices: Array de 4 Vector3 representando el segundo plano [v1_base, v2_base, v3_top, v4_top]
# Retorna: CollisionShape3D con ConvexPolygonShape3D
static func create_collision_shape_from_planes(
	plane1_vertices: Array,
	plane2_vertices: Array
) -> CollisionShape3D:
	
	if plane1_vertices.size() != 4 or plane2_vertices.size() != 4:
		push_error("create_collision_shape_from_planes requiere 4 vértices por plano")
		return null
	
	var points = PackedVector3Array()
	
	# Agregar los 4 vértices del primer plano
	for v in plane1_vertices:
		points.append(v)
	
	# Agregar los 4 vértices del segundo plano
	for v in plane2_vertices:
		points.append(v)
	
	# Crear la forma convexa
	var convex_shape = ConvexPolygonShape3D.new()
	convex_shape.points = points
	
	# Crear el CollisionShape3D
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = convex_shape
	
	return collision_shape

static func create_debug_ring_volume_wireframe(color: Color, outer_radius: float, inner_radius: float, height: float, segments: int = 16) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var half_height = height / 2.0
	
	# Generar vértices para cada segmento
	for i in range(segments):
		var angle1 := TAU * float(i) / float(segments)
		var angle2 := TAU * float(i + 1) / float(segments)
		
		var cos1 := cos(angle1)
		var sin1 := sin(angle1)
		var cos2 := cos(angle2)
		var sin2 := sin(angle2)
		
		# Vértices del segmento
		var inner_bottom_1 := Vector3(cos1 * inner_radius, -half_height, sin1 * inner_radius)
		var inner_bottom_2 := Vector3(cos2 * inner_radius, -half_height, sin2 * inner_radius)
		var inner_top_1 := Vector3(cos1 * inner_radius, half_height, sin1 * inner_radius)
		var inner_top_2 := Vector3(cos2 * inner_radius, half_height, sin2 * inner_radius)
		
		var outer_bottom_1 := Vector3(cos1 * outer_radius, -half_height, sin1 * outer_radius)
		var outer_bottom_2 := Vector3(cos2 * outer_radius, -half_height, sin2 * outer_radius)
		var outer_top_1 := Vector3(cos1 * outer_radius, half_height, sin1 * outer_radius)
		var outer_top_2 := Vector3(cos2 * outer_radius, half_height, sin2 * outer_radius)
		
		# Anillo inferior (bottom ring)
		st.set_color(color)
		st.add_vertex(inner_bottom_1)
		st.set_color(color)
		st.add_vertex(outer_bottom_1)
		st.set_color(color)
		st.add_vertex(outer_bottom_2)
		
		st.set_color(color)
		st.add_vertex(inner_bottom_1)
		st.set_color(color)
		st.add_vertex(outer_bottom_2)
		st.set_color(color)
		st.add_vertex(inner_bottom_2)
		
		# Anillo superior (top ring)
		st.set_color(color)
		st.add_vertex(inner_top_1)
		st.set_color(color)
		st.add_vertex(inner_top_2)
		st.set_color(color)
		st.add_vertex(outer_top_2)
		
		st.set_color(color)
		st.add_vertex(inner_top_1)
		st.set_color(color)
		st.add_vertex(outer_top_2)
		st.set_color(color)
		st.add_vertex(outer_top_1)
		
		# Cara lateral exterior
		st.set_color(color)
		st.add_vertex(outer_bottom_1)
		st.set_color(color)
		st.add_vertex(outer_top_1)
		st.set_color(color)
		st.add_vertex(outer_top_2)
		
		st.set_color(color)
		st.add_vertex(outer_bottom_1)
		st.set_color(color)
		st.add_vertex(outer_top_2)
		st.set_color(color)
		st.add_vertex(outer_bottom_2)
		
		# Cara lateral interior (invertida para que la normal apunte hacia afuera del anillo)
		st.set_color(color)
		st.add_vertex(inner_bottom_1)
		st.set_color(color)
		st.add_vertex(inner_bottom_2)
		st.set_color(color)
		st.add_vertex(inner_top_2)
		
		st.set_color(color)
		st.add_vertex(inner_bottom_1)
		st.set_color(color)
		st.add_vertex(inner_top_2)
		st.set_color(color)
		st.add_vertex(inner_top_1)
	
	var mesh := st.commit()
	mesh_instance.mesh = mesh
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = material
	
	return mesh_instance
	
static func create_debug_path3d(
	points: Array,  # Array de Dictionary con {pos: Vector3, in: Vector3, out: Vector3}
	segments_per_curve: int,
	color: Color,
	width: float
) -> MeshInstance3D:
	var curve := Curve3D.new()
	
	# Construir el Curve3D con los puntos y control points
	for point_data in points:
		curve.add_point(
			point_data.pos,
			point_data.get("in", Vector3.ZERO),
			point_data.get("out", Vector3.ZERO)
		)
	
	# Muestrear la curva
	var total_segments = (points.size() - 1) * segments_per_curve
	var sampled_points: Array[Vector3] = []
	
	for i in range(total_segments + 1):
		var offset = curve.get_baked_length() * (float(i) / total_segments)
		sampled_points.append(curve.sample_baked(offset))
	
	# Crear mesh combinado
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	var vertices: PackedVector3Array = []
	var indices: PackedInt32Array = []
	
	# Generar geometría de cilindros para cada segmento
	var vertex_offset = 0
	for i in range(sampled_points.size() - 1):
		var from = sampled_points[i]
		var to = sampled_points[i + 1]
		var direction = (to - from).normalized()
		var distance = from.distance_to(to)
		
		if distance < 0.001:
			continue
		
		# Crear base para orientar el cilindro
		var y_axis = direction
		var x_axis = y_axis.cross(Vector3.UP)
		if x_axis.length() < 0.001:
			x_axis = y_axis.cross(Vector3.RIGHT)
		x_axis = x_axis.normalized()
		var z_axis = x_axis.cross(y_axis).normalized()
		var basis = Basis(x_axis, y_axis, z_axis)
		
		# 8 vértices del cubo (box) para este segmento
		var half_width = width * 0.5
		var local_verts = [
			Vector3(-half_width, 0, -half_width),
			Vector3(half_width, 0, -half_width),
			Vector3(half_width, 0, half_width),
			Vector3(-half_width, 0, half_width),
			Vector3(-half_width, distance, -half_width),
			Vector3(half_width, distance, -half_width),
			Vector3(half_width, distance, half_width),
			Vector3(-half_width, distance, half_width)
		]
		
		# Transformar y agregar vértices
		for v in local_verts:
			var transformed = from + basis * v
			vertices.append(transformed)
		
		# Índices para las caras del cubo
		var faces = [
			[0,1,2, 0,2,3], # Bottom
			[4,6,5, 4,7,6], # Top
			[0,4,5, 0,5,1], # Front
			[1,5,6, 1,6,2], # Right
			[2,6,7, 2,7,3], # Back
			[3,7,4, 3,4,0]  # Left
		]
		
		for face in faces:
			for idx in face:
				indices.append(vertex_offset + idx)
		
		vertex_offset += 8
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = array_mesh
	
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh_instance.material_override = material
	
	return mesh_instance

# En DebugUtil - versión actualizada
static func create_debug_sphere_2dprint(grid_coords: Vector2i, color: Color, size: float = 0.1, on_top: bool = false, radial_segments: int = 4, rings: int = 4) -> Node3D:
	var container := Node3D.new()

	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = radial_segments
	sphere.rings = rings
	mesh_instance.mesh = sphere
	mesh_instance.scale = Vector3(size, size, size)

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if on_top:
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mesh_instance.material_override = material

	container.add_child(mesh_instance)

	var label := Label3D.new()
	label.text = "[%d, %d]" % [grid_coords.x, grid_coords.y]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 16
	label.outline_size = 4
	label.outline_modulate = Color.BLACK
	label.modulate = Color.WHITE
	label.no_depth_test = true
	label.position = Vector3(0, size * 1.5, 0)

	container.add_child(label)

	return container

static func create_debug_sphere_3dprint(grid_coords: Vector3i, color: Color, size: float = 0.1, on_top: bool = false, radial_segments: int = 4, rings: int = 4) -> Node3D:
	var container := Node3D.new()
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = radial_segments
	sphere.rings = rings
	mesh_instance.mesh = sphere
	mesh_instance.scale = Vector3(size, size, size)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.5
	if on_top:
		material.no_depth_test = true
		material.render_priority = 1
	mesh_instance.material_override = material
	container.add_child(mesh_instance)
	var label := Label3D.new()
	label.text = "[%d, %d, %d]" % [grid_coords.x, grid_coords.y, grid_coords.z]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 16
	label.outline_size = 4
	label.outline_modulate = Color.BLACK
	label.modulate = Color.WHITE
	label.no_depth_test = true
	label.position = Vector3(0, size * 1.5, 0)
	container.add_child(label)
	return container

static func create_debug_sphere_print_int(value: int, color: Color, size: float = 0.1, on_top: bool = false, radial_segments: int = 4, rings: int = 4) -> Node3D:
	var container := Node3D.new()
	
	var mesh_instance := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = radial_segments
	sphere.rings = rings
	mesh_instance.mesh = sphere
	mesh_instance.scale = Vector3(size, size, size)
	
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if on_top:
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	mesh_instance.material_override = material
	
	container.add_child(mesh_instance)
	
	var label := Label3D.new()
	label.text = "%d" % value
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.outline_size = 6
	label.outline_modulate = Color.BLACK
	label.modulate = Color.WHITE
	label.position = Vector3(0, size * 1.5, 0)
	
	container.add_child(label)
	
	return container
