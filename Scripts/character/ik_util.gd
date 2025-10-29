class_name IkUtil

var left_leg_raycast: RayCast3D
var right_leg_raycast: RayCast3D
var left_leg_raycast_indicator: MeshInstance3D
var right_leg_raycast_indicator: MeshInstance3D
var left_leg_pole = Node3D
var right_leg_pole = Node3D
const left_color: Color = Color(1, 0, 0)      # rojo
const right_color: Color = Color(0, 1, 0)    # verde
const raycast_color: Color = Color(0, 0, 1)    # verde
var left_leg_next_target: Node3D
var right_leg_next_target: Node3D
var left_leg_current_target: Node3D
var right_leg_current_target: Node3D
var left_neutral_local: Vector3
var right_neutral_local: Vector3
var raycast_offset: Vector2 = Vector2.ZERO
var current_step_radius: float:
	set(value):
		current_step_radius = value
		current_step_left_mesh_instance.mesh = DebugUtil.create_debug_ring_mesh(current_step_radius)
		current_step_right_mesh_instance.mesh = DebugUtil.create_debug_ring_mesh(current_step_radius)
	get:
		return current_step_radius
var left_leg_airborne_target: Node3D
var right_leg_airborne_target: Node3D

var current_step_left_mesh_instance: MeshInstance3D 
var current_step_right_mesh_instance: MeshInstance3D 

static func create(sizes: SkeletonSizesUtil, bones: CustomBonesUtil, skeleton: BoneInstantiator) -> IkUtil:
	var new_ik_util = IkUtil.new()
	
	#Creo raycasts
	new_ik_util.left_leg_raycast = create_leg_raycast(true,sizes)
	new_ik_util.right_leg_raycast = create_leg_raycast(false,sizes)
	#Creo indicadores de raycasts
	new_ik_util.left_leg_raycast_indicator = create_leg_raycast_indicator(sizes)
	new_ik_util.left_leg_raycast.add_child(new_ik_util.left_leg_raycast_indicator)
	new_ik_util.right_leg_raycast_indicator = create_leg_raycast_indicator(sizes)
	new_ik_util.right_leg_raycast.add_child(new_ik_util.right_leg_raycast_indicator)
	#Creo poles
	new_ik_util.left_leg_pole = create_pole(bones, true, sizes, skeleton.local_targets)
	new_ik_util.right_leg_pole = create_pole(bones, false, sizes, skeleton.local_targets)
	#Creo next targets
	new_ik_util.left_leg_next_target = IkUtil.create_next_target(-sizes.hip_size.y, left_color, sizes.raycast_leg_lenght)
	new_ik_util.right_leg_next_target = IkUtil.create_next_target(sizes.hip_size.y, right_color, sizes.raycast_leg_lenght)
	#Actualizo posicion neutra de iks
	new_ik_util.left_neutral_local  = new_ik_util.left_leg_raycast.transform.origin
	new_ik_util.right_neutral_local  = new_ik_util.right_leg_raycast.transform.origin
	#Creo current targets
	new_ik_util.left_leg_current_target = IkUtil.create_ik_target(true, sizes.step_radius_min, sizes.step_radius_max, new_ik_util)
	new_ik_util.right_leg_current_target = IkUtil.create_ik_target(false, sizes.step_radius_min, sizes.step_radius_max, new_ik_util)
	
	new_ik_util.left_leg_airborne_target = IkUtil.create_simple_ik_target(true)
	new_ik_util.right_leg_airborne_target = IkUtil.create_simple_ik_target(false)
	return new_ik_util

static func create_pole(bones: CustomBonesUtil, left: bool, sizes: SkeletonSizesUtil, local_targets: Node3D) -> Node3D:
	var lower_leg : CustomBone = bones.left_lower_leg if left else bones.right_lower_leg
	var color : Color = left_color if left else right_color
	var horizontal_offset : float = -sizes.hips_width if left else sizes.hips_width
	var pole := Node3D.new()
	local_targets.add_child(pole) # parent first so global == what you expect
	var fwd : Vector3 =  Vector3(0,0,-1) #(lower_leg.global_basis.z).normalized() # Godot forward is -Z
	pole.global_position = local_targets.global_position + Vector3(horizontal_offset,0,0) + fwd * sizes.pole_distance
	pole.add_child(DebugUtil.create_debug_sphere(color))
	return pole

static func create_leg_raycast(left: bool, sizes: SkeletonSizesUtil) -> RayCast3D:
	var length = sizes.raycast_leg_lenght
	var x_offset = -sizes.hip_size.y if left else sizes.hip_size.y
	var raycast = RayCast3D.new()
	raycast.target_position = Vector3(0, -length, 0)
	raycast.translate(Vector3(x_offset, 0, 0))
	return raycast
	
static func create_leg_raycast_indicator(sizes: SkeletonSizesUtil) -> MeshInstance3D:
	var length = sizes.raycast_leg_lenght
	var ray_mesh_instance : MeshInstance3D = DebugUtil.create_debug_line(Color.BLUE, length)
	return ray_mesh_instance

static func create_next_target(x_offset: float, color: Color, length: float) -> Node3D:
	var target = Node3D.new()
	target.position = Vector3(x_offset, -length, 0)
	target.add_child(DebugUtil.create_debug_sphere(color))
	return target

static func create_simple_ik_target(left: bool) -> Node3D:
	var color := left_color if left else right_color
	var _ik_target = Node3D.new()
	_ik_target.add_child(DebugUtil.create_debug_cube(color))
	return _ik_target

static func create_ik_target(left: bool, min_radius: float, max_radius: float, ik_util: IkUtil) -> Node3D:
	var color := left_color if left else right_color
	var _ik_target = Node3D.new()
	_ik_target.add_child(DebugUtil.create_debug_cube(color))
	_ik_target.add_child(DebugUtil.create_debug_ring(color,max_radius))
	var radius_disc : MeshInstance3D = DebugUtil.create_debug_ring(color, min_radius)
	_ik_target.add_child(radius_disc)
	if left:
		ik_util.current_step_left_mesh_instance = radius_disc
	else:
		ik_util.current_step_right_mesh_instance = radius_disc
	return _ik_target

func solve_leg_ik(upper_bone: CustomBone, lower_bone: CustomBone, ik_target: Vector3, pole_target: Vector3) -> void:
	var root_pos  : Vector3 = upper_bone.global_position
	var target_pos: Vector3 = ik_target
	var upper_len : float   = upper_bone.length
	var lower_len : float   = lower_bone.length

	# ---- Direction & reach ----
	var root_to_target : Vector3 = target_pos - root_pos
	var total_len : float = root_to_target.length()
	var clamped_len = clamp(total_len, 0.001, upper_len + lower_len)
	var dir_to_target : Vector3 = root_to_target.normalized()

	# ---- Bend plane using pole ----
	var raw_pole = (pole_target - root_pos).normalized()
	var right_vec = dir_to_target.cross(raw_pole)
	if right_vec.length() < 1e-6:
		right_vec = get_orthogonal(dir_to_target)
	var bend_plane_normal = right_vec.normalized()
	var pole_on_plane = (bend_plane_normal.cross(dir_to_target)).normalized()

	# ---- Knee position (law of cosines) ----
	var a = upper_len
	var b = lower_len
	var c = clamped_len
	var cosA = clamp((a*a + c*c - b*b) / (2.0 * a * c), -1.0, 1.0)
	var sinA = sqrt(max(0.0, 1.0 - cosA * cosA))
	var knee_pos = root_pos + dir_to_target * (cosA * a) + pole_on_plane * (sinA * a)

	# ---- Segment directions ----
	var upper_dir = (knee_pos - root_pos).normalized()
	var lower_dir = (target_pos - knee_pos).normalized()

	upper_bone.global_transform.basis = upper_bone.pose_from_rest_to(upper_dir, pole_on_plane)
	lower_bone.global_transform.basis = upper_bone.pose_from_rest_to(lower_dir, pole_on_plane)


static var _last_step_time: float = -1.0
static var _last_step_frame: int = -1
static var _last_step_leg_id: int = -1  # usamos instance_id() del current_target

static func _store_leg_measure(target: Node3D, dist2: float, wants_step: bool, next_pos: Vector3) -> void:
	var frame := Engine.get_physics_frames()
	target.set_meta("_ik_frame", frame)
	target.set_meta("_ik_dist2", dist2)
	target.set_meta("_ik_wants", wants_step)
	target.set_meta("_ik_next_pos", next_pos)

static func _fresh_measure(target: Node3D) -> bool:
	return target.has_meta("_ik_frame") and int(target.get_meta("_ik_frame")) == Engine.get_physics_frames()

static func _try_start_farther_leg(
a: Node3D, b: Node3D,
step_height: float, step_duration: float,
step_cooldown: float, alternate: bool
) -> void:
	if _is_stepping(a) or _is_stepping(b):
		return
	var frame := Engine.get_physics_frames()
	if frame == _last_step_frame:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _last_step_time >= 0.0 and (now - _last_step_time) < step_cooldown:
		return

	if not _fresh_measure(a) or not _fresh_measure(b):
		return

	var wa := bool(a.get_meta("_ik_wants"))
	var wb := bool(b.get_meta("_ik_wants"))
	if not wa and not wb:
		return

	var chosen := a
	if wa and not wb:
		chosen = a
	elif wb and not wa:
		chosen = b
	else:
		var da := float(a.get_meta("_ik_dist2"))
		var db := float(b.get_meta("_ik_dist2"))
		var eps := 1e-6
		if db > da + eps:
			chosen = b
		elif abs(da - db) <= eps and alternate and _last_step_leg_id == chosen.get_instance_id():
			chosen = b if (chosen == a) else a

	var start_pos: Vector3 = chosen.global_position
	var target_pos: Vector3 = chosen.get_meta("_ik_next_pos")
	var duration: float = max(step_duration, 0.01)  # fija; evitamos 0.0

	_register_step(chosen)
	_tween_foot_to(chosen, start_pos, target_pos, duration, step_height)

static func _register_step(current_target: Node3D) -> void:
	_last_step_time = Time.get_ticks_msec() / 1000.0
	_last_step_frame = Engine.get_physics_frames()
	_last_step_leg_id = current_target.get_instance_id()

func update_ik_raycast(
	left: bool, bones: CustomBonesUtil, sizes: SkeletonSizesUtil, char_rigidbody: CharacterRigidBody3D,
) -> void:
	
	var raycast = left_leg_raycast if left else right_leg_raycast
	var next_target = left_leg_next_target if left else right_leg_next_target
	var current_target = left_leg_current_target if left else right_leg_current_target
	var airborne_target = left_leg_airborne_target if left else right_leg_airborne_target
	var pole = left_leg_pole if left else right_leg_pole
	var opposite_current_target = right_leg_current_target if left else left_leg_current_target
	var upper_leg = bones.left_upper_leg if left else bones.right_upper_leg
	var lower_leg = bones.left_lower_leg if left else bones.right_lower_leg
	var step_radius = current_step_radius
	
	# Actualizar paso en curso ANTES de calcular nuevo paso
	_update_stepping_foot(current_target)
	
	# Recordar si estaba en el aire en la frame anterior
	var was_airborne : bool = current_target.get_meta("was_airborne", false)
	
	# 🔹 NUEVO: Ajustar longitud del raycast según velocidad vertical
	var min_raycast_length : float = sizes.raycast_leg_lenght
	var vertical_velocity : float = char_rigidbody.linear_velocity.y
	var minimal_additional_length : float = sizes.raycast_leg_lenght * 0.2
	var additional_length : float = minimal_additional_length 

	
	# Si está cayendo (velocidad negativa), extender el raycast
	if vertical_velocity < 0.0:
		# Multiplicador para controlar cuánto se extiende por velocidad
		# Ajusta este valor según necesites más o menos anticipación
		var velocity_to_distance_factor : float = 0.3
		additional_length = abs(vertical_velocity) * velocity_to_distance_factor
		additional_length = clamp(additional_length, minimal_additional_length, 9999)
		
		## Opcional: limitar la extensión máxima para evitar raycasts demasiado largos
		#var max_additional_length : float = sizes.leg_height * 2.0
		#additional_length = min(additional_length, max_additional_length)
	
	# Aplicar la nueva longitud al raycast
	var total_raycast_length : float = min_raycast_length + additional_length
	raycast.target_position.y = -total_raycast_length  # Negativo porque apunta hacia abajo
	var max_raycast_distance : float = raycast.target_position.length()
	var leg_reach_raycast_distance : float = sizes.leg_height
	
	if left:
		left_leg_raycast_indicator = DebugUtil.update_debug_line_mesh(left_leg_raycast_indicator,total_raycast_length)
	else:
		right_leg_raycast_indicator = DebugUtil.update_debug_line_mesh(right_leg_raycast_indicator,total_raycast_length)

	
	

	
	raycast.force_raycast_update()
	if raycast.is_colliding():
		var collision_point: Vector3 = raycast.get_collision_point()
		
		# 🔹 NUEVO: Calcular distancia real de colisión
		var collision_distance : float = raycast.global_position.distance_to(collision_point)
		
		# 🔹 NUEVO: Tres zonas de comportamiento según distancia
		if collision_distance >= leg_reach_raycast_distance:
			# ZONA 2: Entre mitad y máximo del raycast
			# Interpolar entre airborne_target y collision_point
			var t : float = (collision_distance - leg_reach_raycast_distance) / (max_raycast_distance - leg_reach_raycast_distance)
			t = clamp(t, 0.0, 1.0)
			
			# t=0 cuando está en la mitad (más cerca de collision_point)
			# t=1 cuando está en el máximo (más cerca de airborne_target)
			var interpolated_position : Vector3 = collision_point.lerp(airborne_target.global_position, t)
			next_target.global_position = interpolated_position
			
			# Marcar como semi-airborne (opcional, para transiciones suaves)
			current_target.set_meta("was_airborne", true)
			
			# Guardar métricas pero sin intentar stepping en esta zona
			var dist2 : float = (
				Vector2(next_target.global_position.x, next_target.global_position.z) -
				Vector2(current_target.global_position.x, current_target.global_position.z)
			).length_squared()
			
			_store_leg_measure(current_target, dist2, false, interpolated_position)
			
			# Transición suave hacia la posición interpolada
			if not _is_stepping(current_target):
				_tween_foot_to(current_target, current_target.global_position, interpolated_position, 0.0, sizes.step_height * 0.5)
		
		else: #else false
			# ZONA 3: Entre inicio y mitad del raycast
			# Comportamiento normal de grounded
			next_target.global_position = collision_point
			
			# Si estaba en el aire y ahora toca el piso, hacer snap inmediato
			if was_airborne:
				_clear_step_data(current_target)
				current_target.global_position = collision_point
				current_target.set_meta("was_airborne", false)
			
			var dist2 : float = (
				Vector2(next_target.global_position.x, next_target.global_position.z) -
				Vector2(current_target.global_position.x, current_target.global_position.z)
			).length_squared()
			
			var dist2Exp : float = (
				Vector2(next_target.global_position.x, next_target.global_position.z) -
				Vector2(char_rigidbody.global_position.x, char_rigidbody.global_position.z)
			).length_squared()
			
			var step_distance : float = sqrt(dist2Exp)
			var wants_step : bool = dist2 > (step_radius * step_radius)
			
			_store_leg_measure(current_target, dist2, wants_step, collision_point)
			
			var step_duration : float = get_step_duration(char_rigidbody, sizes, step_distance)
			
			# Si está pisando, actualizar la duración dinámicamente
			if _is_stepping(current_target):
				_update_step_duration(current_target, step_duration)
			
			_try_start_farther_leg(current_target, opposite_current_target, sizes.step_height, step_duration, 0.05, false)
		
	else:
		# ZONA 1: No hay colisión - usar airborne_target
		_store_leg_measure(current_target, 0.0, false, airborne_target.global_position)
		
		# Marcar que está en el aire
		current_target.set_meta("was_airborne", true)
		
		if not _is_stepping(current_target):
			_tween_foot_to(current_target, current_target.global_position, airborne_target.global_position, 0.0, sizes.step_height)
	
	solve_leg_ik(upper_leg, lower_leg, current_target.global_position, pole.global_position)

static func _tween_foot_to(node: Node3D, from_pos: Vector3, to_pos: Vector3, duration: float, step_height: float) -> void:
	# Si ya hay un paso en curso, lo cancelamos pero guardamos el progreso
	if node.has_meta("ik_step_time"):
		# Opcional: podrías mantener la posición actual como nuevo from_pos
		pass
	
	# Instant snap: no hay animación
	if duration <= 0.0 or from_pos.is_equal_approx(to_pos):
		node.global_position = to_pos
		_clear_step_data(node)
		return
	
	# Inicializar metadata del paso
	node.set_meta("stepping", true)
	node.set_meta("ik_step_start_time", Time.get_ticks_msec() / 1000.0)
	node.set_meta("ik_step_duration", duration)
	node.set_meta("ik_step_from", from_pos)
	node.set_meta("ik_step_to", to_pos)
	node.set_meta("ik_step_height", step_height)

static func _update_stepping_foot(node: Node3D) -> void:
	if not _is_stepping(node):
		return
	
	var now := Time.get_ticks_msec() / 1000.0
	var start_time := float(node.get_meta("ik_step_start_time"))
	var duration := float(node.get_meta("ik_step_duration"))
	var from_pos := Vector3(node.get_meta("ik_step_from"))
	var to_pos := Vector3(node.get_meta("ik_step_to"))
	var step_height := float(node.get_meta("ik_step_height"))
	
	# Calcular progreso (0.0 a 1.0)
	var elapsed := now - start_time
	var progress : float = clamp(elapsed / duration, 0.0, 1.0)
	
	# Aplicar easing (TRANS_SINE + EASE_OUT equivalente)
	var eased_progress := ease_out_sine(progress)
	
	# Lerp posición con arco vertical
	var pos := from_pos.lerp(to_pos, eased_progress)
	pos.y += sin(eased_progress * PI) * step_height
	node.global_position = pos
	
	# Si terminó el paso
	if progress >= 1.0:
		node.global_position = to_pos  # Asegurar posición final exacta
		_clear_step_data(node)

static func ease_out_sine(t: float) -> float:
	return sin(t * PI * 0.5)

static func _clear_step_data(node: Node3D) -> void:
	node.set_meta("stepping", false)
	node.remove_meta("ik_step_start_time")
	node.remove_meta("ik_step_duration")
	node.remove_meta("ik_step_from")
	node.remove_meta("ik_step_to")
	node.remove_meta("ik_step_height")

static func _update_step_duration(node: Node3D, new_duration: float) -> void:
	if not _is_stepping(node):
		return
	
	# Recalcular el start_time para mantener el progreso actual
	var now := Time.get_ticks_msec() / 1000.0
	var old_start_time := float(node.get_meta("ik_step_start_time"))
	var old_duration := float(node.get_meta("ik_step_duration"))
	
	var elapsed := now - old_start_time
	var current_progress : float = clamp(elapsed / old_duration, 0.0, 1.0)
	
	# Ajustar start_time para que el progreso se mantenga con la nueva duración
	var new_start_time := now - (current_progress * new_duration)
	
	node.set_meta("ik_step_start_time", new_start_time)
	node.set_meta("ik_step_duration", new_duration)

static func _is_stepping(n: Node) -> bool:
	return n.has_meta("stepping") and bool(n.get_meta("stepping"))

static func _mark_stepping(n: Node, stepping: bool) -> void:
	n.set_meta("stepping", stepping)

 #speed_for_max: float, speed_curve: Curve, raycast_amount: float, raycast_max_offset: float, axis_weights: Vector2, raycast_smooth: float, neutral_local: Vector3, raycast_offset: Vector2

func update_leg_raycast_offsets(root_rigidbody: RigidBody3D, delta: float, left: bool, sizes: SkeletonSizesUtil, entity_stats: EntityStats) -> void:
	# Velocidad horizontal
	var hvel := root_rigidbody.linear_velocity
	hvel.y = 0.0
	
	var leg_raycast = left_leg_raycast if left else right_leg_raycast
	var leg_airborne_target = left_leg_airborne_target if left else right_leg_airborne_target
	var neutral_local = left_neutral_local if left else right_neutral_local
	
	# A espacio local del padre de raycasts
	var basis_owner := leg_raycast.get_parent() as Node3D
	var local_vel: Vector3 = basis_owner.global_transform.basis.inverse() * hvel
	var v2 := Vector2(local_vel.x, local_vel.z)
	var speed := v2.length()
	var dir := (v2 / speed) if (speed > 0.0) else Vector2.ZERO
	# Velocidad normalizada (0..1) y ganancia total
	var n : float = clamp(speed / sizes.speed_for_max, 0.0, 1.0)
	var curve_gain : = sizes.speed_curve.sample_baked(n) if (sizes.speed_curve != null) else n
	var amount := sizes.raycast_amount * curve_gain
	# Offset objetivo limitado por el radio máximo
	var target_off := dir * (amount * sizes.raycast_max_offset)
	target_off = Vector2(target_off.x * sizes.axis_weights.x, target_off.y * sizes.axis_weights.y)
	# Suavizado
	var k : float = clamp(delta * sizes.raycast_smooth, 0.0, 1.0)
	raycast_offset = raycast_offset.lerp(target_off, k)
	
	# Configuración de posiciones Y
	var ground_leg_y_position = sizes.leg_height - (sizes.leg_height * entity_stats.distance_from_ground_factor)
	var falling_leg_max_y_position = sizes.leg_height * 0.5
	var jumping_leg_max_y_position = sizes.leg_height
	var falling_max_y_speed = -5.0
	var jumping_max_y_speed = 1.0
	
	# Calcular posición Y según velocidad vertical ABSOLUTA
	var y_vel = root_rigidbody.linear_velocity.y
	var abs_y_vel = abs(y_vel)
	
	# Usar el máximo de ambas velocidades para normalizar
	var max_y_speed = max(abs(falling_max_y_speed), jumping_max_y_speed)
	var velocity_factor = clamp(abs_y_vel / max_y_speed, 0.0, 1.0)
	
	# Interpolar: vel=0 está en falling_leg_max_y_position, vel máxima en jumping_leg_max_y_position
	var target_y_position = lerp(falling_leg_max_y_position, jumping_leg_max_y_position, velocity_factor)
	
	# Aplicar alrededor de las posiciones locales neutras
	leg_raycast.transform.origin = neutral_local + Vector3(raycast_offset.x, 0.0, raycast_offset.y)
	leg_airborne_target.transform.origin = Vector3(
		neutral_local.x - raycast_offset.x * 0.3,
		neutral_local.y - target_y_position,
		neutral_local.z - raycast_offset.y * 0.3
	)
	
static func get_orthogonal(v: Vector3) -> Vector3:
	if abs(v.x) < abs(v.y):
		return Vector3(0, -v.z, v.y).normalized()
	else:
		return Vector3(-v.z, 0, v.x).normalized()
	
func get_step_duration(char_rigidbody: CharacterRigidBody3D, sizes: SkeletonSizesUtil, step_distance: float) -> float:
	var leg_height = sizes.leg_height
	var dxz := Vector2(char_rigidbody.linear_velocity.x, char_rigidbody.linear_velocity.z)
	var horizontal_speed = dxz.length()
	
	# El pie debe completar el paso antes de que el cuerpo avance step_distance
	# Usamos un factor < 1.0 para que el pie llegue "antes" y no se quede atrás
	var safety_factor = 0.8 # El paso se completa en el 80% del tiempo teórico
	
	if horizontal_speed < 0.01:
		return 0.3
	
	var step_duration = (step_distance / horizontal_speed) * safety_factor
	
	# Clamp basado en la longitud de pierna para mantener movimientos naturales
	var min_duration = 0.04 * leg_height  # Pasos muy rápidos para piernas pequeñas
	var max_duration = 0.4 * leg_height   # Límite superior para piernas grandes
	
	return clamp(step_duration, min_duration, max_duration)
