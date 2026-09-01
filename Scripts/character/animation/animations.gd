class_name BoneAnimations
extends Node

var bi: BoneInstantiator

func _ready() -> void:
	bi = get_parent() as BoneInstantiator

func register_all() -> void:
	var PA := ProceduralBoneAnimator
	var ls := bi.locomotion_signals

	var shoulder_swing   := bi.entity_instantiation.shoulder_swing
	var hip_swing        := bi.entity_instantiation.hip_swing

	var _top_spine_rotation    := 0.1
	var _bottom_spine_rotation := -0.5 * hip_swing

	var right_hip      := bi.custom_bones_util.right_hip
	var left_hip       := bi.custom_bones_util.left_hip
	var lower_spine    := bi.custom_bones_util.lower_spine
	var higher_spine    := bi.custom_bones_util.higher_spine
	var chest          := bi.custom_bones_util.chest
	var right_shoulder := bi.custom_bones_util.right_shoulder
	var left_shoulder  := bi.custom_bones_util.left_shoulder
	var pa             := bi.procedural_animator

	# ─── HIPS ───────────────────────────────────────────────────────────────────

	pa.register(right_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  0.6 * hip_swing)
	pa.register(left_hip,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  0.6 * hip_swing)
	pa.register(right_hip, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X, -0.1 * hip_swing)
	pa.register(left_hip,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X, -0.1 * hip_swing)

	var hips_rotation := _spine_local_weight(0, 4, _bottom_spine_rotation, _top_spine_rotation)
	pa.register(right_hip, PA.Axis.ROT_X, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -hips_rotation)
	pa.register(left_hip,  PA.Axis.ROT_X, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  hips_rotation)

	# ─── SPINE ──────────────────────────────────────────────────────────────────

	# El rebote vertical de cadera YA NO se registra acá. Era un peso artístico contra la separación de
	# pies — la idea correcta, pero desacoplada de la geometría: podía pelearse con lo que la pierna
	# necesitaba y despegar el pie del piso. Ahora la pelvis baja lo que la pierna pide
	# (BoneInstantiator._update_pelvis_drop) y `root_bounciness` es el MULTIPLICADOR que exagera esa
	# bajada. Misma variable, mismo look, pero imposible de romper. Ver technical/character-animation.md.

	pa.register_formula(lower_spine, PA.Axis.ROT_Z,
		func(): return ls.foot_spread_unified.x * (0.01 + 0.04 * ls.speed_norm),
		1.0)

	var lower_spine_rotation  := _spine_local_weight(1, 4, _bottom_spine_rotation, _top_spine_rotation)
	var higher_spine_rotation := _spine_local_weight(2, 4, _bottom_spine_rotation, _top_spine_rotation)
	var chest_rotation        := _spine_local_weight(3, 4, _bottom_spine_rotation, _top_spine_rotation)

	pa.register(lower_spine,  PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, lower_spine_rotation)
	pa.register(higher_spine, PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, higher_spine_rotation)
	pa.register(chest,        PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, chest_rotation)

	# ─── SPINE BOW ───────────────────────────────────────────────────────────────

	var bow_w := 0.15
	# La curva del bow repartida en tres en vez de cuatro: `middle` aportaba +1.0 y su mitad se fue a
	# cada vecino, así que la suma sigue dando cero y el torso no queda torcido en neto.
	pa.register(lower_spine,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  bow_w * 1.0)
	pa.register(higher_spine, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -bow_w * 0.5)
	pa.register(chest,        PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, -bow_w * 0.5)
	pa.register(lower_spine,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z,  0.03)

	# ─── SPINE TILT ──────────────────────────────────────────────────────────────

	# SIGNO INVERTIDO respecto de la versión original: el torso se inclinaba HACIA EL LADO CONTRARIO al
	# que corre. Provisorio — cuando lo detallemos, esto probablemente quiera depender de la aceleración
	# y no de la velocidad (inclinarse al arrancar y al frenar, no mientras se corre a velocidad pareja).
	var tilt_weight := 0.05
	pa.register(lower_spine, PA.Axis.ROT_X, PA.SignalType.H_VEL_Z, tilt_weight)
	pa.register(lower_spine, PA.Axis.ROT_Z, PA.SignalType.H_VEL_X, tilt_weight)

	# ─── SHOULDERS ───────────────────────────────────────────────────────────────

	# `shoulder_swing` ESCALA LAS SEIS REGISTRACIONES, no una. Antes solo multiplicaba la primera —la más
	# chica de todas— así que el arquetipo creía tener control del hombro y en la práctica no movía nada:
	# el balanceo real venía del -0.95 hardcodeado de más abajo.
	#
	# 1.0 = el andar de referencia. No es un rango 0..1: por debajo de 1 el hombro se apaga (el viejo),
	# por encima se exagera (el giga). Cuando haga falta separar vertical de horizontal, esto se parte en
	# dos variables y cada grupo de abajo toma la suya.
	pa.register(right_shoulder, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X,  shoulder_swing * 0.05)
	pa.register(left_shoulder,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_X,  shoulder_swing * 0.05)
	# Subida y bajada de hombros al caminar. Los dos con el mismo signo, o sea que suben y bajan JUNTOS
	# con la zancada — no es el balanceo alternado, que es el ROT_Y de abajo. Estaba en -0.3 y se leía
	# como un rebote antinatural.
	pa.register(right_shoulder, PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, shoulder_swing * -0.12)
	pa.register(left_shoulder,  PA.Axis.ROT_Z, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, shoulder_swing * -0.12)
	pa.register(right_shoulder, PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, shoulder_swing * -0.95)
	pa.register(left_shoulder,  PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_Z, shoulder_swing * -0.95)
	pa.register(right_shoulder, PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_X, shoulder_swing * -0.5)
	pa.register(left_shoulder,  PA.Axis.ROT_Y, PA.SignalType.FOOT_SPREAD_UNIFIED_X, shoulder_swing * -0.5)

	# ─── HEAD / NECK PITCH ───────────────────────────────────────────────────────

	_register_camera_pitch_animations()

	# ─── ARM SWING ───────────────────────────────────────────────────────────────

	var arm_swing  := bi.entity_instantiation.arch_final.arm_swing
	var arm_total  := bi.skel_sizes_util.upper_arm_size.y + bi.skel_sizes_util.lower_arm_size.y
	var z_weight   := arm_swing * arm_total
	var arc_extra  := 0.4
	var ik         := bi.ik_util

	pa.register_node_formula(ik.left_arm_ik_target, Vector3.FORWARD,
		func(): return ls.foot_spread_unified.y * z_weight * ls.speed_norm, 1.0)
	pa.register_node_formula(ik.right_arm_ik_target, Vector3.FORWARD,
		func(): return -ls.foot_spread_unified.y * z_weight * ls.speed_norm, 1.0)

	pa.register_node_formula(ik.left_arm_ik_target, Vector3.UP,
		func():
			var d := ls.foot_spread_unified.y * z_weight * ls.speed_norm
			return arm_total - sqrt(max(0.0, arm_total * arm_total - d * d)) + abs(d) * arc_extra,
		1.0)
	pa.register_node_formula(ik.right_arm_ik_target, Vector3.UP,
		func():
			var d := ls.foot_spread_unified.y * z_weight * ls.speed_norm
			return arm_total - sqrt(max(0.0, arm_total * arm_total - d * d)) + abs(d) * arc_extra,
		1.0)

	pa.register_node_formula(ik.left_arm_ik_target, Vector3.LEFT,
		func():
			var d := ls.foot_spread_unified.y * z_weight * ls.speed_norm
			return arm_total - sqrt(max(0.0, arm_total * arm_total - d * d)),
		1.0)
	pa.register_node_formula(ik.right_arm_ik_target, Vector3.LEFT,
		func():
			var d := ls.foot_spread_unified.y * z_weight * ls.speed_norm
			return -(arm_total - sqrt(max(0.0, arm_total * arm_total - d * d))),
		1.0)

	# ─── VERTICAL VELOCITY ───────────────────────────────────────────────────────

	var v_vel_arm_weight := 0.44
	var arm_bentness     := bi.entity_instantiation.arch_final.arm_bentness
	var max_extension    := arm_bentness * bi.arms_controller.ARM_JUMP_EXTENSION_FACTOR * arm_total

	pa.register_node_formula(ik.left_arm_ik_target, Vector3.UP,
		func(): return max(ls.vertical_velocity_smooth / -10.0, -max_extension), v_vel_arm_weight)
	pa.register_node_formula(ik.right_arm_ik_target, Vector3.UP,
		func(): return max(ls.vertical_velocity_smooth / -10.0, -max_extension), v_vel_arm_weight)

	pa.register_node_formula(ik.left_arm_ik_target, Vector3.LEFT,
		func():
			var d : float = max(0.0, ls.vertical_velocity_smooth / -10.0) * v_vel_arm_weight
			return arm_total - sqrt(max(0.0, arm_total * arm_total - d * d)),
		1.0)
	pa.register_node_formula(ik.right_arm_ik_target, Vector3.LEFT,
		func():
			var d : float = max(0.0, ls.vertical_velocity_smooth / -10.0) * v_vel_arm_weight
			return -(arm_total - sqrt(max(0.0, arm_total * arm_total - d * d))),
		1.0)

	pa.register_formula(right_shoulder, PA.Axis.ROT_Z,
		func(): return ls.vertical_velocity_smooth / 10.0, 0.3)
	pa.register_formula(left_shoulder, PA.Axis.ROT_Z,
		func(): return ls.vertical_velocity_smooth / 10.0, -0.3)

	pa.register_node_formula(ik.left_arm_pole, Vector3.LEFT,
		func():
			var d : float = max(0.0, ls.vertical_velocity_smooth / -10.0) * v_vel_arm_weight
			return arm_total - sqrt(max(0.0, arm_total * arm_total - d * d)),
		1.0)
	pa.register_node_formula(ik.right_arm_pole, Vector3.LEFT,
		func():
			var d : float = max(0.0, ls.vertical_velocity_smooth / -10.0) * v_vel_arm_weight
			return -(arm_total - sqrt(max(0.0, arm_total * arm_total - d * d))),
		1.0)

	pa.register_node_formula(ik.left_arm_pole, Vector3.UP,
		func(): return max(0.0, ls.vertical_velocity_smooth / -10.0), v_vel_arm_weight)
	pa.register_node_formula(ik.right_arm_pole, Vector3.UP,
		func(): return max(0.0, ls.vertical_velocity_smooth / -10.0), v_vel_arm_weight)

	# ─── ARM COMPRESS ────────────────────────────────────────────────────────────

	var arm_forward_scale := bi.arms_controller.ARM_FORWARD_SCALE
	var arm_bend_scale    := bi.arms_controller.ARM_BEND_SCALE

	pa.register_node_formula(ik.left_arm_ik_target, Vector3.FORWARD,
		func(): return bi.locomotion_signals.arm_compress, arm_forward_scale)
	pa.register_node_formula(ik.right_arm_ik_target, Vector3.FORWARD,
		func(): return bi.locomotion_signals.arm_compress, arm_forward_scale)
	pa.register_node_formula(ik.left_arm_ik_target, Vector3.UP,
		func(): return bi.locomotion_signals.arm_compress, arm_bend_scale)
	pa.register_node_formula(ik.right_arm_ik_target, Vector3.UP,
		func(): return bi.locomotion_signals.arm_compress, arm_bend_scale)

	# ─── LANDING ─────────────────────────────────────────────────────────────────

	var impact_y_weight := 0.9

	pa.register_formula(lower_spine, PA.Axis.POS_Y,
		func(): return max(0.0, ls.impact_y_signed_smooth / 10.0), -impact_y_weight * 2)
	pa.register_formula(lower_spine, PA.Axis.POS_Z,
		func(): return max(0.0, ls.impact_y_signed_smooth / 10.0), impact_y_weight)
	pa.register_formula(lower_spine, PA.Axis.ROT_X,
		func(): return max(0.0, ls.impact_y_signed_smooth / 10.0), -impact_y_weight * 3)

	pa.register_formula(right_shoulder, PA.Axis.ROT_Z,
		func(): return max(0.0, ls.impact_y_signed_smooth / 10.0), -impact_y_weight * 0.5)
	pa.register_formula(left_shoulder, PA.Axis.ROT_Z,
		func(): return max(0.0, ls.impact_y_signed_smooth / 10.0), impact_y_weight * 0.5)

	# ─── XZ IMPACT ───────────────────────────────────────────────────────────────

	pa.register_formula(lower_spine, PA.Axis.ROT_X,
		func(): return ls.impact_xz_smooth.y, impact_y_weight * 1.5)
	pa.register_formula(lower_spine, PA.Axis.ROT_Z,
		func(): return ls.impact_xz_smooth.x, impact_y_weight * 1.5)


func _register_camera_pitch_animations() -> void:
	if not (bi.is_active or bi.is_puppet):
		return  # jugador local o proxy remoto; los NPCs puros no miran con la cámara
	var pa             := bi.procedural_animator
	var PA             := ProceduralBoneAnimator
	var pitch_callable := _make_pitch_callable()

	# ─── HEAD / NECK / SPINE PITCH (ambas direcciones) ───────────────────────
	pa.register_formula(bi.custom_bones_util.head,         PA.Axis.ROT_X, pitch_callable, 0.50)
	if is_instance_valid(bi.custom_bones_util.neck):
		pa.register_formula(bi.custom_bones_util.neck,     PA.Axis.ROT_X, pitch_callable, 0.25)
	pa.register_formula(bi.custom_bones_util.chest,        PA.Axis.ROT_X, pitch_callable, 0.12)
	pa.register_formula(bi.custom_bones_util.higher_spine,  PA.Axis.ROT_X, pitch_callable, 0.08)

	# ─── EXTRA SPINE BEND SOLO AL MIRAR ABAJO ────────────────────────────────
	var look_down_extra := 0.12
	var lower_spine     := bi.custom_bones_util.lower_spine
	var higher_spine     := bi.custom_bones_util.higher_spine
	var chest           := bi.custom_bones_util.chest
	var down_callable   := func() -> float: return -min(0.0, pitch_callable.call())
	pa.register_formula(lower_spine,  PA.Axis.ROT_X, down_callable, -look_down_extra * 0.4)
	pa.register_formula(higher_spine,  PA.Axis.ROT_X, down_callable, -look_down_extra * 1.0)
	pa.register_formula(chest,        PA.Axis.ROT_X, down_callable, -look_down_extra * 0.5)
	pa.register_formula(lower_spine,  PA.Axis.POS_Y, down_callable, -look_down_extra * 0.6)
	pa.register_formula(lower_spine,  PA.Axis.POS_Z, down_callable,  look_down_extra * 0.4)


func refresh_camera_animations() -> void:
	if not (bi.is_active or bi.is_puppet):
		return
	var PA := ProceduralBoneAnimator
	var bones := [
		bi.custom_bones_util.head,
		bi.custom_bones_util.neck,
		bi.custom_bones_util.chest,
		bi.custom_bones_util.higher_spine,
	]
	for bone in bones:
		if is_instance_valid(bone):
			bi.procedural_animator.unregister_bone(bone)
	_register_camera_pitch_animations()


func _make_pitch_callable() -> Callable:
	# El pitch ya viene clampeado en AnimationInputs (productor local / owner antes de enviar).
	var bi_ref := bi
	return func() -> float:
		return bi_ref.animation_inputs.head_pitch if bi_ref.animation_inputs != null else 0.0


func _spine_local_weight(index: int, count: int, min_rot: float, max_rot: float) -> float:
	var global_weight := func(i: int) -> float:
		if i < 0:
			return 0.0
		var t := float(i) / float(count - 1)
		return lerp(max_rot, min_rot, t)
	return global_weight.call(index) - global_weight.call(index - 1)
