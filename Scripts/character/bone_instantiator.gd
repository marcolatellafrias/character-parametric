class_name BoneInstantiator
extends Node3D

## Emitida cuando el jugador activo (re)crea su cámara en initialize_skeleton, para
## que quien la consuma (CharacterSpawner → AreaInstantiator) la reenganche.
signal active_camera_changed(camera: Camera3D)

@export var is_active: bool = false
@export var master_seed: int = 0
## When true (and this character is the active player), unlocks creative mode + the debug panel.
@export var debug_enabled: bool = false
## When true, this is a remote proxy (milestone 3): skeleton reconstructed from the seed, but the
## capsule is a puppet driven by CharacterNetSync — no local physics. Set before add_child.
@export var is_puppet: bool = false
var entity_instantiation: EntityInstantiation

var player_camera: Camera3D
var entity_archetype: EntityArchetype
var skel_sizes_util: SkeletonSizesUtil
var custom_bones_util: CustomBonesUtil
var char_rigidbody: CharacterRigidBody3D
var ik_util: IkUtil
var locomotion_signals: LocomotionSignals
var procedural_animator: ProceduralBoneAnimator
var ragdoll_util: RagdollUtil

## Entrada de animación: la llena _update_animation_inputs() cada frame; los módulos de animación
## la leen en vez de char_rigidbody (refactor de desacople, ver technical/character-animation.md).
var animation_inputs: AnimationInputs

var anim_mod: AnimationModifiers
var bone_animations: BoneAnimations
var arms_controller: ArmsController

var player_controller: PlayerController
## Solo en proxies remotos: lo setea el CharacterSpawner. Se llama al inicio del frame para aplicar
## el transform sincronizado ANTES del solve del esqueleto.
var net_sync: CharacterNetSync

@onready var global_targets:   Node3D = $"global_targets"
@onready var local_targets:    Node3D = $"local_targets"
@onready var skel_rigidbodies: Node3D = $"skel_rigidbodies"
@onready var joints:           Node3D = $"joints"

var jump_squat_t: float = 0.0
var crouch_t:     float = 0.0
## Pitch de la cabeza/columna (mirar arriba/abajo). Jugador local: de la cámara; proxy: de la red
## (lo setea CharacterNetSync.apply_to_puppet). El yaw no va acá: lo maneja la cápsula entera.
var head_pitch:   float = 0.0
var _npc_skip_frame: bool = false
var _reset_feet_after_recovery: bool = false  # plantar los pies el primer frame tras recuperarse

var grab_cone_mesh: MeshInstance3D = null
var show_grab_cone: bool = false
var grab_cone_half_angle: float = 120.0

var is_seated:    bool = false
var current_seat: Node = null

func _ready() -> void:
	if is_active:
		player_controller = PlayerController.new()
		add_child(player_controller)
	initialize_skeleton()

func initialize_skeleton() -> void:
	_clear_prior_generations()

	entity_instantiation = EntityInstantiation.create(master_seed)
	entity_archetype     = entity_instantiation.arch_final
	skel_sizes_util      = SkeletonSizesUtil.create(entity_instantiation)
	custom_bones_util    = CustomBonesUtil.create(skel_sizes_util, entity_instantiation)
	ik_util              = IkUtil.create(skel_sizes_util, self)
	ik_util.debug_enabled = is_active

	var full_height := skel_sizes_util.leg_height + skel_sizes_util.torso_height + skel_sizes_util.head_height
	var charRb      := Vector3(skel_sizes_util.shoulders_width * 2, full_height, skel_sizes_util.hips_width * 2)
	char_rigidbody  = CharacterRigidBody3D.create(charRb, skel_sizes_util.distance_from_ground, skel_sizes_util.leg_height, is_active, entity_instantiation)
	if is_puppet:
		char_rigidbody.setup_as_puppet()  # antes de add_child: no simula ni un frame
	char_rigidbody.fall_triggered.connect(_on_fall_triggered)
	char_rigidbody.add_child(custom_bones_util.lower_spine)
	add_child(char_rigidbody)
	
	var cone_dist := entity_instantiation.arch_final.reach * entity_instantiation.arch_final.reach_multiplier
	var cone_radius : float = cone_dist * abs(tan(deg_to_rad(grab_cone_half_angle)))
	grab_cone_mesh = DebugUtil.create_debug_cone(Color(0.2, 0.8, 1.0, 0.15), cone_dist, cone_radius)
	grab_cone_mesh.visible = false
	char_rigidbody.add_child(grab_cone_mesh)
	_setup_char_grabbable()

	local_targets.add_child(ik_util.left_leg_raycast)
	local_targets.add_child(ik_util.right_leg_raycast)
	ik_util.left_leg_raycast.add_exception(char_rigidbody)
	ik_util.right_leg_raycast.add_exception(char_rigidbody)
	local_targets.add_child(ik_util.left_leg_next_target)
	local_targets.add_child(ik_util.right_leg_next_target)
	local_targets.add_child(ik_util.left_leg_airborne_target)
	local_targets.add_child(ik_util.right_leg_airborne_target)
	global_targets.add_child(ik_util.left_leg_current_target)
	global_targets.add_child(ik_util.right_leg_current_target)

	local_targets.add_child(ik_util.left_arm_ik_target)
	local_targets.add_child(ik_util.right_arm_ik_target)
	local_targets.add_child(ik_util.left_arm_pole)
	local_targets.add_child(ik_util.right_arm_pole)

	# Creamos anim_mod y arms_controller antes del player para que setup los reciba
	anim_mod = AnimationModifiers.new()
	add_child(anim_mod)
	anim_mod.bi = self

	arms_controller = ArmsController.new()
	add_child(arms_controller)
	arms_controller.bi = self
	arms_controller.setup(anim_mod)

	if is_active and is_instance_valid(player_controller):
		player_camera = Camera3D.new()
		player_camera.current = true
		char_rigidbody.add_child(player_camera)
		player_controller.on_skeleton_built(self, player_camera)
		active_camera_changed.emit(player_camera)

	animation_inputs = AnimationInputs.new()
	_update_animation_inputs()
	locomotion_signals = LocomotionSignals.create(ik_util, animation_inputs, skel_sizes_util)

	ik_util.left_arm_ik_target.position  = skel_sizes_util.left_arm_tip_rest_local
	ik_util.right_arm_ik_target.position = skel_sizes_util.right_arm_tip_rest_local
	ik_util.left_arm_pole.position       = skel_sizes_util.left_arm_pole_rest_local
	ik_util.right_arm_pole.position      = skel_sizes_util.right_arm_pole_rest_local

	ik_util.solve_two_bone_ik(custom_bones_util.left_upper_arm, custom_bones_util.left_lower_arm,
		ik_util.left_arm_ik_target.global_position, ik_util.left_arm_pole.global_position)
	ik_util.solve_two_bone_ik(custom_bones_util.right_upper_arm, custom_bones_util.right_lower_arm,
		ik_util.right_arm_ik_target.global_position, ik_util.right_arm_pole.global_position)

	procedural_animator = ProceduralBoneAnimator.create(locomotion_signals)

	bone_animations = BoneAnimations.new()
	add_child(bone_animations)
	bone_animations.bi = self
	bone_animations.register_all()

	ragdoll_util = RagdollUtil.create(custom_bones_util, skel_rigidbodies, joints)
	ragdoll_util.ik_util = ik_util  # para que el IK de recuperación use el mismo pole que la locomoción

	jump_squat_t = 0.0
	crouch_t     = 0.0

func _on_fall_triggered(world_dir: Vector3) -> void:
	if is_seated:
		return
	# No re-disparar si ya estoy ragdolleando NI levantándome: un impacto espurio durante la
	# recuperación (p.ej. la cápsula asentándose) reiniciaría el ragdoll a mitad de camino y dejaría
	# los huesos desarmados. Ver technical/characters.md.
	if not is_instance_valid(ragdoll_util) or ragdoll_util.is_active or ragdoll_util.is_recovering:
		return
	char_rigidbody.is_snapshot_active = false
	ragdoll_util.activate_with_impact(char_rigidbody, custom_bones_util.lower_spine, world_dir)

func _clear_prior_generations() -> void:
	if is_instance_valid(ragdoll_util):
		if ragdoll_util.is_active and is_instance_valid(char_rigidbody):
			char_rigidbody.freeze = false
			char_rigidbody.collider.disabled = false
		ragdoll_util.cleanup()
	ragdoll_util = null

	for child in global_targets.get_children():   child.queue_free()
	for child in local_targets.get_children():    child.queue_free()
	for child in skel_rigidbodies.get_children(): child.queue_free()
	for child in joints.get_children():           child.queue_free()

	if is_instance_valid(char_rigidbody):
		char_rigidbody.queue_free()

	if is_instance_valid(anim_mod):
		anim_mod.queue_free()
		anim_mod = null
	if is_instance_valid(arms_controller):
		arms_controller.queue_free()
		arms_controller = null
	if is_instance_valid(bone_animations):
		bone_animations.queue_free()
		bone_animations = null

	player_camera = null

func _physics_process(delta: float) -> void:
	# Proxy remoto: aplicar el transform sincronizado (posición + yaw) ANTES de todo, para que el
	# solve del esqueleto de este frame use el yaw actual. Va antes del frame-skip así la cápsula
	# sigue moviéndose suave aunque el solve corra a mitad de tasa. Ver character-animation.md.
	if is_instance_valid(net_sync):
		net_sync.apply_to_puppet()

	# NPCs/proxies resuelven a MEDIA TASA por performance (el solve procedural es caro). Eso deja en
	# proxies el esqueleto/cuerpos 1-2 frames atrás de la física (que corre cada frame), así que lo que
	# lea esas poses las sincroniza antes (regla sync-before-snapshot; _build_joints ya lo hace en su
	# primera línea). NO salteamos mientras ragdollea/recupera: si no, el blend de recuperación tarda el
	# doble y _update_active se atrasa. El solve pesado ya se saltea solo al ragdollear, así que full-rate
	# acá no cuesta. Ver technical/character-animation.md (solve a media tasa).
	#
	# Los frames que SÍ resuelven cubren el DOBLE de tiempo real. Todo el suavizado (locomotion,
	# brazos, anim_mod) y la fase de marcha son función de delta, así que hay que pasarles el delta
	# EFECTIVO: con el delta crudo esos sistemas avanzan a la mitad de velocidad en tiempo real y los
	# pies se quedan atrás del cuerpo (el cuerpo sí se mueve todos los frames).
	var _ragdolling := is_instance_valid(ragdoll_util) and (ragdoll_util.is_active or ragdoll_util.is_recovering)
	var solve_delta := delta
	if not is_active and not _ragdolling:
		_npc_skip_frame = not _npc_skip_frame
		if _npc_skip_frame:
			return
		solve_delta = delta * 2.0

	_update_ragdoll_ext_state()
	_update_animation_inputs()          # productor: llena animation_inputs desde la cápsula
	_update_local_targets_positions()   # consumidor: lee animation_inputs (ya no la cápsula)

	if is_instance_valid(ragdoll_util):
		ragdoll_util.update(solve_delta)
		if ragdoll_util.is_active:
			ik_util.update_ik_raycast(true,  custom_bones_util, skel_sizes_util, animation_inputs)
			ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util, animation_inputs)
			return
		if ragdoll_util.is_recovering and not ik_util.recovery_targets_locked:
			ik_util.recovery_targets_locked = true
		elif not ragdoll_util.is_recovering and ik_util.recovery_targets_locked:
			ik_util.recovery_targets_locked = false
			char_rigidbody.is_snapshot_active = true
			_reset_feet_after_recovery = true  # plantar los pies bajo el cuerpo, sin catch-up a los pasos

	skel_sizes_util.update(solve_delta, animation_inputs, entity_instantiation, ik_util)

	if is_instance_valid(arms_controller):
		arms_controller.update_arm_compress(jump_squat_t, 1.0 if is_seated else crouch_t)

	locomotion_signals.update(solve_delta)

	ik_util.left_arm_ik_target.position  = skel_sizes_util.left_arm_tip_rest_local
	ik_util.right_arm_ik_target.position = skel_sizes_util.right_arm_tip_rest_local

	if is_seated and is_instance_valid(current_seat):
		_solve_seated_frame(solve_delta)
	else:
		_solve_standing_frame(solve_delta)

	_update_grab_cone()


func _update_ragdoll_ext_state() -> void:
	if not is_instance_valid(char_rigidbody) or not is_instance_valid(ragdoll_util):
		return
	if ragdoll_util.is_active:
		char_rigidbody._ext_ragdoll_state = 1
	elif ragdoll_util.is_recovering:
		char_rigidbody._ext_ragdoll_state = 2
	else:
		char_rigidbody._ext_ragdoll_state = 0


func _solve_standing_frame(delta: float) -> void:
	ik_util.update_airborne_target(animation_inputs, true,  skel_sizes_util)
	ik_util.update_airborne_target(animation_inputs, false, skel_sizes_util)

	ik_util.update_ik_raycast(true,  custom_bones_util, skel_sizes_util, animation_inputs)
	ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util, animation_inputs)

	if _reset_feet_after_recovery:
		# Ya corrió el raycast (next_target fresco bajo el cuerpo): plantamos ahí el pie, sin catch-up.
		ik_util.reset_step_targets_to_ground()
		_reset_feet_after_recovery = false

	# procedural primero, anim_mod encima — mismo orden que antes
	procedural_animator.update()

	if is_instance_valid(anim_mod):
		anim_mod.jump_squat_t = jump_squat_t
		anim_mod.crouch_t     = crouch_t
		anim_mod.apply(delta)

	var rb_basis := custom_bones_util.lower_spine.global_transform.basis
	var left_anim_offset:  Vector3 = ik_util.left_arm_ik_target.position  - skel_sizes_util.left_arm_tip_rest_local
	var right_anim_offset: Vector3 = ik_util.right_arm_ik_target.position - skel_sizes_util.right_arm_tip_rest_local

	ik_util.left_arm_ik_target.global_position  = custom_bones_util.left_upper_arm.global_position  + rb_basis * (skel_sizes_util.left_arm_tip_rest_local  - skel_sizes_util.left_arm_shoulder_rest_local + left_anim_offset)
	ik_util.right_arm_ik_target.global_position = custom_bones_util.right_upper_arm.global_position + rb_basis * (skel_sizes_util.right_arm_tip_rest_local - skel_sizes_util.right_arm_shoulder_rest_local + right_anim_offset)

	var left_pole_anim_offset:  Vector3 = ik_util.left_arm_pole.position  - skel_sizes_util.left_arm_pole_rest_local
	var right_pole_anim_offset: Vector3 = ik_util.right_arm_pole.position - skel_sizes_util.right_arm_pole_rest_local

	ik_util.left_arm_pole.global_position  = custom_bones_util.left_upper_arm.global_position  + rb_basis * (skel_sizes_util.left_arm_pole_rest_local  - skel_sizes_util.left_arm_shoulder_rest_local + left_pole_anim_offset)
	ik_util.right_arm_pole.global_position = custom_bones_util.right_upper_arm.global_position + rb_basis * (skel_sizes_util.right_arm_pole_rest_local - skel_sizes_util.right_arm_shoulder_rest_local + right_pole_anim_offset)

	# Proxy: manejar el agarre desde el estado sincronizado (el jugador local lo maneja su IC).
	if not is_active and is_instance_valid(arms_controller):
		arms_controller.drive_grab(delta, animation_inputs.grab_target)

	if is_instance_valid(arms_controller):
		arms_controller.apply_world_overrides(delta)

	ik_util.solve_two_bone_ik(custom_bones_util.left_upper_arm, custom_bones_util.left_lower_arm,
		ik_util.left_arm_ik_target.global_position, ik_util.left_arm_pole.global_position)
	ik_util.solve_two_bone_ik(custom_bones_util.right_upper_arm, custom_bones_util.right_lower_arm,
		ik_util.right_arm_ik_target.global_position, ik_util.right_arm_pole.global_position)

	if is_instance_valid(ragdoll_util) and not ragdoll_util.is_recovering:
		ragdoll_util.sync_to_bones()


func _solve_seated_frame(delta: float) -> void:
	current_seat.update_seated_visual(char_rigidbody.global_rotation.y)

	# 1. Fijar spine
	var seat_pos : Vector3 = current_seat.global_position
	var backward  := char_rigidbody.global_transform.basis.z
	var z_offset  : float  = skel_sizes_util.upper_leg_size.y - current_seat.seat_area.z * 0.5
	var spine_target := Vector3(seat_pos.x, seat_pos.y + current_seat.height, seat_pos.z) + backward * z_offset
	custom_bones_util.lower_spine.global_position = spine_target
	char_rigidbody.global_position.x = seat_pos.x
	char_rigidbody.global_position.z = seat_pos.z

	# 2. Procedural animator para cuello/cabeza (look up/down), anim_mod is_seated=true
	#    así que _apply_root_offsets no mueve el spine
	procedural_animator.update()
	if is_instance_valid(anim_mod):
		anim_mod.jump_squat_t = jump_squat_t
		anim_mod.crouch_t     = crouch_t
		anim_mod.apply(delta)

	# 3. Re-fijar spine por si procedural_animator lo movió
	custom_bones_util.lower_spine.global_position = spine_target

	# 4. Calcular y fijar piernas
	var forward := -char_rigidbody.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var left_hip_tip  := custom_bones_util.left_hip.global_position  + custom_bones_util.left_hip.global_transform.basis.y  * custom_bones_util.left_hip.capsule_dimensions.y
	var right_hip_tip := custom_bones_util.right_hip.global_position + custom_bones_util.right_hip.global_transform.basis.y * custom_bones_util.right_hip.capsule_dimensions.y

	var left_knee  := left_hip_tip  + forward * skel_sizes_util.upper_leg_size.y
	var right_knee := right_hip_tip + forward * skel_sizes_util.upper_leg_size.y

	var tuck       := forward * -skel_sizes_util.lower_leg_size.y * 0.2
	var left_foot  := left_knee  + Vector3.DOWN * skel_sizes_util.lower_leg_size.y * 0.85 + tuck
	var right_foot := right_knee + Vector3.DOWN * skel_sizes_util.lower_leg_size.y * 0.85 + tuck
	var pole       := forward

	ik_util.solve_two_bone_ik(custom_bones_util.left_upper_leg,  custom_bones_util.left_lower_leg,  left_foot,  left_knee  + pole)
	ik_util.solve_two_bone_ik(custom_bones_util.right_upper_leg, custom_bones_util.right_lower_leg, right_foot, right_knee + pole)
	ik_util.left_leg_current_target.global_position  = left_foot
	ik_util.right_leg_current_target.global_position = right_foot

	# 5. Recalcular targets de brazos desde spine ya fijado
	var rb_basis := custom_bones_util.lower_spine.global_transform.basis
	var left_anim_offset:  Vector3 = ik_util.left_arm_ik_target.position  - skel_sizes_util.left_arm_tip_rest_local
	var right_anim_offset: Vector3 = ik_util.right_arm_ik_target.position - skel_sizes_util.right_arm_tip_rest_local

	ik_util.left_arm_ik_target.global_position  = custom_bones_util.left_upper_arm.global_position  + rb_basis * (skel_sizes_util.left_arm_tip_rest_local  - skel_sizes_util.left_arm_shoulder_rest_local + left_anim_offset)
	ik_util.right_arm_ik_target.global_position = custom_bones_util.right_upper_arm.global_position + rb_basis * (skel_sizes_util.right_arm_tip_rest_local - skel_sizes_util.right_arm_shoulder_rest_local + right_anim_offset)

	var left_pole_anim_offset:  Vector3 = ik_util.left_arm_pole.position  - skel_sizes_util.left_arm_pole_rest_local
	var right_pole_anim_offset: Vector3 = ik_util.right_arm_pole.position - skel_sizes_util.right_arm_pole_rest_local

	ik_util.left_arm_pole.global_position  = custom_bones_util.left_upper_arm.global_position  + rb_basis * (skel_sizes_util.left_arm_pole_rest_local  - skel_sizes_util.left_arm_shoulder_rest_local + left_pole_anim_offset)
	ik_util.right_arm_pole.global_position = custom_bones_util.right_upper_arm.global_position + rb_basis * (skel_sizes_util.right_arm_pole_rest_local - skel_sizes_util.right_arm_shoulder_rest_local + right_pole_anim_offset)

	# 6. World overrides de brazos (pitch de cámara)
	if is_instance_valid(arms_controller):
		arms_controller.apply_world_overrides(delta)

	# 7. IK de brazos
	ik_util.solve_two_bone_ik(custom_bones_util.left_upper_arm,  custom_bones_util.left_lower_arm,
		ik_util.left_arm_ik_target.global_position, ik_util.left_arm_pole.global_position)
	ik_util.solve_two_bone_ik(custom_bones_util.right_upper_arm, custom_bones_util.right_lower_arm,
		ik_util.right_arm_ik_target.global_position, ik_util.right_arm_pole.global_position)

	# 8. Re-fijar piernas por si world_overrides movió el spine
	ik_util.solve_two_bone_ik(custom_bones_util.left_upper_leg,  custom_bones_util.left_lower_leg,  left_foot,  left_knee  + pole)
	ik_util.solve_two_bone_ik(custom_bones_util.right_upper_leg, custom_bones_util.right_lower_leg, right_foot, right_knee + pole)

## Ubica local_targets (raycasts de pies, targets/poles de brazos) siguiendo el transform del
## personaje. Lee animation_inputs (no la cápsula en vivo): así el facing viene de una sola fuente
## llenada por el productor tras aplicarse el transform (local o de red), sin depender del orden.
func _update_local_targets_positions() -> void:
	if animation_inputs == null:
		return
	local_targets.global_position = animation_inputs.origin
	local_targets.global_rotation = Vector3(0, animation_inputs.basis.get_euler().y, 0)

## Productor de la entrada de animación. Hoy lee la cápsula física (igual que antes lo hacían los
## módulos directo); a futuro un proxy la llenará desde la red. Ver technical/character-animation.md.
func _update_animation_inputs() -> void:
	if not is_instance_valid(char_rigidbody) or animation_inputs == null:
		return
	var t := char_rigidbody.global_transform
	animation_inputs.velocity     = char_rigidbody.get_motion_velocity()
	animation_inputs.basis        = t.basis
	animation_inputs.origin       = t.origin
	animation_inputs.grounded     = char_rigidbody.is_grounded
	animation_inputs.ground_point = char_rigidbody.get_ground_collision_point()
	animation_inputs.impact_y     = char_rigidbody.impact_y
	animation_inputs.impact_xz    = char_rigidbody.impact_xz
	animation_inputs.crouch_t     = crouch_t
	animation_inputs.jump_squat_t = jump_squat_t
	# Head pitch: jugador local = de su cámara (clampeado); proxy = lo que ya dejó la red en head_pitch
	# (apply_to_puppet corre antes que este productor). Los NPCs quedan en 0 (mirada neutra).
	if is_active and is_instance_valid(player_camera):
		head_pitch = clampf(player_camera.rotation.x, -0.5, 0.8)
	animation_inputs.head_pitch   = head_pitch
	# Grab: proxy = lo sincronizado; jugador local = lo que setea su InteractionController.
	animation_inputs.grab_target  = net_sync.grab_target if is_instance_valid(net_sync) else null
	# Sentado: en un proxy derivamos el estado del asiento sincronizado (el jugador local lo maneja
	# su SeatInteractable._sit/_stand_up). Estos flags los lee el gate seated/standing de este frame.
	if not is_active:
		_set_seated_flags(net_sync.seat_target if is_instance_valid(net_sync) else null)
	# Reset del pulso de impacto vertical (antes lo hacía locomotion_signals._update_velocity_signals).
	char_rigidbody.impact_y_signed = 0.0

## Setea todo el estado de pose "sentado" (flags que leen el gate del solve, el anim_mod y el
## procedural). Lo usa el proxy para replicar; el jugador local lo maneja su SeatInteractable.
func _set_seated_flags(seat: Node) -> void:
	var seated := is_instance_valid(seat)
	is_seated    = seated
	current_seat = seat
	if is_instance_valid(anim_mod):
		anim_mod.is_seated = seated
	if is_instance_valid(procedural_animator):
		procedural_animator.is_seated = seated
		procedural_animator._seated_locked_bone = custom_bones_util.lower_spine if seated else null

func refresh_camera_animations() -> void:
	if is_instance_valid(bone_animations):
		bone_animations.refresh_camera_animations()

func set_first_person_visibility(first_person: bool) -> void:
	var visible_bones: Array[CustomBone] = [
		custom_bones_util.left_upper_feet,
		custom_bones_util.right_upper_feet,
		custom_bones_util.left_lower_arm,
		custom_bones_util.right_lower_arm,
	]
	var all_bones: Array[CustomBone] = [
		custom_bones_util.lower_spine,
		custom_bones_util.middle_spine,
		custom_bones_util.upper_spine,
		custom_bones_util.chest,
		custom_bones_util.left_hip,
		custom_bones_util.right_hip,
		custom_bones_util.left_upper_leg,
		custom_bones_util.left_lower_leg,
		custom_bones_util.right_upper_leg,
		custom_bones_util.right_lower_leg,
		custom_bones_util.left_upper_feet,
		custom_bones_util.right_upper_feet,
		custom_bones_util.left_shoulder,
		custom_bones_util.right_shoulder,
		custom_bones_util.left_upper_arm,
		custom_bones_util.left_lower_arm,
		custom_bones_util.right_upper_arm,
		custom_bones_util.right_lower_arm,
		custom_bones_util.neck,
		custom_bones_util.head,
	]
	for bone in all_bones:
		if not is_instance_valid(bone):
			continue
		bone.set_mesh_visible(first_person == false or visible_bones.has(bone))

func _setup_char_grabbable() -> void:
	var grabbable := CharacterGrabbable.new()
	grabbable.owner_bi = self  # para apagarse cuando este personaje ragdolea (no se agarra a un caído)
	grabbable.name = "Grabbable"  # nombre estable para el grab sync entre máquinas
	char_rigidbody.add_child(grabbable)

	var full_height    := skel_sizes_util.leg_height + skel_sizes_util.torso_height + skel_sizes_util.head_height
	var ground_local_y := char_rigidbody._capsule_stand_y_offset - full_height * 0.5
	var handle_y       := ground_local_y + skel_sizes_util.leg_height \
		+ skel_sizes_util.lower_spine_size.y + skel_sizes_util.middle_spine_size.y
	var handle_x := skel_sizes_util.shoulders_width * 0.5

	grabbable.add_handle_point_local(Vector3(-handle_x, handle_y, 0.0))
	grabbable.add_handle_point_local(Vector3( handle_x, handle_y, 0.0))
	grabbable.add_grab_point_local(Vector3(0.0, char_rigidbody._capsule_stand_y_offset, 0.0))

func _update_grab_cone() -> void:
	if not is_instance_valid(grab_cone_mesh) or not is_instance_valid(player_camera):
		return
	grab_cone_mesh.visible = is_active and show_grab_cone
	if not grab_cone_mesh.visible:
		return
	var chest := custom_bones_util.chest
	var origin := chest.global_position + chest.global_transform.basis.y * skel_sizes_util.chest_size.y
	var fwd := -player_camera.global_transform.basis.z
	grab_cone_mesh.global_position = origin
	grab_cone_mesh.global_transform.basis = Basis.looking_at(-fwd, Vector3.UP)

func get_interaction_origin() -> Vector3:
	var sizes       := skel_sizes_util
	var full_height := sizes.leg_height + sizes.torso_height + sizes.head_height
	var ground_y    := char_rigidbody.global_position.y + (char_rigidbody._capsule_stand_y_offset - full_height * 0.5)

	if is_seated and is_instance_valid(current_seat):
		var seat_pos    : Vector3 = current_seat.global_position
		var backward    := char_rigidbody.global_transform.basis.z
		var z_offset    : float = sizes.upper_leg_size.y - current_seat.seat_area.z * 0.5
		var spine_world := Vector3(seat_pos.x, seat_pos.y + current_seat.height, seat_pos.z) + backward * z_offset
		return spine_world + Vector3(0.0,
			sizes.lower_spine_size.y + sizes.middle_spine_size.y + sizes.upper_spine_size.y + sizes.chest_size.y,
			0.0)

	var chest_tip_y := ground_y + sizes.leg_height \
		+ sizes.lower_spine_size.y + sizes.middle_spine_size.y \
		+ sizes.upper_spine_size.y + sizes.chest_size.y

	chest_tip_y -= sizes.leg_height * 0.35 * crouch_t

	return Vector3(char_rigidbody.global_position.x, chest_tip_y, char_rigidbody.global_position.z)
