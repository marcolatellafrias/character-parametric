extends RigidBody3D

# --- CONFIGURACIÓN DE VUELO ---
@export var hover_height: float = 2.0           # Altura deseada
@export var ray_length: float = 15.0             # Largo del rayo
@export var height_kp: float = 400.0            # Fuerza de resorte
@export var height_kd: float = 24.0             # Amortiguación
@export var upright_kp: float = 30.0            # Estabilidad rotación
@export var upright_kd: float = 4.0             # Freno rotación
@export var max_up_force: float = 300.0          # Límite de fuerza
@export var speed_force: float = 20.0           # Velocidad avance
@export var turn_speed: float = 10.0             # Velocidad giro
@export var rise_speed: float = 5.0      # Metros por segundo que sube la nave
@export var min_height: float = 1.0      # Altura mínima (para no atravesar el suelo)
@export var max_ceiling: float = 90.0
# --- VARIABLES DE CONTROL (INPUTS) ---
var input_throttle: float = 0.0
var input_vertical: float = 0.0
var input_steering: float = 0.0
@export var palanca_altura: Node3D
@export var volante: Node3D
# --- VARIABLES INTERNAS ---
@onready var _collider: CollisionShape3D = $CollisionShape3D
var _box: BoxShape3D
var _local_bottom: Vector3 = Vector3.ZERO
var _ray: RayCast3D

func _ready() -> void:
	# --- 1. CONFIGURACIÓN FÍSICA (RAYCAST Y COLISIÓN) ---
	_box = _collider.shape as BoxShape3D
	if _box == null:
		push_warning("Se esperaba un BoxShape3D en el collider.")
		return
	
	_local_bottom = Vector3(0.0, -_box.size.y * 0.5, 0.0)

	# Configurar RayCast (Ojos de la nave)
	_ray = RayCast3D.new()
	_ray.target_position = Vector3(0, -ray_length, 0)
	_ray.collision_mask = 1  # Solo mira el suelo (Capa 1)
	_ray.collide_with_areas = false
	_ray.collide_with_bodies = true
	add_child(_ray)
	_ray.enabled = true
	
	_place_raycast()
	can_sleep = false # Mantiene la física despierta siempre

	# --- 2. CONEXIÓN AUTOMÁTICA DE CONTROLES ---
	print("--- INICIANDO BÚSQUEDA DE CONTROLES ---")
	
	# Buscamos en TODOS los hijos y nietos (true en el tercer parámetro)
	var posibles_controles = find_children("*", "StaticBody3D", true, false)
	
	if posibles_controles.is_empty():
		print("⚠️ ALERTA: No se encontraron objetos StaticBody3D hijos de la nave.")
	
	for control in posibles_controles:
		# Verificamos si el objeto tiene la señal que necesitamos (Duck Typing)
		if control.has_signal("value_changed"):
			
			# Evitamos conectar dos veces si ya estaba conectado
			if not control.is_connected("value_changed", _on_control_value_changed):
				control.connect("value_changed", _on_control_value_changed)
				
				# Intentamos obtener el nombre del eje para decírtelo en consola
				var nombre_eje = "Desconocido"
				if "output_axis_name" in control:
					nombre_eje = control.output_axis_name
				
				print("✅ CONECTADO EXITOSAMENTE: ", control.name, " [Controla: ", nombre_eje, "]")
		else:
			# Esto te dirá si hay objetos que el código está ignorando
			print("ℹ️ Ignorado (No es un control): ", control.name)
			
	print("--- BÚSQUEDA FINALIZADA ---")
func _place_raycast() -> void:
	if not _box: return
	
	# Mueve el origen del RayCast a la panza de la nave
	var start_global: Vector3 = _collider.to_global(_local_bottom)
	var end_global: Vector3 = start_global + Vector3.DOWN * ray_length
	
	_ray.global_transform.origin = start_global
	_ray.target_position = _ray.to_local(end_global)

# --- RECEPCIÓN DE SEÑALES ---
func _on_control_value_changed(value: float, axis_name: String) -> void:
	print("Nave escuchó: ", axis_name, " Valor: ", value)
	match axis_name:
		"throttle": input_throttle = value
		"vertical": input_vertical = value
		"steering": input_steering = value

# --- FÍSICA ---
func _physics_process(delta: float) -> void:
	if _box == null: return
	
	# Ajuste automático del largo del rayo (para que no salte)
	if ray_length < hover_height + 5.0:
		ray_length = hover_height + 5.0
		_ray.target_position = Vector3(0, -ray_length, 0)
	
	_place_raycast()

	# --- 1. LÓGICA HELICÓPTERO (Altura Acumulativa) ---
	if input_vertical != 0.0:
		hover_height += input_vertical * rise_speed * delta
		hover_height = clamp(hover_height, min_height, max_ceiling)

	# --- 2. SUSTENTACIÓN (Hover) ---
	if _ray.is_colliding():
		var start_global: Vector3 = _ray.global_transform.origin
		var hit_point: Vector3 = _ray.get_collision_point()
		var distance: float = start_global.distance_to(hit_point)

		var up: Vector3 = Vector3.UP
		var v_up: float = linear_velocity.dot(up)
		var height_error: float = hover_height - distance

		var spring: float = height_kp * height_error
		var damper: float = -height_kd * v_up
		var g_scalar: float = ProjectSettings.get_setting("physics/3d/default_gravity")
		var gravity_comp: float = mass * g_scalar
		var force_up: float = clamp(spring + damper + gravity_comp, 0.0, max_up_force)
		
		apply_central_force(up * force_up)

	# --- 3. AVANCE (Throttle) ---
	var forward_dir: Vector3 = global_transform.basis.z 
	if input_throttle != 0.0:
		apply_central_force(forward_dir * input_throttle * speed_force)

	# --- 4. GIRO CON INERCIA (Steering) ---
	if input_steering != 0.0:
		# Aplicamos TORQUE (Fuerza de giro) en el eje Y local
		# Esto acumula velocidad angular (inercia)
		var torque_giro = global_transform.basis.y * input_steering * turn_speed
		apply_torque(torque_giro)

	# --- 5. ESTABILIZACIÓN INTELIGENTE (El cambio clave) ---
	var current_up: Vector3 = global_transform.basis.y.normalized()
	var desired_up: Vector3 = Vector3.UP
	var error_axis: Vector3 = current_up.cross(desired_up)
	
	# Calculamos el freno (Damping)
	var freno_angular = angular_velocity * upright_kd
	
	# [TRUCO] Reducimos drásticamente el freno SOLO en el eje Y (Giro)
	# Multiplicamos Y por 0.05 para que tenga muy poca fricción al girar
	freno_angular.y *= 0.05 
	
	# Aplicamos el torque de corrección (Enderezar - Freno ajustado)
	var torque_estabilizacion: Vector3 = error_axis * upright_kp - freno_angular
	apply_torque(torque_estabilizacion)
