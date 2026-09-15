class_name DoorArchetype
extends SeededArchetype

## UN TIPO DE PUERTA: su tamaño real en metros y su pieza (ver FacadeProps). Mismo esquema que las ventanas
## (ver WindowArchetype): el arquetipo de edificio lista las que puede usar y cada edificio elige una con su
## semilla (`BuildingCluster.door`); dónde va la puerta lo decide TraversalGenerator, y cómo se apoya sobre
## la vereda, el placer. Hoy la pieza es un panel y la semilla no cambia nada.

var width_m := 1.4
var height_m := 2.2
var depth_m := 0.15
var color := Color(0.9, 0.9, 0.85)
## La sección de arco de la abertura (ver WindowArchetype).
var arch_height_m := 0.3
var arch_segments := 4
## Si la hoja SE MUEVE: no es una pieza fija en la pared sino un portón que sube, con sus botones (ver
## Gate). Un edificio lleva uno solo.
var moving := false


func _init(p_name := "puerta", p_width_m := 1.4, p_height_m := 2.2) -> void:
	display_name = p_name
	width_m = p_width_m
	height_m = p_height_m


static func delivery() -> DoorArchetype:
	return DoorArchetype.new("Puerta de entrega", 1.4, 2.2)


static func gate() -> DoorArchetype:
	var door := DoorArchetype.new("Portón", 2.4, 2.6)
	door.arch_height_m = 0.6
	door.arch_segments = 5
	return door


## El portón de una sucursal: por donde entra y sale la nave (ver ShipHull.HALF_WIDTH), sin arco.
static func garage() -> DoorArchetype:
	var door := DoorArchetype.new("Portón de garaje", 12.0, 6.0)
	door.arch_height_m = 0.0
	door.moving = true
	return door


## Todas las que algún arquetipo de edificio lista, sin repetir: la fila del sandbox, sin registro aparte.
static func catalogue() -> Array[DoorArchetype]:
	var out: Array[DoorArchetype] = []
	var seen := {}
	for building in ArchetypeDefinitions.all():
		for door in building.door_archetypes:
			if not seen.has(door.display_name):
				seen[door.display_name] = true
				out.append(door)
	return out


## La pieza, una sola vez (ver WindowArchetype.unit).
var _unit: UnitMesh = null


func unit() -> UnitMesh:
	if _unit == null:
		_unit = FacadeProps.door_unit(color)
	return _unit


func max_footprint() -> Vector2:
	return Vector2(SampleWall.WIDTH + 1.0, SampleWall.THICKNESS + 2.0)


func build(_seed_value: int, parent: Node3D) -> Node3D:
	return SampleWall.build(parent, unit(), Vector3(width_m, depth_m, height_m), 0.0, CityIndex.Kind.DOOR,
		arch_height_m, arch_segments)


func describe(_seed_value: int) -> PackedStringArray:
	return PackedStringArray(["%.2f × %.2f m" % [width_m, height_m], "la semilla todavía no la varía"])
