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
## Ocupación exclusiva (un solo jugador por asiento), arbitrada por el host. Ver ExclusiveClaim.
var _claim:         ExclusiveClaim = null

func _ready() -> void:
	if Engine.is_editor_hint():
		_build_visual()
		return
	_build_visual()
	_build_collider()
	_build_spawn_point()
	_claim = ExclusiveClaim.new()
	_claim.name = "Claim"  # nombre estable → mismo path en todas las máquinas
	add_child(_claim)
	_claim.granted.connect(_on_claim_granted)
	_claim.released.connect(_on_claim_released)

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
	return _claim == null or _claim.is_free() or _claim.is_mine()

func activate(actor: Node = null) -> void:
	if not is_instance_valid(actor) or _claim == null:
		return
	if _claim.is_mine():
		_claim.release()      # ya estoy sentado → pararme
	elif _claim.is_free():
		_claim.request()      # libre → sentarme (offline concede al toque; online arbitra el host)
	# ocupado por otro → nada (can_interact ya lo bloquea)

## El asiento pasó a ser mío: sentar al jugador local (en las demás máquinas es un proxy y el pose
## llega aparte por CharacterNetSync.seat_target, que setea _sit).
func _on_claim_granted(_peer: int) -> void:
	if not _claim.is_mine():
		return
	var local := _local_player()
	if is_instance_valid(local):
		_sit(local)

## El asiento se liberó: si yo era el ocupante, pararme.
func _on_claim_released() -> void:
	if is_instance_valid(_seated_bi):
		_stand_up()

func _local_player() -> Node:
	var spawner := get_tree().get_first_node_in_group("character_spawner")
	return spawner.get("local_player") if is_instance_valid(spawner) else null

## Libera el asiento localmente e informa al host, sin esperar el round-trip. Para el respawn con
## alguien sentado: hay que soltarlo YA (sincrónico) antes de reconstruir el esqueleto.
func release_occupant_for_teardown() -> void:
	if not is_instance_valid(_seated_bi):
		return
	if is_instance_valid(_claim):
		_claim.release()          # que el host libere la ocupación (async, no importa el orden)
	_release_occupant(false, true)  # revert local ya, sin teleport pero avisando a los proxies

## El asiento gira con el ocupante (mismo yaw) — sin sincronizar nada extra: el yaw ya viaja en el
## transform del personaje. Owner: la malla prestada (hija de la cápsula, para esconderse en primera
## persona con el cuerpo); proxy remoto: el visual propio del asiento (a la vista, porque ahí nunca
## se corrió _sit). Lo llama BoneInstantiator._pose_root cada frame del que está sentado.
func update_seated_visual(occupant_yaw: float) -> void:
	var mesh: Node3D = _borrowed_mesh if is_instance_valid(_borrowed_mesh) else _visual_root
	if not is_instance_valid(mesh):
		return
	mesh.global_position = _visual_root.global_position
	mesh.global_rotation = Vector3(0.0, occupant_yaw, 0.0)

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

	# Multiplayer: avisar a los demás en qué asiento me senté (arman el pose sentado del proxy).
	var ns: CharacterNetSync = bi.get("net_sync")
	if is_instance_valid(ns):
		ns.set_seat_target(self)


func _stand_up() -> void:
	_release_occupant(true, true)

## Si el asiento se destruye (despawn) con alguien sentado, hay que liberarlo o queda trabado: en la
## máquina del ocupante _sit dejó la cápsula inactiva + colisión off + axis lock, y sin _stand_up eso
## nunca se revierte. Solo corre donde _seated_bi está seteado (el ocupante); en las demás máquinas el
## proxy se auto-cura (el productor ve el asiento inválido y limpia los flags). Ver multiplayer.md.
func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	_release_occupant(false, false)  # sin broadcast: el asiento ya se borró en todas las máquinas

## Revierte el estado de "sentado" del ocupante: flags (bi/anim/proc) + física de la cápsula. Con
## teleport=true lo reubica en el spawn point del asiento (pararse normal); con false lo deja donde
## está y no hace RPC — el asiento se está destruyendo y ya no existe en ninguna máquina.
func _release_occupant(teleport: bool, broadcast: bool) -> void:
	if not is_instance_valid(_seated_bi):
		return
	var bi      := _seated_bi
	var char_rb := bi.get("char_rigidbody") as CharacterRigidBody3D
	_seated_bi = null

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

	var ns: CharacterNetSync = bi.get("net_sync")
	if is_instance_valid(ns):
		if broadcast:
			ns.set_seat_target(null)  # avisar a los proxies (vuelven al solve de parado)
		else:
			ns.seat_target = null     # destrucción: el asiento ya se borró en todas las máquinas

	var pc: PlayerController = bi.get("player_controller")
	if is_instance_valid(pc):
		pc.call("apply_camera_pitch", 0.0)

	if not is_instance_valid(char_rb):
		return
	char_rb.axis_lock_linear_y = false
	char_rb.collider.disabled  = false
	char_rb.linear_velocity    = Vector3.ZERO
	char_rb.angular_velocity   = Vector3.ZERO
	char_rb.reset_impact_state()
	char_rb.is_snapshot_active = true
	char_rb.is_active          = true

	if teleport and is_instance_valid(_spawn_point):
		var target_pos   := _spawn_point.global_position
		var target_rot_y := char_rb.global_rotation.y
		char_rb.call_deferred("set", "global_position", target_pos)
		char_rb.call_deferred("set", "global_rotation", Vector3(0.0, target_rot_y, 0.0))
