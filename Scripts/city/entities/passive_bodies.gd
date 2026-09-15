class_name PassiveBodies
extends Node3D

## COLISIÓN PASIVA: cuerpos que no existen para la física hasta que alguien que puede tocarlos está cerca.
## Un auto estacionado, un container, mañana un auto NPC o un peatón que se mueve programáticamente: miles
## de cuerpos por ciudad, de los que en cualquier momento importan los diez que tienen a un jugador al lado.
##
## Cada cuerpo registrado vive CONGELADO como estático —para Jolt es una forma quieta, como una pared— y se
## despierta (dinámico, con gravedad y empuje) cuando un TOCADOR entra en `wake_radius`: una cápsula de
## jugador o una nave. Cuando todos se alejan y el cuerpo descansa, se vuelve a congelar donde quedó. Un
## solo nodo recorre a todos cada `CHECK_EVERY` cuadros de física: sin un script por cuerpo.
##
## Lo que todavía no es tocador: los objetos agarrables y los peatones (ver technical/traffic.md, "Passive
## collision"). Empujar sincronizado por red tampoco existe aún: lo que un jugador mueve, lo ve solo él.

const CHECK_EVERY := 6
const DEFAULT_WAKE_RADIUS := 12.0

var wake_radius := DEFAULT_WAKE_RADIUS
var _bodies: Array[RigidBody3D] = []


func register(body: RigidBody3D) -> void:
	body.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	body.freeze = true
	_bodies.append(body)


func _physics_process(_delta: float) -> void:
	if Engine.get_physics_frames() % CHECK_EVERY != 0:
		return
	var touchers := _toucher_positions()
	var radius_squared := wake_radius * wake_radius
	for body in _bodies:
		if not is_instance_valid(body):
			continue
		var at := body.global_position
		var near := false
		for t in touchers:
			if at.distance_squared_to(t) < radius_squared:
				near = true
				break
		if near and body.freeze:
			body.freeze = false
		elif not near and not body.freeze and body.sleeping:
			body.freeze = true


## Quiénes pueden tocar: las cápsulas de los jugadores y las naves.
func _toucher_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	var tree := get_tree()
	for node in tree.get_nodes_in_group(CharacterRigidBody3D.CHARACTER_GROUP):
		out.append((node as Node3D).global_position)
	for node in tree.get_nodes_in_group(Ship.GROUP):
		out.append((node as Node3D).global_position)
	return out
