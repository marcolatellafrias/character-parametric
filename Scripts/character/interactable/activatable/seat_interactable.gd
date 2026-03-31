@tool
class_name SeatInteractable
extends ActivatableInteractable

@export var height:            float       = 0.5
@export var seat_area:         Vector3     = Vector3(0.6, 0.5, 0.6)
@export var stand_up_location: Vector2     = Vector2(0.0, 1.2)
@export var seat_scene:        PackedScene = null
@export var show_debug:        bool        = false

var _visual_root:   Node3D      = null
var _body:          RigidBody3D = null
var _spawn_point:   Node3D      = null
var _seated_bi:     Node        = null
var _borrowed_mesh: Node3D      = null

func _ready() -> void:
	if Engine.is_editor_hint():
		_build_visual()
		return
	_build_visual()
	_build_collider()
	_build_spawn_point()

func _build_visual() -> void:
	if not is_instance_valid(seat_scene):
		return
	_visual_root = seat_scene.instantiate() as Node3D
	add_child(_visual_root)

func _build_collider() -> void:
	_body                 = RigidBody3D.new()
	_body.freeze_mode     = RigidBody3D.FREEZE_MODE_KINEMATIC
	_body.freeze          = true
	_body.collision_layer = 1
	_body.collision_mask  = 0
	_body.position.y      = seat_area.y * 0.5

	var shape  := CollisionShape3D.new()
	var box    := BoxShape3D.new()
	box.size   = seat_area
	shape.shape = box
	_body.add_child(shape)

	if show_debug:
		var dbg_mesh               := MeshInstance3D.new()
		dbg_mesh.set_meta("no_outline", true)
		var box_mesh               := BoxMesh.new()
		box_mesh.size              = seat_area
		dbg_mesh.mesh              = box_mesh
		var mat                    := StandardMaterial3D.new()
		mat.albedo_color           = Color(0.2, 0.8, 1.0, 0.15)
		mat.transparency           = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode              = BaseMaterial3D.CULL_DISABLED
		dbg_mesh.material_override = mat
		_body.add_child(dbg_mesh)

	add_child(_body)
	add_handle_point_local(Vector3(0.0, height + seat_area.y * 0.5, 0.0))

func _build_spawn_point() -> void:
	_spawn_point = Node3D.new()
	_spawn_point.position = Vector3(stand_up_location.x, 0.0, stand_up_location.y)
	add_child(_spawn_point)

	if show_debug:
		var dbg          := MeshInstance3D.new()
		dbg.set_meta("no_outline", true)
		var sphere       := SphereMesh.new()
		sphere.radius    = 0.12
		sphere.height    = 0.24
		dbg.mesh         = sphere
		var mat          := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.4, 0.0, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dbg.material_override = mat
		_spawn_point.add_child(dbg)

func get_prompt() -> String:
	return "[E] Sit"

func can_interact() -> bool:
	return not is_instance_valid(_seated_bi)

func activate(actor: Node = null) -> void:
	if not is_instance_valid(actor):
		return
	if is_instance_valid(_seated_bi):
		if _seated_bi == actor:
			_stand_up()
	else:
		_sit(actor)

func update_borrowed_mesh() -> void:
	if is_instance_valid(_borrowed_mesh) and is_instance_valid(_visual_root):
		_borrowed_mesh.global_position = _visual_root.global_position
		_borrowed_mesh.rotation        = Vector3.ZERO

func _sit(bi: Node) -> void:
	_seated_bi = bi
	var char_rb := bi.get("char_rigidbody") as CharacterRigidBody3D
	if not is_instance_valid(char_rb):
		return

	char_rb.linear_velocity    = Vector3.ZERO
	char_rb.angular_velocity   = Vector3.ZERO
	char_rb.is_snapshot_active = false
	char_rb.reset_impact_state()
	char_rb.collider.disabled  = true
	char_rb.axis_lock_linear_y = true
	char_rb.is_active          = false

	char_rb.global_position.x = global_position.x
	char_rb.global_position.z = global_position.z
	char_rb.global_rotation.y = global_rotation.y

	var pc: PlayerController = bi.get("player_controller")
	if is_instance_valid(pc):
		pc.set("camera_yaw", global_rotation.y)
		pc.call("apply_camera_pitch", 0.0)

	if is_instance_valid(_visual_root):
		_visual_root.visible   = false
		_borrowed_mesh         = seat_scene.instantiate() as Node3D
		_borrowed_mesh.visible = true
		char_rb.add_child(_borrowed_mesh)
		_borrowed_mesh.global_position = _visual_root.global_position
		_borrowed_mesh.rotation        = Vector3.ZERO

	bi.set("is_seated", true)
	bi.set("current_seat", self)

	var ic: InteractionController = bi.get("interaction_controller")
	if is_instance_valid(ic):
		ic.detector.force_clear()

	var anim_mod: AnimationModifiers = bi.get("anim_mod")
	if is_instance_valid(anim_mod):
		anim_mod.set("is_seated", true)

	var proc_anim: ProceduralBoneAnimator = bi.get("procedural_animator")
	if is_instance_valid(proc_anim):
		proc_anim.set("is_seated", true)
		var bu: CustomBonesUtil = bi.get("custom_bones_util")
		if is_instance_valid(bu):
			proc_anim.set("_seated_locked_bone", bu.lower_spine)


func _stand_up() -> void:
	if not is_instance_valid(_seated_bi):
		return
	var bi      := _seated_bi
	var char_rb := bi.get("char_rigidbody") as CharacterRigidBody3D
	if not is_instance_valid(char_rb):
		return

	if is_instance_valid(_borrowed_mesh):
		_borrowed_mesh.queue_free()
		_borrowed_mesh = null
	if is_instance_valid(_visual_root):
		_visual_root.visible = true

	bi.set("is_seated", false)
	bi.set("current_seat", null)

	var anim_mod: AnimationModifiers = bi.get("anim_mod")
	if is_instance_valid(anim_mod):
		anim_mod.set("is_seated", false)

	var proc_anim: ProceduralBoneAnimator = bi.get("procedural_animator")
	if is_instance_valid(proc_anim):
		proc_anim.set("is_seated", false)
		proc_anim.set("_seated_locked_bone", null)

	var pc: PlayerController = bi.get("player_controller")
	if is_instance_valid(pc):
		pc.call("apply_camera_pitch", 0.0)

	_seated_bi = null

	char_rb.axis_lock_linear_y = false
	char_rb.collider.disabled  = false
	char_rb.linear_velocity    = Vector3.ZERO
	char_rb.angular_velocity   = Vector3.ZERO
	char_rb.reset_impact_state()
	char_rb.is_snapshot_active = true
	char_rb.is_active          = true

	var target_pos   := _spawn_point.global_position
	var target_rot_y := char_rb.global_rotation.y
	char_rb.call_deferred("set", "global_position", target_pos)
	char_rb.call_deferred("set", "global_rotation", Vector3(0.0, target_rot_y, 0.0))
