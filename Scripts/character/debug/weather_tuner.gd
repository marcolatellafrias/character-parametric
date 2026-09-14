class_name WeatherTuner
extends CanvasLayer

## EL AFINADOR DEL CLIMA (F6) — el unico menu de clima que hay. Toca en vivo el clima, el alcance de la
## niebla, las nubes, su luz y su viento, y copia todo al portapapeles para pegarlo en el codigo.
##
## No arma un control por seccion: le pasa cada objeto a `PropertyTuner`, que lee sus `@export`s. Por eso
## no puede haber perillas muertas —lo que se ve es lo que el objeto aplica— ni copia desincronizada: el
## boton recorre exactamente la misma lista.
##
## Cada seccion dice EN QUE ARCHIVO se pega lo que se copie, porque los valores viven en tres lados y no
## hay forma de unificarlos: el clima es codigo, el alcance es el autoload de settings y las nubes son un
## recurso del addon, atado al Compositor.
##
## `HELP` es lo unico escrito a mano, y a proposito: las propiedades de Sunshine Clouds no estan
## documentadas en ningun lado, asi que cada linea sale de leer su GLSL. Si una propiedad desaparece la
## linea simplemente no se muestra — no puede quedar una perilla fantasma.
##
## A diferencia del mapa de F2, este SI se anota en `UIState`: hay que arrastrar sliders y abrir
## selectores de color, y para eso el mouse tiene que estar libre. El juego sigue corriendo detras, asi
## que los cambios se ven en vivo sobre la ciudad.
##
## OJO con el alcance: mover `render_distance` no alcanza. El corte por distancia de cada edificio se
## calcula UNA VEZ al generar la ciudad, asi que hay que recalcularlo (`CityDebugView.refresh_ranges`) o
## la niebla se moveria y la geometria se seguiria cortando donde estaba antes.
##
## Nada se guarda en disco: es para mirar y decidir, y lo que sirva se copia a mano.

const MARGIN := 16.0
const WIDTH := 520.0
const BACKGROUND := Color(0.0, 0.0, 0.0, 0.85)

## Que hace cada perilla. Las del clima salen de `city_fog.gd`; las de las nubes, de leer
## `SunshineCloudsCompute.glsl` y `SunshineCloudsDriver.gd`.
const HELP := {
	# ── Clima ──
	"fog_from_sky": "Prendido, la niebla ES el horizonte del cielo y ningun edificio puede recortarse contra el fondo. Apagado usa fog_color, y la silueta la resuelve el fundido de entrada.",
	"fog_curve": "Como se reparte la densidad entre donde empieza y donde tapa del todo. Mayor a 1 empuja la niebla al fondo y deja limpio el medio campo.",
	"sun_energy": "Cuanta luz da el sol AL MUNDO. No cambia el disco (sun_disc_energy) ni cuanto ilumina las nubes (directional_light_power_multiplier, mas abajo).",
	"sun_size": "Diametro del disco en el cielo, en grados. No toca la sombra.",
	"shadow_softness": "Ancho de la penumbra, en grados. 0 = sombra dura. No toca el disco.",
	"sun_disc_energy": "Brillo del disco y de su halo, independiente de la luz que el sol da al mundo. Son dos luces distintas justamente para poder separarlos.",
	"sun_glow": "Radio del halo alrededor del disco, en grados. Grande reparte el mismo brillo sobre medio cielo y el sol se ve como un degrade lavado; chico lo concentra.",
	"sun_curve": "Como cae el halo del borde del disco hacia afuera. Chico lo pega contra el disco; grande lo estira.",
	"ambient_energy": "Luz del cielo sobre todo lo demas. Bajarla sube el contraste entre lo iluminado y lo sombreado.",
	"tint1_strength": "Capa 1 del filtro: multiplica. Un gris 0.5 no hace nada, mas claro levanta y mas oscuro apaga.",
	"tint2_strength": "Capa 2 del filtro: lava plano hacia su color. Es la que aplana el contraste.",
	# ── Alcance ──
	"render_distance": "Donde la niebla tapa del todo Y donde se corta la ciudad: son el mismo numero a proposito. El area crece con el cuadrado, asi que subirlo cuesta caro.",
	"fade_ring": "Metros de fundido con los que entra una pieza antes de su corte.",
	# ── Nubes ──
	"clouds_coverage": "Umbral sobre el ruido grande: cuanto cielo ocupan. Moverlo cambia QUE nubes hay, no solo cuantas. Ademas amplifica lighting_density.",
	"clouds_density": "Multiplica la densidad de cada muestra. Mas densas = mas opacas y mas oscuras por dentro.",
	"atmospheric_density": "Cuanto se funden las nubes con el color de niebla a medida que se alejan. Es el velo blanco del horizonte.",
	"lighting_density": "Cuanto se tapa la nube a si misma del sol. Es LA perilla contra el aspecto plano: junto con lighting_travel_distance decide la profundidad de la sombra propia.",
	"fog_effect_ground": "Cuanto de ese velo atmosferico se aplica tambien sobre la geometria del mundo, no solo sobre el cielo.",
	"use_environment_fog": "Mezcla entre atmosphere_color (en 0) y el color de niebla del clima (en 1). En 1, atmosphere_color no hace absolutamente nada.",
	"clouds_anisotropy": "Cuanto dispersa la luz hacia adelante (el borde plateado mirando al sol). OJO: en 1.0 la funcion de fase da exactamente 0, la absorcion se anula y desaparece toda la sombra propia.",
	"clouds_powder": "Oscurece las zonas de poca densidad, o sea los bordes deshilachados. En 0 no hace nada.",
	"cloud_ambient_color": "Luz del cielo sobre las nubes. Se MULTIPLICA con cloud_ambient_tint antes de llegar al shader: el color efectivo es el producto de los dos.",
	"cloud_ambient_tint": "El otro factor del producto de arriba. Bajarlo apaga la luz ambiente de las nubes aunque el color se vea claro.",
	"atmosphere_color": "Color del velo de distancia. Solo se usa en la medida en que use_environment_fog sea menor a 1.",
	"ambient_occlusion_color": "Tinte de lo que queda a la sombra del cielo. Su ALPHA es el interruptor: en 0 no se calcula oclusion.",
	"accumulation_decay": "Cuanto se reusa del cuadro anterior. Alto es mas suave y mas barato, pero deja estelas al girar la camara.",
	"extra_large_noise_scale": "Tamaño en metros del patron 2D que decide en que ZONAS del mapa hay nubes. Si es mucho mayor que la ciudad, todo el cielo visible cae dentro de una sola mancha.",
	"large_noise_scale": "Tamaño en metros de las masas de nube.",
	"medium_noise_scale": "Tamaño en metros de los bultos dentro de cada masa.",
	"small_noise_scale": "Tamaño en metros del detalle del borde.",
	"clouds_sharpness": "Dureza del borde: un exponente invertido sobre la densidad. Mas alto = bordes mas definidos y menos gasa.",
	"clouds_detail_power": "Cuanto se concentra el ruido chico en los bordes. Cerca de 0 lo reparte parejo por toda la nube, que es lo que las hace verse ruidosas en vez de detalladas.",
	"curl_noise_strength": "Metros que el ruido curl retuerce la forma. Da las volutas; de mas, ruido.",
	"lighting_sharpness": "Contraste entre lo iluminado y lo sombreado, sin cambiar cuanta sombra hay.",
	"wind_swept_range": "Hasta que fraccion de la altura de la capa llega la inclinacion por viento.",
	"wind_swept_strength": "Metros que el viento corre la base respecto del tope. Da la inclinacion tipo yunque.",
	"cloud_floor": "Piso de la capa, en metros.",
	"cloud_ceiling": "Techo de la capa. Mirando al horizonte el rayo cruza kilometros de capa y mirando arriba solo su espesor: una capa fina se ve densa en el horizonte y vacia sobre tu cabeza.",
	"max_step_count": "Techo de pasos por rayo. Cuesta FPS.",
	"max_lighting_steps": "Pasos de la marcha hacia el sol. Cuesta FPS.",
	"resolution_scale": "Resolucion a la que se dibujan las nubes. Native saca los bordes raros contra los edificios, a costa de FPS.",
	"lod_bias": "A que distancia se apaga el detalle (ruido chico, curl y pasos de sombra).",
	"min_step_distance": "Paso del rayo dentro de la nube, en metros. Mas corto = mas detalle y menos bandas, y mas caro.",
	"max_step_distance": "Paso del rayo fuera de la nube, en metros.",
	"lighting_travel_distance": "Metros que se marcha hacia el sol para ver que hay tapando, y a la vez la longitud de absorcion. El otro mando de la profundidad de la sombra propia.",
	# ── Luz y viento de las nubes ──
	"directional_light_power_multiplier": "Escala la fuerza del sol SOLO para las nubes. Es la perilla para tener el mundo bien iluminado y las nubes sin lavarse.",
	"point_light_power_multiplier": "Lo mismo para las luces puntuales que siga el driver.",
	"extra_large_structures_wind_speed": "Velocidad con la que se desplaza cada escala de ruido. Distintas por escala es lo que da sensacion de profundidad.",
}

var _box: VBoxContainer = null
var _copy_button: Button = null
var _built := false


func setup() -> void:
	layer = 95  # debajo del panel de debug (100), encima del mapa (90)
	visible = false
	UIState.changed.connect(_on_ui_changed)

	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.corner_radius_top_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10

	var frame := PanelContainer.new()
	frame.anchor_left = 1.0
	frame.anchor_right = 1.0
	frame.anchor_bottom = 1.0
	frame.offset_left = -(MARGIN + WIDTH)
	frame.offset_right = -MARGIN
	frame.offset_top = MARGIN
	frame.offset_bottom = -MARGIN
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)

	var column := VBoxContainer.new()
	frame.add_child(column)

	var title := Label.new()
	title.text = "AFINAR CLIMA Y NUBES  (F6 cierra)"
	title.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	column.add_child(title)

	_copy_button = Button.new()
	_copy_button.text = "Copiar todo al portapapeles"
	_copy_button.focus_mode = Control.FOCUS_NONE
	_copy_button.pressed.connect(_copy)
	column.add_child(_copy_button)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)

	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)


func toggle() -> void:
	UIState.toggle(UIState.TUNER)


func _on_ui_changed() -> void:
	visible = UIState.is_open(UIState.TUNER)
	# Se arma la primera vez que se abre, no al spawnear: los controles nacen con el valor que el mundo
	# tiene en ese momento, y un panel que casi nunca se abre no cuesta nada.
	if visible and not _built:
		_built = true
		for section in _sections():
			_build(section)


## Las cuatro cosas afinables, cada una con el archivo donde se pegan sus valores.
func _sections() -> Array[Dictionary]:
	var fog := CityFog.find(get_tree())
	if fog == null:
		return []
	var out: Array[Dictionary] = [
		{"title": "CLIMA → Scripts/city/core/weather.gd",
			"target": fog.weather, "help": HELP, "on_change": fog.apply},
		{"title": "ALCANCE DE LA NIEBLA → Scripts/world_settings.gd",
			"target": WorldSettings, "include": PackedStringArray(["Fog"]),
			"help": HELP, "on_change": _refresh_ranges},
	]
	var clouds := fog.clouds()
	if clouds != null:
		# De todo lo que expone el addon se muestran solo esos grupos: lo demas son texturas, shaders y
		# estado interno. `sampled_environment_fog_color` lo reescribe el driver cada cuadro desde el
		# Environment, asi que a mano seria una perilla que se pisa sola.
		out.append({"title": "NUBES → Scenes/clouds.tres", "target": clouds,
			"include": PackedStringArray(["Basic Settings", "Colors", "Structure", "Performance"]),
			"skip": PackedStringArray(["sampled_environment_fog_color"]), "help": HELP})
	var driver := get_tree().get_first_node_in_group("clouds_driver")
	if driver != null:
		out.append({"title": "LUZ Y VIENTO DE LAS NUBES → Scenes/Demo.tscn, nodo Clouds",
			"target": driver, "include": PackedStringArray(["Light Controls", "Wind Controls"]),
			"help": HELP})
	return out


func _build(section: Dictionary) -> void:
	var title := Label.new()
	title.text = str(section["title"])
	title.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	_box.add_child(title)
	PropertyTuner.build(_box, section)
	_box.add_child(HSeparator.new())


## El estado entero como texto pegable, seccion por seccion, con el archivo de destino de cada una.
func _copy() -> void:
	var blocks := PackedStringArray()
	for section in _sections():
		blocks.append("# %s\n%s" % [section["title"], PropertyTuner.dump(section)])
	DisplayServer.clipboard_set("\n\n".join(blocks))
	_copy_button.text = "Copiado ✓"
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(_copy_button):
		_copy_button.text = "Copiar todo al portapapeles"


## Mover el alcance de la niebla obliga a recalcular el corte por distancia de lo ya generado (ver arriba).
func _refresh_ranges() -> void:
	CityDebugView.refresh_ranges(get_tree())
