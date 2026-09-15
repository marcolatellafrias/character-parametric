class_name ViewTuner
extends TunerPanel

## EL AFINADOR DE VISTA (F3) — la vista debug de los edificios. Mismo mecanismo que F6 y F7:
## `PropertyTuner` sobre el grupo "Vista" del nodo `city`.
##
## Todo es en vivo y nada regenera: las dos mallas de cada edificio (la final y la debug) y las cajas de lo
## colocado se construyen al generar la ciudad, y acá solo se elige qué se ve (ver BuildingShell y
## City._apply_view).

## Cómo se llama cada perilla en el panel. El nombre de código sigue siendo el que escupe el botón de
## copiar, que es el que se pega en `city.gd`.
const LABELS := {
	"building_debug_view": "Vista debug de edificios",
	"building_grid": "Grilla",
	"show_deformable_boxes": "Cajas de deformables",
	"show_rigid_boxes": "Cajas de rígidos",
	"show_free_boxes": "Cajas de free placement",
}

const HELP := {
	"building_debug_view": "Muestra la malla debug de los edificios en lugar de la final: color del barrio, un piso sí y uno no más oscuro, módulos en damero, la forma básica sin huecos. Apagada, la final: color del arquetipo, sin caras interiores, coplanares unidas.",
	"building_grid": "Con la vista debug, una grilla translúcida sobre cada cara de cada módulo. DEFORMABLE: la del módulo (celdas de 0,213 m; techos, veredas, extremos de puente). RIGID: la de cada superficie (~0,25 m; puertas, ventanas, tanques). Es la misma grilla donde se coloca, vértice por vértice.",
	"show_deformable_boxes": "Con la vista debug, la región exacta que ocupa cada objeto deformable en su grilla, como caja roja translúcida.",
	"show_rigid_boxes": "Lo mismo para los rígidos, en verde.",
	"show_free_boxes": "Lo mismo para las entidades de free placement —autos estacionados, tanques—, en azul. Ahí no hay celdas: la caja es la de la entidad.",
}


func setup_panel() -> void:
	setup(UIState.VIEW, "VISTA DE LA CIUDAD  (F3 cierra)")


func sections() -> Array[Dictionary]:
	var city := _city()
	if city == null:
		return []
	return [{"title": "VISTA → Scripts/city/core/city.gd", "target": city,
		"include": PackedStringArray(["Vista"]), "labels": LABELS, "help": HELP}]


func _city() -> Node:
	for node in get_tree().get_nodes_in_group("city_generator"):
		if node.has_method("generate_and_visualize"):
			return node
	return null
