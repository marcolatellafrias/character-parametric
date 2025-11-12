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
		material.depth_test = 1
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
		material.depth_test = 1
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
	return mesh_instance

static func create_debug_plane(corner1: Vector3, corner2: Vector3, corner3: Vector3, corner4: Vector3, color: Color) -> MeshInstance3D:
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
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible desde ambos lados
	
	mesh_instance.material_override = material
	
	return mesh_instance
