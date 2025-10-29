class_name CharacterRigidBody3D
extends RigidBody3D

@export var hover_height := 1.0
@export var height_kp := 800.0
@export var height_kd := 24.0
@export var max_height_error_below := 0.5
@export var max_height_error_above := 0.2
@export var upright_kp := 30.0
@export var upright_kd := 4.0
@export var max_up_force := 40.0

# Umbrales para desactivar estabilización
@export_group("Stop Trying Thresholds")
@export var max_fall_velocity := -15.0      # velocidad Y negativa para desactivar (m/s)
@export var max_horizontal_velocity := 20.0  # velocidad XZ para desactivar (m/s)
@export var max_tilt_angle := 60.0          # ángulo máximo de inclinación en grados
@export var recovery_time := 2.0            # tiempo antes de intentar recuperarse
@export var upright_threshold := 15.0       # ángulo para considerar "erguido" (grados)

var collider: CollisionShape3D 
var mesh_instance: MeshInstance3D
var _capsule: CapsuleShape3D
var _local_bottom := Vector3.ZERO
var left_ray: RayCast3D
var right_ray: RayCast3D

# Estados de recuperación
enum RecoveryState {
	ACTIVE,        # funcionando normalmente
	LIMP,          # desactivado (no hace nada)
	STANDING_UP    # fase 1: solo ponerse erguido
}

var _state := RecoveryState.ACTIVE
var _limp_timer := 0.0

func _ready() -> void:
	_capsule = collider.shape as CapsuleShape3D
	if _capsule == null:
		push_warning("Expected a BoxShape3D on the collider.")
		return
	_local_bottom = Vector3(0.0, -_capsule.height * 0.5, 0.0)
	can_sleep = false

func _physics_process(delta: float) -> void:
	if _capsule == null:
		return
	
	# Manejo de estados de recuperación
	match _state:
		RecoveryState.ACTIVE:
			_check_stop_conditions()
			_apply_full_control()
		
		RecoveryState.LIMP:
			_limp_timer += delta
			if _limp_timer >= recovery_time:
				_begin_standing_up()
		
		RecoveryState.STANDING_UP:
			_apply_upright_only()
			_check_if_upright()

# Aplica control completo (hover + upright)
func _apply_full_control() -> void:
	var up := Vector3.UP
	
	# Hover control
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
			ground_point = (hit_left + hit_right) * 0.5
			used_start = (start_left + start_right) * 0.5
		elif left_hit:
			ground_point = left_ray.get_collision_point()
			used_start = start_left
		else:
			ground_point = right_ray.get_collision_point()
			used_start = start_right
		
		var vertical_distance := used_start.y - ground_point.y
		var v_up := linear_velocity.dot(up)
		var height_error := hover_height - vertical_distance
		
		# Límites asimétricos
		var clamped_error: float
		if height_error > 0:
			clamped_error = min(height_error, max_height_error_below)
		else:
			clamped_error = max(height_error, -max_height_error_above)
		
		var spring := height_kp * clamped_error
		var damper := -height_kd * v_up
		
		var g_scalar := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
		var gravity_comp := mass * g_scalar
		var force_up :float= clamp(spring + damper + gravity_comp, 0.0, max_up_force)
		
		apply_central_force(up * force_up)
	
	# Upright stabilization
	_apply_upright_torque()

# Aplica solo el control de orientación (para fase de levantarse)
func _apply_upright_only() -> void:
	_apply_upright_torque()

# Aplica el torque para mantenerse erguido
func _apply_upright_torque() -> void:
	var current_up := global_transform.basis.y.normalized()
	var desired_up := Vector3.UP
	var error_axis := current_up.cross(desired_up)
	var torque := error_axis * upright_kp - angular_velocity * upright_kd
	apply_torque(torque)

# Verifica todas las condiciones para desactivar
func _check_stop_conditions() -> void:
	# Verificar velocidades
	var v_y := linear_velocity.y
	var v_horizontal := Vector2(linear_velocity.x, linear_velocity.z).length()
	
	if v_y < max_fall_velocity or v_horizontal > max_horizontal_velocity:
		stop_trying()
		return
	
	# Verificar ángulo de inclinación
	var current_up := global_transform.basis.y.normalized()
	var tilt_angle_rad := current_up.angle_to(Vector3.UP)
	var tilt_angle_deg := rad_to_deg(tilt_angle_rad)
	
	if tilt_angle_deg > max_tilt_angle:
		stop_trying()

# Verifica si ya está lo suficientemente erguido para activar hover
func _check_if_upright() -> void:
	var current_up := global_transform.basis.y.normalized()
	var tilt_angle_rad := current_up.angle_to(Vector3.UP)
	var tilt_angle_deg := rad_to_deg(tilt_angle_rad)
	
	if tilt_angle_deg <= upright_threshold:
		_fully_activate()

# Desactiva los sistemas de estabilización
func stop_trying() -> void:
	if _state == RecoveryState.LIMP:
		return
	_state = RecoveryState.LIMP
	_limp_timer = 0.0
	print("CharacterRigidBody: Going limp...")

# Comienza la fase 1: ponerse erguido
func _begin_standing_up() -> void:
	_state = RecoveryState.STANDING_UP
	print("CharacterRigidBody: Trying to stand up...")

# Activa completamente el sistema (fase 2: hover)
func _fully_activate() -> void:
	if _state == RecoveryState.ACTIVE:
		return
	_state = RecoveryState.ACTIVE
	_limp_timer = 0.0
	print("CharacterRigidBody: Fully active!")

# Funciones públicas para control manual (opcional)
func force_stop() -> void:
	stop_trying()

func force_wake_up() -> void:
	_begin_standing_up()

static func create(root_size: Vector3, new_left_leg_raycast: RayCast3D, new_right_leg_raycast: RayCast3D, distance_from_ground: float, max_height_error: float) -> CharacterRigidBody3D:
	var character_rigidbody := CharacterRigidBody3D.new()
	var new_mesh_instance := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.height = root_size.y 
	capsule_mesh.radius = root_size.x/2
	new_mesh_instance.mesh = capsule_mesh
	new_mesh_instance.position = Vector3(0, root_size.y * 0.5, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.CORAL
	material.albedo_color = Color(1, 1, 1, 0.2) # Blanco con opacidad 0.5
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.flags_transparent = true
	new_mesh_instance.material_override = material
	var new_collision_shape := CollisionShape3D.new()
	var capsule_shape := CapsuleShape3D.new()
	capsule_shape.height = root_size.y
	capsule_shape.radius = root_size.x/2
	new_collision_shape.shape = capsule_shape
	new_collision_shape.position = Vector3(0, root_size.y * 0.5, 0)
	character_rigidbody.add_child(new_mesh_instance)
	character_rigidbody.add_child(new_collision_shape)
	character_rigidbody.left_ray = new_left_leg_raycast
	character_rigidbody.right_ray = new_right_leg_raycast
	character_rigidbody.collider = new_collision_shape
	character_rigidbody.mesh_instance = new_mesh_instance
	character_rigidbody.hover_height = distance_from_ground
	#character_rigidbody.max_height_error = max_height_error
	return character_rigidbody
