#class_name CharacterRigidBody3D
#extends RigidBody3D
#
#@export var move_force: float = 35.0
#@export var air_control: float = 0.3
#@export var jump_impulse: float = 7.5
#@export var mouse_sensitivity: float = 0.3
#@export var sprint_multiplier: float = 2.0
#@export var camera: Camera3D
#
## --- Ray settings ---
#@export var ray_length: float = 1.6
#@export var left_ray_offset: Vector3 = Vector3(-0.25, 0.0, 0.0)   # local-space offset from the body
#@export var right_ray_offset: Vector3 = Vector3(0.25, 0.0, 0.0)
#
#@export var collision_shape: CollisionShape3D
#@export var mesh_instance: MeshInstance3D
#var left_leg_raycast : RayCast3D
#var right_leg_raycast: RayCast3D
#
#var input_dir: Vector3
#var target_velocity: Vector3
#var is_sprinting := false
#
#func _ready():
	#Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	## Create & attach raycasts as children so they follow the body's position
	#left_leg_raycast  = _make_leg_raycast("LeftLegRaycast")
	#right_leg_raycast = _make_leg_raycast("RightLegRaycast")
	## Initial placement & orientation (also handled every physics frame)
	#_update_leg_rays_world_down()
#
#func _make_leg_raycast(name_str: String) -> RayCast3D:
	#var ray := RayCast3D.new()
	#ray.name = name_str
	#ray.add_child(DebugUtil.create_debug_line(Color.BLUE, ray_length))
	#add_child(ray)
	## Always cast straight down a fixed length (in its *local* space).
	## We'll keep the node's *global* basis aligned to world so this is always world-down.
	#ray.target_position = Vector3(0.0, -ray_length, 0.0)
	#ray.enabled = true
	#return ray
#
#func _input(event):
	#if event.is_action_pressed("ui_cancel"):
		#_toggle_mouse_capture()
#
#func _unhandled_input(event):
	#if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		#_rotate_camera(event.relative)
#
#func _physics_process(_delta):
	## Force the leg rays to be world-down at the correct positions each physics frame
	#_update_leg_rays_world_down()
	#_change_color
#
#func _integrate_forces(state: PhysicsDirectBodyState3D):
	#_handle_movement(state)
	#_handle_jump(state)
#
## --- Keep rays world-down and following the character ---
#func _update_leg_rays_world_down() -> void:
	#if left_leg_raycast:
		## Place at the character's left offset (in local space), but force world-aligned basis
		#var left_world_pos = to_global(left_ray_offset)
		#left_leg_raycast.global_transform = Transform3D(Basis.IDENTITY, left_world_pos)
		#left_leg_raycast.target_position = Vector3(0.0, -ray_length, 0.0)
#
	#if right_leg_raycast:
		#var right_world_pos = to_global(right_ray_offset)
		#right_leg_raycast.global_transform = Transform3D(Basis.IDENTITY, right_world_pos)
		#right_leg_raycast.target_position = Vector3(0.0, -ray_length, 0.0)
#
## --- Movimiento ---
#func _handle_movement(_state: PhysicsDirectBodyState3D):
	#var input_vec = Vector2(
		#Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		#Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	#).normalized()
#
	#var forward = -camera.global_transform.basis.z
	#var right = camera.global_transform.basis.x
	#input_dir = (forward * input_vec.y + right * input_vec.x).normalized()
#
	#is_sprinting = Input.is_action_pressed("sprint") and input_vec != Vector2.ZERO and _is_on_floor()
#
	#var control_strength = move_force * (sprint_multiplier if is_sprinting else 1.0)
	#if not _is_on_floor():
		#control_strength *= air_control
#
	#if input_vec != Vector2.ZERO:
		#apply_central_force(input_dir * control_strength)
#
## --- Saltar ---
#func _handle_jump(_state: PhysicsDirectBodyState3D):
	#if _is_on_floor() and Input.is_action_just_pressed("jump"):
		#apply_central_impulse(Vector3.UP * jump_impulse)
#
## --- Detectar si está en el suelo ---
#func _is_on_floor() -> bool:
	#return (left_leg_raycast and left_leg_raycast.is_colliding()) \
		#or (right_leg_raycast and right_leg_raycast.is_colliding())
#
## --- Rotación de cámara ---
#func _rotate_camera(relative: Vector2):
	#rotate_y(deg_to_rad(-relative.x * mouse_sensitivity))
	#camera.rotate_x(deg_to_rad(-relative.y * mouse_sensitivity))
	#camera.rotation_degrees.x = clamp(camera.rotation_degrees.x, -80, 80)
#
#func _toggle_mouse_capture():
	#var mode = Input.get_mouse_mode()
	#Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED)
#
#
#static func create(root_size: Vector3, new_left_leg_raycast: RayCast3D, new_right_leg_raycast: RayCast3D, camera: Camera3D) -> CharacterRigidBody3D:
	#var character_rigidbody := CharacterRigidBody3D.new()
	#var mesh_instance := MeshInstance3D.new()
	#var cube_mesh := BoxMesh.new()
	#cube_mesh.size = root_size
	#mesh_instance.mesh = cube_mesh
	#mesh_instance.position = Vector3(0, root_size.y * 0.5, 0)
	#var material := StandardMaterial3D.new()
	#material.albedo_color = Color.CORAL
	#mesh_instance.material_override = material
	#var collision_shape := CollisionShape3D.new()
	#var cube_shape := BoxShape3D.new()
	#cube_shape.size = root_size
	#collision_shape.shape = cube_shape
	#collision_shape.position = Vector3(0, root_size.y * 0.5, 0)
	#character_rigidbody.add_child(mesh_instance)
	#character_rigidbody.add_child(collision_shape)
	#character_rigidbody.left_leg_raycast = new_left_leg_raycast
	#character_rigidbody.right_leg_raycast = new_right_leg_raycast
	#character_rigidbody.camera = camera
	#return character_rigidbody
#
#
#func _change_color()-> void:
		## Check if any leg is colliding
	#var on_ground := (
		#(left_leg_raycast and left_leg_raycast.is_colliding()) or
		#(right_leg_raycast and right_leg_raycast.is_colliding())
	#)
#
	## Set mesh color based on ground contact
	#if mesh_instance:
		#var material := mesh_instance.get_active_material(0)
		#if material == null:
			## Ensure we’re modifying a unique material
			#material = StandardMaterial3D.new()
			#mesh_instance.set_surface_override_material(0, material)
		#else:
			## Duplicate so we don’t affect shared resources
			#material = material.duplicate()
			#mesh_instance.set_surface_override_material(0, material)
#
		#material.albedo_color = Color(0.0, 0.3, 1.0) if on_ground else Color(1.0, 1.0, 1.0)
