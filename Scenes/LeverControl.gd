extends "Interactable.gd"
class_name LeverControl

signal value_changed(new_value, axis_name)

@export var sensitivity: float = 0.005
@export var max_angle: float = 45.0
@export var output_axis_name: String = "throttle"

# --- NUEVA VARIABLE ---
# Aquí asignarás SOLO la parte que se mueve (el mango)
@export var mesh_manija: MeshInstance3D 

var current_value: float = 0.0
var _current_rotation_degrees: float = 0.0

# Dentro de WheelControl.gd

func interact(player):
	
	print("Interactuando con el volante")
	
	

func on_mouse_drag(relative: Vector2):
	var movement = -relative.y * sensitivity 
	
	_current_rotation_degrees += movement * 50.0 
	_current_rotation_degrees = clamp(_current_rotation_degrees, -max_angle, max_angle)
	
	# --- CAMBIO IMPORTANTE ---
	# En lugar de rotar 'meshes_visuales' (que tiene la base),
	# rotamos SOLO la manija específica.
	if mesh_manija:
		# Asumimos rotación en X (Rojo). Si rota raro, prueba .z o .y
		mesh_manija.rotation_degrees.x = _current_rotation_degrees
	
	current_value = _current_rotation_degrees / max_angle
	emit_signal("value_changed", current_value, output_axis_name)
