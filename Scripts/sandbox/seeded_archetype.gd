class_name SeededArchetype
extends RefCounted

## UN ARQUETIPO CON SEMILLA — la base de todo lo que el juego genera por "clase + individuo": el arquetipo
## dice QUÉ es (un edificio pobre, una ventana chica, una nave domo) y la semilla varía el individuo dentro
## de esa clase. Lo comparten los edificios, las ventanas, las puertas, las naves y los vehículos, y por
## eso el design sandbox puede tratarlos a todos igual: una parcela por arquetipo, R para regenerar con
## otra semilla, y el panel que dice qué es y con qué semilla salió.
##
## Nació para el sandbox, pero la intención es que sea el criterio común de generación del mundo: a medida
## que aparezcan cosas en común (cómo se derivan semillas, qué se sincroniza, cómo se describe algo) van a
## vivir acá y no repetidas en cada sistema.

## Cómo se llama en el panel y en la parcela. Obligatorio: un arquetipo sin nombre no se puede señalar.
var display_name := "sin nombre"

## Las OPCIONES DE SU CATEGORÍA (ver `category_options`), compartidas por todos los arquetipos de una fila
## del sandbox: la fila les da a todos el mismo diccionario, y `build` lee de acá lo que la fila tenga
## elegido (la distorsión de la manzana, la vista debug). Fuera del sandbox queda vacío y no pesa.
var options: Dictionary = {}


## Cuánto puede llegar a ocupar en el suelo, en metros (ancho, profundidad), con CUALQUIER semilla. La
## parcela del sandbox se dimensiona con esto una sola vez y no cambia en runtime: regenerar no puede mover
## la grilla. Si un individuo lo excede, el sandbox lo avisa en consola y es un número a corregir acá.
func max_footprint() -> Vector2:
	return Vector2(4.0, 4.0)


## Construye el individuo `seed_value` colgado de `parent`, centrado en su origen y apoyado en y = 0, y
## devuelve su raíz. Quien regenera libera la raíz anterior y vuelve a llamar.
func build(_seed_value: int, _parent: Node3D) -> Node3D:
	return null


## Qué decir de este individuo, una línea por entrada, para el panel del sandbox. El nombre y la semilla
## los pone el panel: acá va lo propio de cada clase.
func describe(_seed_value: int) -> PackedStringArray:
	return PackedStringArray()


## Las opciones de la FILA, para que en el sandbox cada categoría tenga lo que en el juego son menús: la
## transparencia de las naves, la distorsión de la manzana, la vista debug de los edificios. Cada una es
## `{"key": KEY_X, "label": String o Callable que la devuelve, "apply": Callable}`, y `apply(parcels)`
## recibe todas las parcelas de la fila: lo que cambie en `options` lo ven todas, y si hace falta las
## regenera. Se piden al primer arquetipo de la fila.
func category_options() -> Array[Dictionary]:
	return []
