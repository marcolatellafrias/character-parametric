class_name VehicleArchetype
extends SeededArchetype

## UN TIPO DE VEHÍCULO (ver CarArchetypes) parado en el suelo, a escala 1:1, para el design sandbox. Es la
## misma caja que el tráfico dibuja para ese tipo (ver FlyingCar.get_shared_mesh): medidas y color del
## arquetipo. La semilla de un auto en el juego decide su ruta (FlyingCar.initialize_from_seed); parado,
## no cambia nada todavía.

var type: CarArchetypes.Type = CarArchetypes.Type.TAXI


func _init(p_type: CarArchetypes.Type = CarArchetypes.Type.TAXI) -> void:
	type = p_type
	display_name = _archetype().name


## Uno por tipo del enum: agregar un tipo a `CarArchetypes.Type` lo pone en la fila.
static func catalogue() -> Array[VehicleArchetype]:
	var out: Array[VehicleArchetype] = []
	for car_type: int in CarArchetypes.Type.values():
		out.append(VehicleArchetype.new(car_type as CarArchetypes.Type))
	return out


func _archetype() -> CarArchetypes.Archetype:
	return CarArchetypes.get_archetype(type)


func max_footprint() -> Vector2:
	var a := _archetype()
	return Vector2(a.width + 1.0, a.depth + 1.0)


func build(_seed_value: int, parent: Node3D) -> Node3D:
	var a := _archetype()
	var car := MeshInstance3D.new()
	car.name = "vehicle"
	var box := BoxMesh.new()
	box.size = Vector3(a.width, a.height, a.depth)
	car.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = a.color
	car.material_override = material
	car.position = Vector3(0.0, a.height * 0.5, 0.0)
	parent.add_child(car)
	return car


func describe(_seed_value: int) -> PackedStringArray:
	var a := _archetype()
	return PackedStringArray(["%.1f × %.1f × %.1f m · %.0f–%.0f m/s" % [a.width, a.height, a.depth, a.min_speed, a.max_speed],
		"la semilla decide su ruta en el juego; parado no cambia nada"])
