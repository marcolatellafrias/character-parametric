class_name CityFog
extends WorldEnvironment

## EL CLIMA — la niebla, el cielo, la luz ambiente y el tinte de pantalla, todos juntos porque son una sola
## decisión. Vive en el Environment de Godot; no hay shader de niebla propio.
##
## ── NIEBLA Y CIELO: LO DECIDE EL PRESET ──────────────────────────────────────────────────────────
## `fog_color` y `sky_horizon` son campos SEPARADOS, y cada clima elige si los hace coincidir.
##
## Los ocho presets de San Andreas los igualan, que es lo que hace el timecyc (una sola columna, `Sky bot`,
## para los dos). Con eso la silueta es imposible: una pieza saturada de niebla queda pintada exactamente
## del color que tiene detrás. Es elegante, pero obliga a que el color de la ciudad lejana sea el del
## cielo, y eso terminó no gustando.
##
## El preset `original` —el default— hace lo contrario a propósito: CIELO STOCK y NIEBLA AZUL OSCURA,
## independiente. Es el look de la build del 25/6. Ahí la silueta sí existe, y por eso el fundido de
## entrada (`City._fade_into_fog`) vuelve a ser la pieza que la sostiene, en vez de un lujo.
##
## ── LO QUE EL CLIMA NO CAMBIA ────────────────────────────────────────────────────────────────────
## LAS DISTANCIAS. En las ocho filas de timecyc que copié, el far clip vale 2000 en todas: San Andreas
## cambia el COLOR con el clima, nunca el alcance. Por eso `fog_depth_begin/end` salen de WorldSettings y
## son iguales para todos los presets — y por eso cambiar de clima nunca puede hacer que la ciudad se
## sienta más chica.
##
## ── EL SOL, EN DOS LUCES ─────────────────────────────────────────────────────────────────────────
## `DirectionalLight3D.light_angular_distance` viene en 0 de fábrica, y con 0 el disco que dibuja el
## ProceduralSkyMaterial es un punto: por eso no había sol visible. Pero esa MISMA propiedad es el tamaño
## angular del sol para la sombra, o sea el ancho de la penumbra —el sol real mide 0,53°—. Subirla para
## que se vea el disco difumina las sombras entre edificios hasta borrarlas.
##
## Son dos cosas distintas, así que van dos luces: la del grupo `sun` ilumina y proyecta con la dureza de
## `shadow_softness`, y una segunda en `SKY_MODE_SKY_ONLY` dibuja el disco con `sun_size` sin aportar ni
## luz ni sombra. Con `sun_size` en 0 no hay disco pero sigue habiendo sol, que es lo que hace San
## Andreas en lluvia y en tormenta de arena.
##
## ── EL TINTE DE PANTALLA ─────────────────────────────────────────────────────────────────────────
## Dos capas sobre el cuadro terminado (ver Shaders/screen_tint.gdshader). En San Andreas van con alpha 195
## de 255; acá `tint_strength` las escala porque nuestro tonemapping no es el de RenderWare y a fuerza
## completa se come el contraste. Es la perilla de "qué tan película vieja" se ve el juego.

const TINT_SHADER := "res://Shaders/screen_tint.gdshader"

## Qué clima está puesto. Se cambia con F5 o desde la pestaña Clima del panel (F1). Elegir uno BORRA los
## retoques manuales del afinador (F6): un preset es un punto de partida completo, no una capa.
@export var preset_id: String = "":
	set(value):
		preset_id = value
		_overrides.clear()
		_apply()

## Cuánto de las dos capas de tinte se aplica, sobre lo que dice el preset. En 0 no hay tinte.
@export_range(0.0, 1.0) var tint_strength: float = 1.0:
	set(value):
		tint_strength = value
		_apply()

## Cómo se reparte la densidad de niebla entre las dos distancias: >1 la empuja hacia el fondo, dejando el
## medio campo limpio. En 1.0 sube lineal desde `fog_start_distance` y la ciudad se siente encerrada.
@export_range(0.1, 8.0) var depth_curve: float = 1.5:
	set(value):
		depth_curve = value
		_apply()

## Cuánto se aclara la niebla mirando hacia el sol.
@export_range(0.0, 1.0) var sun_scatter: float = 0.2:
	set(value):
		sun_scatter = value
		_apply()

var _tint_material: ShaderMaterial = null
## Retoques a mano encima del preset (los pone el afinador de F6). Viven en memoria y nada más: lo que
## sirva se copia a mano a `WeatherPresets`, que es donde las decisiones quedan.
var _overrides: Dictionary = {}


func _ready() -> void:
	add_to_group("city_fog")
	if preset_id.is_empty():
		preset_id = WeatherPresets.default_id()
	_setup_tint()
	_apply()
	WorldSettings.settings_changed.connect(_apply)


## El tinte necesita un nodo propio por encima de todo. Se arma una sola vez.
func _setup_tint() -> void:
	var shader := load(TINT_SHADER) as Shader
	if shader == null:
		return
	_tint_material = ShaderMaterial.new()
	_tint_material.shader = shader
	var layer := CanvasLayer.new()
	layer.name = "ScreenTint"
	layer.layer = 100
	var rect := ColorRect.new()
	rect.name = "Tint"
	rect.material = _tint_material
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	add_child(layer)


## Los setters corren durante la carga de la escena, antes de que el nodo tenga Environment: de ahí la guarda.
func _apply() -> void:
	if environment == null:
		return
	var horizon: Color = value_of("sky_horizon")

	# ── Niebla ──
	environment.fog_enabled = CityDebugView.fog_on
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = WorldSettings.fog_start_distance
	environment.fog_depth_end = WorldSettings.render_distance
	environment.fog_depth_curve = depth_curve
	environment.fog_density = 1.0
	environment.fog_sun_scatter = sun_scatter
	# El cielo NO se tiñe nunca: teñirlo fue justamente lo que no gustaba —queda de un solo color— y el
	# shader viejo lo resolvía descartándolo. Aerial perspective queda en 0 porque mezcla con el radiance
	# cubemap —el domo entero promediado—, que lava la niebla hacia un gris azulado ajeno a su color.
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.0
	environment.fog_light_color = value_of("fog_color")

	# ── Cielo ──
	var sky_material := _sky_material()
	if sky_material != null:
		sky_material.sky_top_color = value_of("sky_top")
		sky_material.sky_horizon_color = horizon
		sky_material.sky_curve = value_of("sky_curve")
		# La mitad de abajo del domo es lo que se ve al mirar al suelo desde altura. Del mismo color que el
		# horizonte, así mirar hacia abajo no tiene borde y la geometría vista contra el suelo tampoco se
		# recorta. Su color de fábrica es un marrón casi negro y aparecía como una franja oscura.
		sky_material.ground_horizon_color = horizon
		sky_material.ground_bottom_color = horizon
		sky_material.ground_curve = value_of("sky_curve")

	# ── Luz ambiente ──
	environment.ambient_light_color = value_of("ambient")
	environment.ambient_light_energy = value_of("ambient_energy")

	# ── El sol: DOS luces ──
	# `light_angular_distance` hace dos cosas a la vez —el tamaño del disco en el cielo Y el ancho de la
	# penumbra—, así que con una sola luz no se puede tener sol visible y sombras definidas al mismo
	# tiempo. La del grupo `sun` ILUMINA Y PROYECTA, con la dureza que pida el clima; el disco lo dibuja
	# una segunda luz en modo SKY_ONLY, que no aporta luz ni sombra y existe solo para verse.
	var aim := Vector3(-float(value_of("sun_elevation")), float(value_of("sun_azimuth")), 0.0)
	for node in get_tree().get_nodes_in_group("sun"):
		var sun := node as DirectionalLight3D
		if sun == null:
			continue
		sun.light_color = value_of("sun_core")
		sun.light_energy = value_of("sun_energy")
		# Una direccional apunta por su -Z: con rotación 0 mira al horizonte, con -90° en X mira al piso.
		# Así `sun_elevation` es, literal, la altura del sol sobre el horizonte.
		sun.rotation_degrees = aim
		sun.light_angular_distance = value_of("shadow_softness")
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_apply_sun_disc(aim)
	if sky_material != null:
		sky_material.sun_angle_max = value_of("sun_glow")

	# ── Tinte de pantalla ──
	if _tint_material != null:
		_tint_material.set_shader_parameter("tint1", value_of("tint1"))
		_tint_material.set_shader_parameter("tint1_strength", float(value_of("tint1_alpha")) * tint_strength)
		_tint_material.set_shader_parameter("tint2", value_of("tint2"))
		_tint_material.set_shader_parameter("tint2_strength", float(value_of("tint2_alpha")) * tint_strength * 0.5)


## El disco del sol: una luz aparte, en SKY_ONLY, que no ilumina ni proyecta. Se crea la primera vez y
## después solo se actualiza. Con `sun_size` en 0 se apaga —es lo que hace San Andreas en lluvia y en
## tormenta de arena: sigue habiendo luz, pero no hay disco—.
func _apply_sun_disc(aim: Vector3) -> void:
	var size: float = value_of("sun_size")
	var disc := get_node_or_null("SunDisc") as DirectionalLight3D
	if disc == null:
		disc = DirectionalLight3D.new()
		disc.name = "SunDisc"
		disc.shadow_enabled = false
		add_child(disc)
	disc.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	disc.rotation_degrees = aim
	disc.light_color = value_of("sun_core")
	disc.light_angular_distance = size
	disc.visible = size > 0.0


## El material del cielo, si el Environment tiene uno procedural.
func _sky_material() -> ProceduralSkyMaterial:
	if environment.sky == null:
		return null
	return environment.sky.sky_material as ProceduralSkyMaterial


## El valor vivo de un campo del clima: el retoque manual si lo hay, y si no lo que dice el preset.
func value_of(key: String) -> Variant:
	if _overrides.has(key):
		return _overrides[key]
	return WeatherPresets.get_preset(preset_id).get(key)


## Pisa un campo del clima a mano (afinador F6).
func set_override(key: String, value: Variant) -> void:
	_overrides[key] = value
	_apply()


## Devuelve todo al preset tal cual está en la tabla.
func clear_overrides() -> void:
	_overrides.clear()
	_apply()


func current_name() -> String:
	return str(WeatherPresets.get_preset(preset_id)["name"])


## ── API de debug (F5 y la pestaña Clima del panel) ───────────────────────────────────────────────

## Pone un clima en todos los CityFog de la escena. Devuelve su nombre para mostrarlo.
static func apply_to_tree(tree: SceneTree, id: String) -> String:
	var shown := ""
	for node in tree.get_nodes_in_group("city_fog"):
		var fog := node as CityFog
		if fog != null:
			fog.preset_id = id
			shown = fog.current_name()
	return shown


## Pasa al siguiente clima de la rueda.
static func cycle(tree: SceneTree) -> String:
	var current := ""
	for node in tree.get_nodes_in_group("city_fog"):
		var fog := node as CityFog
		if fog != null:
			current = fog.preset_id
			break
	return apply_to_tree(tree, WeatherPresets.next_id(current))
