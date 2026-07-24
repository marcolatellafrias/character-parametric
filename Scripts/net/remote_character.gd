class_name RemoteCharacter
extends Node3D
## Proxy de un jugador remoto (milestone 2 de multiplayer): solo la cápsula + su
## ground ray, sin esqueleto ni física. Su transform lo maneja el CharacterNetSync
## hijo, que interpola los estados que manda el peer dueño. El esqueleto estético
## (reconstruido desde el seed) llega en el milestone 3 — ver
## Scripts/city/docs/conceptual/multiplayer.md.
##
## El root se coloca en el CENTRO de la cápsula (lo que transmite el dueño), así que
## la malla va centrada en el origen y el ray sale desde la base.

const HEIGHT := 1.8
const RADIUS := 0.3
const COLOR_GROUNDED := Color(1.0, 1.0, 1.0, 0.4)
const COLOR_AIRBORNE := Color(1.0, 0.5, 0.0, 0.4)

var _material: StandardMaterial3D
var _ground_ray: RayCast3D

func _ready() -> void:
	var capsule := CapsuleMesh.new()
	capsule.height = HEIGHT
	capsule.radius = RADIUS

	_material = StandardMaterial3D.new()
	_material.albedo_color = COLOR_GROUNDED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = capsule
	mesh_instance.material_override = _material
	add_child(mesh_instance)

	_ground_ray = RayCast3D.new()
	_ground_ray.position = Vector3(0.0, -(HEIGHT * 0.5) + RADIUS, 0.0)
	_ground_ray.target_position = Vector3(0.0, -(RADIUS + 0.12), 0.0)
	add_child(_ground_ray)

func _physics_process(_delta: float) -> void:
	# El ray corre local sobre la posición ya interpolada, así el color grounded/aire
	# no necesita sincronizarse.
	if not is_instance_valid(_ground_ray):
		return
	_ground_ray.force_raycast_update()
	_material.albedo_color = COLOR_GROUNDED if _ground_ray.is_colliding() else COLOR_AIRBORNE
