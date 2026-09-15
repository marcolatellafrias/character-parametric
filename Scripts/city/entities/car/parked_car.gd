class_name ParkedCar
extends RigidBody3D

## UN AUTO ESTACIONADO: la misma caja que el tráfico dibuja para su tipo (ver CarArchetypes), apoyado en la
## franja de cordón por free placement (ver City._visualize_parked_cars). Es un obstáculo que se puede
## empujar —el más pesado de los personajes tiene que poder moverlo; `MASS` se afina en partida— pero solo
## existe para la física cuando alguien está cerca (ver PassiveBodies).

const MASS := 350.0
## Ancho de la franja de cordón donde se estaciona, del cordón hacia la calle: entra cualquier auto de
## hasta ~2,2 m de ancho con margen. Lo lee también el tráfico, que la reserva como obstáculo fijo (ver
## AreaInstantiator._register_parking_strips).
const STRIP_M := 2.6

var type: CarArchetypes.Type = CarArchetypes.Type.TAXI


## El auto de un tipo, con su cuerpo. `physical` en false da solo la caja (la muestra a escala del sandbox,
## donde un cuerpo escalado no tiene sentido).
static func create(car_type: CarArchetypes.Type, physical: bool) -> Node3D:
	var archetype := CarArchetypes.get_archetype(car_type)
	var visual := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(archetype.width, archetype.height, archetype.depth)
	visual.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = archetype.color
	visual.material_override = material
	visual.position = Vector3(0.0, archetype.height * 0.5, 0.0)
	if not physical:
		return visual

	var car := ParkedCar.new()
	car.type = car_type
	car.mass = MASS
	car.add_child(visual)
	var shape := CollisionShape3D.new()
	var collider := BoxShape3D.new()
	collider.size = box.size
	shape.shape = collider
	shape.position = visual.position
	car.add_child(shape)
	return car
