class_name WindowArchetype
extends SeededArchetype

## UN TIPO DE VENTANA: su tamaño real en metros y su pieza (ver FacadeProps). Cada arquetipo de edificio
## lista los tipos que puede usar (`BuildingArchetype.window_archetypes`) y cada edificio elige uno con su
## semilla (`BuildingCluster.window`); dónde van las ventanas lo siguen decidiendo las reglas del edificio
## (FacadePlanner: apiladas o ralas, alféizar, separación).
##
## HACIA DÓNDE VA ESTO (todavía no implementado): como en la vida real, un edificio tiene ventanas de
## fachada, de callejón, de baño (más chicas), de planta baja… Elige UN tipo para cada una de esas
## pseudo-categorías y lo repite —no hay un baño con una ventana distinta de la del baño de al lado—, y
## dentro de un tipo cada ventana varía apenas con su propia semilla: unas macetas, una persiana rota. Esa
## variación por individuo es lo que lo vuelve creíble, y es lo que `build(seed)` va a mostrar en el
## sandbox. Hoy la pieza es un panel y la semilla no cambia nada.

var width_m := 1.0
var height_m := 2.2
var color := Color(0.18, 0.22, 0.28)
## A qué altura del piso se muestra en el sandbox.
var sample_sill_m := 1.2
## LA SECCIÓN DE ARCO: cuánto de arriba de la abertura tiene las esquinas redondeadas, y con cuántos
## segmentos (ver BuildingSkin.add_opening). Es de la abertura en la pared, no de la pieza; una ventana
## común lleva pocos segmentos, un portón más.
var arch_height_m := 0.25
var arch_segments := 3


func _init(p_name := "ventana", p_width_m := 1.0, p_height_m := 2.2) -> void:
	display_name = p_name
	width_m = p_width_m
	height_m = p_height_m


## Los tipos con nombre. Los tres salen de las medidas que cada distrito venía usando.
static func small() -> WindowArchetype:
	return WindowArchetype.new("Ventana chica", 0.8, 1.2)


static func tall() -> WindowArchetype:
	return WindowArchetype.new("Ventanal alto", 1.0, 2.4)


static func wide() -> WindowArchetype:
	return WindowArchetype.new("Ventana de nave", 1.8, 1.4)


## Todos los tipos que algún arquetipo de edificio lista, sin repetir: la fila del sandbox. No hay registro
## aparte —una ventana que ningún edificio lista no existe en el juego, y una que sí, aparece sola.
static func catalogue() -> Array[WindowArchetype]:
	var out: Array[WindowArchetype] = []
	var seen := {}
	for building in ArchetypeDefinitions.all():
		for window in building.window_archetypes:
			if not seen.has(window.display_name):
				seen[window.display_name] = true
				out.append(window)
	return out


## La pieza, una sola vez: se coloca cientos de miles de veces, y armarla cada vez costaba más que colocarla.
var _unit: UnitMesh = null


func unit() -> UnitMesh:
	if _unit == null:
		_unit = FacadeProps.window_unit(color)
	return _unit


func max_footprint() -> Vector2:
	return Vector2(SampleWall.WIDTH + 1.0, SampleWall.THICKNESS + 2.0)


func build(_seed_value: int, parent: Node3D) -> Node3D:
	return SampleWall.build(parent, unit(), Vector3(width_m, FacadePlanner.WINDOW_DEPTH_M, height_m),
		sample_sill_m, CityIndex.Kind.WINDOW, arch_height_m, arch_segments)


func describe(_seed_value: int) -> PackedStringArray:
	return PackedStringArray(["%.2f × %.2f m" % [width_m, height_m], "la semilla todavía no la varía"])
