class_name ShipArchetype
extends SeededArchetype

## UNA FORMA DE NAVE con su tripulación (ver Ship.Shape y ShipHull), para verla sola en el design sandbox:
## congelada en el lugar, pero con sus controles vivos —se puede abrir la compuerta o mover una palanca; la
## nave no se va a ningún lado porque el cuerpo está congelado—. La nave no tiene semilla todavía: dos
## regeneraciones dan la misma nave.

## De sobra para el domo y las dos cajas (el domo mide ~10 m; ver ShipHull.HALF_WIDTH).
const FOOTPRINT := Vector2(16.0, 16.0)
## Con cuánta tripulación se muestra cada forma.
const CREW := {Ship.Shape.DOME: 1, Ship.Shape.BOX: 4, Ship.Shape.SMALL_BOX: 3}

var shape: Ship.Shape = Ship.Shape.DOME
var crew := 1


func _init(p_shape: Ship.Shape = Ship.Shape.DOME) -> void:
	shape = p_shape
	crew = CREW.get(shape, 1)
	display_name = "Nave %s (%d)" % [Ship.Shape.keys()[shape].to_lower().replace("_", " "), crew]


## Una por forma del enum: agregar una forma a `Ship.Shape` la pone en la fila.
static func catalogue() -> Array[ShipArchetype]:
	var out: Array[ShipArchetype] = []
	for shape: int in Ship.Shape.values():
		out.append(ShipArchetype.new(shape as Ship.Shape))
	return out


func max_footprint() -> Vector2:
	return FOOTPRINT


func build(_seed_value: int, parent: Node3D) -> Node3D:
	var ship := Ship.new()
	ship.name = "ship"
	ship.shape = shape
	ship.crew_size = crew
	# Congelada como estática: los controles funcionan, el modelo de vuelo escribe velocidades que el
	# cuerpo ignora. El transform va antes de entrar al árbol, como al spawnearla en el juego.
	ship.freeze = true
	ship.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	ship.transform = Transform3D.IDENTITY
	parent.add_child(ship)
	return ship


func describe(_seed_value: int) -> PackedStringArray:
	return PackedStringArray(["congelada; los controles responden, la nave no se mueve",
		"sin variación por semilla todavía"])


func category_options() -> Array[Dictionary]:
	return [{"key": KEY_T, "label": "T  paredes translúcidas", "apply": _toggle_walls}]


## El mismo interruptor que el menú de debug del juego, sobre todas las naves de la fila.
func _toggle_walls(parcels: Array) -> void:
	if not parcels.is_empty():
		Ship.toggle_translucent_walls((parcels[0] as Node).get_tree())
