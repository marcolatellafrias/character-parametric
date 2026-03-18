class_name CharacterRigidBody3D
extends RigidBody3D

var can_sprint: bool = true

const SPEED_SCALE := 10.0
const ACCEL_SCALE := 10.0
const BRAKE_FACTOR := 0.375

@export var show_mesh := true

var is_active: bool = false
var collider: CollisionShape3D
var mesh_instance: MeshInstance3D

var accel_forward: float = 4.0
var accel_back: float = 4.0
var accel_side: float = 4.0

var brake_forward: float = 1.0
var brake_back: float = 1.0
var brake_side: float = 1.0

var max_speed_forward: float = 10.0
var max_speed_back: float = 10.0
var max_speed_side: float = 10.0

var sprint_multiplier: float = 2.0

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

	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_backward")
	)

	if input != Vector2.ZERO:
		var right := global_transform.basis.x
		var forward := global_transform.basis.z
		right.y = 0.0
		forward.y = 0.0
		right = right.normalized()
		forward = forward.normalized()

		var forward_component: float = input.y
		var side_component: float = input.x
		var is_sprinting := Input.is_action_pressed("sprint") and forward_component < 0.0 and can_sprint

		var abs_fwd: float = abs(forward_component)
		var abs_side: float = abs(side_component)
		var total_input: float = abs_fwd + abs_side

		var fwd_max: float = max_speed_back if forward_component >= 0.0 else max_speed_forward
		var effective_max: float = (fwd_max * abs_fwd + max_speed_side * abs_side) / max(total_input, 0.001)
		if is_sprinting:
			effective_max *= sprint_multiplier

		var fwd_accel: float = accel_back if forward_component >= 0.0 else accel_forward
		var current_accel: float = (fwd_accel * abs_fwd + accel_side * abs_side) / max(total_input, 0.001)

		var direction := (right * side_component + forward * forward_component).normalized()
		var is_changing_direction := horizontal_vel.dot(direction) < 0.0
		var effective_accel := current_accel * (sprint_multiplier if is_sprinting and not is_changing_direction else 1.0)

		if horizontal_vel.length() < effective_max or is_changing_direction:
			apply_central_force(direction * effective_accel)

		var opposing_vel: Vector3 = horizontal_vel - direction * max(0.0, horizontal_vel.dot(direction))
		if opposing_vel.length() > 0.0:
			var local_opp: Vector3 = global_transform.basis.inverse() * opposing_vel
			var brake_opp: float = (brake_side * abs(local_opp.x) + brake_forward * abs(local_opp.z)) / max(abs(local_opp.x) + abs(local_opp.z), 0.001)
			apply_central_force(-opposing_vel.normalized() * brake_opp)
	else:
		if horizontal_vel.length() > 0.0:
			var local_vel: Vector3 = global_transform.basis.inverse() * horizontal_vel
			var is_moving_back := local_vel.z < 0.0
			var brake_fwd: float = brake_back if is_moving_back else brake_forward
			var brake_blend: float = (brake_fwd * abs(local_vel.z) + brake_side * abs(local_vel.x)) / max(abs(local_vel.z) + abs(local_vel.x), 0.001)
			apply_central_force(-horizontal_vel.normalized() * brake_blend)

static func create(root_size: Vector3, distance_from_ground: float, leg_height: float, active: bool, inst: EntityInstantiation) -> CharacterRigidBody3D:
	var rb := CharacterRigidBody3D.new()

	var arch := inst.arch_final
	var spec := inst.spec
	rb.mass = arch.weight
	rb.sprint_multiplier = arch.sprint_multiplier

	rb.max_speed_forward = arch.speed * spec.speed_forw_multiplier * SPEED_SCALE
	rb.max_speed_back    = arch.speed * arch.back_speed_factor    * spec.speed_back_multiplier  * SPEED_SCALE
	rb.max_speed_side    = arch.speed * arch.lateral_speed_factor * spec.speed_side_multiplier  * SPEED_SCALE

	rb.accel_forward = arch.weight * arch.acceleration * spec.acceleration_multiplier * ACCEL_SCALE
	rb.accel_back    = arch.weight * arch.acceleration * arch.back_speed_factor    * spec.acceleration_multiplier * ACCEL_SCALE
	rb.accel_side    = arch.weight * arch.acceleration * arch.lateral_speed_factor * spec.acceleration_multiplier * ACCEL_SCALE

	rb.brake_forward = rb.accel_forward * BRAKE_FACTOR
	rb.brake_back    = rb.accel_back    * BRAKE_FACTOR
	rb.brake_side    = rb.accel_side    * BRAKE_FACTOR

	var y_offset := root_size.y / 2.0 - (leg_height - distance_from_ground)

	var new_mesh_instance := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.height = root_size.y
	capsule_mesh.radius = root_size.x * 0.5
	new_mesh_instance.mesh = capsule_mesh
	new_mesh_instance.position = Vector3(0.0, y_offset, 0.0)
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
	new_collision_shape.position = Vector3(0.0, y_offset, 0.0)

	rb.add_child(new_mesh_instance)
	rb.add_child(new_collision_shape)
	rb.collider = new_collision_shape
	rb.mesh_instance = new_mesh_instance
	rb.is_active = active
	return rb
