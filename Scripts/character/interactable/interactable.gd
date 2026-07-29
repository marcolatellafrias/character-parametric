class_name Interactable
extends Node3D

var handle_points: Array[Node3D] = []

func add_handle_point_local(local_pos: Vector3) -> void:
	var pt := Node3D.new()
	pt.position = local_pos
	add_child(pt)
	handle_points.append(pt)

func get_nearest_handle_point(world_pos: Vector3, exclude: Node3D = null) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for pt in handle_points:
		if not is_instance_valid(pt) or pt == exclude:
			continue
		var d := pt.global_position.distance_to(world_pos)
		if d < best_dist:
			best_dist = d
			best = pt
	return best

func get_prompt() -> String:
	return ""

func can_interact() -> bool:
	return true

## Nodos cuyos meshes se contornean al mirar este interactuable. Por defecto el propio
## interactuable (dashboards/controllables contienen su malla). Un grabbable representa al
## objeto sobre el que cuelga (su padre) → lo overridea.
func get_outline_targets() -> Array[Node]:
	var targets: Array[Node] = [self]
	return targets

func _clear_handle_points() -> void:
	for pt in handle_points:
		if is_instance_valid(pt):
			pt.queue_free()
	handle_points.clear()
