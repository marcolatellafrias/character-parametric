extends Node

signal settings_changed

@export_group("Fog")
@export_range(0.0, 600.0, 5.0) var fog_start_distance: float = 0.0:
	set(value):
		fog_start_distance = value
		settings_changed.emit()

## Donde la niebla tapa del todo. Es SOLO niebla: nada de la ciudad deja de dibujarse a esta distancia.
## Estuvo acoplado al corte por distancia de las piezas y se desacoplo a proposito: con el mismo numero,
## acercar la niebla para que la ciudad se sienta mas grande costaba la silueta lejana de los edificios.
## Hoy la ciudad se dibuja entera; un LOD por distancia de verdad queda para mas adelante.
##
## Sigue arrastrando el radio de spawn de autos (este + spawn_buffer): con niebla corta un auto puede
## nacer a la vista. Aceptado por ahora; mejorar el spawn es otro tema.
@export_range(100.0, 2000.0, 10.0) var fog_distance: float = 670.0:
	set(value):
		fog_distance = value
		settings_changed.emit()

@export_group("Limite del mundo")
## LA ALTURA INFRANQUEABLE en metros, y cuanto mide un piso de edificio. Las dos las publica `City` al
## generar las afueras, y salen de una sola variable suya: `City.impassable_floors`.
##
## Viven aca porque quien las necesita no puede preguntarle a la ciudad: la nave se instancia sola, en
## cualquier escena, y no tiene por que conocerla. En 0 significan "todavia no hay ciudad", y quien las
## lea tiene que tener su propio numero de respaldo.
var impassable_height := 0.0
var floor_height := 0.0

@export_group("Spawning")
@export var spawn_buffer: float = 90.0:
	set(value):
		spawn_buffer = value
		settings_changed.emit()

@export var max_cars: int = 100:
	set(value):
		max_cars = value
		settings_changed.emit()

var spawn_radius: float:
	get: return fog_distance + spawn_buffer
