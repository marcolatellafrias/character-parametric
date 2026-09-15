class_name WeatherTuner
extends TunerPanel

## EL AFINADOR DEL CLIMA (F6) — el unico menu de clima que hay. Toca en vivo el clima, el alcance de la
## niebla, las nubes, su luz y su viento. El marco, el scroll y el boton de copiar los pone `TunerPanel`;
## aca solo esta QUE se afina.
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
	"clouds_enabled": "Si las nubes volumetricas se calculan. Apagadas por defecto: cuestan FPS. Lo demas de las nubes se afina mas abajo, y solo se ve con esto prendido.",
	# ── Alcance ──
	"fog_distance": "Donde la niebla tapa del todo. Solo niebla: la ciudad se dibuja entera igual, asi que acercarla la hace sentir mas grande sin perder la silueta lejana. Arrastra el radio de spawn de autos.",
	# ── Nubes ──
	"clouds_coverage": "Umbral sobre el ruido grande: cuanto cielo ocupan. Moverlo cambia QUE nubes hay, no solo cuantas. Ademas amplifica lighting_density.",
	"clouds_density": "Multiplica la densidad de cada muestra, y la alfa final es esa densidad acumulada hasta saturar en 1. El addon la declara hasta 20; el slider llega a 4, que a escala de ciudad ya es opacidad total y de sobra.",
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

func setup_panel() -> void:
	setup(UIState.TUNER, "AFINAR CLIMA Y NUBES  (F6 cierra)")


## Las cuatro cosas afinables, cada una con el archivo donde se pegan sus valores.
func sections() -> Array[Dictionary]:
	var fog := CityFog.find(get_tree())
	if fog == null:
		return []
	var out: Array[Dictionary] = [
		{"title": "CLIMA → Scripts/city/core/weather.gd",
			"target": fog.weather, "help": HELP, "on_change": fog.apply},
		{"title": "ALCANCE DE LA NIEBLA → Scripts/world_settings.gd",
			"target": WorldSettings, "include": PackedStringArray(["Fog"]),
			"help": HELP},
	]
	var clouds := fog.clouds()
	if clouds != null:
		# De todo lo que expone el addon se muestran solo esos grupos: lo demas son texturas, shaders y
		# estado interno. `sampled_environment_fog_color` lo reescribe el driver cada cuadro desde el
		# Environment, asi que a mano seria una perilla que se pisa sola.
		out.append({"title": "NUBES → Scenes/clouds.tres", "target": clouds,
			"include": PackedStringArray(["Basic Settings", "Colors", "Structure", "Performance"]),
			"skip": PackedStringArray(["sampled_environment_fog_color"]),
			# El addon declara la densidad hasta 20, que es honesto para una capa de 15 km. A escala de
			# ciudad todo lo util vive abajo de 4, o sea en el 20% inicial del recorrido, y un slider lo
			# limitan los pixeles y no el paso. Es la unica que lo necesita: el resto de los rangos del
			# addon caen donde caen los valores que usamos.
			"ranges": {"clouds_density": [0.0, 4.0]}, "help": HELP})
	var driver := get_tree().get_first_node_in_group("clouds_driver")
	if driver != null:
		out.append({"title": "LUZ Y VIENTO DE LAS NUBES → Scenes/Demo.tscn, nodo Clouds",
			"target": driver, "include": PackedStringArray(["Light Controls", "Wind Controls"]),
			"help": HELP})
	return out
