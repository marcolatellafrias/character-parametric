extends "res://Scripts/common/interactable.gd"
class_name WheelControl

signal value_changed(new_value, axis_name)

@export var sensitivity: float = 0.005
@export var max_rotation_degrees: float = 90.0
@export var output_axis_name: String = "steering"
@export var soft_lock_threshold: float = 3.5 # Umbral en grados para el snap

# --- VARIABLE SEGURA ---
# Arrastra aquí tu Marker3D o Pivote
@export var pivote_rotacion: Node3D 

var _rotation_acc: float = 0.0
var current_value: float = 0.0

func interact(_player):
	print("Interactuando con el volante")
	
func on_mouse_drag(relative: Vector2):
	var movement = relative.x * sensitivity * 50.0
	var old_acc = _rotation_acc
	
	# Acumulamos el movimiento siempre (para que no se sienta "trabado" al mover lento)
	_rotation_acc += movement
	_rotation_acc = clamp(_rotation_acc, -max_rotation_degrees, max_rotation_degrees)
	
	# MAGNETISMO: Si cruzamos el cero en un movimiento rápido, lo capturamos
	if old_acc != 0 and sign(old_acc) != sign(_rotation_acc):
		_rotation_acc = 0.0
	
	# SOFT LOCK: Visualmente y funcionalmente es 0 si estamos dentro del umbral
	var effective_rotation = _rotation_acc
	if abs(_rotation_acc) < soft_lock_threshold:
		effective_rotation = 0.0
	
	if pivote_rotacion != null:
		pivote_rotacion.rotation_degrees.z = effective_rotation
	else:
		print_debug("⚠️ ALERTA: No has asignado el 'pivote_rotacion' en el Inspector del volante.")

	current_value = effective_rotation / max_rotation_degrees
	emit_signal("value_changed", current_value, output_axis_name)
