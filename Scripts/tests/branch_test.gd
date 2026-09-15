extends Node3D

## PRUEBA HEADLESS DE LA SUCURSAL (ver BranchArchetype): se construye como en el sandbox y se verifica que
## salió UN edificio hueco —paredes por dentro— con el collider hecho de su piel, y UN portón con sus dos
## botones; y que apretar un botón lo abre: la hoja se achica hasta apagarse. Corre con
##
##     godot --headless --path . res://Scenes/tests/branch.tscn --quit-after 200
##
## y escribe `[BranchTest] PASS` o `FAIL` en la consola.

## Cuánto se espera a que la compuerta termine de abrir (ShipDoor.DURATION, con margen).
const OPEN_SECONDS := 1.5

var _failures := PackedStringArray()
var _leaf_shape: CollisionShape3D = null
var _elapsed := 0.0
var _done := false


func _ready() -> void:
	# Headless corre los cuadros a toda velocidad: a 60 Hz el tiempo de la compuerta cabe en los cuadros
	# que da `--quit-after`.
	Engine.max_fps = 60
	var city := BranchArchetype.new().build(3, self)
	var gates := city.find_children("gate_*", "", true, false)
	if gates.size() != 1:
		_failures.append("portones: %d" % gates.size())
		return
	var gate := gates[0] as Gate
	var leaf := gate.get_node_or_null("Leaf") as StaticBody3D
	if leaf != null:
		_leaf_shape = leaf.get_child(0) as CollisionShape3D
	var outside := gate.get_node_or_null("button_out/ctrl_0/Control") as TouchComponent
	var inside := gate.get_node_or_null("button_in/ctrl_0/Control") as TouchComponent
	if _leaf_shape == null or outside == null or inside == null:
		_failures.append("al portón le falta la hoja o un botón")
		return

	# La piel: paredes mirando hacia adentro además de las de afuera.
	var final_mesh := (city.find_child("Final", true, false).get_child(0) as MeshInstance3D).mesh as ArrayMesh
	var arrays := final_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var centre := final_mesh.get_aabb().get_center()
	var inward := 0
	for i in vertices.size():
		var to_centre := Vector3(centre.x - vertices[i].x, 0.0, centre.z - vertices[i].z).normalized()
		if absf(normals[i].y) < 0.01 and normals[i].dot(to_centre) > 0.9:
			inward += 1
	if inward < 8:
		_failures.append("la piel no tiene paredes por dentro (%d vértices)" % inward)

	# El collider es la piel, no la cáscara.
	var collider := city.find_child("BuildingColliders", true, false)
	var shape: ConcavePolygonShape3D = null
	if collider != null and collider.get_child_count() > 0:
		shape = (collider.get_child(0).get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D
	if shape == null or shape.get_faces().size() != final_mesh.get_faces().size():
		_failures.append("el collider no es la piel")

	outside.start_control()
	outside.stop_control()


func _process(delta: float) -> void:
	if _done:
		return
	if _leaf_shape == null:
		_finish()
		return
	_elapsed += delta
	if _elapsed < OPEN_SECONDS:
		return
	if not _leaf_shape.disabled:
		_failures.append("la hoja no se abrió")
	_finish()


func _finish() -> void:
	_done = true
	if _failures.is_empty():
		print("[BranchTest] PASS: sucursal hueca, con collider de piel y portón que abre")
	else:
		print("[BranchTest] FAIL: " + " · ".join(_failures))
