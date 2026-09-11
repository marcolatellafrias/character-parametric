@tool
class_name SeatInteractable
extends ActivatableInteractable

## ── ALTURA ──────────────────────────────────────────────────────────────────────────────────────
## La silla se acomoda al que se sienta: sube o baja hasta que el origen de SU rayo de interacción quede
## a `eye_height` sobre la base, la altura óptima para usar lo que tiene adelante. Así un tablero se ve
## y se alcanza igual con cualquier arquetipo. Las piernas todavía no se acomodan: a los bajos les
## cuelgan y a los altos se les pueden meter en el piso.
##
## Sin nadie vuelve a la altura de un arquetipo medio (ver TYPICAL_EYE_ABOVE_PELVIS): no se acuerda del
## último que se sentó. Cada cambio es una transición corta, y el ocupante sube y baja con la silla
## porque la pose sentada lee `height` en cada frame.
##
## No viaja por red: cada máquina conoce el esqueleto de cada personaje y deriva la misma altura.
## Altura de la pelvis sobre la base con la silla a su altura de modelo. Es la referencia de SwivelSeat
## para estirar el pie, no la altura de la silla vacía.
@export var rest_height:       float       = 0.42
## A qué altura sobre la base tiene que quedar la mira del que se sienta. La nave pone la de su piloto
## según el tablero (ver Ship.EYE_OVER_PANEL); este default es para asientos sueltos.
@export var eye_height:        float       = 1.15
@export var seat_area:         Vector3     = Vector3(0.6, 0.5, 0.6)
@export var stand_up_location: Vector2     = Vector2(0.0, 1.2)
@export var seat_scene:        PackedScene = null
@export var show_debug:        bool        = false

## Cuánto puede bajar y subir la silla respecto de su altura de modelo, en metros.
const MIN_LIFT := -0.2
const MAX_LIFT := 0.5
## Qué tan rápido llega a la altura nueva (1/s): con 8 está al 95 % en unos 0,4 s.
const LIFT_RATE := 8.0
## La mira sobre la pelvis de un arquetipo medio: medida, los arquetipos van de 0,61 (nene) a 0,79
## (gordo). Pone la altura de la silla vacía, a mitad de camino entre sus ocupantes posibles.
const TYPICAL_EYE_ABOVE_PELVIS := 0.70

## Altura ACTUAL de la pelvis sobre la base. Ver ALTURA.
var height := 0.0
var _visual_root:   Node3D      = null
var _body:          RigidBody3D = null
var _spawn_point:   Node3D      = null
var _seated_bi:     Node        = null
var _borrowed_mesh: Node3D      = null
## Transform de reposo del visual (sin ocupante), guardado al construirlo: es a donde vuelve solo.
var _visual_rest_local: Transform3D = Transform3D.IDENTITY
## Personaje que está posando este asiento EN ESTA MÁQUINA (lo registra update_seated_visual).
var _visual_occupant: Node = null
## Ocupación exclusiva (un solo jugador por asiento), arbitrada por el host. Ver ExclusiveClaim.
var _claim:         ExclusiveClaim = null

## ── ASIENTO SOBRE ALGO QUE SE MUEVE ─────────────────────────────────────────────────────────────
## Sentarse es una FOTO: `_sit` pone la cápsula en el asiento una vez y la deja inerte (collider
## apagado, Y bloqueada). La pose del esqueleto sí sigue al asiento cada frame, y
## `BoneInstantiator._pose_root` además fija la cápsula en X y Z — pero nada movía su ALTURA ni su
## rumbo. En un asiento fijo da igual; en la nave, al despegar el piloto quedaba colgando donde se
## sentó —y la cámara, que es hija de la cápsula, con él—, y al girar la nave seguía mirando al mismo
## punto del mundo mientras la cabina rotaba alrededor.
##
## Mover la cápsula acá es seguro justamente porque está inerte: con el collider apagado no tiene
## contactos, así que escribirle la posición no pelea con el motor de física.
##
## Solo corre en la máquina del ocupante (`_seated_bi` lo setea `_sit`). En las demás la cápsula
## llega por red, ya movida.
var _occupant_y_offset := 0.0
var _last_yaw          := 0.0
## Para quién está calculada `_occupant_eye` (la mira sobre la pelvis), así no se recalcula cada frame.
var _lift_occupant: Node = null
var _occupant_eye       := 0.0

func _ready() -> void:
	height = typical_height()  # nace ya a su altura, sin acomodarse al aparecer
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
	_visual_rest_local = _visual_root.transform

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
	add_handle_point_local(Vector3(0.0, rest_height + seat_area.y * 0.5, 0.0))

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

## Saca al ocupante EN EL LUGAR (sin teleport al spawn point): libera localmente ya —sincrónico, sin
## esperar el round-trip del host— y avisa a los proxies. Lo usan los cambios de estado que la cápsula
## sentada no soporta y que necesitan el asiento libre ANTES de seguir: el respawn (reconstruye el
## esqueleto) y el ragdoll (ver PlayerController._leave_seat_in_place).
func release_occupant_in_place() -> void:
	if not is_instance_valid(_seated_bi):
		return
	if is_instance_valid(_claim):
		_claim.release()          # que el host libere la ocupación (async, no importa el orden)
	_release_occupant(false, true)  # revert local ya, sin teleport pero avisando a los proxies

# ── Visual: función de la ocupación, no efecto de los eventos ─────────────────
# Girar con el ocupante y volver al reposo se DERIVAN cada frame de quién ocupa el asiento,
# revalidado contra el estado vivo del personaje. No salen de los eventos de sentarse/pararse porque
# esos solo corren en la máquina del ocupante (_seated_bi solo lo setea _sit): en un proxy el visual
# se rotaba y nadie lo devolvía nunca, así que quedaba congelado en el último yaw al pararse. Con la
# derivación no hay ninguna salida —pararse, ragdollear, despawn del personaje, desconexión— que haya
# que acordarse de limpiar: dejan de cumplir la condición y el asiento se acomoda solo.

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_carry_occupant()
	if not _is_occupied_by(_visual_occupant):
		_visual_occupant = null
		_restore_rest_visual()
	_update_height(delta)

## Lleva la silla a la altura de su ocupante, o a la de reposo si no hay nadie. Ver ALTURA.
func _update_height(delta: float) -> void:
	var target := typical_height()
	if is_instance_valid(_visual_occupant):
		if _visual_occupant != _lift_occupant:
			_lift_occupant = _visual_occupant
			var bones: CustomBonesUtil = _visual_occupant.get("custom_bones_util")
			_occupant_eye = bones.rest_eye_above_pelvis() if bones != null else eye_height - rest_height
		target = _height_for(_occupant_eye)
	else:
		_lift_occupant = null
	height = lerpf(height, target, 1.0 - exp(-LIFT_RATE * delta))
	_apply_lift(_visual_root)
	_apply_lift(_borrowed_mesh)

## Altura de la silla vacía: la de un arquetipo medio. Con ella planea quien arma el asiento, por ejemplo
## el lugar para las rodillas.
func typical_height() -> float:
	return _height_for(TYPICAL_EYE_ABOVE_PELVIS)

## La altura de pelvis que deja la mira a `eye_height`, dentro de lo que la silla puede estirarse.
func _height_for(eye_above_pelvis: float) -> float:
	return clampf(eye_height - eye_above_pelvis, rest_height + MIN_LIFT, rest_height + MAX_LIFT)

func _apply_lift(visual: Node3D) -> void:
	var swivel := visual as SwivelSeat
	if is_instance_valid(swivel):
		swivel.set_lift(height - rest_height)

## Lleva al ocupante con el asiento: altura y rumbo. Ver ASIENTO SOBRE ALGO QUE SE MUEVE.
func _carry_occupant() -> void:
	if not is_instance_valid(_seated_bi):
		return
	var char_rb := _seated_bi.get("char_rigidbody") as CharacterRigidBody3D
	if not is_instance_valid(char_rb):
		return
	char_rb.global_position.y = global_position.y + _occupant_y_offset
	var yaw := global_rotation.y
	var turned := wrapf(yaw - _last_yaw, -PI, PI)
	_last_yaw = yaw
	if absf(turned) < 0.000001:
		return
	# El rumbo de la cápsula lo escribe PlayerController desde `camera_yaw` en cada frame, así que es eso
	# lo que hay que girar: tocar la cápsula directo se pisaría en el frame siguiente.
	var pc: PlayerController = _seated_bi.get("player_controller")
	if is_instance_valid(pc):
		pc.camera_yaw += turned

## ¿Este personaje sigue realmente sentado acá? Es la MISMA condición que el gate del solve de pose
## (BoneInstantiator._solve_frame), así que el visual y el pose no pueden discrepar. Ragdollear cuenta
## como NO sentado: la cápsula deja de mandar el pose y el asiento no tiene a quién seguir. Eso lo
## cubre además en el orden en que llegan las dos novedades a un proxy (el asiento libre viaja por RPC
## confiable y el flag de ragdoll en el estado por tick), sin importar cuál gane.
func _is_occupied_by(bi: Node) -> bool:
	if not is_instance_valid(bi):
		return false
	if bi.get("current_seat") != self or not bi.get("is_seated"):
		return false
	var rd = bi.get("ragdoll_util")
	return not (is_instance_valid(rd) and (rd.is_active or rd.is_recovering))

func _restore_rest_visual() -> void:
	if not is_instance_valid(_visual_root):
		return
	_visual_root.transform = _visual_rest_local
	if not is_instance_valid(_borrowed_mesh):
		_visual_root.visible = true  # sin malla prestada, nadie lo está reemplazando

## El asiento gira con el ocupante (mismo yaw) — sin sincronizar nada extra: el yaw ya viaja en el
## transform del personaje. Owner: la malla prestada (hija de la cápsula, para esconderse en primera
## persona con el cuerpo); proxy remoto: el visual propio del asiento (a la vista, porque ahí nunca
## se corrió _sit). Lo llama BoneInstantiator._pose_root cada frame del que está sentado, y de paso
## REGISTRA al ocupante para que _physics_process pueda soltar el visual cuando deje de estarlo.
func update_seated_visual(occupant: Node, occupant_yaw: float) -> void:
	_visual_occupant = occupant
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
	# Para `_carry_occupant`: a qué altura quedó la cápsula respecto del asiento, y hacia dónde mira.
	_occupant_y_offset = char_rb.global_position.y - global_position.y
	_last_yaw          = global_rotation.y

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
