extends Node
## NetSpawner (autoload). Spawn replicado y host-authoritative de entidades de debug/prueba.
## Quien spawnea le pide al host; el host asigna un id incremental y transmite a todos, que
## instancian "spawned_<id>" bajo la escena actual — mismo nombre y path en todas las máquinas,
## así el sync de cada entidad (NetBody, etc.) rutea.
##
## Permanencia: el host mantiene un registro de lo spawneado y, al unirse un peer, le manda un
## SNAPSHOT (re-spawnea cada objeto en su transform actual). Sin esto los objetos serían solo
## eventos y un joiner no vería nada spawneado antes de entrar. Ver _spawned / _request_snapshot.
##
## Herramienta de authoring/testing, NO la vía de producción (el juego reconstruye por seed).
## Las cajas se construyen por código a partir de una variante determinística (mismo nombre →
## mismo tamaño/masa en todas las máquinas). Ver Scripts/city/docs/conceptual/multiplayer.md.

## Escenas para entidades no-caja.
const SCENES := {
	"dashboard": "res://Scripts/character/interactable/controllable/dashboard.tscn",
	"seat": "res://Scenes/ship/working_seat.tscn",  # SeatInteractable funcional (no la malla suelta)
}

## Variantes de caja: tamaño (m), masa (kg) y color.
const BOX_VARIANTS := {
	"box_light_square": {"size": Vector3(0.5, 0.5, 0.5), "mass": 2.0,  "color": Color(0.45, 0.7, 1.0),  "label": "liviana ▪"},
	"box_heavy_square": {"size": Vector3(0.5, 0.5, 0.5), "mass": 30.0, "color": Color(0.7, 0.2, 0.2),   "label": "pesada ▪"},
	"box_light_long":   {"size": Vector3(0.4, 0.4, 1.2), "mass": 3.0,  "color": Color(0.5, 0.85, 0.5),  "label": "liviana ▬"},
	"box_heavy_long":   {"size": Vector3(0.4, 0.4, 1.2), "mass": 40.0, "color": Color(0.85, 0.5, 0.2),  "label": "pesada ▬"},
}

var _next_id: int = 0

## Registro host-authoritative de lo spawneado: id -> {type, node}. Solo lo mantiene el host y es la
## fuente de verdad para el SNAPSHOT que recibe cada peer al unirse. Sin esto los objetos serían
## solo eventos (un joiner no vería nada spawneado antes de entrar). El transform NO se guarda acá:
## el snapshot lo lee en vivo del nodo, así lo que se movió y quedó quieto llega en su lugar real
## (base de la futura dormancy: lo dormido viaja una vez, en reposo). Ver multiplayer.md.
var _spawned: Dictionary = {}

## Cliente recién llegado (ya en la escena del mundo): pide al host el mundo ya spawneado
## (permanencia). Lo llama el CharacterSpawner al spawnear el jugador local — así el pedido y su
## respuesta caen con la escena del juego ya cargada (session_ready se emite ANTES del change_scene,
## por eso no se dispara solo acá). El host reenvía su registro.
func request_world_snapshot() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_request_snapshot.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_snapshot() -> void:
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	var stale: Array = []
	for id in _spawned:
		var node := (_spawned[id] as Dictionary)["node"] as Node3D
		if not is_instance_valid(node):
			stale.append(id)
			continue
		# Autoridad ACTUAL del cuerpo (host si está en reposo; el que lo sostiene si está agarrado),
		# así un objeto sostenido justo al unirse llega con la autoridad correcta y acepta su stream.
		var auth := 1
		var nb := node.get_node_or_null("NetBody")
		if nb != null:
			auth = nb.get_multiplayer_authority()
		# Transform ACTUAL, no el de spawn: un objeto que se movió llega donde está de verdad.
		_do_spawn.rpc_id(requester, int(id), (_spawned[id] as Dictionary)["type"], node.global_transform, auth)
	for id in stale:
		_spawned.erase(id)

## Pide spawnear una entidad. type_name ∈ BOX_VARIANTS o SCENES; xform es el transform inicial.
func request_spawn(type_name: String, xform: Transform3D) -> void:
	if not BOX_VARIANTS.has(type_name) and not SCENES.has(type_name):
		push_warning("[NetSpawner] tipo desconocido: %s" % type_name)
		return
	if not multiplayer.has_multiplayer_peer():
		_do_spawn(_alloc_id(), type_name, xform, 1)        # offline: local
	elif multiplayer.is_server():
		_do_spawn.rpc(_alloc_id(), type_name, xform, 1)    # host: a todos (call_local incluido)
	else:
		_request_spawn.rpc_id(1, type_name, xform)         # cliente: le pide al host

func _alloc_id() -> int:
	_next_id += 1
	return _next_id

@rpc("any_peer", "reliable")
func _request_spawn(type_name: String, xform: Transform3D) -> void:
	if not multiplayer.is_server():
		return
	_do_spawn.rpc(_alloc_id(), type_name, xform, 1)  # spawn nuevo: siempre nace con autoridad del host

@rpc("authority", "reliable", "call_local")
func _do_spawn(id: int, type_name: String, xform: Transform3D, body_authority: int) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var node_name := "spawned_%d" % id
	if scene_root.has_node(NodePath(node_name)):
		return  # ya existe: el snapshot de join y el broadcast normal pueden solaparse

	var inst: Node3D = null
	if BOX_VARIANTS.has(type_name):
		inst = _build_box(BOX_VARIANTS[type_name])
	elif SCENES.has(type_name):
		var scene := load(SCENES[type_name]) as PackedScene
		if scene != null:
			inst = scene.instantiate() as Node3D
	if inst == null:
		return

	inst.name = node_name  # mismo nombre en todas las máquinas → path estable
	if "show_debug" in inst:  # spawns de debug: mostrar la zona de interacción (asiento, etc.)
		inst.set("show_debug", true)
	scene_root.add_child(inst)
	inst.global_transform = xform

	# El host guarda la referencia: fuente de verdad para el snapshot de join (ver _request_snapshot).
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_spawned[id] = {"type": type_name, "node": inst}

	# Cuerpos físicos (cajas): sync por NetBody, autoridad inicial = host. Al agarrar, la
	# autoridad migra al que agarra (NetBody desde el InteractionController).
	if inst is RigidBody3D:
		var net := NetBody.new()
		net.name = "NetBody"
		inst.add_child(net)
		net.set_body_authority(body_authority)  # spawn nuevo = host; snapshot = la autoridad actual (p.ej. quien lo sostiene)
		if _grabbable_of(inst) == null:
			var grab := GrabbableInteractable.new()
			grab.name = "Grabbable"  # nombre estable → mismo path en todas las máquinas (grab sync)
			inst.add_child(grab)
			var cells := _box_cells(inst)
			grab.setup_from_cells(cells.x, cells.y, cells.z)
			grab.show_debug_points()  # grab (cyan) + handle (amarillo), atravesando el mesh

# ── Despawn ────────────────────────────────────────────────────────────────────
# Host-authoritative como el spawn (cliente le pide al host). Cierra el ciclo del registro.

## Borra todo lo spawneado (acción de debug). Offline no hay registro (se llena solo con peer),
## así que barremos la escena por nombre.
func request_clear_all() -> void:
	if not multiplayer.has_multiplayer_peer():
		_clear_local_spawned()
	elif multiplayer.is_server():
		_host_clear_all()
	else:
		_request_clear_all.rpc_id(1)

@rpc("any_peer", "reliable")
func _request_clear_all() -> void:
	if multiplayer.is_server():
		_host_clear_all()

func _host_clear_all() -> void:
	for id in _spawned.keys():
		_do_despawn.rpc(int(id))

@rpc("authority", "reliable", "call_local")
func _do_despawn(id: int) -> void:
	_spawned.erase(id)  # inofensivo donde no exista (los clientes no llevan registro)
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var node := scene_root.get_node_or_null(NodePath("spawned_%d" % id))
	if is_instance_valid(node):
		node.queue_free()

func _clear_local_spawned() -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for child in scene_root.get_children():
		if child.name.begins_with("spawned_"):
			child.queue_free()

# ── Construcción de cajas ─────────────────────────────────────────────────────

func _build_box(cfg: Dictionary) -> RigidBody3D:
	var size: Vector3 = cfg["size"]
	var body := RigidBody3D.new()
	body.mass = cfg["mass"]

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = cfg["color"]
	box_mesh.material = mat
	mesh_inst.mesh = box_mesh
	body.add_child(mesh_inst)

	var label := Label3D.new()
	label.text = cfg["label"]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 4
	label.pixel_size = 0.004
	label.position.y = size.y * 0.5 + 0.25
	body.add_child(label)
	return body

# ── Helpers ───────────────────────────────────────────────────────────────────

func _grabbable_of(body: Node) -> GrabbableInteractable:
	for c in body.get_children():
		if c is GrabbableInteractable:
			return c as GrabbableInteractable
	return null

func _box_cells(body: Node) -> Vector3i:
	var size := Vector3.ONE
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			size = ((c as CollisionShape3D).shape as BoxShape3D).size
			break
	var cs := GrabbableInteractable.CELL_SIZE
	return Vector3i(
		max(1, int(round(size.x / cs))),
		max(1, int(round(size.y / cs))),
		max(1, int(round(size.z / cs))))
