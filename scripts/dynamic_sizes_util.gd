class_name DynamicSizesUtil

var leg_height : float
var skel : BoneInstantiator #skeleton
var collision_shape:
	get:
		return skel.collision_shape
	set(value):
		skel.collision_shape = value
var stable_sizes:
	get:
		return skel.stable_sizes_util

static func create(new_skeleton: BoneInstantiator, new_leg_height: float) -> DynamicSizesUtil:
	var newDynamicUtil = DynamicSizesUtil.new()
	newDynamicUtil.skel = new_skeleton
	newDynamicUtil.leg_height = new_leg_height
	return newDynamicUtil

func set_base() -> void:
	_set_step_base_duration()
	_set_capsule_base_dimensions()

func update(delta: float) -> void:
	_update_step_duration(delta)

var _prev_origin: Vector3 = Vector3.INF
var _ema_speed: float = 0.0
const SPEED_TAU := 0.15 # s, suavizado (más chico = más reactivo)

func _update_step_duration(delta: float) -> void:
	# Nodo de referencia para posición (usamos el controller)
	var node := skel.character_controller
	var origin: Vector3 = node.global_transform.origin

	# Primera llamada: inicializa y usa la base (sin variar por velocidad)
	if _prev_origin == Vector3.INF:
		_prev_origin = origin
		skel.step_duration = max(0.001, skel.base_step_duration)
		return

	# Velocidad horizontal medida por desplazamiento real
	var dxz := Vector2(origin.x - _prev_origin.x, origin.z - _prev_origin.z)
	var instant_speed: float = dxz.length() / max(delta, 0.0001)

	# sprint_multiplier opcional (fallback a 1.0)
	var sprint_mult: float = 1.0
	if node.has_method("get"):
		var _sm = node.get("sprint_multiplier")
		if typeof(_sm) == TYPE_FLOAT or typeof(_sm) == TYPE_INT:
			sprint_mult = max(1.0, float(_sm))

	var effective_speed: float = instant_speed * sprint_mult

	# Suavizado exponencial con constante de tiempo
	var alpha := 1.0 - exp(-delta / SPEED_TAU)
	_ema_speed += (effective_speed - _ema_speed) * alpha

	# Término de velocidad (↑ vel ⇒ ↓ duración)
	var speed_ref : float = max(0.001, skel.speed_ref)
	var beta := skel.beta
	var speed_term := pow(1.0 + (_ema_speed / speed_ref), beta)

	var base : float = max(0.001, skel.base_step_duration)
	var new_duration := base / speed_term

	# (Opcional) límites si los tenés definidos en skel
	if "min_step_duration" in skel:
		new_duration = max(new_duration, skel.min_step_duration)
	if "max_step_duration" in skel:
		new_duration = min(new_duration, skel.max_step_duration)

	skel.step_duration = new_duration
	_prev_origin = origin

func _set_step_base_duration() -> void:
	# --- tamaños estáticos que dependen SOLO de leg_height ---
	var h: float = max(leg_height, 0.001)
	skel.character_controller.speed = leg_height * 1.8
	skel.step_radius_walk   = h * 0.5
	skel.step_radius_turn   = h * 0.20
	skel.step_height        = h * 0.40
	skel.pole_distance      = h
	skel.raycast_max_offset = h * 0.20

	# --- duración base del paso (SIN velocidad) ---
	# Guardamos una referencia inmutable del valor "de fábrica" (para leg_ref)
	# la primera vez que se llama, para no re-escalarla en cada cambio.
	var bsd_ref: float
	if skel.has_meta("bsd_ref"):
		bsd_ref = float(skel.get_meta("bsd_ref"))
	else:
		# Asumimos que skel.base_step_duration contiene el valor de referencia (p.ej. 0.2s) para leg_ref
		bsd_ref = float(skel.base_step_duration)
		skel.set_meta("bsd_ref", bsd_ref)

	var leg_term: float = pow(h / skel.leg_ref, skel.alpha)
	skel.base_step_duration = bsd_ref * leg_term
	skel.step_duration = skel.base_step_duration

func _set_capsule_base_dimensions() -> void:
	if collision_shape is CollisionShape3D:
		if collision_shape.shape is CapsuleShape3D:
			var radius :=  skel.hip_width.y * 2
			var height := skel.feet_to_head_height
			var y_offset : float = stable_sizes.torso_height + stable_sizes.head_height + height/2 - height + skel.distance_from_ground
			collision_shape.shape.height = height
			collision_shape.shape.radius = radius
			collision_shape.position = (Vector3(0, y_offset ,0))
			skel.character_controller.add_child.call_deferred(DebugUtil.create_debug_capsule(radius,  height, y_offset))
