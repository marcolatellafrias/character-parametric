class_name CityFog
extends WorldEnvironment

## APLICA EL CLIMA — niebla, cielo, luz ambiente, sol y tinte de pantalla, todos juntos porque son una
## sola decision. Los valores viven en `Weather`; aca solo se vuelcan al
## Environment de Godot. No hay shader de niebla propio.
##
## El juego tiene UN clima: no hay presets, ni rueda, ni overrides. Se afina en vivo con F6 y lo que
## funcione se copia a los defaults de `weather.gd` — ver ahi las tres decisiones estructurales
## (niebla contra cielo, color y no alcance, el sol en dos luces).
##
## LAS DISTANCIAS NO SON DEL CLIMA: `fog_depth_begin/end` salen de `WorldSettings` porque ademas mandan
## el corte por distancia de la ciudad y el radio de spawn de autos.
##
## LAS NUBES leen el color de la niebla solas: el driver de Sunshine Clouds copia `fog_light_color` del
## Environment a su recurso en cada cuadro (ver `SunshineCloudsDriver._process`). Por eso el clima les
## llega sin que haya que escribirles nada, y por eso ese campo no se afina a mano.
##
## DOS BANDERAS DEL ENVIRONMENT QUEDAN CLAVADAS EN 0. `fog_sky_affect`, porque el cielo ya lleva el color
## de la niebla en su borde de abajo y teñirlo otra vez lo ensucia dos veces. Y `fog_aerial_perspective`,
## que suena a lo que queremos pero no lo es: mezcla con el cubemap de radiancia —el domo entero
## promediado, dominado por el cenit—, no con el cielo en esa direccion, y lava la niebla hacia un gris
## azulado ajeno a su color.

const TINT_SHADER := "res://Shaders/screen_tint.gdshader"

## El clima. Si no se asigna uno en la escena se usa el de fabrica, que son los defaults de `weather.gd`.
@export var weather: Weather

var _tint_material: ShaderMaterial = null


func _ready() -> void:
	add_to_group("city_fog")
	if weather == null:
		weather = Weather.new()
	_setup_tint()
	apply()
	WorldSettings.settings_changed.connect(apply)


## El unico CityFog de la escena, o null. Lo usa el afinador (F6).
static func find(tree: SceneTree) -> CityFog:
	for node in tree.get_nodes_in_group("city_fog"):
		var fog := node as CityFog
		if fog != null:
			return fog
	return null


## El recurso de nubes (Sunshine Clouds 2), que vive en el Compositor de este mismo nodo. Se devuelve
## como `Resource` a proposito: el afinador lo lee por reflexion, asi nada del juego depende del addon.
func clouds() -> Resource:
	if compositor == null or compositor.compositor_effects.is_empty():
		return null
	return compositor.compositor_effects[0]


## Vuelca el clima entero. Los setters corren durante la carga de la escena, antes de que el nodo tenga
## Environment: de ahi la guarda.
func apply() -> void:
	if environment == null or weather == null:
		return
	var horizon := weather.sky_horizon
	# La disputa hecha interruptor: prendido la niebla ES el horizonte y no hay silueta posible; apagado
	# tiene color propio y la silueta la resuelve el fundido de entrada.
	var fog_color := horizon if weather.fog_from_sky else weather.fog_color

	# ── Niebla ──
	environment.fog_enabled = CityDebugView.fog_on
	environment.fog_mode = Environment.FOG_MODE_DEPTH
	environment.fog_depth_begin = WorldSettings.fog_start_distance
	environment.fog_depth_end = WorldSettings.render_distance
	environment.fog_depth_curve = weather.fog_curve
	environment.fog_density = 1.0
	environment.fog_sun_scatter = weather.fog_sun_scatter
	environment.fog_sky_affect = 0.0
	environment.fog_aerial_perspective = 0.0
	environment.fog_light_color = fog_color

	# ── Cielo ──
	var sky_material := _sky_material()
	if sky_material != null:
		sky_material.sky_top_color = weather.sky_top
		sky_material.sky_horizon_color = horizon
		sky_material.sky_curve = weather.sky_curve
		# La mitad de abajo del domo es lo que se ve al mirar al suelo desde altura. Del mismo color que
		# el horizonte, asi mirar hacia abajo no tiene borde ni recorta la geometria vista contra el
		# suelo. Su color de fabrica es un marron casi negro y aparecia como una franja oscura.
		sky_material.ground_horizon_color = horizon
		sky_material.ground_bottom_color = horizon
		sky_material.ground_curve = weather.sky_curve
		sky_material.sun_angle_max = weather.sun_glow
		sky_material.sun_curve = weather.sun_curve

	# ── Luz ambiente ──
	environment.ambient_light_color = weather.ambient
	environment.ambient_light_energy = weather.ambient_energy

	# ── El sol, en dos luces (ver weather.gd) ──
	# Una direccional apunta por su -Z: con rotacion 0 mira al horizonte, con -90° en X mira al piso.
	# Asi `sun_elevation` es, literal, la altura del sol sobre el horizonte.
	var aim := Vector3(-weather.sun_elevation, weather.sun_azimuth, 0.0)
	for node in get_tree().get_nodes_in_group("sun"):
		var sun := node as DirectionalLight3D
		if sun == null:
			continue
		sun.light_color = weather.sun_core
		sun.light_energy = weather.sun_energy
		sun.rotation_degrees = aim
		sun.light_angular_distance = weather.shadow_softness
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	_apply_sun_disc(aim)

	# ── Tinte de pantalla ──
	if _tint_material != null:
		_tint_material.set_shader_parameter("tint1", weather.tint1)
		_tint_material.set_shader_parameter("tint1_strength", weather.tint1_strength)
		_tint_material.set_shader_parameter("tint2", weather.tint2)
		_tint_material.set_shader_parameter("tint2_strength", weather.tint2_strength)


## El disco del sol: una luz aparte, en SKY_ONLY, que no ilumina ni proyecta. Se crea la primera vez y
## despues solo se actualiza. Con `sun_size` en 0 se apaga: sigue habiendo luz, pero no hay disco.
func _apply_sun_disc(aim: Vector3) -> void:
	var disc := get_node_or_null("SunDisc") as DirectionalLight3D
	if disc == null:
		disc = DirectionalLight3D.new()
		disc.name = "SunDisc"
		disc.shadow_enabled = false
		add_child(disc)
	disc.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	disc.rotation_degrees = aim
	disc.light_color = weather.sun_core
	disc.light_energy = weather.sun_disc_energy
	disc.light_angular_distance = weather.sun_size
	disc.visible = weather.sun_size > 0.0


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


## El material del cielo, si el Environment tiene uno procedural.
func _sky_material() -> ProceduralSkyMaterial:
	if environment.sky == null:
		return null
	return environment.sky.sky_material as ProceduralSkyMaterial
