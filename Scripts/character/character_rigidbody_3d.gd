class_name CharacterRigidBody3D
extends RigidBody3D

@export var sprint_speed_multiplier := 1.5
@export var sprint_acceleration_multiplier := 1.5
@export var acceleration_force := 4.0
@export var braking_force := 1.5
@export var max_speed := 4.0
@export var show_mesh := true

var is_active: bool = false
var collider: CollisionShape3D
var mesh_instance: MeshInstance3D

func _ready() -> void:
	linear_damp = 0.0
	var physics_mat := PhysicsMaterial.new()
	physics_mat.friction = 0.15
	physics_material_override = physics_mat
	can_sleep = false
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	mesh_instance.visible = show_mesh

func _physics_process(_delta: float) -> void:
	if is_active:
		_apply_movement_force()

func _apply_movement_force() -> void:
	var horizontal_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	var is_sprinting := Input.is_action_pressed("sprint")
	var current_max_speed := max_speed * (sprint_speed_multiplier if is_sprinting else 1.0)
	var current_acceleration := acceleration_force * (sprint_acceleration_multiplier if is_sprinting else 1.0)

	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_backward")
	)

	if input != Vector2.ZERO:
		var right := global_transform.basis.x
		var forward := global_transform.basis.z
		right.y = 0.0
		forward.y = 0.0
		var direction := (right.normalized() * input.x + forward.normalized() * input.y).normalized()

		if horizontal_vel.length() < current_max_speed or horizontal_vel.dot(direction) < 0.0:
			apply_central_force(direction * current_acceleration)

		var opposing_vel: Vector3 = horizontal_vel - direction * max(0.0, horizontal_vel.dot(direction))
		if opposing_vel.length() > 0.0:
			apply_central_force(-opposing_vel.normalized() * braking_force)
	else:
		if horizontal_vel.length() > 0.0:
			apply_central_force(-horizontal_vel.normalized() * braking_force)

static func create(root_size: Vector3, distance_from_ground: float, active: bool) -> CharacterRigidBody3D:
	var character_rigidbody := CharacterRigidBody3D.new()

	var new_mesh_instance := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.height = root_size.y
	capsule_mesh.radius = root_size.x * 0.5
	new_mesh_instance.mesh = capsule_mesh
	new_mesh_instance.position = Vector3(0.0, distance_from_ground, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1, 1, 1, 0.2)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.flags_transparent = true
	new_mesh_instance.material_override = material

	var new_collision_shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.height = root_size.y
	capsule_shape.radius = root_size.x * 0.5
	new_collision_shape.shape = capsule_shape
	new_collision_shape.position = Vector3(0.0, distance_from_ground, 0.0)

	character_rigidbody.add_child(new_mesh_instance)
	character_rigidbody.add_child(new_collision_shape)
	character_rigidbody.collider = new_collision_shape
	character_rigidbody.mesh_instance = new_mesh_instance
	character_rigidbody.is_active = active
	return character_rigidbody
