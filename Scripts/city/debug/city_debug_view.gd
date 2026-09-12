class_name CityDebugView

## VISTA DE DEBUG DE LA CIUDAD — lo que se prende y apaga para MIRAR la ciudad, desde el panel F1
## (Acciones). Ver technical/ui.md.
##
## Por ahora una sola cosa: la NEBLINA. Apagarla apaga la del Environment (`CityFog`) y, lo que en
## realidad importa, levanta el CORTE POR DISTANCIA: los edificios, las veredas flotantes y los
## puentes nacen con `visibility_range_end` en `WorldSettings.render_distance` más su propio radio, así que sin
## esto la ciudad se seguiría cortando a esa distancia aunque no hubiera niebla —que es justo lo que uno
## quiere ver cuando la apaga—.
##
## Es reversible: cada malla que se toca se guarda su distancia original en un meta, y al prender la
## neblina se la devuelve. Así no se le inventa un corte a lo que nunca lo tuvo (el suelo, por ejemplo).
##
## Cuidado: con esto prendido se dibuja la ciudad ENTERA. Es para mirarla, no para medir performance —para
## eso está la pestaña Performance—.

const RANGE_META := "city_debug_range"

static var fog_on := true


## Prende o apaga la neblina, con su corte por distancia.
static func toggle_fog(tree: SceneTree) -> void:
	fog_on = not fog_on
	for node in tree.get_nodes_in_group("city_fog"):
		var world_env := node as WorldEnvironment
		if world_env != null and world_env.environment != null:
			world_env.environment.fog_enabled = fog_on
	for city in tree.get_nodes_in_group("city_generator"):
		_apply_range(city)


## RECALCULA EL CORTE POR DISTANCIA de todo lo que ya está dibujado.
##
## Hace falta porque `City._fade_into_fog` corre UNA SOLA VEZ, al generar la ciudad: mover
## `render_distance` después (desde el afinador de F6) movería la niebla y dejaría la geometría
## cortándose donde estaba antes. Solo toca lo que YA tenía un corte —el suelo y la muralla no tienen, y
## no hay que inventarles uno— y se saltea lo que esté guardado con la niebla apagada.
static func refresh_ranges(tree: SceneTree) -> void:
	for city in tree.get_nodes_in_group("city_generator"):
		_refresh_range(city)


static func _refresh_range(node: Node) -> void:
	var piece := node as MeshInstance3D
	if piece != null and piece.mesh != null and not piece.has_meta(RANGE_META) \
			and piece.visibility_range_end > 0.0:
		var radius := piece.mesh.get_aabb().size.length() * 0.5
		var end_distance := WorldSettings.render_distance + radius
		piece.visibility_range_end = end_distance
		piece.visibility_range_end_margin = WorldSettings.fade_ring_for(end_distance)
	for child in node.get_children():
		_refresh_range(child)


## Levanta o devuelve el corte por distancia de todo lo que cuelga de la ciudad. En Godot, 0 es "sin
## límite"; la distancia original queda guardada en un meta para poder devolverla.
static func _apply_range(node: Node) -> void:
	var piece := node as GeometryInstance3D
	if piece != null:
		if fog_on:
			if piece.has_meta(RANGE_META):
				piece.visibility_range_end = piece.get_meta(RANGE_META)
				piece.remove_meta(RANGE_META)
		elif piece.visibility_range_end > 0.0:
			piece.set_meta(RANGE_META, piece.visibility_range_end)
			piece.visibility_range_end = 0.0
	for child in node.get_children():
		_apply_range(child)
