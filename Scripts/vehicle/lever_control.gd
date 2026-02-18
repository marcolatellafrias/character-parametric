extends "res://Scripts/common/interactable.gd"
class_name LeverControl

signal value_changed(new_value, axis_name)

@export var sensitivity: float = 0.005
@export var max_angle: float = 45.0
@export var output_axis_name: String = "throttle"
@export var soft_lock_threshold: float = 2.5 # Umbral en grados para el snap

# --- NUEVA VARIABLE ---
# Aquí asignarás SOLO la parte que se mueve (el mango)
@export var mesh_manija: MeshInstance3D 

var current_value: float = 0.0
var _current_rotation_degrees: float = 0.0

func interact(_player):
	print("Interactuando con la palanca")

func on_mouse_drag(relative: Vector2):
	var movement = -relative.y * sensitivity * 50.0
	var old_deg = _current_rotation_degrees
	
	_current_rotation_degrees += movement 
	_current_rotation_degrees = clamp(_current_rotation_degrees, -max_angle, max_angle)
	
	# MAGNETISMO: Si cruzamos el cero, nos enganchamos (bloqueo instantáneo)
	if old_deg != 0 and sign(old_deg) != sign(_current_rotation_degrees):
		_current_rotation_degrees = 0.0
	
	# SOFT LOCK: Output 0 si estamos dentro del umbral
	var effective_deg = _current_rotation_degrees
	if abs(_current_rotation_degrees) < soft_lock_threshold:
		effective_deg = 0.0
	
	if mesh_manija:
		mesh_manija.rotation_degrees.x = effective_deg
	
	current_value = effective_deg / max_angle
	emit_signal("value_changed", current_value, output_axis_name)
