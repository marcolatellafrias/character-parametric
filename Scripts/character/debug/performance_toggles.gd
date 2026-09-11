class_name PerformanceToggles

## Pestaña Performance del panel F1: apaga partes del juego para ver cuánto cuesta cada una. Ver
## technical/ui.md.
##
## Cada parte tiene dos llaves, DIBUJO y LÓGICA, así se ve si pesa en la GPU o en la CPU. Las dos actúan
## sobre los nodos raíz de la parte (ver `_roots`): sin dibujo, invisibles; sin lógica, en
## PROCESS_MODE_DISABLED, que corta el process y el physics_process de todo lo que cuelga y saca sus
## cuerpos de la física. Arriba van los números en vivo, para leer el efecto sin salir del panel.
##
## - Controles de relleno: los tableros de relleno de las naves. Los que funcionan quedan, así se sigue
##   pudiendo volar y abrir la compuerta.
## - Autos: quedan congelados donde estaban, y su spawner se para.
## - Edificios: sin lógica quedan sin colliders.
## - Personajes: solo los NPC, los que no maneja ningún jugador —ni el propio ni los de otros—.
##
## El estado es estático: sobrevive al respawn, que rehace el panel, y alcanza a lo que aparece después
## —una nave o un NPC nuevos nacen como diga su llave— escuchando `SceneTree.node_added`.

enum Part { DUMMIES, CARS, BUILDINGS, NPCS }

const TAB := "Performance"
const PART_NAMES: Array[String] = ["Controles de relleno", "Autos", "Edificios", "Personajes (NPC)"]
## Cada cuánto se refrescan los números, en segundos.
const READOUT_PERIOD := 0.25

static var _draw: Array[bool] = [true, true, true, true]
static var _logic: Array[bool] = [true, true, true, true]


## Arma la pestaña en `panel`.
static func build_tab(panel: DebugPanel, tree: SceneTree) -> void:
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)

	var readout := Label.new()
	readout.text = _readout(tree)
	panel.add_control(TAB, readout)
	var timer := Timer.new()
	timer.wait_time = READOUT_PERIOD
	timer.autostart = true
	timer.timeout.connect(func() -> void: _refresh(readout, tree))
	readout.add_child(timer)

	for part: int in Part.values():
		panel.add_control(TAB, HSeparator.new())
		panel.add_text(TAB, PART_NAMES[part])
		panel.add_toggle(TAB, "Dibujo", _draw[part], func(on: bool) -> void: _toggle(tree, part, false, on))
		panel.add_toggle(TAB, "Lógica", _logic[part], func(on: bool) -> void: _toggle(tree, part, true, on))


static func _toggle(tree: SceneTree, part: int, logic: bool, on: bool) -> void:
	if logic:
		_logic[part] = on
	else:
		_draw[part] = on
	for node in _roots(tree, part):
		_power(node, part)
	if part == Part.CARS:
		# Congelados: además se para el spawner, que si no seguiría sumando autos que no avanzan.
		for spawner in tree.get_nodes_in_group("area_instantiator"):
			spawner.set_physics_process(_logic[part])


## Los nodos raíz de `part`: prender o apagar uno alcanza a todo lo que cuelga de él.
static func _roots(tree: SceneTree, part: int) -> Array[Node]:
	match part:
		Part.DUMMIES:
			return tree.get_nodes_in_group(ShipHull.DUMMY_GROUP)
		Part.CARS:
			return tree.get_nodes_in_group("car_manager")
		Part.BUILDINGS:
			return tree.get_nodes_in_group("city_buildings")
	var npcs: Array[Node] = []
	for capsule in tree.get_nodes_in_group(CharacterRigidBody3D.CHARACTER_GROUP):
		if _is_npc(capsule.get_parent()):
			npcs.append(capsule.get_parent())
	return npcs


## Prende o apaga un nodo raíz según las llaves de su parte.
static func _power(node: Node, part: int) -> void:
	(node as Node3D).visible = _draw[part]
	node.process_mode = Node.PROCESS_MODE_INHERIT if _logic[part] else Node.PROCESS_MODE_DISABLED


## Lo que aparece después nace como diga la llave de su parte. Solo si está apagada: prendida, se deja
## como lo haya dejado quien lo creó.
static func _on_node_added(node: Node) -> void:
	var part := _part_of(node)
	if part >= 0 and not (_draw[part] and _logic[part]):
		_power(node, part)
	elif node is AreaInstantiator and not _logic[Part.CARS]:
		# El spawner prende su physics_process recién al estar listo: se lo apaga después.
		node.ready.connect(func() -> void: node.set_physics_process(false), CONNECT_ONE_SHOT)


## De qué parte es raíz `node`, o -1 si de ninguna. Por el grupo cuando se anota antes de entrar al
## árbol; el CarManager se anota recién en su _ready, así que se lo reconoce por la clase.
static func _part_of(node: Node) -> int:
	if node.is_in_group(ShipHull.DUMMY_GROUP):
		return Part.DUMMIES
	if node is CarManager:
		return Part.CARS
	if node.is_in_group("city_buildings"):
		return Part.BUILDINGS
	if _is_npc(node):
		return Part.NPCS
	return -1


## Un NPC: un personaje que no maneja ningún jugador, ni el propio (activo) ni el proxy de uno remoto
## (puppet).
static func _is_npc(node: Node) -> bool:
	var character := node as BoneInstantiator
	return character != null and not character.is_active and not character.is_puppet


static func _refresh(readout: Label, tree: SceneTree) -> void:
	if readout.is_visible_in_tree():
		readout.text = _readout(tree)


## Los números en vivo: cuánto cuesta el frame y cuánto hay de cada parte.
static func _readout(tree: SceneTree) -> String:
	var fps := Engine.get_frames_per_second()
	var dummies := 0
	for dash in tree.get_nodes_in_group(ShipHull.DUMMY_GROUP):
		dummies += dash.get_child_count()
	var cars := 0
	for manager in tree.get_nodes_in_group("car_manager"):
		cars += (manager as CarManager).cars.size()
	return "\n".join([
		"FPS %d  ·  %.1f ms por frame" % [fps, 1000.0 / maxf(fps, 1.0)],
		"process %.2f ms  ·  física %.2f ms por paso" % [
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0],
		"draw calls %d  ·  objetos %d  ·  triángulos %.0fk" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0],
		# Sin los monitores de cuerpos activos y pares de física: Jolt no los llena, dan siempre 0.
		"nodos %d  ·  controles de relleno %d  ·  autos %d  ·  NPC %d" % [
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), dummies, cars, _roots(tree, Part.NPCS).size()],
	])
