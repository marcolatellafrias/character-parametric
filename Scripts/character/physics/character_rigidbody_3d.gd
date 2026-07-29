class_name CharacterRigidBody3D
extends RigidBody3D

var _last_impact_world_dir: Vector3 = Vector3.ZERO

var can_sprint: bool = true

# Creative/debug flight (see PlayerController + technical/characters.md). No noclip: the capsule still collides.
var creative_mode: bool = false
var fly_speed: float = 12.0
var fly_sprint_multiplier: float = 2.0

const SPEED_SCALE := 10.0
const ACCEL_SCALE := 10.0
const BRAKE_FACTOR := 0.375
const JUMP_SCALE := 30.0

@export var show_mesh := false

var is_active: bool = false
var is_grounded: bool = false
var collider: CollisionShape3D
var mesh_instance: MeshInstance3D
var _ground_ray: RayCast3D

# Modo puppet: proxy remoto (milestone 3). La posición/yaw los pone el CharacterNetSync
# desde la red; no simulamos física ni detectamos impactos. La animación lee la velocidad
# de red (puppet_velocity) en vez de linear_velocity, que en un cuerpo freeze es 0.
var is_puppet: bool = false
var puppet_velocity: Vector3 = Vector3.ZERO

var _capsule_stand_height: float = 0.0
var _capsule_stand_y_offset: float = 0.0

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

var impact_y_stiffness: float = 25.0
var impact_y_damping: float = 6.0
var impact_stiffness: float = 25.0
var impact_damping: float = 6.0
var impact_xz_scale: float = 0.3
var impact_y_scale: float = 0.3
var impact_xz_threshold: float = 1.5
var impact_y_threshold: float = 2.0

var ragdoll_threshold: float = 0.85

var velocity_indicator: Vector2 = Vector2.ZERO
var impact_xz: Vector2 = Vector2.ZERO
var impact_y: float = 0.0

signal fall_triggered(world_dir: Vector3)

var _impact_xz_vel: Vector2 = Vector2.ZERO
var _impact_y_vel: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
var _frame_force: Vector3 = Vector3.ZERO

var _last_impact_xz_magnitude: float = 0.0

var is_snapshot_active: bool = true
var _ext_ragdoll_state: int = 0
var _snapshot_capture_count: int = 0
var _snapshot_flag_at_capture: bool = false
var _snapshot_ragdoll_at_capture: int = 0
var _snapshot_acc_before: float = 0.0
var _snapshot_acc_after: float = 0.0

var crouch_speed_factor: float = 1.0

var impact_y_signed: float = 0.0

func get_ground_collision_point() -> Vector3:
	return _ground_ray.get_collision_point()

## Velocidad que maneja la animación: la real si simulamos, o la de red si somos puppet.
func get_motion_velocity() -> Vector3:
	return puppet_velocity if is_puppet else linear_velocity

## Convierte la cápsula en un proxy manejado por red: sin física, sin colisión.
func setup_as_puppet() -> void:
	is_puppet = true
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	gravity_scale = 0.0
	collision_layer = 0
	collision_mask = 0

func _ready() -> void:
	linear_damp = 0.0
	var physics_mat := PhysicsMaterial.new()
	physics_mat.friction = 0.0
	physics_mat.bounce = 0.0
	physics_mat.absorbent = true
	physics_material_override = physics_mat
	can_sleep = false
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	mesh_instance.visible = show_mesh
	contact_monitor = true
	max_contacts_reported = 4
	axis_lock_angular_y = true

func _physics_process(delta: float) -> void:
	# Puppet (proxy remoto): la posición la maneja la red y no simulamos, pero SÍ actualizamos el
	# ground ray para que la animación sepa si está apoyado (si no, los pies quedan recogidos y no
	# camina). Ver technical/character-animation.md.
	if is_puppet:
		_ground_ray.force_raycast_update()
		is_grounded = _ground_ray.is_colliding()
		return

	# El movimiento lee Input directo, así que se congela mientras haya un overlay
	# abierto (pausa/menú/consola/debug). El mundo sigue simulando igual.
	var input_active := UIState.gameplay_active()

	if creative_mode:
		if input_active:
			_apply_creative_fly()
		else:
			linear_velocity = Vector3.ZERO
		_ground_ray.force_raycast_update()
		is_grounded = _ground_ray.is_colliding()
		_prev_velocity = linear_velocity
		return

	_frame_force = Vector3.ZERO

	if is_active and input_active:
		_apply_movement_force()
	_apply_braking_force()

	_update_velocity_indicator()
	_detect_external_impact(delta)
	_update_impact_pd(delta)

	_ground_ray.force_raycast_update()
	is_grounded = _ground_ray.is_colliding()
	var mat := mesh_instance.material_override as StandardMaterial3D
	mat.albedo_color = Color(1, 1, 1, 0.2) if is_grounded else Color(1, 0.5, 0, 0.2)

	_prev_velocity = linear_velocity
	
func _detect_external_impact(delta: float) -> void:
	var gravity := get_gravity()
	var expected_dv := (_frame_force / mass + gravity) * delta
	var actual_dv   := linear_velocity - _prev_velocity
	var impact_dv   := actual_dv - expected_dv

	var local_impact := global_transform.basis.inverse() * impact_dv

	var xz := Vector2(local_impact.x, local_impact.z)
	if xz.length() > impact_xz_threshold:
		var impact_dir_world := (global_transform.basis * Vector3(local_impact.x, 0.0, local_impact.z)).normalized()

		if is_snapshot_active:
			_last_impact_world_dir = impact_dir_world
			_last_impact_xz_magnitude = xz.length() * impact_xz_scale
			_snapshot_flag_at_capture = is_snapshot_active
			_snapshot_ragdoll_at_capture = _ext_ragdoll_state
			_snapshot_acc_before = impact_xz.length()
			_snapshot_capture_count += 1
		impact_xz = (impact_xz + xz * impact_xz_scale).limit_length(1.0)
		_impact_xz_vel = Vector2.ZERO

		if impact_xz.length() >= ragdoll_threshold:
			_snapshot_acc_after = impact_xz.length()
			fall_triggered.emit(_last_impact_world_dir)
			impact_xz = Vector2.ZERO
			_impact_xz_vel = Vector2.ZERO

	if abs(local_impact.y) > impact_y_threshold:
		impact_y_signed = local_impact.y  # agregá esta línea
		impact_y = clamp(impact_y + local_impact.y * impact_y_scale, -1.0, 1.0)
		_impact_y_vel = 0.0

func _update_velocity_indicator() -> void:
	var local_vel := global_transform.basis.inverse() * linear_velocity
	var max_vel: float = max(max_speed_forward, max_speed_side) * sprint_multiplier
	velocity_indicator = (Vector2(local_vel.x, local_vel.z) / max(max_vel, 0.001)).limit_length(1.0)

func _update_impact_pd(delta: float) -> void:
	var xz_acc := -impact_xz * impact_stiffness - _impact_xz_vel * impact_damping
	_impact_xz_vel += xz_acc * delta
	impact_xz += _impact_xz_vel * delta

	var y_acc := -impact_y * impact_y_stiffness - _impact_y_vel * impact_y_damping
	_impact_y_vel += y_acc * delta
	impact_y += _impact_y_vel * delta

func _apply_movement_force() -> void:
	var horizontal_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)

	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_backward")
	)

	if input == Vector2.ZERO:
		return

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
	effective_max *= crouch_speed_factor

	var fwd_accel: float = accel_back if forward_component >= 0.0 else accel_forward
	var current_accel: float = (fwd_accel * abs_fwd + accel_side * abs_side) / max(total_input, 0.001)

	var direction := (right * side_component + forward * forward_component).normalized()
	var is_changing_direction := horizontal_vel.dot(direction) < 0.0
	var effective_accel := current_accel * (sprint_multiplier if is_sprinting and not is_changing_direction else 1.0)

	if horizontal_vel.length() < effective_max or is_changing_direction:
		var force := direction * effective_accel
		apply_central_force(force)
		_frame_force += force

	var opposing_vel: Vector3 = horizontal_vel - direction * max(0.0, horizontal_vel.dot(direction))
	if opposing_vel.length() > 0.0:
		var local_opp: Vector3 = global_transform.basis.inverse() * opposing_vel
		var brake_opp: float = (brake_side * abs(local_opp.x) + brake_forward * abs(local_opp.z)) / max(abs(local_opp.x) + abs(local_opp.z), 0.001)
		var brake_force := -opposing_vel.normalized() * brake_opp
		apply_central_force(brake_force)
		_frame_force += brake_force

func jump(impulse: float) -> void:
	apply_central_impulse(Vector3.UP * impulse)

func set_creative_mode(enabled: bool) -> void:
	creative_mode = enabled
	if enabled:
		gravity_scale    = 0.0
		linear_velocity  = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		reset_impact_state()
	else:
		gravity_scale      = 1.0
		linear_velocity    = Vector3.ZERO
		_prev_velocity     = Vector3.ZERO
		is_snapshot_active = true

func _apply_creative_fly() -> void:
	var input := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_backward")
	)
	var right   := global_transform.basis.x
	var forward := global_transform.basis.z
	right.y = 0.0
	forward.y = 0.0
	right = right.normalized()
	forward = forward.normalized()

	var dir := right * input.x + forward * input.y
	var vertical := 0.0
	if Input.is_physical_key_pressed(KEY_SPACE): vertical += 1.0
	if Input.is_physical_key_pressed(KEY_CTRL):  vertical -= 1.0

	var speed := fly_speed
	if Input.is_action_pressed("sprint"):
		speed *= fly_sprint_multiplier

	linear_velocity = dir * speed + Vector3.UP * vertical * speed

func set_crouched(crouched: bool) -> void:
	var shape := collider.shape as CapsuleShape3D
	var target_height := _capsule_stand_height * 0.55 if crouched else _capsule_stand_height
	shape.height = target_height
	var height_diff := _capsule_stand_height - target_height
	collider.position.y = _capsule_stand_y_offset - height_diff * 0.5
	mesh_instance.position.y = collider.position.y
	_ground_ray.position.y = collider.position.y - target_height / 2.0 + (collider.shape as CapsuleShape3D).radius

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

	rb._capsule_stand_height = root_size.y
	rb._capsule_stand_y_offset = y_offset

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

	var radius := root_size.x * 0.5
	var ground_ray := RayCast3D.new()
	ground_ray.position = Vector3(0, y_offset - root_size.y / 2.0 + radius, 0)
	ground_ray.target_position = Vector3(0, -(radius + 0.12), 0)
	ground_ray.add_exception(rb)
	
	rb.add_child(new_mesh_instance)
	rb.add_child(new_collision_shape)
	rb.add_child(ground_ray)
	rb.collider = new_collision_shape
	rb.mesh_instance = new_mesh_instance
	rb._ground_ray = ground_ray
	rb.is_active = active
	return rb

func _apply_braking_force() -> void:
	var horizontal_vel := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
	if horizontal_vel.length() > 0.0:
		var local_vel := global_transform.basis.inverse() * horizontal_vel
		var is_moving_back := local_vel.z < 0.0
		var brake_fwd := brake_back if is_moving_back else brake_forward
		var brake_blend : float = (brake_fwd * abs(local_vel.z) + brake_side * abs(local_vel.x)) / max(abs(local_vel.z) + abs(local_vel.x), 0.001)
		var brake_force := -horizontal_vel.normalized() * brake_blend
		apply_central_force(brake_force)
		_frame_force += brake_force
		
func reset_impact_state() -> void:
	impact_xz        = Vector2.ZERO
	_impact_xz_vel   = Vector2.ZERO
	impact_y         = 0.0
	_impact_y_vel    = 0.0
	_prev_velocity   = linear_velocity
	is_snapshot_active = false
