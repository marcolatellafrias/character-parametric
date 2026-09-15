extends Node3D

## EL DESIGN SANDBOX — otro mundo, para iterar sin generar la ciudad: un plano claro y neutro con FILAS de
## parcelas, una fila por categoría del juego (edificios, ventanas, puertas, naves, controles, vehículos) y una
## parcela por arquetipo de esa categoría (ver SeededArchetype). Sin red, sin menús de debug, sin HUD: solo
## el ente (SandboxEntity) caminando entre parcelas —V vuela—, y un panel a la derecha cuando está en la
## zona de interacción de una (ver SandboxPanel). R regenera el individuo con otra semilla y lo hace
## destellar; cada fila puede tener además sus propias teclas (`SeededArchetype.category_options`).
##
## LAS TRES ZONAS de una parcela, concéntricas: la PARCELA, donde vive el individuo, del ancho que declare
## su arquetipo (`max_footprint`, el máximo en cualquier semilla: la grilla no cambia en runtime) y de la
## profundidad mayor de su categoría; la ZONA DE INTERACCIÓN, `INTERACT_PAD` alrededor, para dar la vuelta
## al objeto mirándolo con el panel abierto; y la SEPARACIÓN con los vecinos, `ELEMENT_GAP` dentro de una
## fila y `CATEGORY_GAP` entre filas. Las tres constantes son globales.
##
## Se entra desde el menú de inicio. Ver technical/design-sandbox.md.

const INTERACT_PAD := 2.0
const ELEMENT_GAP := 3.0
const CATEGORY_GAP := 8.0

const GROUND_SIZE := 2000.0
const GROUND_COLOR := Color(0.82, 0.80, 0.76)
const SKY_TOP := Color(0.55, 0.68, 0.85)
const SKY_HORIZON := Color(0.82, 0.86, 0.9)
const CATEGORY_LABEL_COLOR := Color(0.25, 0.24, 0.22)
const PLAYER_START := Vector3(-5.0, 0.5, -5.0)

## Cada fila: `{name, parcels: Array[SandboxParcel], options: Array[Dictionary]}`.
var _rows: Array[Dictionary] = []
var _panel: SandboxPanel = null
var _entity: SandboxEntity = null
var _current: SandboxParcel = null
var _current_row: Dictionary = {}


func _ready() -> void:
	_build_world()
	_build_rows()
	_panel = SandboxPanel.new()
	add_child(_panel)
	_entity = SandboxEntity.new()
	_entity.position = PLAYER_START
	add_child(_entity)


## Las categorías y sus arquetipos, en el orden de las filas. Cada catálogo se arma solo de lo que el juego
## ya registra (el enum de formas de nave, los tipos de auto, lo que listan los edificios): agregar un
## arquetipo al juego lo pone acá sin tocar esto.
static func _categories() -> Array[Dictionary]:
	return [
		{"name": "Edificios", "archetypes": ArchetypeDefinitions.all()},
		{"name": "Ventanas", "archetypes": WindowArchetype.catalogue()},
		{"name": "Puertas", "archetypes": DoorArchetype.catalogue()},
		{"name": "Naves", "archetypes": ShipArchetype.catalogue()},
		{"name": "Controles", "archetypes": ControlArchetype.catalogue()},
		{"name": "Vehículos", "archetypes": VehicleArchetype.catalogue()},
	]


# ── Construcción ─────────────────────────────────────────────────────────────────────────────────

func _build_world() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOR
	floor_mesh.material_override = material
	ground.add_child(floor_mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 1.0, GROUND_SIZE)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	add_child(ground)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	sky_material.ground_bottom_color = GROUND_COLOR
	sky_material.ground_horizon_color = SKY_HORIZON
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)


## Las filas: una por categoría a lo largo de +Z, sus parcelas a lo largo de +X. Cada parcela se coloca
## por el centro, con su zona de interacción entera dentro del tramo que le toca. Los arquetipos de una
## fila comparten un mismo diccionario de opciones (ver SeededArchetype.options).
func _build_rows() -> void:
	var z := 0.0
	for category in _categories():
		var category_name: String = category["name"]
		var archetypes: Array = category["archetypes"]
		if archetypes.is_empty():
			continue
		var shared_options := {}
		var depth := 0.0
		for a in archetypes:
			var archetype := a as SeededArchetype
			archetype.options = shared_options
			depth = maxf(depth, archetype.max_footprint().y)

		var label := Label3D.new()
		label.text = category_name.to_upper()
		label.font_size = 96
		label.modulate = CATEGORY_LABEL_COLOR
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(-2.0, 1.0, z + INTERACT_PAD + depth * 0.5)
		add_child(label)

		var parcels: Array[SandboxParcel] = []
		var x := 0.0
		for a in archetypes:
			var archetype := a as SeededArchetype
			var width := archetype.max_footprint().x
			var parcel := SandboxParcel.new()
			parcel.position = Vector3(x + INTERACT_PAD + width * 0.5, 0.0, z + INTERACT_PAD + depth * 0.5)
			add_child(parcel)
			parcel.setup(archetype, category_name, Vector2(width, depth), INTERACT_PAD,
				_initial_seed(category_name, archetype.display_name))
			parcels.append(parcel)
			x += width + INTERACT_PAD * 2.0 + ELEMENT_GAP
		_rows.append({"name": category_name, "parcels": parcels,
			"options": (archetypes[0] as SeededArchetype).category_options()})
		z += depth + INTERACT_PAD * 2.0 + CATEGORY_GAP


## La misma semilla de arranque para la misma parcela en cada sesión: lo que se vio ayer se vuelve a ver.
static func _initial_seed(category_name: String, archetype_name: String) -> int:
	return absi(hash(category_name + "/" + archetype_name)) % 1000000


# ── En juego ─────────────────────────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	var at := _entity.global_position
	var inside: SandboxParcel = null
	var inside_row: Dictionary = {}
	for row in _rows:
		for parcel: SandboxParcel in row["parcels"]:
			if parcel.contains(at):
				inside = parcel
				inside_row = row
				break
		if inside != null:
			break
	if inside == _current:
		return
	_current = inside
	_current_row = inside_row
	_refresh_panel()


func _refresh_panel() -> void:
	if _current != null:
		_panel.show_parcel(_current, _current_row["options"])
	else:
		_panel.hide_panel()


func _input(event: InputEvent) -> void:
	if _current == null or not (event is InputEventKey) or not UIState.gameplay_active():
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_R:
			_current.regenerate(randi())
		KEY_C:
			_panel.copy(_current)
		_:
			for option: Dictionary in _current_row["options"]:
				if int(option["key"]) == key.keycode:
					(option["apply"] as Callable).call(_current_row["parcels"])
					break
	_refresh_panel()
