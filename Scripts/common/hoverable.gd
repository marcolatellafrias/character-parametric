class_name CharacterRigidBody3D
extends RigidBody3D

@export var hover_height := 1.0          # meters (target: bottom of collider to ground)
@export var height_kp := 800.0           # spring (N per meter)
@export var height_kd := 24.0           # damper (N per m/s)
@export var upright_kp := 30.0           # torque gain
@export var upright_kd := 4.0            # angular damping gain
@export var max_up_force := 40.0       # clamp for stability

var collider: CollisionShape3D 
var mesh_instance: MeshInstance3D
var _box: BoxShape3D
var _local_bottom := Vector3.ZERO
var left_ray: RayCast3D
var right_ray: RayCast3D

func _ready() -> void:
	_box = collider.shape as BoxShape3D
	if _box == null:
		push_warning("Expected a BoxShape3D on the collider.")
		return

	# Bottom of the collider in its local space (BoxShape3D.size is FULL size in Godot 4)
	_local_bottom = Vector3(0.0, -_box.size.y * 0.5, 0.0)

	can_sleep = false  # keep it active so it continuously stabilizes

func _physics_process(_delta: float) -> void:
	if _box == null:
		return

	var up := Vector3.UP

	# --- Hover control (vertical only) using two legs ---
	var left_hit := left_ray.is_colliding()
	var right_hit := right_ray.is_colliding()

	if left_hit or right_hit:
		var start_left := left_ray.global_transform.origin
		var start_right := right_ray.global_transform.origin

		var used_start: Vector3
		var ground_point: Vector3

		if left_hit and right_hit:
			var hit_left := left_ray.get_collision_point()
			var hit_right := right_ray.get_collision_point()
			# Average ground position from both legs
			ground_point = (hit_left + hit_right) * 0.5
			# Use the midpoint between the two leg bases
			used_start = (start_left + start_right) * 0.5
		elif left_hit:
			ground_point = left_ray.get_collision_point()
			used_start = start_left
		else:
			ground_point = right_ray.get_collision_point()
			used_start = start_right

		# Use vertical separation only (more stable on slopes than full 3D distance).
		var vertical_distance := used_start.y - ground_point.y

		# PD controller on height (positive = push up)
		var v_up := linear_velocity.dot(up)
		var height_error := hover_height - vertical_distance

		var spring := height_kp * height_error
		var damper := -height_kd * v_up

		# Gravity compensation
		var g_scalar := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
		var gravity_comp := mass * g_scalar

		var force_up : float = clamp(spring + damper + gravity_comp, 0.0, max_up_force)
		apply_central_force(up * force_up)
	# If neither leg hits within ray_length, do nothing vertical: gravity brings it down.

	# --- Upright stabilization (roll/pitch only) ---
	var current_up := global_transform.basis.y.normalized()
	var desired_up := Vector3.UP
	var error_axis := current_up.cross(desired_up)

	var torque := error_axis * upright_kp - angular_velocity * upright_kd
	apply_torque(torque)


static func create(root_size: Vector3, new_left_leg_raycast: RayCast3D, new_right_leg_raycast: RayCast3D, distance_from_ground: float) -> CharacterRigidBody3D:
	var character_rigidbody := CharacterRigidBody3D.new()
	var new_mesh_instance := MeshInstance3D.new()
	var cube_mesh := BoxMesh.new()
	cube_mesh.size = root_size
	new_mesh_instance.mesh = cube_mesh
	new_mesh_instance.position = Vector3(0, root_size.y * 0.5, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.CORAL
	material.albedo_color = Color(1, 1, 1, 0.2) # Blanco con opacidad 0.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.flags_transparent = true
	new_mesh_instance.material_override = material
	var new_collision_shape := CollisionShape3D.new()
	var cube_shape := BoxShape3D.new()
	cube_shape.size = root_size
	new_collision_shape.shape = cube_shape
	new_collision_shape.position = Vector3(0, root_size.y * 0.5, 0)
	character_rigidbody.add_child(new_mesh_instance)
	character_rigidbody.add_child(new_collision_shape)
	character_rigidbody.left_ray = new_left_leg_raycast
	character_rigidbody.right_ray = new_right_leg_raycast
	character_rigidbody.collider = new_collision_shape
	character_rigidbody.mesh_instance = new_mesh_instance
	character_rigidbody.hover_height = distance_from_ground
	return character_rigidbody
