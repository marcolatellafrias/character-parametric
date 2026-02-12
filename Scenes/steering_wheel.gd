extends "Interactable.gd" # Hereda del script que pusiste antes (Opción 2)
class_name WheelControl

signal value_changed(new_value, axis_name)

@export var sensitivity: float = 0.005
@export var max_rotation_degrees: float = 90.0
@export var output_axis_name: String = "steering"

# --- VARIABLE SEGURA ---
# Arrastra aquí tu Marker3D o Pivote
@export var pivote_rotacion: Node3D 

var _rotation_acc: float = 0.0
var current_value: float = 0.0
# Dentro de WheelControl.gd

func interact(player):
	# Esta función puede quedar vacía o tener un print
	# Su único trabajo es existir para que el jugador no crashee
	print("Interactuando con el volante")
	
	# Si quieres que al tocar el volante el jugador también se siente 
	# automáticamente (opcional), podrías poner:
	#if player.has_method("sit_down"):
	#     player.sit_down(un_marker_de_referencia)
func on_mouse_drag(relative: Vector2):
	var movement = -relative.x * sensitivity * 50.0
	_rotation_acc += movement
	_rotation_acc = clamp(_rotation_acc, -max_rotation_degrees, max_rotation_degrees)
	
	# --- AQUÍ ESTABA EL ERROR ---
	# Antes intentaba rotar sin preguntar. Ahora preguntamos primero.
	if pivote_rotacion != null:
		pivote_rotacion.rotation_degrees.z = _rotation_acc
	else:
		# Si se te olvidó asignarlo, te avisará en la consola sin romper el juego
		print_debug("⚠️ ALERTA: No has asignado el 'pivote_rotacion' en el Inspector del volante.")

	current_value = _rotation_acc / max_rotation_degrees
	print("Volante gritando: ", output_axis_name, " Valor: ", current_value) # <--- AGREGAR ESTO
	emit_signal("value_changed", current_value, output_axis_name)
# Al final de la función:
