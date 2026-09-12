extends Node

signal settings_changed

@export_group("Fog")
@export var fog_start_distance: float = 50.0:
	set(value):
		fog_start_distance = value
		settings_changed.emit()

## Donde la niebla llega a tapar del todo Y donde se cortan las piezas de la ciudad: son el mismo numero a
## proposito (ver Scripts/city/core/city_fog.gd). Subirlo abre el horizonte pero dibuja mucha mas ciudad: el
## area crece con el cuadrado, asi que subirlo cuesta caro. Tambien arrastra el radio de spawn de autos,
## que es este + spawn_buffer.
##
## 350 m son los de la build del 25/6, elegidos a ojo y confirmados despues: con niebla FUERTE (que este
## juego necesita, o el mundo se ve monotono) ese radio no se siente encerrado. Se probo 800 y se sintio
## peor, no mejor: lo que abre el mundo es el color de la niebla, no su alcance.
@export var render_distance: float = 350.0:
	set(value):
		render_distance = value
		settings_changed.emit()

## Ancho MINIMO del anillo donde las piezas entran fundiendose, justo antes de que se dejen de dibujar.
## El ancho real lo da `fade_ring_for()`, que lo escala con la distancia —ver ahi por que—.
@export var fade_ring: float = 20.0:
	set(value):
		fade_ring = value
		settings_changed.emit()

## Cuantos metros dura el fundido de entrada de una pieza que se deja de dibujar a `end_distance`.
##
## La formula es la de GTA San Andreas (`CVisibilityPlugins::CalculateFadingAtomicAlpha`): 20 unidades
## para lo cercano, y `distancia/15 + 10` para todo lo que se dibuje a mas de 150. La idea es que el
## fundido se vea igual de gradual a cualquier distancia: un anillo de 20 m es suave para algo que
## aparece a 100 m y un parpadeo para algo que aparece a 800. Con 800 m de alcance da unos 63 m.
func fade_ring_for(end_distance: float) -> float:
	if end_distance <= 150.0:
		return fade_ring
	return maxf(fade_ring, end_distance / 15.0 + 10.0)

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
	get: return render_distance + spawn_buffer
