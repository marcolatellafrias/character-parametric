extends Node3D

# Parámetros del paso
var target_position: Vector3  # Donde debe aterrizar el pie
var step_progress: float = 0.0  # 0.0 a 1.0
var is_stepping: bool = false

# Configuración ajustable por personaje
@export var step_height: float = 0.3  # Altura del paso
@export var step_speed_multiplier: float = 8.0  # Multiplicador base
@export var min_step_speed: float = 0.1  # Velocidad mínima para evitar pasos infinitos

func start_step(target_pos: Vector3):
	target_position = target_pos
	step_progress = 0.0
	is_stepping = true

func update_step(delta: float, current_velocity: Vector3):
	if not is_stepping:
		return
	
	# Calcular distancia restante
	var remaining_distance = global_position.distance_to(target_position)
	
	# Velocidad adaptativa basada en:
	# 1. Velocidad actual del personaje
	# 2. Distancia restante al objetivo
	var character_speed = current_velocity.length()
	
	# Factor de urgencia: más rápido cuando está más lejos del objetivo
	var urgency_factor = clamp(remaining_distance / 2.0, 0.5, 2.0)
	
	# Velocidad del paso que se ajusta dinámicamente
	var adaptive_speed = max(
		character_speed * step_speed_multiplier * urgency_factor,
		min_step_speed  # Evita que se quede congelado
	)
	
	# Incrementar progreso basado en velocidad adaptativa
	var speed_normalized = adaptive_speed / remaining_distance if remaining_distance > 0.01 else 10.0
	step_progress += speed_normalized * delta
	step_progress = clamp(step_progress, 0.0, 1.0)
	
	# Interpolación suave
	var t = ease(step_progress, -2.0)  # Ease out para llegada suave
	
	# Curva de altura (arco del paso)
	var height_curve = sin(step_progress * PI) * step_height
	
	# Posición interpolada
	var base_pos = lerp(global_position, target_position, t)
	global_position = base_pos + Vector3.UP * height_curve
	
	# Terminar paso
	if step_progress >= 1.0:
		global_position = target_position
		is_stepping = false
		
func calculate_landing_position(character_pos: Vector3, character_velocity: Vector3, leg_length: float) -> Vector3:
	# Predecir dónde estará el personaje cuando el paso termine
	var prediction_time = 0.3  # Ajustable según la velocidad de tus pasos
	var predicted_pos = character_pos + character_velocity * prediction_time
	
	# Dirección del paso
	var step_direction = character_velocity.normalized()
	if step_direction.length() < 0.01:
		step_direction = global_transform.basis.z  # Dirección por defecto
	
	# Posición objetivo adelante del personaje
	var landing_pos = predicted_pos + step_direction * leg_length * 0.5
	
	return landing_pos
