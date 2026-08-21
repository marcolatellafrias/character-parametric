class_name RagdollUtil
extends RefCounted

const RAGDOLL_LAYER := 2
const RAGDOLL_MASK  := 1

var is_active: bool = false
var is_recovering: bool = false
var recovery_duration: float = 0.8
var debug_ragdoll_color: bool = false

var trip_force_multiplier: float = 1.0
var trip_twist_multiplier: float = 0.5

var impact_fall_linear: float = 1.5

# ── Recuperación (levantarse): ilusión de empujar el cuerpo hacia arriba con las piernas ──────────
## Si true, durante la recuperación las piernas se resuelven por IK (pies plantados en el piso) y la
## pelvis sube de a poco: los pies quedan fijos mientras la cadera sube → las piernas se estiran de
## cuclillas a parado, como si empujaran. El torso para arriba mantiene el blend normal.
var recovery_leg_ik: bool = true
## Altura de la pelvis sobre el piso al ARRANCAR la recuperación (t=0). Bien bajo = arranca agachado.
var recovery_rise_start_height: float = 0.15
## Fracción de la recuperación en la que los pies terminan de plantarse bajo la cadera (0..1).
var recovery_plant_fraction: float = 0.45

var _recovery_timer: float = 0.0
var _skeleton_root: CustomBone = null
var _recovery_start_transforms: Dictionary = {}

var head_body: RigidBody3D = null

var _skel_rb_node: Node3D
var _joints_node: Node3D
var _bones_util: CustomBonesUtil
## Referencia al IkUtil del mismo personaje: la usa el IK de recuperación para tomar el MISMO pole de
## rodilla que la locomoción, y que la pierna no pegue un salto de flexión al terminar de levantarse.
var ik_util: IkUtil = null
var _bodies: Dictionary = {}
var _ragdoll_rids: Array[RID] = []
var _joints: Array[Generic6DOFJoint3D] = []
var _pending_bodies: Array[RigidBody3D] = []
var _char_rid: RID
var _char_rb: CharacterRigidBody3D = null
var _recovering_char_rb: CharacterRigidBody3D = null
var _lower_spine_body: RigidBody3D = null

var _parent_bone: Dictionary = {}
var _ordered_bones: Array[CustomBone] = []

var _momentum_dir: Vector3 = Vector3.ZERO

static func create(bones_util: CustomBonesUtil, skel_rb_node: Node3D, joints_node: Node3D) -> RagdollUtil:
	var ru := RagdollUtil.new()
	ru._skel_rb_node = skel_rb_node
	ru._joints_node  = joints_node
	ru._bones_util   = bones_util
	ru._build_bodies(bones_util)
	return ru

func _build_bodies(bu: CustomBonesUtil) -> void:
	var all_bones: Array = [
		bu.lower_spine, bu.middle_spine, bu.higher_spine, bu.chest,
		bu.left_hip, bu.right_hip,
		bu.left_higher_leg, bu.left_lower_leg,
		bu.right_higher_leg, bu.right_lower_leg,
		bu.right_foot, bu.left_foot,
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

	for child in bone.get_children():
		if child is MeshInstance3D:
			var mesh_copy := child.duplicate() as MeshInstance3D
			mesh_copy.material_override = child.material_override
			mesh_copy.visible = false
			rb.add_child(mesh_copy)
			break

	return rb

func _build_joints() -> void:
	# Primero, SIEMPRE: poner los cuerpos en los huesos. Cada joint captura la posición relativa de su
	# par de huesos en ESTE instante y la fija rígido, así que los cuerpos tienen que reflejar la pose
	# actual del esqueleto antes de armarlas. En un proxy el solve corre a media tasa (los cuerpos van
	# 1-2 frames atrás de los huesos), y sin este sync la junta congelaría el brazo/pie en su lugar viejo
	# → pegado pero corrido del hombro/tobillo. Al ser la primera línea, armar juntas desde una pose vieja
	# es imposible por construcción. Ver technical/character-animation.md (solve a media tasa).
	sync_to_bones()
	_parent_bone.clear()
	var bu := _bones_util

	var pairs: Array = [
		[bu.lower_spine,  bu.middle_spine,    55.0, 6.0, -20.0, 20.0, -30.0, 30.0, -20.0, 20.0],
		[bu.middle_spine, bu.higher_spine,     55.0, 6.0, -20.0, 20.0, -30.0, 30.0, -20.0, 20.0],
		[bu.higher_spine,  bu.chest,           50.0, 6.0, -20.0, 20.0, -25.0, 25.0, -20.0, 20.0],
		[bu.lower_spine,  bu.left_hip,        40.0, 5.0, -30.0, 30.0, -40.0, 40.0, -30.0, 30.0],
		[bu.lower_spine,  bu.right_hip,       40.0, 5.0, -30.0, 30.0, -40.0, 40.0, -30.0, 30.0],
		[bu.left_hip,     bu.left_higher_leg,  35.0, 5.0, -40.0, 40.0, -80.0, 40.0, -30.0, 30.0],
		[bu.right_hip,    bu.right_higher_leg, 35.0, 5.0, -40.0, 40.0, -80.0, 40.0, -30.0, 30.0],
		[bu.left_higher_leg,  bu.left_lower_leg,  25.0, 4.0, -10.0, 10.0,   0.0, 130.0, -10.0, 10.0],
		[bu.right_higher_leg, bu.right_lower_leg, 25.0, 4.0, -10.0, 10.0,   0.0, 130.0, -10.0, 10.0],
		[bu.left_lower_leg,  bu.left_foot,  10.0, 3.0, -20.0, 20.0, -30.0, 30.0, -15.0, 15.0],
		[bu.right_lower_leg, bu.right_foot, 10.0, 3.0, -20.0, 20.0, -30.0, 30.0, -15.0, 15.0],
		[bu.chest, bu.left_shoulder,  35.0, 5.0, -50.0, 50.0, -60.0, 60.0, -40.0, 40.0],
		[bu.chest, bu.right_shoulder, 35.0, 5.0, -50.0, 50.0, -60.0, 60.0, -40.0, 40.0],
		[bu.left_shoulder,  bu.left_upper_arm,  25.0, 4.0, -70.0, 70.0, -70.0, 70.0, -70.0, 70.0],
		[bu.right_shoulder, bu.right_upper_arm, 25.0, 4.0, -70.0, 70.0, -70.0, 70.0, -70.0, 70.0],
		[bu.left_upper_arm,  bu.left_lower_arm,  15.0, 3.0, -10.0, 10.0,   0.0, 140.0, -10.0, 10.0],
		[bu.right_upper_arm, bu.right_lower_arm, 15.0, 3.0, -10.0, 10.0,   0.0, 140.0, -10.0, 10.0],
	]

	if is_instance_valid(bu.neck):
		pairs.append([bu.chest, bu.neck, 50.0, 6.0, -35.0, 35.0, -40.0, 40.0, -30.0, 30.0])
		pairs.append([bu.neck,  bu.head, 45.0, 6.0, -25.0, 25.0, -30.0, 30.0, -20.0, 20.0])
	else:
		pairs.append([bu.chest, bu.head, 45.0, 6.0, -35.0, 35.0, -40.0, 40.0, -30.0, 30.0])

	for pair in pairs:
		var pa: CustomBone = pair[0]
		var ch: CustomBone = pair[1]
		if not is_instance_valid(pa) or not is_instance_valid(ch):
			continue
		if not _bodies.has(pa) or not _bodies.has(ch):
			continue
		_parent_bone[ch] = pa
		_create_joint(
			_bodies[pa], _bodies[ch], ch.global_position, pa, ch,
			pair[2], pair[3],
			deg_to_rad(pair[4]), deg_to_rad(pair[5]),
			deg_to_rad(pair[6]), deg_to_rad(pair[7]),
			deg_to_rad(pair[8]), deg_to_rad(pair[9])
		)

func _create_joint(
		body_a: RigidBody3D, body_b: RigidBody3D, anchor: Vector3,
		bone_a: CustomBone, bone_b: CustomBone,
		stiffness: float, damping: float,
		xl: float, xh: float,
		yl: float, yh: float,
		zl: float, zh: float) -> void:

	var j := Generic6DOFJoint3D.new()
	_joints_node.add_child(j)
	j.global_position = anchor
	j.node_a = j.get_path_to(body_a)
	j.node_b = j.get_path_to(body_b)

	var LL   := Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT
	var LU   := Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT
	var AL   := Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT
	var AU   := Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT
	var LF   := Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT
	var AF   := Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT
	var ASF  := Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING
	var ASST := Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS
	var ASSD := Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING
	var AEQ  := Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_EQUILIBRIUM_POINT

	j.set_flag_x(LF, true); j.set_flag_y(LF, true); j.set_flag_z(LF, true)
	j.set_param_x(LL, 0.0); j.set_param_x(LU, 0.0)
	j.set_param_y(LL, 0.0); j.set_param_y(LU, 0.0)
	j.set_param_z(LL, 0.0); j.set_param_z(LU, 0.0)

	j.set_flag_x(AF, true); j.set_flag_y(AF, true); j.set_flag_z(AF, true)
	j.set_param_x(AL, xl); j.set_param_x(AU, xh)
	j.set_param_y(AL, yl); j.set_param_y(AU, yh)
	j.set_param_z(AL, zl); j.set_param_z(AU, zh)

	var rest_basis_a  := Basis.from_euler(bone_a.rest_rotation)
	var rest_basis_b  := Basis.from_euler(bone_b.rest_rotation)
	var rest_relative := rest_basis_a.inverse() * rest_basis_b
	var anim_relative := body_a.global_basis.inverse() * body_b.global_basis
	var offset_quat   := anim_relative.get_rotation_quaternion().inverse() \
						* rest_relative.get_rotation_quaternion()
	var offset_euler  := offset_quat.get_euler()

	j.set_flag_x(ASF, true); j.set_flag_y(ASF, true); j.set_flag_z(ASF, true)
	j.set_param_x(ASST, stiffness); j.set_param_y(ASST, stiffness); j.set_param_z(ASST, stiffness)
	j.set_param_x(ASSD, damping);   j.set_param_y(ASSD, damping);   j.set_param_z(ASSD, damping)
	j.set_param_x(AEQ, offset_euler.x)
	j.set_param_y(AEQ, offset_euler.y)
	j.set_param_z(AEQ, offset_euler.z)

	_joints.append(j)

func sync_to_bones() -> void:
	for bone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if is_instance_valid(rb) and is_instance_valid(bone):
			rb.global_transform = bone.global_transform

# Camera is no longer managed here — PlayerController owns it entirely.
func activate(char_rb: CharacterRigidBody3D, skeleton_root: CustomBone) -> void:
	if is_recovering:
		is_recovering       = false
		_recovery_timer     = 0.0
		_recovering_char_rb = null
		_recovery_start_transforms.clear()

	is_active      = true
	_char_rid      = char_rb.get_rid()
	_char_rb       = char_rb
	_skeleton_root = skeleton_root

	char_rb.is_active         = false
	char_rb.collider.disabled = true
	char_rb.freeze_mode       = RigidBody3D.FREEZE_MODE_STATIC
	char_rb.freeze            = true

	if is_instance_valid(skeleton_root):
		skeleton_root.visible = false

	_set_meshes_visible(true)
	_build_joints()  # arma las juntas desde la pose actual (sync_to_bones corre adentro, primera línea)

	var space: PhysicsDirectSpaceState3D = _skel_rb_node.get_world_3d().direct_space_state
	var exclude: Array[RID]              = _make_exclude()
	_pending_bodies.clear()

	for bone: CustomBone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if not is_instance_valid(rb):
			continue
		rb.collision_layer  = RAGDOLL_LAYER
		rb.collision_mask   = RAGDOLL_MASK
		rb.linear_velocity  = char_rb.linear_velocity
		rb.angular_velocity = Vector3.ZERO
		rb.freeze           = false

		if _is_overlapping(rb, space, exclude):
			rb.collision_layer = 0
			rb.collision_mask  = 0
			if debug_ragdoll_color:
				_set_body_mesh_color(rb, Color.RED)
			else:
				_clear_body_mesh_color(rb)
			_pending_bodies.append(rb)
		else:
			if debug_ragdoll_color:
				_set_body_mesh_color(rb, Color.GREEN)
			else:
				_clear_body_mesh_color(rb)

	if is_instance_valid(_lower_spine_body):
		var vel: Vector3     = char_rb.linear_velocity
		var speed: float     = max(vel.length(), 3.0)
		# Dirección de la caída. Si venimos de un impacto/empujón, _momentum_dir ya trae la dirección
		# real (la del empujón) — es más confiable que linear_velocity, que a veces todavía no integró
		# el impulso y deja al personaje cayendo hacia su propio frente (o en el lugar). Sin impacto
		# (ragdoll manual con G), _momentum_dir está en cero → usamos velocidad o el frente.
		var forward: Vector3
		if _momentum_dir.length() > 0.01:
			forward = _momentum_dir.normalized()
		elif vel.length() > 0.1:
			forward = vel.normalized()
		else:
			forward = -char_rb.global_basis.z

		var base_y: float = _lower_spine_body.global_position.y
		var top_y: float  = head_body.global_position.y if is_instance_valid(head_body) else base_y + 1.5

		var upper_bones: Array = [
			_bodies.get(_bones_util.lower_spine,    null),
			_bodies.get(_bones_util.middle_spine,   null),
			_bodies.get(_bones_util.higher_spine,    null),
			_bodies.get(_bones_util.chest,          null),
			_bodies.get(_bones_util.left_shoulder,  null),
			_bodies.get(_bones_util.right_shoulder, null),
			_bodies.get(_bones_util.left_upper_arm, null),
			_bodies.get(_bones_util.right_upper_arm,null),
			_bodies.get(_bones_util.neck,           null),
			_bodies.get(_bones_util.head,           null),
		]

		for rb: RigidBody3D in upper_bones:
			if not is_instance_valid(rb):
				continue
			var height_t: float  = clamp((rb.global_position.y - base_y) / max(top_y - base_y, 0.001), 0.0, 1.0)
			var impulse: Vector3 = (forward + Vector3.UP * height_t * 0.5).normalized() * speed * trip_force_multiplier * (0.3 + height_t * 0.7)
			rb.apply_central_impulse(impulse)

		var lower_bones: Array = [
			_bodies.get(_bones_util.left_hip,         null),
			_bodies.get(_bones_util.right_hip,        null),
			_bodies.get(_bones_util.left_higher_leg,   null),
			_bodies.get(_bones_util.right_higher_leg,  null),
			_bodies.get(_bones_util.left_lower_leg,   null),
			_bodies.get(_bones_util.right_lower_leg,  null),
		]

		for rb: RigidBody3D in lower_bones:
			if not is_instance_valid(rb):
				continue
			var height_t: float  = clamp((rb.global_position.y - base_y) / max(top_y - base_y, 0.001), 0.0, 1.0)
			var impulse: Vector3 = (-forward - Vector3.UP * 0.3).normalized() * speed * trip_force_multiplier * (0.3 + (1.0 - height_t) * 0.7)
			rb.apply_central_impulse(impulse)

		var trip_axis: Vector3   = forward.cross(Vector3.UP).normalized()
		var trip_torque: Vector3 = trip_axis * speed * trip_twist_multiplier
		_lower_spine_body.apply_torque_impulse(trip_torque)

func activate_with_impact(
	char_rb: CharacterRigidBody3D,
	skeleton_root: CustomBone,
	world_dir: Vector3
) -> void:
	var vel := char_rb._prev_velocity
	var speed := vel.length()
	var impact_magnitude := char_rb._last_impact_xz_magnitude

	if speed > 0.5:
		_momentum_dir = vel.normalized()
	else:
		_momentum_dir = world_dir
	
	activate(char_rb, skeleton_root)

	var effective_speed : float = max(speed, impact_magnitude * 2.0)
	_apply_impact_fall_impulses(effective_speed)


func _apply_impact_fall_impulses(speed: float) -> void:
	if not is_instance_valid(_lower_spine_body):
		return
	for bone: CustomBone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if not is_instance_valid(rb):
			continue
		rb.apply_central_impulse(_momentum_dir * speed * impact_fall_linear * rb.mass)

func deactivate(char_rb: CharacterRigidBody3D, skeleton_root: CustomBone) -> void:
	is_active            = false
	is_recovering        = true
	_recovery_timer      = recovery_duration
	_skeleton_root       = skeleton_root
	_char_rb             = null
	_recovering_char_rb  = char_rb
	_pending_bodies.clear()
	_clear_joints()

	_recovery_start_transforms.clear()
	for bone: CustomBone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if is_instance_valid(rb):
			_recovery_start_transforms[bone] = rb.global_transform
			rb.freeze          = true
			rb.collision_layer = 0
			rb.collision_mask  = 0

	_ordered_bones.clear()
	var root_bone: CustomBone = _bones_util.lower_spine
	var queue: Array[CustomBone] = [root_bone]
	var visited: Dictionary = {}
	while not queue.is_empty():
		var current: CustomBone = queue.pop_front()
		if visited.has(current):
			continue
		visited[current] = true
		_ordered_bones.append(current)
		for child_bone: CustomBone in _parent_bone:
			if _parent_bone[child_bone] == current and _bodies.has(child_bone):
				queue.append(child_bone)

	# Te parás donde quedó tu cuerpo, apoyando los pies en el piso (ground-snap en el XZ de la pelvis).
	# La cápsula queda CONGELADA (estática, como en el ragdoll) durante toda la recuperación: antes se
	# descongelaba acá y, si el ground-snap fallaba, Jolt la eyectaba por el aire → ese impacto
	# re-disparaba el ragdoll a mitad de recuperación y los huesos quedaban desarmados. Frozen no se
	# puede eyectar; el esqueleto (hijo de la cápsula) queda quieto y el blend converge limpio. La
	# descongela _finish_recovery al terminar. Ver technical/characters.md.
	if is_instance_valid(_lower_spine_body):
		char_rb.snap_feet_to_ground(_lower_spine_body.global_position, _ragdoll_rids)
	char_rb.linear_velocity   = Vector3.ZERO
	char_rb.angular_velocity  = Vector3.ZERO
	char_rb.collider.disabled = false
	char_rb.is_active         = false
	_momentum_dir             = Vector3.ZERO  # el próximo ragdoll (p.ej. manual) arranca sin dirección heredada

	if is_instance_valid(_skeleton_root):
		_skeleton_root.visible = false

## Semilla de velocidad para el ragdoll PROXY: arrancar con el momento del dueño (su velocidad de
## caída), si no el proxy cae de CERO (cápsula puppet congelada) mientras el dueño sale volando →
## el ragdoll queda "offseteado" del lugar donde debería. Los huesos siguen conectados; sólo iguala
## el impulso inicial. Ver technical/characters.md.
func seed_velocity(vel: Vector3) -> void:
	for bone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if is_instance_valid(rb):
			rb.linear_velocity = vel

## Encendido del ragdoll en un PROXY: una sola entrada que lo deja listo para que la red lo maneje.
## Orienta el esqueleto al yaw AUTORITATIVO (el de la pelvis del dueño, `pelvis_world_rot`) ANTES de
## armarlo: el ragdoll se arma desde la pose local (los huesos cuelgan de la cápsula) y en el flanco la
## cápsula del proxy trae yaw≈0 (el dueño manda rb.rotation.y≈0 al ragdollear), así que sin esto se
## armaría mirando al norte y la pelvis kinemática pegaría un giro instantáneo a la dirección real.
## Después siembra el momento del dueño y fija la pelvis kinemática (la maneja la red; el resto simula
## local). El yaw del ragdoll sale SIEMPRE de acá, nunca de la cápsula del proxy. Ver characters.md.
func activate_as_proxy(char_rb: CharacterRigidBody3D, skeleton_root: CustomBone,
		pelvis_world_rot: Quaternion, seed_vel: Vector3) -> void:
	char_rb.rotation.y = Basis(pelvis_world_rot).get_euler().y
	activate(char_rb, skeleton_root)
	seed_velocity(seed_vel)
	set_pelvis_kinematic(true)

## Apagado del ragdoll en un PROXY: arranca la recuperación local y restaura el estado puppet
## (deactivate des-congela la cápsula; el proxy tiene que volver a ser kinemático sin gravedad).
func deactivate_as_proxy(char_rb: CharacterRigidBody3D, skeleton_root: CustomBone) -> void:
	deactivate(char_rb, skeleton_root)
	char_rb.setup_as_puppet()

# ── Replicación proxy: raíz sincronizada, resto local ─────────────────────────
## En el PROXY la pelvis (raíz) es KINEMÁTICA: la maneja la red. Los demás cuerpos quedan dinámicos y
## simulan LOCAL colgados de ella por las joints. La pelvis kinemática es un ancla de masa infinita:
## se mueve donde se le dice y, al moverse suave (interp), arrastra a las caderas por las joints sin
## reventarlas (siempre que las joints se hayan armado bien — ver el sync_to_bones antes de _build_joints).
## La rotación que manejamos es la AUTORITATIVA del dueño (world_rot = s["ragdoll_rot"]), directa y absoluta.
## Para que el arranque sea seamless, el proxy orienta su esqueleto a ese mismo yaw ANTES de activate
## (ver CharacterNetSync._drive_proxy_ragdoll): así la pose con la que se arman las joints ya mira igual
## que el dueño y no hay giro instantáneo. (La cápsula del proxy no es fuente confiable de yaw en el
## flanco del ragdoll — el dueño manda yaw≈0 ahí —, por eso el ragdoll se orienta desde ragdoll_rot.)

func set_pelvis_kinematic(enabled: bool) -> void:
	if not is_instance_valid(_lower_spine_body):
		return
	_lower_spine_body.freeze = enabled  # freeze_mode ya es KINEMATIC (de _make_body); activate lo puso dynamic

## Rotación actual de la pelvis (para que el dueño la sincronice). La POSICIÓN ya viaja como la cápsula
## (que en ragdoll sigue a la pelvis via _update_active).
func pelvis_rotation() -> Quaternion:
	if is_instance_valid(_lower_spine_body):
		return _lower_spine_body.global_transform.basis.get_rotation_quaternion()
	return Quaternion.IDENTITY

## Proxy: pone la pelvis kinemática en la posición y rotación autoritativas del dueño (directo, sin offset).
func drive_pelvis_to(world_pos: Vector3, world_rot: Quaternion) -> void:
	if not is_instance_valid(_lower_spine_body):
		return
	_lower_spine_body.global_transform = Transform3D(Basis(world_rot), world_pos)

func update(delta: float) -> void:
	if is_active:
		_update_active(delta)
	elif is_recovering:
		_update_recovery(delta)


func _update_active(_delta: float) -> void:
	if is_instance_valid(_char_rb) and is_instance_valid(_lower_spine_body):
		_char_rb.global_position = _lower_spine_body.global_position

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
			if debug_ragdoll_color:
				_set_body_mesh_color(rb, Color.GREEN)
			else:
				_clear_body_mesh_color(rb)
	_pending_bodies = still_pending

func _update_recovery(delta: float) -> void:
	_recovery_timer -= delta
	var t: float        = 1.0 - clamp(_recovery_timer / recovery_duration, 0.0, 1.0)
	var t_eased: float  = t * t * (3.0 - 2.0 * t)

	var root_bone: CustomBone  = _bones_util.lower_spine
	var root_body: RigidBody3D = _lower_spine_body

	# ¿Podemos hacer el IK de piernas (pies plantados + cadera que sube)? Necesitamos raíz válida y
	# encontrar el piso bajo la pelvis. Si no, caemos al blend uniforme de siempre.
	var do_leg_ik := recovery_leg_ik and is_instance_valid(root_body) and is_instance_valid(root_bone)
	var floor_y := 0.0
	if do_leg_ik:
		var fy := _recovery_floor_y(root_bone.global_position)
		if is_inf(fy):
			do_leg_ik = false
		else:
			floor_y = fy

	if is_instance_valid(root_body) and is_instance_valid(root_bone):
		var start: Transform3D = _recovery_start_transforms.get(root_bone, root_body.global_transform)
		var pos := start.origin.lerp(root_bone.global_position, t_eased)
		if do_leg_ik:
			# La pelvis NO interpola su Y a la pose parado: arranca apenas sobre el piso y sube a su Y
			# final a lo largo de la recuperación. Con los pies plantados, esto estira las piernas.
			var start_y := floor_y + recovery_rise_start_height
			pos.y = lerpf(start_y, root_bone.global_position.y, t_eased)
		root_body.global_position = pos
		root_body.global_basis    = start.basis.slerp(root_bone.global_transform.basis, t_eased)

	for bone: CustomBone in _ordered_bones:
		if bone == root_bone:
			continue
		if do_leg_ik and _is_recovery_leg_bone(bone):
			continue  # las piernas las maneja el IK abajo, no el blend uniforme
		var rb: RigidBody3D = _bodies.get(bone, null)
		if not is_instance_valid(rb) or not is_instance_valid(bone):
			continue

		var parent_bone: CustomBone  = _parent_bone.get(bone, null)
		var parent_rb: RigidBody3D   = _bodies.get(parent_bone, null) if is_instance_valid(parent_bone) else null

		var start: Transform3D = _recovery_start_transforms.get(bone, rb.global_transform)

		if is_instance_valid(parent_rb) and is_instance_valid(parent_bone):
			var parent_start: Transform3D = _recovery_start_transforms.get(parent_bone, parent_rb.global_transform)
			var local_start_basis: Basis  = parent_start.basis.inverse() * start.basis
			var local_target_basis: Basis = parent_bone.global_transform.basis.inverse() * bone.global_transform.basis
			rb.global_basis = parent_rb.global_basis * local_start_basis.slerp(local_target_basis, t_eased)
			var local_anim_pos: Vector3 = parent_bone.to_local(bone.global_position)
			rb.global_position = parent_rb.to_global(local_anim_pos)
		else:
			rb.global_basis = start.basis.slerp(bone.global_transform.basis, t_eased)
			if is_instance_valid(root_body) and is_instance_valid(root_bone):
				var local_anim_pos: Vector3 = root_bone.to_local(bone.global_position)
				rb.global_position = root_body.to_global(local_anim_pos)

	if do_leg_ik:
		_solve_recovery_leg(true,  root_body, root_bone, floor_y, t)
		_solve_recovery_leg(false, root_body, root_bone, floor_y, t)

	if _recovery_timer <= 0.0:
		_finish_recovery()

## Bones de pierna que resuelve el IK de recuperación (los hips quedan en el blend normal, cerca de
## la pelvis). higher_leg → lower_leg → feet, ambos lados.
func _is_recovery_leg_bone(bone: CustomBone) -> bool:
	return bone == _bones_util.left_higher_leg  or bone == _bones_util.left_lower_leg  or bone == _bones_util.left_foot \
		or bone == _bones_util.right_higher_leg or bone == _bones_util.right_lower_leg or bone == _bones_util.right_foot

## Piso bajo world_pos (raycast hacia abajo, solo mundo). INF si no hay.
func _recovery_floor_y(world_pos: Vector3) -> float:
	if not is_instance_valid(_skel_rb_node):
		return INF
	var from := world_pos + Vector3.UP * 2.0
	var to   := world_pos - Vector3.UP * 3.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # mundo (la capa 2 es el propio ragdoll)
	query.exclude = _make_exclude()
	var hit := _skel_rb_node.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return INF
	return (hit["position"] as Vector3).y

## IK de 2 huesos para una pierna durante la recuperación. Ancla la cadera a la pelvis (que sube) y
## planta el pie en el piso; el pie interpola desde donde quedó tirado hasta bajo la cadera al
## principio de la recuperación (para no dar un salto). Misma matemática que IkUtil.solve_two_bone_ik,
## pero aplicada a los CUERPOS del ragdoll (que es lo visible), con la convención cuerpo≡hueso.
func _solve_recovery_leg(left: bool, root_body: RigidBody3D, root_bone: CustomBone, floor_y: float, t: float) -> void:
	var upper_bone: CustomBone = _bones_util.left_higher_leg  if left else _bones_util.right_higher_leg
	var lower_bone: CustomBone = _bones_util.left_lower_leg  if left else _bones_util.right_lower_leg
	var foot_bone:  CustomBone = _bones_util.left_foot if left else _bones_util.right_foot
	var upper_body: RigidBody3D = _bodies.get(upper_bone, null)
	var lower_body: RigidBody3D = _bodies.get(lower_bone, null)
	var foot_body:  RigidBody3D = _bodies.get(foot_bone,  null)
	if not (is_instance_valid(upper_body) and is_instance_valid(lower_body) \
			and is_instance_valid(upper_bone) and is_instance_valid(lower_bone)):
		return

	# Cadera relativa a la pelvis que sube (offset de la pose parada, aplicado sobre el root_body).
	var hip_world := root_body.to_global(root_bone.to_local(upper_bone.global_position))

	# Objetivo del IK: leg.NEXT_target — el punto de piso vivo bajo el stance neutral, recalculado cada
	# frame incluso en recuperación. NO current_target: durante la recuperación (recovery_targets_locked)
	# el sistema de pasos está apagado y current_target queda CONGELADO donde estaba antes de caer (puede
	# quedar a metros → la pierna se estira derecha). next_target sigue vivo bajo la cápsula ya apoyada,
	# así que es el "dónde va el pie parado" correcto. Ver technical/character-animation.md.
	var plant_t: float = smoothstep(0.0, 1.0, clamp(t / max(recovery_plant_fraction, 0.001), 0.0, 1.0))
	var ankle_target := Vector3(hip_world.x, floor_y, hip_world.z)  # fallback: bajo la cadera, en el piso
	if is_instance_valid(ik_util):
		var nt: Node3D = ik_util.left_leg_next_target if left else ik_util.right_leg_next_target
		if is_instance_valid(nt):
			ankle_target = nt.global_position
	elif is_instance_valid(foot_bone):
		ankle_target = foot_bone.global_position
	var foot_world := ankle_target
	if is_instance_valid(foot_body) and is_instance_valid(foot_bone):
		var foot_start := _recovery_start_transforms.get(foot_bone, foot_body.global_transform) as Transform3D
		foot_world = foot_start.origin.lerp(ankle_target, plant_t)

	# IK de 2 huesos (ley de cosenos). El pole (hacia dónde flexiona la rodilla) es el MISMO nodo que
	# usa la locomoción, así la flexión coincide con la pose parada y no hay salto al terminar. Si no
	# hay ik_util, caemos al frente parado.
	var pole_world := hip_world - root_bone.global_transform.basis.z
	if is_instance_valid(ik_util):
		var pole_node: Node3D = ik_util.left_leg_pole if left else ik_util.right_leg_pole
		if is_instance_valid(pole_node):
			pole_world = pole_node.global_position
	var upper_len: float = upper_bone.length
	var lower_len: float = lower_bone.length
	var root_to_target := foot_world - hip_world
	var reach: float = clamp(root_to_target.length(), 0.001, upper_len + lower_len)
	var dir := root_to_target.normalized()
	var right_vec := dir.cross((pole_world - hip_world).normalized())
	if right_vec.length() < 1e-6:
		right_vec = IkUtil.get_orthogonal(dir)
	var bend_plane_normal := right_vec.normalized()
	var pole_on_plane := bend_plane_normal.cross(dir).normalized()
	var cosA: float = clamp((upper_len * upper_len + reach * reach - lower_len * lower_len) / (2.0 * upper_len * reach), -1.0, 1.0)
	var sinA: float = sqrt(max(0.0, 1.0 - cosA * cosA))
	var knee := hip_world + dir * (cosA * upper_len) + pole_on_plane * (sinA * upper_len)

	# Aplicar a los cuerpos (convención cuerpo≡hueso: global_position = junta proximal, base con
	# pose_from_rest_to — igual que solve_two_bone_ik, que usa upper_bone para ambos segmentos).
	upper_body.global_position = hip_world
	upper_body.global_basis    = upper_bone.pose_from_rest_to((knee - hip_world).normalized(), pole_on_plane)
	lower_body.global_position = knee
	lower_body.global_basis    = upper_bone.pose_from_rest_to((foot_world - knee).normalized(), pole_on_plane)
	# El pie va SIEMPRE colgado rígido de la tibia (nunca se interpola su posición suelta → nada de
	# flips). Lo que interpolamos es su ÁNGULO relativo a la tibia: arranca en el que tenía tirado
	# (para no pegar un salto al apretar G) y va al de la pose base (~90°). Al terminar coincide con la
	# pose parada (incluido que "clave" en el piso igual que parado; eso es de la pose base).
	if is_instance_valid(foot_body) and is_instance_valid(foot_bone) and is_instance_valid(lower_bone):
		var rest_foot_local := lower_bone.global_transform.affine_inverse() * foot_bone.global_transform
		var fallen_lower := _recovery_start_transforms.get(lower_bone, lower_body.global_transform) as Transform3D
		var fallen_foot  := _recovery_start_transforms.get(foot_bone,  foot_body.global_transform)  as Transform3D
		var fallen_foot_local := fallen_lower.affine_inverse() * fallen_foot
		var foot_local := fallen_foot_local.interpolate_with(rest_foot_local, plant_t)
		foot_body.global_transform = lower_body.global_transform * foot_local
	elif is_instance_valid(foot_body):
		foot_body.global_position = foot_world
		foot_body.global_basis    = lower_body.global_basis

func _finish_recovery() -> void:
	is_recovering = false
	_recovery_start_transforms.clear()
	_set_meshes_visible(false)
	for bone: CustomBone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if is_instance_valid(rb) and is_instance_valid(bone):
			rb.global_transform = bone.global_transform
			rb.collision_layer  = RAGDOLL_LAYER
			rb.collision_mask   = RAGDOLL_MASK
	if is_instance_valid(_skeleton_root):
		_skeleton_root.visible = true
	_skeleton_root = null

	if is_instance_valid(_recovering_char_rb):
		_recovering_char_rb.is_active = true
		# Descongelamos ACÁ (no en deactivate): la cápsula estuvo estática toda la recuperación, apoyada
		# en el piso, así no la eyecta la física a mitad de blend. Sólo el jugador local (no un puppet,
		# que debe seguir kinemático manejado por la red).
		if not _recovering_char_rb.is_puppet:
			_recovering_char_rb.freeze = false

	_recovering_char_rb = null

func cleanup() -> void:
	is_recovering   = false
	_recovery_timer = 0.0
	_recovery_start_transforms.clear()
	_clear_joints()
	for bone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if is_instance_valid(rb):
			rb.queue_free()
	_bodies.clear()
	_ragdoll_rids.clear()
	head_body           = null
	_lower_spine_body   = null
	_char_rb            = null
	_recovering_char_rb = null
	_skeleton_root      = null

func _clear_joints() -> void:
	for j in _joints:
		if is_instance_valid(j):
			j.queue_free()
	_joints.clear()

## Los cuerpos del ragdoll (cajas con la forma del hueso) son lo VISIBLE mientras se ragdollea.
## Con el modelo skinneado puesto dejan de serlo: se quedan invisibles siempre y el espejo los lee a
## ellos, así la malla skinneada es lo único que se ve en los dos estados. Lo apaga BoneInstantiator.
var show_bodies: bool = true

## Los RigidBody3D por hueso (CustomBone → RigidBody3D), con la convención cuerpo≡hueso: el transform
## global del cuerpo es el del hueso. Por eso el espejo puede leerlos con la MISMA corrección de ejes.
func get_bodies() -> Dictionary:
	return _bodies

func _set_meshes_visible(value: bool) -> void:
	var visible_value := value and show_bodies
	for bone in _bodies:
		var rb: RigidBody3D = _bodies[bone]
		if not is_instance_valid(rb):
			continue
		for child in rb.get_children():
			if child is MeshInstance3D:
				child.visible = visible_value

func _set_body_mesh_color(rb: RigidBody3D, color: Color) -> void:
	for child in rb.get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			child.material_override = mat
			break

func _clear_body_mesh_color(rb: RigidBody3D) -> void:
	var original_bone: CustomBone = null
	for bone in _bodies:
		if _bodies[bone] == rb:
			original_bone = bone
			break
	for child in rb.get_children():
		if child is MeshInstance3D:
			if is_instance_valid(original_bone):
				for bone_child in original_bone.get_children():
					if bone_child is MeshInstance3D:
						child.material_override = bone_child.material_override
						break
			else:
				child.material_override = null
			break

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
