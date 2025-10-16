class_name CustomBone
extends Node3D

var capsule_dimensions: Vector3 
var rest_rotation: Vector3
var length :float = capsule_dimensions.y :
		get:  return capsule_dimensions.y
		set(val): capsule_dimensions.y = val

static func create(new_capsule_dimensions: Vector3, new_rest_rotation: Vector3, new_color: Color,father_bone: CustomBone=null, use_father_end: bool= true) -> CustomBone:
	#Instancio
	var bone := preload("res://Scenes/custom_bone.tscn").instantiate() as CustomBone
	bone.capsule_dimensions = new_capsule_dimensions
	bone.rest_rotation = new_rest_rotation
	
	#Añado esfera en el pivot para debug
	var pivot_mesh_instance := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	pivot_mesh_instance.scale = Vector3(0.05,0.05,0.05)
	pivot_mesh_instance.mesh = sphere_mesh
	pivot_mesh_instance.position = Vector3.ZERO
	var sphere_material := StandardMaterial3D.new()
	sphere_material.albedo_color = Color.BLACK
	pivot_mesh_instance.material_override = sphere_material
	bone.add_child(pivot_mesh_instance)
	
	#Añado mesh
	var mesh_instance := MeshInstance3D.new()
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = bone.capsule_dimensions
	mesh_instance.mesh = cube_mesh
	mesh_instance.position = Vector3(0, bone.capsule_dimensions.y * 0.5, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = new_color
	material.albedo_color.a = 0.5
	#material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	#material.flags_transparent = true
	mesh_instance.material_override = material
	bone.add_child(mesh_instance)
	
	# Hago que el pivot del hueso, este donde termina o empieza el hueso padre
	if father_bone:
		bone.position = father_bone.get_end_position() if use_father_end else Vector3.ZERO
		
	# Roto el nodo en base a la rotacion inicial, tomando en cuenta la rotacion del padre para que no se acumulen (ya que es local)
	bone.rotation = (+father_bone.rest_rotation + new_rest_rotation) if father_bone else new_rest_rotation
	if father_bone:
		father_bone.add_child(bone) 
	return bone

func get_end_position() -> Vector3:
	var local_end := Vector3(0, capsule_dimensions.y, 0)
	return local_end

func _ready() -> void:
	pass


static func createFromToLeft(new_parent: CustomBone, new_capsule_dimensions: Vector3, y_offset_rotation: float, z_offset_rotation: float, new_color: Color, use_parent_end_as_pivot: bool) -> CustomBone:
	var base_rotation := Vector3(0, 0, deg_to_rad(90))
	var offset_rotation := Vector3(0.0, y_offset_rotation, z_offset_rotation)
	var final_rest_rotation := base_rotation + offset_rotation
	return create(new_capsule_dimensions, final_rest_rotation, new_color, new_parent, use_parent_end_as_pivot)

static func createFromToRight(new_parent: CustomBone, new_capsule_dimensions: Vector3, y_offset_rotation: float, z_offset_rotation: float, new_color: Color, use_parent_end_as_pivot: bool) -> CustomBone:
	var base_rotation := Vector3(0, 0, deg_to_rad(-90))
	var offset_rotation := Vector3(0.0, y_offset_rotation, z_offset_rotation)
	var final_rest_rotation := base_rotation + offset_rotation
	return create(new_capsule_dimensions, final_rest_rotation, new_color, new_parent, use_parent_end_as_pivot)

static func createFromToDown(new_parent: CustomBone, new_capsule_dimensions: Vector3, z_offset_rotation: float, x_offset_rotation: float, new_color: Color, use_parent_end_as_pivot: bool) -> CustomBone:
	var base_rotation := Vector3(deg_to_rad(180), 0, 0)
	var offset_rotation := Vector3(x_offset_rotation, 0.0, z_offset_rotation)
	var final_rest_rotation :=  base_rotation + offset_rotation
	return create(new_capsule_dimensions, final_rest_rotation, new_color, new_parent, use_parent_end_as_pivot)

static func createFromToUp(new_parent: CustomBone, new_capsule_dimensions: Vector3, z_offset_rotation: float, x_offset_rotation: float, new_color: Color, use_parent_end_as_pivot: bool) -> CustomBone:
	var base_rotation := Vector3(0, 0, 0)
	var offset_rotation := Vector3(x_offset_rotation, 0.0, z_offset_rotation)
	var final_rest_rotation := base_rotation + offset_rotation
	return create(new_capsule_dimensions, final_rest_rotation, new_color, new_parent, use_parent_end_as_pivot)

static func createFromToForward(new_parent: CustomBone, new_capsule_dimensions: Vector3, y_offset_rotation: float, z_offset_rotation: float, new_color: Color, use_parent_end_as_pivot: bool) -> CustomBone:
	var base_rotation := Vector3(-deg_to_rad(90), 0, 0)
	var offset_rotation := Vector3(0.0, y_offset_rotation, z_offset_rotation)
	var final_rest_rotation := base_rotation + offset_rotation
	return create(new_capsule_dimensions, final_rest_rotation, new_color, new_parent, use_parent_end_as_pivot)
