extends RigidBody3D

# --- CONFIGURACIÓN DE VUELO ---
@export_group("Hover Settings")
@export var hover_height: float = 2.0           # Altura deseada sobre el suelo
@export var ray_length: float = 15.0            # Largo del rayo detector
@export var height_kp: float = 400.0            # Fuerza de resorte (Proporcional)
@export var height_kd: float = 30.0             # Amortiguación (Derivativo)
@export var max_up_force: float = 500.0         # Límite de fuerza vertical

@export_group("Movement Settings")
@export var speed_force: float = 40.0           # Fuerza de avance/retroceso
@export var turn_speed: float = 15.0            # Velocidad de rotación
@export var rise_speed: float = 8.0             # Velocidad de ascenso manual
@export var linear_damping: float = 1.0         # Fricción aire (frenado gradual)
@export var angular_damping: float = 2.0        # Fricción rotación

@export_group("Stability & Visuals")
@export var upright_kp: float = 40.0            # Fuerza para mantenerse derecho
@export var upright_kd: float = 5.0             # Amortiguación de rotación
@export var bank_amount: float = 0.4            # Inclinación lateral al girar
@export var tilt_amount: float = 0.2            # Inclinación frontal al acelerar

@export_group("Limits")
@export var min_height: float = 1.0             # Altura mínima absoluta
@export var max_ceiling: float = 90.0           # Altura máxima absoluta

# --- VARIABLES DE CONTROL (INPUTS) ---
var input_throttle: float = 0.0
var input_vertical: float = 0.0
var input_steering: float = 0.0

# Inputs suavizados para una sensación más orgánica
var _smooth_throttle: float = 0.0
var _smooth_vertical: float = 0.0
var _smooth_steering: float = 0.0
@export var input_lerp_speed: float = 5.0

@export var palanca_altura: Node3D
@export var volante: Node3D

# --- VARIABLES INTERNAS ---
@onready var _collider: CollisionShape3D = $CollisionShape3D
var _box: BoxShape3D
var _local_bottom: Vector3 = Vector3.ZERO
var _ray: RayCast3D
var current_target_altitude: float = 0.0
var is_hovering: bool = false

func _ready() -> void:
	current_target_altitude = global_position.y
	_box = _collider.shape as BoxShape3D
	if _box:
		_local_bottom = Vector3(0.0, -_box.size.y * 0.5, 0.0)

	# Configurar RayCast (Ojos de la nave)
	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, -ray_length, 0)
	_ray.collision_mask = 1  # Capa 1 (Suelo)
	_ray.enabled = true
	add_child(_ray)
	
	# Colocar el rayo en la base de la colisión
	if _collider:
		_ray.position = _collider.position + _local_bottom

	can_sleep = false # Mantiene la física despierta
	
	# Configurar damping nativo como base
	linear_damp = linear_damping
	angular_damp = angular_damping

	_connect_controls()

func _connect_controls() -> void:
	print("--- INICIANDO BÚSQUEDA DE CONTROLES ---")
	var posibles_controles = find_children("*", "StaticBody3D", true, false)
	for control in posibles_controles:
		if control.has_signal("value_changed"):
			if not control.is_connected("value_changed", _on_control_value_changed):
				control.connect("value_changed", _on_control_value_changed)
				var nombre_eje = control.get("output_axis_name") if "output_axis_name" in control else "Desconocido"
				print("✅ CONECTADO: ", control.name, " [", nombre_eje, "]")
	print("--- BÚSQUEDA FINALIZADA ---")

func _on_control_value_changed(value: float, axis_name: String) -> void:
	match axis_name:
		"throttle": input_throttle = -value
		"vertical": input_vertical = value
		"steering": input_steering = value

func _physics_process(delta: float) -> void:
	# 1. Suavizar entradas
	_smooth_throttle = lerp(_smooth_throttle, input_throttle, input_lerp_speed * delta)
	_smooth_vertical = lerp(_smooth_vertical, input_vertical, input_lerp_speed * delta)
	_smooth_steering = lerp(_smooth_steering, input_steering, input_lerp_speed * delta)

	# 2. Control de Altura y Hover
	_process_altitude(delta)

	# 3. Movimiento Horizontal
	_process_movement(delta)

	# 4. Estabilización y Banking (Visual)
	_process_stability(delta)
	
	# 5. Animar controles visuales
	_animate_visual_controls()

func _process_altitude(delta: float) -> void:
	# Actualizar meta de altitud global con la entrada vertical
	if abs(input_vertical) > 0.01:
		current_target_altitude += input_vertical * rise_speed * delta
	
	current_target_altitude = clamp(current_target_altitude, min_height, max_ceiling)

	var error: float = 0.0
	
	# Lógica Híbrida: Hover sobre suelo o Vuelo libre
	if _ray.is_colliding():
		var hit_point = _ray.get_collision_point()
		var ground_target = hit_point.y + hover_height
		
		# Si estamos cerca del suelo, nos aseguramos de no chocar (hovering)
		# Pero también respetamos la altura deseada por el piloto
		var final_target = max(current_target_altitude, ground_target)
		error = final_target - global_position.y
		is_hovering = true
	else:
		# Vuelo libre (sin suelo detectado por el rayo)
		error = current_target_altitude - global_position.y
		is_hovering = false

	# Aplicar fuerza PID vertical
	# Usamos la velocidad vertical para la amortiguación (D)
	var spring_force = error * height_kp
	var damping_force = linear_velocity.y * height_kd
	var total_up_force = clamp(spring_force - damping_force, -max_up_force, max_up_force)
	
	apply_central_force(Vector3.UP * total_up_force)

func _process_movement(_delta: float) -> void:
	# Empuje hacia adelante/atrás (basado en la orientación de la nave)
	if abs(_smooth_throttle) > 0.01:
		var forward_dir = -global_transform.basis.z
		apply_central_force(forward_dir * _smooth_throttle * speed_force)
	
	# Giro (Torque en el eje Y global para estabilidad)
	if abs(_smooth_steering) > 0.01:
		apply_torque(Vector3.UP * -_smooth_steering * turn_speed)
	
	# Compensar deslizamiento lateral (Derrape)
	# Esto hace que la nave se sienta más como si volara y menos como si estuviera en hielo
	var lateral_vel = global_transform.basis.x.dot(linear_velocity)
	apply_central_force(-global_transform.basis.x * lateral_vel * 2.0)

func _process_stability(_delta: float) -> void:
	var target_up = Vector3.UP
	
	target_up = target_up.rotated(-global_transform.basis.z.normalized(), _smooth_steering * bank_amount)
	target_up = target_up.rotated(global_transform.basis.x.normalized(), _smooth_throttle * tilt_amount)
	
	target_up = target_up.normalized()
	
	var current_up = global_transform.basis.y
	var torque_correction = current_up.cross(target_up)
	
	apply_torque(torque_correction * upright_kp - angular_velocity * upright_kd)

func _animate_visual_controls() -> void:
	# Animación suave de los nodos de control si están asignados
	if volante:
		volante.rotation.z = lerp_angle(volante.rotation.z, -input_steering * 0.8, 0.1)
	if palanca_altura:
		palanca_altura.rotation.x = lerp_angle(palanca_altura.rotation.x, input_vertical * 0.5, 0.1)
