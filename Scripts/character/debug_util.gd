# res://utils/debug_utils.gd
class_name DebugUtil

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

static func create_wireframe_cube(color: Color, size: float = 1.0, transparency: float = 0.5) -> Node3D:
	var container := Node3D.new()
	
	# Definir los 8 vértices del cubo
	var half := size / 2.0
	var vertices := [
		Vector3(-half, -half, -half),  # 0
		Vector3(half, -half, -half),   # 1
		Vector3(half, -half, half),    # 2
		Vector3(-half, -half, half),   # 3
		Vector3(-half, half, -half),   # 4
		Vector3(half, half, -half),    # 5
		Vector3(half, half, half),     # 6
		Vector3(-half, half, half)     # 7
	]
	
	# Definir las 12 aristas (pares de vértices)
	var edges := [
		[0, 1], [1, 2], [2, 3], [3, 0],  # Base inferior
		[4, 5], [5, 6], [6, 7], [7, 4],  # Base superior
		[0, 4], [1, 5], [2, 6], [3, 7]   # Columnas verticales
	]
	
	# Crear material semitransparente
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = transparency
	
	# Grosor de las aristas
	var edge_thickness := size * 0.02
	
	# Crear cada arista como un cilindro estirado
	for edge in edges:
		var start: Vector3 = vertices[edge[0]]
		var end: Vector3 = vertices[edge[1]]
		
		var mesh_instance := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = edge_thickness
		cylinder.bottom_radius = edge_thickness
		
		# Calcular longitud y posición
		var length := start.distance_to(end)
		cylinder.height = length
		
		mesh_instance.mesh = cylinder
		mesh_instance.material_override = material
		
		# Posicionar en el punto medio
		mesh_instance.position = (start + end) / 2.0
		
		# Rotar para alinear con la arista
		var direction := (end - start).normalized()
		var up := Vector3.UP
		
		# Evitar problemas cuando la dirección es paralela a UP
		if abs(direction.dot(up)) > 0.99:
			up = Vector3.RIGHT
		
		mesh_instance.look_at(mesh_instance.position + direction, up)
		mesh_instance.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		
		container.add_child(mesh_instance)
	
	return container

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
	
	return mesh_instance

static func create_skewed_cube(base_vertices: Array, height: float, color: Color) -> MeshInstance3D:
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
	var indices = PackedInt32Array()
	
	var add_triangle = func(v1: Vector3, v2: Vector3, v3: Vector3):
		var start_idx = vertices.size()
		vertices.append(v1)
		vertices.append(v2)
		vertices.append(v3)
		indices.append(start_idx)
		indices.append(start_idx + 1)
		indices.append(start_idx + 2)
	
	# Cara inferior (normal hacia abajo, visto desde arriba = CW)
	add_triangle.call(bottom_verts[0], bottom_verts[2], bottom_verts[1])
	add_triangle.call(bottom_verts[0], bottom_verts[3], bottom_verts[2])
	
	# Cara superior (normal hacia arriba, visto desde arriba = CCW)
	add_triangle.call(top_verts[0], top_verts[1], top_verts[2])
	add_triangle.call(top_verts[0], top_verts[2], top_verts[3])
	
	# Caras laterales
	for i in range(4):
		var next_i = (i + 1) % 4
		add_triangle.call(bottom_verts[i], top_verts[next_i], top_verts[i])
		add_triangle.call(bottom_verts[i], bottom_verts[next_i], top_verts[next_i])
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	
	st.create_from_arrays(arrays)
	st.set_color(color)
	st.generate_normals()
	
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_BACK
	st.set_material(material)
	
	mesh_instance.mesh = st.commit()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	return mesh_instance
## Ejemplo de uso:
## var base = [
##     Vector3(0, 0, 0),
##     Vector3(1, 0, 0),
##     Vector3(1, 0, 1),
##     Vector3(0, 0, 1)
## ]
## var cube = DebugUtil.create_skewed_cube(base, 2.0, Color.RED)
## add_child(cube)

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

static func create_building_cube(base_vertices: Array, height: float, color: Color, edge_types: Array[int], is_clockwise: bool) -> MeshInstance3D:
	if base_vertices.size() != 4:
		push_error("Se requieren exactamente 4 vértices para la base")
		return null
	
	if edge_types.size() != 4:
		push_error("Se requieren exactamente 4 tipos de edges [north, east, south, west]")
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
	
	var edge_map: Array[int]
	
	if is_clockwise:
		edge_map = [3, 2, 1, 0]
	else:
		edge_map = [0, 1, 2, 3]
	
	# Caras laterales
	for i in range(4):
		var edge_type = edge_types[edge_map[i]]
		
		if edge_type != 0:
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
	st.set_color(color)
	
	var material = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	st.set_material(material)
	
	mesh_instance.mesh = st.commit()
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	
	return mesh_instance
