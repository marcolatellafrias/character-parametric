extends Node3D

## PRUEBA HEADLESS DE LOS ARQUETIPOS DE CONTROL (ver ControlArchetype): cada estilo del catálogo se
## construye como en el sandbox, y se verifica que el tablero lo vistió —base bajo el cuerpo, parte móvil
## bajo el componente, las dos con triángulos— y que la parte móvil se mueve con el componente: un botón
## se hunde al apretarlo, un volante gira. Corre con
##
##     godot --headless --path . res://Scenes/tests/control_archetypes.tscn --quit-after 10
##
## y escribe `[ControlsTest] PASS` o `FAIL` en la consola.


func _ready() -> void:
	var failures := PackedStringArray()
	for archetype in ControlArchetype.catalogue():
		var stand := archetype.build(1, self)
		var body := stand.get_node_or_null("Dashboard/ctrl_0") as StaticBody3D
		var control := stand.get_node_or_null("Dashboard/ctrl_0/Control") as ControllableInteractable
		if body == null or control == null:
			failures.append("%s: sin control" % archetype.key)
			continue
		if _faces(body) == 0:
			failures.append("%s: base sin triángulos" % archetype.key)
		if control.highlighted.is_empty() or _faces(control) == 0:
			failures.append("%s: parte móvil sin triángulos" % archetype.key)
		var before := control.transform
		if control is TouchComponent:
			control.start_control()
			if control.position.z >= before.origin.z:
				failures.append("%s: no se hunde al apretarlo" % archetype.key)
			control.stop_control()
		elif control is RotatingComponent:
			control.handle_scroll(1.0)
			control.handle_mouse_motion(Vector2(200.0, 0.0))
			if control.rotation.is_equal_approx(before.basis.get_euler()):
				failures.append("%s: no gira" % archetype.key)
	if failures.is_empty():
		print("[ControlsTest] PASS: %d estilos vestidos y móviles" % ControlArchetype.catalogue().size())
	else:
		print("[ControlsTest] FAIL: " + " · ".join(failures))


## Los triángulos de las mallas colgadas DIRECTAMENTE de `node`.
static func _faces(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi.mesh != null:
			count += mi.mesh.get_faces().size() / 3
	return count
