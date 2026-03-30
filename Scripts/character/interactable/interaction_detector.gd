class_name InteractionDetector
extends Node

var player_camera:   Camera3D
var char_rigidbody:  CharacterRigidBody3D
var ray_length:      float = 10.0
var max_reach:       float = 3.0
var outline_color:   Color = Color(1, 1, 0, 1)
var outline_size:    float = 0.01

var _hovered:          Interactable           = null
var _hovered_meshes:   Array[MeshInstance3D]  = []
var _outline_material: ShaderMaterial         = null
var _own_bi:           BoneInstantiator       = null

signal hovered_changed(interactable: Interactable)

func setup(rb: CharacterRigidBody3D, cam: Camera3D, bi: BoneInstantiator) -> void:
    char_rigidbody = rb
    player_camera  = cam
    _own_bi        = bi
    _build_outline_material()

func set_reach(reach: float) -> void:
    max_reach  = reach
    ray_length = reach + 2.0
    print("[DETECTOR] set_reach: max_reach=%.3f ray_length=%.3f" % [max_reach, ray_length])

func update() -> void:
    _process_hover()

func get_hovered() -> Interactable:
    return _hovered

func force_clear() -> void:
    _set_hovered(null)

func _process_hover() -> void:
    if not is_instance_valid(player_camera):
        return
    var vp_size := player_camera.get_viewport().get_visible_rect().size
    var from    := player_camera.global_position
    var dir     := player_camera.project_ray_normal(vp_size * 0.5)
    var query   := PhysicsRayQueryParameters3D.create(from, from + dir * ray_length)
    query.collision_mask = 1 | 2

    var excludes: Array[RID] = [char_rigidbody.get_rid()]
    if is_instance_valid(_own_bi) and is_instance_valid(_own_bi.ragdoll_util):
        for rid in _own_bi.ragdoll_util._ragdoll_rids:
            excludes.append(rid)
    query.exclude = excludes

    var hit := player_camera.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        _set_hovered(null)
        return

    var collider := hit.collider as Node
    if not is_instance_valid(collider) or _is_own_character(collider):
        _set_hovered(null)
        return

    var found := _find_interactable(collider)
    if not is_instance_valid(found) or not found.can_interact():
        _set_hovered(null)
        return

    var check_point := _get_nearest_interactable_point(found)
    print("[DETECTOR] dist_to_chest=%.3f max_reach=%.3f" % [check_point.distance_to(_get_chest_tip()), max_reach])
    if check_point.distance_to(_get_chest_tip()) > max_reach:
        _set_hovered(null)
        return

    _set_hovered(found)

func _set_hovered(interactable: Interactable) -> void:
    if interactable == _hovered:
        return
    _clear_outline()
    _hovered = interactable
    if is_instance_valid(_hovered):
        _apply_outline_to(_hovered)
    hovered_changed.emit(_hovered)

func _get_chest_tip() -> Vector3:
    if not is_instance_valid(_own_bi):
        return player_camera.global_position
    return _own_bi.get_interaction_origin()

func _find_interactable(node: Node) -> Interactable:
    if node is Interactable:
        return node as Interactable
    for child in node.get_children():
        if child is Interactable:
            return child as Interactable
    var parent := node.get_parent()
    if is_instance_valid(parent):
        if parent is Interactable:
            return parent as Interactable
        for child in parent.get_children():
            if child is Interactable:
                return child as Interactable
    return null

func _is_own_character(node: Node) -> bool:
    if not is_instance_valid(_own_bi):
        return false
    var current := node
    while is_instance_valid(current):
        if current == _own_bi:
            return true
        current = current.get_parent()
    return false

func _apply_outline_to(interactable: Interactable) -> void:
    _collect_meshes_recursive(interactable, _hovered_meshes)
    if _hovered_meshes.is_empty() and is_instance_valid(interactable.get_parent()):
        _collect_meshes_recursive(interactable.get_parent(), _hovered_meshes)
    for mesh in _hovered_meshes:
        if is_instance_valid(mesh):
            for i in mesh.mesh.get_surface_count():
                var mat := mesh.get_active_material(i)
                if mat: mat.next_pass = _outline_material

func _clear_outline() -> void:
    for mesh in _hovered_meshes:
        if is_instance_valid(mesh):
            for i in mesh.mesh.get_surface_count():
                var mat := mesh.get_active_material(i)
                if mat: mat.next_pass = null
    _hovered_meshes.clear()

func _collect_meshes_recursive(node: Node, result: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D and not node.has_meta("no_outline"):
        result.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes_recursive(child, result)

func _build_outline_material() -> void:
    var shader         := load("res://shaders/outline.gdshader") as Shader
    _outline_material   = ShaderMaterial.new()
    _outline_material.shader = shader
    _outline_material.set_shader_parameter("color",             outline_color)
    _outline_material.set_shader_parameter("outline_thickness", outline_size)


func _get_nearest_interactable_point(interactable: Interactable) -> Vector3:
    var origin := _get_chest_tip()
    if interactable is GrabbableInteractable:
        var grab := (interactable as GrabbableInteractable).get_nearest_grab_point(origin)
        if is_instance_valid(grab):
            print("[DETECTOR] using grab_point at %.3f from chest" % grab.global_position.distance_to(origin))
            return grab.global_position
    var handle := interactable.get_nearest_handle_point(origin)
    if is_instance_valid(handle):
        print("[DETECTOR] using handle_point at %.3f from chest" % handle.global_position.distance_to(origin))
        return handle.global_position
    print("[DETECTOR] WARNING — no points found, using interactable.global_position")
    return interactable.global_position
