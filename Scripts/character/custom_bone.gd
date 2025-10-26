class_name CustomBone
extends Node3D

var capsule_dimensions: Vector3
var rest_rotation: Vector3
var length :float = capsule_dimensions.y :
	get:  return capsule_dimensions.y
	set(val): capsule_dimensions.y = val
var visual_offsets : Vector2

func _get_mesh_instance3d() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new() #DebugUtil.create_debug_colored_cube(bone.capsule_dimensions)
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = capsule_dimensions
	mesh_instance.mesh = cube_mesh
	mesh_instance.position = Vector3(0, length * 0.5, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE_SMOKE #new_color
	mesh_instance.material_override = material
	return mesh_instance
	
func _get_collision_shape3d() -> CollisionShape3D:
	var collision_shape :=  CollisionShape3D.new()
	var cube_shape := BoxShape3D.new()
	cube_shape.size = capsule_dimensions
	collision_shape.shape = cube_shape
	collision_shape.position = Vector3(0, length * 0.5, 0)
	return collision_shape

func get_rigidbody() -> RigidBody3D:
	var rigid_body = RigidBody3D.new()
	rigid_body.rotation = rest_rotation
	var collision_shape3d = _get_collision_shape3d()
	rigid_body.add_child(collision_shape3d)
	var mesh_instance3d = _get_mesh_instance3d()
	rigid_body.add_child(mesh_instance3d)
	return rigid_body

func set_rigidbody(rigid_body: RigidBody3D) -> void:
	rigid_body.rotation = rest_rotation
	var collision_shape3d = _get_collision_shape3d()
	rigid_body.add_child(collision_shape3d)
	var mesh_instance3d = _get_mesh_instance3d()
	rigid_body.add_child(mesh_instance3d)
	rigid_body.camera.position = Vector3(0, 1.7, 2.7)

static func create(new_capsule_dimensions: Vector3, new_rest_rotation: Vector3, new_color: Color, offsets: Vector3, father_bone: CustomBone=null, use_father_end: bool= true) -> CustomBone:
	#Instancio
	var bone := preload("res://Scenes/custom_bone.tscn").instantiate() as CustomBone
	bone.capsule_dimensions = new_capsule_dimensions
	bone.rest_rotation = new_rest_rotation
	
	#Añado mesh
	var bone_mesh_instance := get_bone_mesh(bone.capsule_dimensions, offsets) #DebugUtil.create_debug_colored_cube(bone.capsule_dimensions)
	var bone_material := StandardMaterial3D.new()
	bone_material.albedo_color = Color.WHITE_SMOKE #new_color
	bone_mesh_instance.material_override = bone_material
	var min_side : float = min(bone.capsule_dimensions.x,bone.capsule_dimensions.z)
	bone_mesh_instance.position = Vector3(0.0, 0.0,min_side * (offsets.z/2))
	var debug_line := DebugUtil.create_debug_line(Color.RED,bone.capsule_dimensions.y,true,false)
	var debug_sphere := DebugUtil.create_debug_sphere(Color.RED,0.03,true)
	
	bone.add_child(bone_mesh_instance)
	bone.add_child(debug_line)
	bone.add_child(debug_sphere)
	
	# Hago que el pivot del hueso, este donde termina o empieza el hueso padre
	if father_bone:
		bone.position = father_bone.get_end_position() if use_father_end else Vector3.ZERO
		
	if father_bone:
		bone.position = father_bone.get_end_position() if use_father_end else Vector3.ZERO
		father_bone.add_child(bone)
		
		# Convertir la rotación global deseada a rotación local
		var parent_global_basis = _get_accumulated_rotation(father_bone)
		var desired_global_basis = Basis.from_euler(new_rest_rotation)
		var local_basis = parent_global_basis.inverse() * desired_global_basis
		bone.rotation = local_basis.get_euler()
	else:
		bone.rotation = new_rest_rotation
	#bone.rotation = new_rest_rotation #(+father_bone.rest_rotation + new_rest_rotation) if father_bone else new_rest_rotation

	return bone

func get_end_position() -> Vector3:
	var local_end := Vector3(0, capsule_dimensions.y, 0)
	return local_end

func _ready() -> void:
	pass


static func createFromToLeft(new_parent: CustomBone, new_capsule_dimensions: Vector3,offsets: Vector3, y_offset_rotation: float, z_offset_rotation: float, new_color: Color, use_parent_end_as_pivot: bool) -> CustomBone:
	var base_rotation := Vector3(0, 0, deg_to_rad(90))
	var offset_rotation := Vector3(0.0, y_offset_rotation, z_offset_rotation)
	var final_rest_rotation := base_rotation + offset_rotation
	return create(new_capsule_dimensions, final_rest_rotation, new_color, offsets, new_parent, use_parent_end_as_pivot)

static func createFromToRight(new_parent: CustomBone, new_capsule_dimensions: Vector3, offsets: Vector3, y_offset_rotation: float, z_offset_rotation: float, new_color: Color, use_parent_end_as_pivot: bool) -> CustomBone:
	var base_rotation := Vector3(0, 0, deg_to_rad(-90))
	var offset_rotation := Vector3(0.0, y_offset_rotation, z_offset_rotation)
	var final_rest_rotation := base_rotation + offset_rotation
	return create(new_capsule_dimensions, final_rest_rotation, new_color, offsets, new_parent, use_parent_end_as_pivot)

static func createFromToDown(new_parent: CustomBone, new_capsule_dimensions: Vector3,offsets: Vector3, z_offset_rotation: float, x_offset_rotation: float, new_color: Color, use_parent_end_as_pivot: bool) -> CustomBone:
	var base_rotation := Vector3(deg_to_rad(180), 0, 0)
	var offset_rotation := Vector3(x_offset_rotation, 0.0, z_offset_rotation)
	var final_rest_rotation :=  base_rotation + offset_rotation
	return create(new_capsule_dimensions, final_rest_rotation, new_color, offsets, new_parent, use_parent_end_as_pivot)

static func createFromToUp(new_parent: CustomBone, new_capsule_dimensions: Vector3,offsets: Vector3, z_offset_rotation: float, x_offset_rotation: float, new_color: Color, use_parent_end_as_pivot: bool) -> CustomBone:
	var base_rotation := Vector3(0, 0, 0)
	var offset_rotation := Vector3(x_offset_rotation, 0.0, z_offset_rotation)
	var final_rest_rotation := base_rotation + offset_rotation
	return create(new_capsule_dimensions, final_rest_rotation, new_color, offsets, new_parent, use_parent_end_as_pivot)

static func createFromToForward(new_parent: CustomBone, new_capsule_dimensions: Vector3,offsets: Vector3, y_offset_rotation: float, z_offset_rotation: float, new_color: Color, use_parent_end_as_pivot: bool) -> CustomBone:
	var base_rotation := Vector3(-deg_to_rad(90), 0, 0)
	var offset_rotation := Vector3(0.0, y_offset_rotation, z_offset_rotation)
	var final_rest_rotation := base_rotation + offset_rotation
	return create(new_capsule_dimensions, final_rest_rotation, new_color, offsets, new_parent, use_parent_end_as_pivot)

func pose_from_rest_to(dir: Vector3, pole: Vector3) -> Basis:
	# Compute the rest basis from the bone's stored rest_rotation
	var rest_basis := Basis.from_euler(rest_rotation) # rest_rotation must be in radians

	# Normalize target direction
	var y = dir.normalized()

	# --- 1) Align REST +Y to desired direction ---
	var rest_y = rest_basis.y.normalized()
	var c = clamp(rest_y.dot(y), -1.0, 1.0)
	var align := Basis()

	if c > 0.999999:
		# Already aligned
		align = Basis()
	elif c < -0.999999:
		# Opposite direction -> 180° flip
		var axis = rest_y.cross(Vector3.RIGHT)
		if axis.length_squared() < 0.0001:
			axis = rest_y.cross(Vector3.UP)
		axis = axis.normalized()
		align = Basis(axis, PI)
	else:
		var axis = rest_y.cross(y).normalized()
		var angle = acos(c)
		align = Basis(axis, angle)

	# --- 2) Twist so REST X matches pole projection ---
	var projected_pole = (pole - y * pole.dot(y)).normalized()
	if projected_pole.length() < 1e-6:
		projected_pole = IkUtil.get_orthogonal(y).normalized()

	# Align local -Z with pole direction (bend plane)
	var ref_axis = (align * rest_basis).z.normalized()  # treat -Z as "forward"
	var s = ref_axis.cross(projected_pole).dot(y)
	var t = ref_axis.dot(projected_pole)
	var twist_angle = atan2(s, t)
	var twist = Basis(y, twist_angle)

	# --- Combine ---
	return twist * align * rest_basis


static func get_bone_mesh(size: Vector3, offset: Vector3) -> MeshInstance3D:
	var scene: PackedScene = load("res://Models/bone.glb")
	if scene == null:
		push_error("Could not load bone.glb")
		return null

	var root: Node3D = scene.instantiate()
	var mesh_instance: MeshInstance3D = root.get_node_or_null("Sphere") as MeshInstance3D
	if mesh_instance == null:
		push_error("MeshInstance3D not found")
		return null
	
	var max_top_offset = 0.4 * size.x
	var max_bottom_offset = 0.4 * size.z
	
	var top_offset = max_top_offset * offset.x
	var bottom_offset = max_bottom_offset * offset.y
	
	var final_height = (size.y - bottom_offset -top_offset)/2
	var height_index := mesh_instance.find_blend_shape_by_name("height")
	mesh_instance.set_blend_shape_value(height_index, final_height)
	var top_radius_index := mesh_instance.find_blend_shape_by_name("top_radius")
	mesh_instance.set_blend_shape_value(top_radius_index, size.x)
	var bottom_radius_index := mesh_instance.find_blend_shape_by_name("bottom_radius")
	mesh_instance.set_blend_shape_value(bottom_radius_index, size.z)
	
	var top_dome_height_index := mesh_instance.find_blend_shape_by_name("top_dome_height")
	mesh_instance.set_blend_shape_value(top_dome_height_index, size.x)
	var bottom_dome_height_index := mesh_instance.find_blend_shape_by_name("bottom_dome_height")
	mesh_instance.set_blend_shape_value(bottom_dome_height_index, size.z)
	
	mesh_instance.position = Vector3(0,bottom_offset, 0)
	
	root.remove_child(mesh_instance)
	return mesh_instance

static func _get_accumulated_rotation(bone: CustomBone) -> Basis:
	var accumulated = Basis.from_euler(bone.rotation)  # Cambiar rest_rotation por rotation
	var current = bone.get_parent()
	
	while current != null and current is CustomBone:
		accumulated = Basis.from_euler(current.rotation) * accumulated  # Aquí también
		current = current.get_parent()
	
	return accumulated
