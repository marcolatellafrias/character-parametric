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
## Espejo del rig lógico sobre el Skeleton3D del modelo de Blender. null mientras no exista el
## modelo — en ese caso el personaje se sigue dibujando con los meshes de CustomBone, como siempre.
## Ver technical/skinned-character-migration.md.
var skinned_body: SkinnedBodyUtil
## Gizmos de debug del esqueleto (líneas/articulaciones y cápsulas de colisión). Se crea recién
## cuando alguien prende un visualizador desde el panel. Ver Scripts/character/debug/skeleton_debug_draw.gd.
var skeleton_debug: SkeletonDebugDraw
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

## Debug: esconde el personaje ENTERO (malla skinneada + cápsulas de CustomBone). Gana sobre la
## primera persona — si no, cambiar de cámara con el numpad lo volvía a mostrar a medias.
var character_hidden: bool = false
var grab_cone_mesh: MeshInstance3D = null
var show_grab_cone: bool = false
var grab_cone_half_angle: float = 120.0

var is_seated:    bool = false
var current_seat: Node = null
## Targets de las piernas sentadas, cacheados por _pose_legs_seated para que _repin_legs_seated
## re-resuelva contra los MISMOS. Ver _solve_frame.
var _seated_left_foot:  Vector3 = Vector3.ZERO
var _seated_right_foot: Vector3 = Vector3.ZERO
var _seated_left_pole:  Vector3 = Vector3.ZERO
var _seated_right_pole: Vector3 = Vector3.ZERO

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

	var full_height := skel_sizes_util.leg_height + skel_sizes_util.torso_height + skel_sizes_util.head_height
	var charRb      := Vector3(skel_sizes_util.shoulders_width * 2, full_height, skel_sizes_util.hips_width * 2)
	char_rigidbody  = CharacterRigidBody3D.create(charRb, skel_sizes_util.distance_from_ground, skel_sizes_util.leg_height, is_active, entity_instantiation)
	if is_puppet:
		char_rigidbody.setup_as_puppet()  # antes de add_child: no simula ni un frame
	char_rigidbody.fall_triggered.connect(_on_fall_triggered)
	char_rigidbody.add_child(custom_bones_util.lower_spine)
	add_child(char_rigidbody)


	var cone_dist := skel_sizes_util.interaction_reach
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

	# El espejo va acá nada más que por orden de construcción: su calibración NO depende de la pose
	# (sale de dos reposos, ver SkinnedBodyUtil._bind), así que da igual si los brazos ya se
	# resolvieron o no. Durante un tiempo sí dependía, y era un bug: la pose viva trae la torsión que
	# eligió la IK ese frame, y cada respawn congelaba un roll distinto en las manos.
	skinned_body = SkinnedBodyUtil.create(custom_bones_util, char_rigidbody)

	procedural_animator = ProceduralBoneAnimator.create(locomotion_signals)

	bone_animations = BoneAnimations.new()
	add_child(bone_animations)
	bone_animations.bi = self
	bone_animations.register_all()

	ragdoll_util = RagdollUtil.create(custom_bones_util, skel_rigidbodies, joints)
	ragdoll_util.ik_util = ik_util  # para que el IK de recuperación use el mismo pole que la locomoción
	# Con el modelo skinneado, los cuerpos del ragdoll dejan de ser lo visible: quedan invisibles y la
	# malla los sigue vía _sync_skinned_body.
	ragdoll_util.show_bodies = not is_instance_valid(skinned_body)

	# Los visualizadores de debug son estado GLOBAL: un personaje que spawnea o respawnea nace con lo
	# que esté prendido, sin que nadie tenga que volver a tocar el panel.
	CharacterDebugView.apply_to(self)

	# Primera persona: se aplica ACÁ, al final. PlayerController.rebind (que corre en
	# on_skeleton_built, bastante más arriba) es quien venía seteando esto, pero el espejo se crea
	# DESPUÉS de esa llamada — así que en el build y en cada respawn el estado nunca llegaba a las
	# mallas skinneadas y la cara se veía hasta que cambiabas de cámara y volvías con numpad 5.
	if is_active and is_instance_valid(player_controller):
		set_first_person_visibility(player_controller.is_first_person_view())

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
		char_rigidbody.queue_free()  # se lleva puesto el skinned_body, que cuelga de él
	skinned_body = null
	if is_instance_valid(skeleton_debug):
		# Sus gizmos cuelgan de los CustomBone, que se van con la generación anterior.
		skeleton_debug.queue_free()
	skeleton_debug = null

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
			# El solve entero se saltea acá, así que la malla skinneada se sincroniza a mano: si no,
			# se congela en el pose del último frame parado mientras el cuerpo cae.
			_sync_skinned_body()
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

	_solve_frame(solve_delta)

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


# ── Solve del pose: UN solo camino ────────────────────────────────────────────
# Sentado y parado NO son dos pipelines. Es el mismo frame, y lo único que cambia es:
#   1. la RAÍZ    — parado la manda la cápsula; sentado se ancla al asiento.
#   2. las PIERNAS — parado, la marcha con IK contra el piso; sentado, plegadas fijas.
# Todo lo demás (procedural + anim_mod, brazos, sync de los cuerpos del ragdoll) es COMPARTIDO y
# existe una sola vez. Antes eran dos funciones copiadas y derivaron: al sentado le faltaba
# `drive_grab` — los brazos de un proxy sentado nunca llegaban al controllable que manejaba — y
# `sync_to_bones`. Regla: un paso nuevo va al bloque compartido; si ramificás, tiene que ser raíz o
# piernas. Ver technical/character-animation.md.
#
# El ORDEN de las piernas es lo único que difiere entre modos, y no es negociable:
#   - Parado van ANTES del procedural: los raycasts de pie salen de las caderas, y el procedural
#     anima las caderas con señales de pie (FOOT_SPREAD_*) → resolverlas después realimenta la marcha.
#   - Sentado van DESPUÉS, porque cuelgan de la raíz ya anclada al asiento.
func _solve_frame(delta: float) -> void:
	var seated := is_seated and is_instance_valid(current_seat)

	if not seated:
		_pose_legs_standing()
		# Con los pies ya colocados se puede medir si las piernas llegan. Va acá, entre colocarlos y la
		# capa procedural: el resultado lo aplica _apply_root_offsets, que corre dentro de _pose_procedural.
		_update_pelvis_drop(delta)

	_pose_root(seated)
	_pose_procedural(delta)
	_pose_root(seated)         # el procedural mueve el spine: re-anclarlo al asiento

	if seated:
		_pose_legs_seated()

	_pose_arms(delta)

	# ── LAS PIERNAS SE CLAVAN AL FINAL, DESPUÉS DE TODO LO QUE MUEVA LA RAÍZ ──────────────────────
	# INVARIANTE: el tren inferior NO lo maneja el tren superior. Los pies siguen la IK a un punto
	# FIJO DEL MUNDO, y todo lo que mueva la raíz —bajada de pelvis, agacharse, squat, y sobre todo la
	# inclinación de torso del agarre— tiene que resolverse volviendo a clavar las piernas a esos
	# MISMOS puntos, nunca dejando que la pierna acompañe a la cadera.
	#
	# Este repin ya existía, pero corría ANTES de _pose_arms — o sea antes de la única cosa que todavía
	# movía la raíz. La pierna se quedaba con la solución vieja y giraba con la cadera, como si el pie
	# no estuviera apoyado. Sentado el bug no aparecía porque el caso sentado sí re-clava después de los
	# brazos (era este mismo comentario, dos líneas más abajo).
	if seated:
		_repin_legs_seated()
	else:
		_repin_legs_standing()

	_sync_ragdoll_bodies()
	_sync_skinned_body()

## Raíz. Sentado: clava el spine en el asiento, fija la cápsula en XZ y gira la malla del asiento con
## el ocupante. Parado: nada, la raíz la manda la cápsula. Es idempotente a propósito (se llama antes
## y después del procedural, y sus entradas —asiento + yaw de la cápsula— no cambian entre medio).
func _pose_root(seated: bool) -> void:
	if not seated:
		return
	current_seat.update_seated_visual(self, char_rigidbody.global_rotation.y)
	var seat_pos : Vector3 = current_seat.global_position
	var backward := char_rigidbody.global_transform.basis.z
	var z_offset : float = skel_sizes_util.higher_leg_size.y - current_seat.seat_area.z * 0.5
	custom_bones_util.lower_spine.global_position = \
		Vector3(seat_pos.x, seat_pos.y + current_seat.height, seat_pos.z) + backward * z_offset
	char_rigidbody.global_position.x = seat_pos.x
	char_rigidbody.global_position.z = seat_pos.z

## Piernas paradas: la marcha (target aéreo + raycast al piso + IK). Ver el modelo de gait en
## technical/character-animation.md.
func _pose_legs_standing() -> void:
	ik_util.update_airborne_target(animation_inputs, true,  skel_sizes_util)
	ik_util.update_airborne_target(animation_inputs, false, skel_sizes_util)

	ik_util.update_ik_raycast(true,  custom_bones_util, skel_sizes_util, animation_inputs)
	ik_util.update_ik_raycast(false, custom_bones_util, skel_sizes_util, animation_inputs)

	if _reset_feet_after_recovery:
		# Ya corrió el raycast (next_target fresco bajo el cuerpo): plantamos ahí el pie, sin catch-up.
		ik_util.reset_step_targets_to_ground()
		_reset_feet_after_recovery = false

## Piernas sentadas: plegadas hacia adelante, sin piso ni marcha. Cachea los targets porque
## _repin_legs_seated re-resuelve contra los mismos — recalcularlos después de que los overrides de
## brazos inclinaron el spine arrastraría los pies con el torso.
func _pose_legs_seated() -> void:
	var forward := -char_rigidbody.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var left_hip_tip  := custom_bones_util.left_hip.global_position  + custom_bones_util.left_hip.global_transform.basis.y  * custom_bones_util.left_hip.capsule_dimensions.y
	var right_hip_tip := custom_bones_util.right_hip.global_position + custom_bones_util.right_hip.global_transform.basis.y * custom_bones_util.right_hip.capsule_dimensions.y

	var left_knee  := left_hip_tip  + forward * skel_sizes_util.higher_leg_size.y
	var right_knee := right_hip_tip + forward * skel_sizes_util.higher_leg_size.y

	var tuck := forward * -skel_sizes_util.lower_leg_size.y * 0.2
	_seated_left_foot  = left_knee  + Vector3.DOWN * skel_sizes_util.lower_leg_size.y * 0.85 + tuck
	_seated_right_foot = right_knee + Vector3.DOWN * skel_sizes_util.lower_leg_size.y * 0.85 + tuck
	_seated_left_pole  = left_knee  + forward
	_seated_right_pole = right_knee + forward

	_repin_legs_seated()
	ik_util.left_leg_current_target.global_position  = _seated_left_foot
	ik_util.right_leg_current_target.global_position = _seated_right_foot

## Re-resuelve el IK de las piernas sentadas contra los targets ya cacheados (los huesos se movieron
## porque algo tocó el spine después de plantarlas).
func _repin_legs_seated() -> void:
	ik_util.solve_two_bone_ik(custom_bones_util.left_higher_leg,  custom_bones_util.left_lower_leg,  _seated_left_foot,  _seated_left_pole)
	ik_util.solve_two_bone_ik(custom_bones_util.right_higher_leg, custom_bones_util.right_lower_leg, _seated_right_foot, _seated_right_pole)

## Capa procedural + modificadores de raíz. Igual en los dos modos: sentado, `anim_mod.is_seated`
## hace que _apply_root_offsets no toque el spine y el procedural saltea POS_Y/POS_Z de la raíz, así
## que acá no hay nada que ramificar.
func _pose_procedural(delta: float) -> void:
	procedural_animator.update()
	if is_instance_valid(anim_mod):
		anim_mod.jump_squat_t = jump_squat_t
		anim_mod.crouch_t     = crouch_t
		anim_mod.apply(delta)

## Brazos, COMPARTIDO: recalcula targets/poles desde el spine ya posado, maneja el agarre de un proxy
## desde el estado sincronizado, aplica los overrides (throw/grab) y resuelve el IK.
## Brazos, COMPARTIDO: recoloca targets y poles desde el spine ya posado, maneja el agarre de un
## proxy desde el estado sincronizado, aplica los overrides y resuelve la IK.
func _pose_arms(delta: float) -> void:
	var rb_basis := custom_bones_util.lower_spine.global_transform.basis

	var left_anim_offset:  Vector3 = ik_util.left_arm_ik_target.position  - skel_sizes_util.left_arm_tip_rest_local
	var right_anim_offset: Vector3 = ik_util.right_arm_ik_target.position - skel_sizes_util.right_arm_tip_rest_local
	var left_pole_offset:  Vector3 = ik_util.left_arm_pole.position  - skel_sizes_util.left_arm_pole_rest_local
	var right_pole_offset: Vector3 = ik_util.right_arm_pole.position - skel_sizes_util.right_arm_pole_rest_local

	ik_util.left_arm_ik_target.global_position  = custom_bones_util.left_upper_arm.global_position  + rb_basis * (skel_sizes_util.left_arm_tip_rest_local  - skel_sizes_util.left_arm_shoulder_rest_local + left_anim_offset)
	ik_util.right_arm_ik_target.global_position = custom_bones_util.right_upper_arm.global_position + rb_basis * (skel_sizes_util.right_arm_tip_rest_local - skel_sizes_util.right_arm_shoulder_rest_local + right_anim_offset)
	ik_util.left_arm_pole.global_position  = custom_bones_util.left_upper_arm.global_position  + rb_basis * (skel_sizes_util.left_arm_pole_rest_local  - skel_sizes_util.left_arm_shoulder_rest_local + left_pole_offset)
	ik_util.right_arm_pole.global_position = custom_bones_util.right_upper_arm.global_position + rb_basis * (skel_sizes_util.right_arm_pole_rest_local - skel_sizes_util.right_arm_shoulder_rest_local + right_pole_offset)

	# Proxy: manejar el agarre desde el estado sincronizado (el jugador local lo maneja su IC). Vale
	# igual sentado que parado — un proxy sentado en un dashboard también tiene que llegar al handle.
	if not is_active and is_instance_valid(arms_controller):
		arms_controller.drive_grab(delta, animation_inputs.grab_target)

	if is_instance_valid(arms_controller):
		arms_controller.apply_world_overrides(delta)

	ik_util.solve_two_bone_ik(custom_bones_util.left_upper_arm, custom_bones_util.left_lower_arm,
		ik_util.left_arm_ik_target.global_position, ik_util.left_arm_pole.global_position)
	ik_util.solve_two_bone_ik(custom_bones_util.right_upper_arm, custom_bones_util.right_lower_arm,
		ik_util.right_arm_ik_target.global_position, ik_util.right_arm_pole.global_position)

## Copia el pose de los huesos a los cuerpos del ragdoll mientras NO se está ragdolleando (regla
## sync-before-snapshot). También sentado: antes solo corría parado y los cuerpos quedaban viejos
## todo el rato que estabas en el asiento.
func _sync_ragdoll_bodies() -> void:
	if is_instance_valid(ragdoll_util) and not ragdoll_util.is_recovering:
		ragdoll_util.sync_to_bones()

## Copia el pose del rig lógico a la malla skinneada. Va al FINAL del solve, después de que todo lo
## demás terminó de mover los CustomBone — el espejo no anima nada, solo refleja el resultado.
##
## La FUENTE cambia según el estado: parado son los CustomBone; ragdolleando o levantándose son los
## cuerpos rígidos, porque ahí los huesos quedan congelados y lo que se mueve son ellos (antes eran
## además lo visible; ahora van invisibles y la malla skinneada los sigue). Ver "What breaks" en
## technical/skinned-character-migration.md.
func _sync_skinned_body() -> void:
	if not is_instance_valid(skinned_body):
		return
	if is_instance_valid(ragdoll_util) and (ragdoll_util.is_active or ragdoll_util.is_recovering):
		skinned_body.sync_from_ragdoll(ragdoll_util.get_bodies())
	else:
		skinned_body.sync_from_bones()

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

## Primera persona: la maneja enteramente la malla skinneada — los CustomBone no dibujan nada.
## Perdimos la granularidad por hueso de antes (mostrar solo antebrazos y pies); recuperarla
## necesitaría máscara por índice de hueso en el shader. Ver "What breaks" en el doc de migración.
func set_first_person_visibility(first_person: bool) -> void:
	if character_hidden:
		return  # el toggle de debug manda: no lo pisa un cambio de cámara
	if is_instance_valid(skinned_body):
		skinned_body.set_first_person(first_person)

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
		var z_offset    : float = sizes.higher_leg_size.y - current_seat.seat_area.z * 0.5
		var spine_world := Vector3(seat_pos.x, seat_pos.y + current_seat.height, seat_pos.z) + backward * z_offset
		return spine_world + Vector3(0.0,
			sizes.lower_spine_size.y + sizes.middle_spine_size.y + sizes.higher_spine_size.y + sizes.chest_size.y,
			0.0)

	var chest_tip_y := ground_y + sizes.leg_height \
		+ sizes.lower_spine_size.y + sizes.middle_spine_size.y \
		+ sizes.higher_spine_size.y + sizes.chest_size.y

	chest_tip_y -= sizes.leg_height * 0.35 * crouch_t

	return Vector3(char_rigidbody.global_position.x, chest_tip_y, char_rigidbody.global_position.z)

## Gizmos de debug, creados recién al primer uso: un personaje normal no paga nada por esto.
func get_skeleton_debug() -> SkeletonDebugDraw:
	if not is_instance_valid(skeleton_debug):
		skeleton_debug = SkeletonDebugDraw.new()
		skeleton_debug.bi = self
		add_child(skeleton_debug)
	return skeleton_debug

## Debug: muestra u oculta el personaje COMPLETO. A diferencia de la primera persona, que deja manos
## y uñas a la vista, esto no deja nada — es para mirar la cápsula, el esqueleto o los colisionadores
## sin el cuerpo encima.
func set_character_visible(value: bool) -> void:
	character_hidden = not value
	if not is_instance_valid(skinned_body):
		return
	if character_hidden:
		skinned_body.set_meshes_visible(false)
		return
	# Al volver a mostrar NO se prende todo a lo bruto: se restaura el estado de primera persona. Si no,
	# cualquier toggle del panel (que pasa por acá con value = true) le devolvía el cuerpo entero al
	# jugador que estaba en primera persona.
	var first_person := is_active and is_instance_valid(player_controller) and player_controller.is_first_person_view()
	skinned_body.set_first_person(first_person)

# ── AJUSTE DE PELVIS ──────────────────────────────────────────────────────────────────────────────
# La pelvis baja SOLO lo que haga falta para que las piernas lleguen a sus pies. Es el patrón estándar
# de foot IK (pelvis adjustment): se mide la distancia cadera↔pie de cada pierna y, si supera lo que
# la pierna estira, se baja la raíz por el peor déficit de las dos.
#
# Es geométrico, no predictivo: no adivina por velocidad, mide. Por eso funciona igual en escaleras,
# pendientes, agachado o cuando te empujan — casos donde una fórmula por velocidad se equivoca.
#
# Y reemplaza a la derivación vieja `stride → altura de pelvis → alcance del pie`, que iba al revés:
# ahora `stride` significa literalmente el largo del paso, y la pelvis es una consecuencia.

## Cuánto más de lo estrictamente necesario baja la pelvis, por unidad de `root_bounciness`. Es un
## MULTIPLICADOR sobre la bajada geométrica, nunca un sumando: así el arte puede exagerar el andar
## pero no puede romperlo — con factor ≥ 1 es imposible que la pierna no llegue. Ver el doc.
const PELVIS_DROP_EXAGGERATION := 0.6
## Suavizado de la bajada (1/s). Sin esto la pelvis salta en cuanto un pie pisa un desnivel.
const PELVIS_DROP_SMOOTH := 12.0

var _pelvis_drop_smooth: float = 0.0

## Mide el déficit de alcance de las dos piernas y deja el resultado suavizado en anim_mod. Corre
## DESPUÉS de colocar los pies (necesita sus targets) y ANTES de la capa procedural (que es la que
## aplica el offset de raíz).
func _update_pelvis_drop(delta: float) -> void:
	if not is_instance_valid(anim_mod):
		return
	if is_seated or (is_instance_valid(ragdoll_util) and (ragdoll_util.is_active or ragdoll_util.is_recovering)):
		_pelvis_drop_smooth = 0.0
		anim_mod.pelvis_drop = 0.0
		return

	var max_len: float = skel_sizes_util.leg_height * SkeletonSizesUtil.MAX_EXTENSION
	var deficit: float = maxf(
		_leg_deficit(custom_bones_util.left_higher_leg,  ik_util.left_leg_current_target,  max_len),
		_leg_deficit(custom_bones_util.right_higher_leg, ik_util.right_leg_current_target, max_len))
	# El arte solo puede EXAGERAR lo que la geometría ya pide (factor ≥ 1). No puede atenuarlo: con los
	# pies en el piso, bajar menos de lo necesario es imposible — el pie se despegaría.
	deficit *= 1.0 + entity_instantiation.root_bounciness * PELVIS_DROP_EXAGGERATION

	_pelvis_drop_smooth = lerpf(_pelvis_drop_smooth, deficit, clampf(delta * PELVIS_DROP_SMOOTH, 0.0, 1.0))
	anim_mod.pelvis_drop = _pelvis_drop_smooth

## Cuánto le falta a esta pierna para llegar a su pie, o 0 si llega.
func _leg_deficit(hip: CustomBone, target: Node3D, max_len: float) -> float:
	if not (is_instance_valid(hip) and is_instance_valid(target)):
		return 0.0
	return maxf(0.0, hip.global_position.distance_to(target.global_position) - max_len)

## Re-resuelve la IK de las piernas contra los MISMOS targets de piso, después de que los offsets de
## raíz movieron la pelvis. Sin esto los pies se despegan del suelo exactamente lo que bajó la
## pelvis. Mismo patrón que _repin_legs_seated. Ver technical/character-animation.md.
func _repin_legs_standing() -> void:
	ik_util.solve_two_bone_ik(custom_bones_util.left_higher_leg, custom_bones_util.left_lower_leg,
		ik_util.left_leg_current_target.global_position, ik_util.left_leg_pole.global_position)
	ik_util.solve_two_bone_ik(custom_bones_util.right_higher_leg, custom_bones_util.right_lower_leg,
		ik_util.right_leg_current_target.global_position, ik_util.right_leg_pole.global_position)
