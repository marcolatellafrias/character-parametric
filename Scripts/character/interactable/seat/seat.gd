class_name Seat
extends StaticBody3D

@export var width: float  = 0.5
@export var depth: float  = 0.5
@export var height: float = 0.5          # altura del seat_point desde el origen local
@export var custom_mesh_scene: PackedScene = null

var seat_point: Marker3D

const COLLISION_LAYER_SEAT := 4

var _mesh_instances: Array[MeshInstance3D] = []
var _outline_material: ShaderMaterial = null

var _mesh_local_transforms: Array[Transform3D] = []

func _ready() -> void:
    collision_layer = COLLISION_LAYER_SEAT
    collision_mask  = 0

    seat_point          = Marker3D.new()
    seat_point.position = Vector3(0.0, height, 0.0)
    add_child(seat_point)

    if custom_mesh_scene:
        var inst := custom_mesh_scene.instantiate()
        add_child(inst)
        _collect_meshes(inst, _mesh_instances)
    else:
        _create_default_mesh()

    var col      := CollisionShape3D.new()
    var box      := BoxShape3D.new()
    box.size      = Vector3(width, 0.15, depth)
    col.shape     = box
    col.position  = Vector3(0.0, height, 0.0)
    add_child(col)

    _build_outline_material()

func set_hovered(on: bool) -> void:
    for mi in _mesh_instances:
        if not is_instance_valid(mi): continue
        for i in mi.mesh.get_surface_count():
            var mat := mi.get_active_material(i)
            if mat:
                mat.next_pass = _outline_material if on else null

func _create_default_mesh() -> void:
    var mi    := MeshInstance3D.new()
    var mesh  := BoxMesh.new()
    mesh.size  = Vector3(width, 0.05, depth)
    mi.mesh    = mesh
    mi.position = Vector3(0.0, height - 0.025, 0.0)
    add_child(mi)
    _mesh_instances.append(mi)

func _build_outline_material() -> void:
    var shader := load("res://shaders/outline.gdshader") as Shader
    if not shader:
        return
    _outline_material = ShaderMaterial.new()
    _outline_material.shader = shader
    _outline_material.set_shader_parameter("color", Color(0.0, 1.0, 0.3, 1.0))
    _outline_material.set_shader_parameter("outline_thickness", 0.01)

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child, result)

func borrow_mesh(new_parent: Node3D) -> void:
    _mesh_local_transforms.clear()
    for mi in _mesh_instances:
        if is_instance_valid(mi):
            _mesh_local_transforms.append(mi.transform)
            mi.reparent(new_parent, true)

func return_mesh() -> void:
    for i in _mesh_instances.size():
        if is_instance_valid(_mesh_instances[i]):
            _mesh_instances[i].reparent(self, false)
            if i < _mesh_local_transforms.size():
                _mesh_instances[i].transform = _mesh_local_transforms[i]
