class_name CityDebugView

## VISTA DE DEBUG DE LA CIUDAD — lo que se prende y apaga para MIRAR la ciudad desde el panel F1
## (Acciones). Ver technical/ui.md.
##
## Por ahora una sola cosa: la NEBLINA del Environment (`CityFog`). Apagarla muestra la ciudad entera
## nítida: ya no hay corte por distancia que levantar —las piezas se dibujan siempre, y la niebla es lo
## único que las esconde—. Cuando exista un LOD por distancia de verdad, volverá a haber algo que apagar
## junto con ella.

static var fog_on := true


static func toggle_fog(tree: SceneTree) -> void:
	fog_on = not fog_on
	for node in tree.get_nodes_in_group("city_fog"):
		var world_env := node as WorldEnvironment
		if world_env != null and world_env.environment != null:
			world_env.environment.fog_enabled = fog_on
