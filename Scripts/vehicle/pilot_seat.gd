extends "res://Scripts/vehicle/steering_wheel.gd"

@export var posicion_ojos: Marker3D

# Sobrescribimos la función que busca el jugador
func interact(player):
	if player.has_method("sit_down"):
		player.sit_down(posicion_ojos)

# Sobrescribimos esta para que no haga nada raro con el mouse al clickearlo
func on_mouse_drag(_relative):
	pass
