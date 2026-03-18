class_name RagdollUtil
extends RefCounted

const RAGDOLL_LAYER := 2
const RAGDOLL_MASK  := 1

var is_active: bool = false
var head_body: RigidBody3D = null

var _skel_rb_node: Node3D
var _joints_node: Node3D
var _bones_util: CustomBonesUtil
var _bodies: Dictionary = {}
var _ragdoll_rids: Array[RID] = []
var _joints: Array[Generic6DOFJoint3D] = []
var _pending_bodies: Array[RigidBody3D] = []
var _char_rid: RID
var _lower_spine_body: RigidBody3D = null


static func create(bones_util: CustomBonesUtil, skel_rb_node: Node3D, joints_node: Node3D) -> RagdollUtil:
	var ru := RagdollUtil.new()
	ru._skel_rb_node = skel_rb_node
	ru._joints_node  = joints_node
	ru._bones_util   = bones_util
	ru._build_bodies(bones_util)
	return ru


func _build_bodies(bu: CustomBonesUtil) -> void:
	var all_bones: Array = [
		bu.lower_spine, bu.middle_spine, bu.upper_spine, bu.chest,
		bu.left_hip, bu.right_hip,
		bu.left_upper_leg, bu.left_lower_leg,
		bu.right_upper_leg, bu.right_lower_leg,
		bu.right_upper_feet, bu.left_upper_feet,
		bu.neck, bu.head,
		bu.left_shoulder, bu.right_shoulder,
		bu.right_upper_arm, bu.right_lower_arm,
		bu.left_upper_arm, bu.left_lower_arm,
	]
	for bone in all_bones:
		if not is_instance_valid(bone):
			continue
		var rb := _make_body(bone)
		_bodies[bone] = rb
		_skel_rb_node.add_child(rb)
		_ragdoll_rids.append(rb.get_rid())

	_lower_spine_body = _bodies.get(bu.lower_spine, null)
	head_body         = _bodies.get(bu.head, null)


func _make_body(bone: CustomBone) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.freeze_mode     = RigidBody3D.FREEZE_MODE_KINEMATIC
	rb.freeze          = true
	rb.collision_layer = RAGDOLL_LAYER
	rb.collision_mask  = RAGDOLL_MASK
	rb.can_sleep       = false
	rb.mass            = 1.0
	rb.linear_damp     = 0.5
	rb.angular_damp    = 1.0
	rb.global_transform = bone.global_transform

	var d := bone.capsule_dimensions
	var caps := CapsuleShape3D.new()
	caps.radius = min(d.x, d.z) * 0.45
	caps.height = max(d.y, caps.radius * 2.1)

	var shape := CollisionShape3D.new()
	shape.shape    = caps
	shape.position = Vector3(0.0, d.y * 0.5, 0.0)
	rb.add_child(shape)

	# Duplicar el mesh del hueso original
	for child in bone.get_children():
		if child is MeshInstance3D:
			var mesh_copy := child.duplicate() as MeshInstance3D
			mesh_copy.visible = false
			rb.add_child(mesh_copy)
			break

	return rb


func _build_joints() -> void:
	var bu := _bones_util
	var pairs: Array = [
		[bu.lower_spine,     bu.middle_spine],
		[bu.middle_spine,    bu.upper_spine],
		[bu.upper_spine,     bu.chest],
		[bu.lower_spine,     bu.left_hip],
		[bu.lower_spine,     bu.right_hip],
		[bu.left_hip,        bu.left_upper_leg],
		[bu.left_upper_leg,  bu.left_lower_leg],
		[bu.left_lower_leg,  bu.left_upper_feet],
		[bu.right_hip,       bu.right_upper_leg],
		[bu.right_upper_leg, bu.right_lower_leg],
		[bu.right_lower_leg, bu.right_upper_feet],
		[bu.chest,           bu.left_shoulder],
		[bu.chest,           bu.right_shoulder],
		[bu.left_shoulder,   bu.left_upper_arm],
		[bu.left_upper_arm,  bu.left_lower_arm],
		[bu.right_shoulder,  bu.right_upper_arm],
		[bu.right_upper_arm, bu.right_lower_arm],
	]
	if is_instance_valid(bu.neck):
		pairs.append([bu.chest, bu.neck])
		pairs.append([bu.neck,  bu.head])
	else:
		pairs.append([bu.chest, bu.head])

	for pair in pairs:
		var pa: CustomBone = pair[0]
		var ch: CustomBone = pair[1]
		if not is_instance_valid(pa) or not is_instance_valid(ch):
			continue
		if not _bodies.has(pa) or not _bodies.has(ch):
			continue
		_create_joint(_bodies[pa], _bodies[ch], ch.global_position)


func _create_joint(body_a: RigidBody3D, body_b: RigidBody3D, anchor: Vector3) -> void:
	var j := Generic6DOFJoint3D.new()
	_joints_node.add_child(j)
	j.global_position = anchor
	j.node_a = j.get_path_to(body_a)
	j.node_b = j.get_path_to(body_b)

	var LL := Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT
	var LU := Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT
	var AL := Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT
	var AU := Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT
	var LF := Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT
	var AF := Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT
	var lim := deg_to_rad(60.0)

	j.set_flag_x(LF, true); j.set_flag_y(LF, true); j.set_flag_z(LF, true)
	j.set_param_x(LL, 0.0);  j.set_param_x(LU, 0.0)
	j.set_param_y(LL, 0.0);  j.set_param_y(LU, 0.0)
	j.set_param_z(LL, 0.0);  j.set_param_z(LU, 0.0)

	j.set_flag_x(AF, true); j.set_flag_y(AF, true); j.set_flag_z(AF, true)
	j.set_param_x(AL, -lim); j.set_param_x(AU, lim)
	j.set_param_y(AL, -lim); j.set_param_y(AU, lim)
	j.set_param_z(AL, -lim); j.set_param_z(AU, lim)

	_joints.append(j)


func sync_to_bones() -> void:
	for bone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if is_instance_valid(rb) and is_instance_valid(bone):
			rb.global_transform = bone.global_transform


func activate(char_rb: CharacterRigidBody3D, skeleton_root: CustomBone) -> void:
	is_active = true
	_char_rid = char_rb.get_rid()

	char_rb.is_active         = false
	char_rb.collider.disabled = true
	char_rb.freeze_mode       = RigidBody3D.FREEZE_MODE_STATIC
	char_rb.freeze            = true

	if is_instance_valid(skeleton_root):
		skeleton_root.visible = false

	_set_meshes_visible(true)
	_build_joints()

	var space   := _skel_rb_node.get_world_3d().direct_space_state
	var exclude := _make_exclude()
	_pending_bodies.clear()

	for bone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if not is_instance_valid(rb):
			continue
		rb.linear_velocity  = char_rb.linear_velocity
		rb.angular_velocity = Vector3.ZERO
		rb.freeze           = false

		if _is_overlapping(rb, space, exclude):
			rb.collision_layer = 0
			rb.collision_mask  = 0
			_pending_bodies.append(rb)


func deactivate(char_rb: CharacterRigidBody3D, skeleton_root: CustomBone) -> void:
	is_active = false
	_pending_bodies.clear()
	_clear_joints()

	for bone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if is_instance_valid(rb):
			rb.freeze          = true
			rb.collision_layer = RAGDOLL_LAYER
			rb.collision_mask  = RAGDOLL_MASK

	if is_instance_valid(_lower_spine_body):
		char_rb.global_position = _lower_spine_body.global_position + Vector3(0.0, 1.0, 0.0)
	char_rb.linear_velocity   = Vector3.ZERO
	char_rb.angular_velocity  = Vector3.ZERO
	char_rb.collider.disabled = false
	char_rb.freeze            = false
	char_rb.is_active         = true

	_set_meshes_visible(false)

	if is_instance_valid(skeleton_root):
		skeleton_root.visible = true


func update(_delta: float) -> void:
	if _pending_bodies.is_empty():
		return
	var space   := _skel_rb_node.get_world_3d().direct_space_state
	var exclude := _make_exclude()
	var still_pending: Array[RigidBody3D] = []
	for rb in _pending_bodies:
		if not is_instance_valid(rb):
			continue
		if _is_overlapping(rb, space, exclude):
			still_pending.append(rb)
		else:
			rb.collision_layer = RAGDOLL_LAYER
			rb.collision_mask  = RAGDOLL_MASK
	_pending_bodies = still_pending


func cleanup() -> void:
	_clear_joints()
	for bone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if is_instance_valid(rb):
			rb.queue_free()
	_bodies.clear()
	_ragdoll_rids.clear()
	head_body         = null
	_lower_spine_body = null


func _clear_joints() -> void:
	for j in _joints:
		if is_instance_valid(j):
			j.queue_free()
	_joints.clear()


func _set_meshes_visible(value: bool) -> void:
	for bone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if not is_instance_valid(rb):
			continue
		for child in rb.get_children():
			if child is MeshInstance3D:
				child.visible = value


func _make_exclude() -> Array[RID]:
	var arr: Array[RID] = []
	for rid in _ragdoll_rids:
		arr.append(rid)
	if _char_rid.is_valid():
		arr.append(_char_rid)
	return arr


func _is_overlapping(rb: RigidBody3D, space: PhysicsDirectSpaceState3D, exclude: Array[RID]) -> bool:
	var shape_node := rb.get_child(0) as CollisionShape3D
	if not shape_node or not shape_node.shape:
		return false
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape          = shape_node.shape
	params.transform      = rb.global_transform * shape_node.transform
	params.exclude        = exclude
	params.collision_mask = RAGDOLL_MASK
	return not space.intersect_shape(params, 1).is_empty()
