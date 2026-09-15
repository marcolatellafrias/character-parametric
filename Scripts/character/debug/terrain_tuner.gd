class_name TerrainTuner
extends TunerPanel

## EL AFINADOR DEL TERRENO (F7) — las afueras y el relieve de la ciudad. Mismo mecanismo que el del clima:
## `PropertyTuner` lee los `@export` del nodo `city` y arma un control por propiedad.
##
## LAS DOS SECCIONES NO CUESTAN LO MISMO, y por eso están separadas:
##
##   · LAS AFUERAS se rehacen SOLAS, en el acto. Son mil y pico de triángulos que no dependen de nada más
##     que del borde del grafo y del relieve, así que cada slider llama a `City.rebuild_outskirts()` y se
##     ve al toque. Acá se puede iterar de verdad.
##   · EL RELIEVE DE LA CIUDAD mueve las alturas de los nodos, y sobre esas alturas se apoya TODO —
##     manzanas, veredas, edificios, puentes—. No hay forma de tocarlo sin volver a generar la ciudad
##     entera, que tarda decenas de segundos. Por eso sus sliders no aplican nada solos y hay un botón.
##
## Nada se guarda: el botón de copiar escupe los valores para pegarlos en los defaults del script, y lo
## que esté puesto en `Demo.tscn` sobre el nodo `city` los pisa.

const HELP := {
	# ── Afueras ──
	"impassable_floors": "La altura infranqueable, en pisos. Es el techo del mundo: hasta ahí sube la barrera invisible y de ahí sale el techo de la nave. NO es la altura de las montañas.",
	"outskirts_crest_floors": "Dónde nivelan las afueras, en pisos y CON SIGNO. Positivo son montañas alrededor; negativo hunde la falda y la ciudad queda sobre una meseta con la tierra cayendo hacia afuera.",
	"outskirts_depth": "Metros del borde de la ciudad a la cima, antes de la variación por dirección. Grande da faldas largas y suaves; chico, paredones.",
	"outskirts_depth_variation": "Cuánto se estira o se acorta esa distancia según hacia dónde se mire. En 0 el anillo queda parejo y se lee artificial.",
	"outskirts_crest_variation": "Cuánto puede quedarse corta una cima. En 0 todas miden igual —el anillo soso—; alto da cordones y pasos. Que un paso quede bajo no abre el mundo: contiene la barrera.",
	"outskirts_relief": "Valles y lomos POR ENCIMA del perfil, como fracción de la cima. Tiene signo: resta tanto como suma. En 0 la falda es una rampa lisa.",
	"outskirts_feature_size": "Tamaño de esas formas en metros. Grande da cordones largos; chico, cerros sueltos. Es también lo que decide cuántos nodos del borde comparten una misma cima.",
	"outskirts_seed_offset": "Vuelve a sortear las montañas SIN tocar la ciudad. Si la silueta no gusta, mové esto antes que cualquier otra cosa.",
	"outskirts_rise_power": "Cómo sube el perfil. 1 es una rampa recta; arriba de 1 arranca plano y se empina al final, como una montaña; abajo de 1 sube de golpe y se aplana, como una meseta.",
	"outskirts_crest_at": "En qué punto del recorrido está la cima. Chico la trae cerca de la ciudad y deja una bajada larga detrás; en 1.0 la cima es la última tira.",
	"outskirts_back_drop": "Cuánto baja pasada la cima. Le da espesor a la silueta en vez de terminar en un filo en el aire.",
	"outskirts_rings": "En cuántas tiras se parte la subida. Más tiras, silueta más fina y más triángulos.",
	"enable_outskirts_barrier": "La barrera invisible de la última tira. Es LO ÚNICO que contiene: apagarla deja salir del mundo por el paso más bajo.",
	"enable_outskirts_collider": "Si la montaña es sólida. Apagarlo la deja de adorno y se la atraviesa.",
	# ── Relieve de la ciudad ── (piden regenerar)
	"terrain_floors": "Alto de la loma más alta, en pisos de edificio. Es la amplitud del relieve: en 0 la ciudad queda plana.",
	"terrain_max_slope": "La inclinación máxima que se le permite a una calle, en metros por metro. Si el ruido se pasa, se baja la amplitud de TODO el relieve hasta que entre — así que este número puede terminar mandando por encima de terrain_floors.",
	"terrain_feature_size": "Cada cuántos metros cambia el relieve. Chico da lomas apretadas; grande, una sola pendiente larga bajo toda la ciudad.",
	"show_ground": "Si se dibuja el suelo. Apagado se ve el mundo sin piso, útil para mirar los cimientos.",
}


func setup_panel() -> void:
	var regenerate := Button.new()
	regenerate.text = "Regenerar ciudad  (tarda ~30 s)"
	regenerate.pressed.connect(_regenerate)
	var buttons: Array[Button] = [regenerate]
	setup(UIState.TERRAIN, "AFINAR TERRENO Y AFUERAS  (F7 cierra)", buttons)


func sections() -> Array[Dictionary]:
	var city := _city()
	if city == null:
		return []
	return [
		{"title": "AFUERAS (se rehacen solas) → Scripts/city/core/city.gd",
			"target": city, "include": PackedStringArray(["Afueras"]),
			"help": HELP, "on_change": city.rebuild_outskirts},
		{"title": "RELIEVE DE LA CIUDAD (pide regenerar) → Scripts/city/core/city.gd",
			"target": city, "include": PackedStringArray(["Terreno"]), "help": HELP},
	]


## El nodo `city`, que es quien tiene las propiedades y quien sabe rehacerse.
func _city() -> Node:
	for node in get_tree().get_nodes_in_group("city_generator"):
		if node.has_method("rebuild_outskirts"):
			return node
	return null


func _regenerate() -> void:
	var city := _city()
	if city != null and city.has_method("generate_and_visualize"):
		city.call("generate_and_visualize")
