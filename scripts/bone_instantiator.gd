extends Node3D

#ALTURA DEL PERSONAJE
@export var feet_to_head_height := 1.8: #This excludes arms and horizontal bones,
	set(value):
		feet_to_head_height = value
		initialize_skeleton()

#PROPORCIONES/INTERFAZ
@export var neck_to_head_proportion := 0.1:
	set(value):
		neck_to_head_proportion = value
		initialize_skeleton()
@export var chest_to_low_spine_proportion := 0.4:
	set(value):
		chest_to_low_spine_proportion = value
		initialize_skeleton()
@export var legs_to_feet_proportion := 0.6:
	set(value):
		legs_to_feet_proportion = value
		initialize_skeleton()
@export var hips_width_proportion := 0.15:
	set(value):
		hips_width_proportion = value
		initialize_skeleton()	
@export var shoulder_width_proportion := 0.2:
	set(value):
		shoulder_width_proportion = value
		initialize_skeleton()
@export var arms_proportion := 0.7:
	set(value):
		arms_proportion = value
		initialize_skeleton()
@export var has_neck := true:
	set(value):
		has_neck = value
		initialize_skeleton()

#PARAMETROS DE CAMINATA
var step_radius_walk := 0.4
var step_radius_turn := 0.2
@export var distance_from_ground_factor := 0.7
var distance_from_ground: float

#IK variables
@onready var ik_targets := $"../../ik_targets"
var pole_distance: float = 0.8
var target_height: float = -2.0
var left_color: Color = Color(1, 0, 0)      # rojo
var right_color: Color = Color(0, 1, 0)    # verde
var raycast_color: Color = Color(0, 0, 1)    # verde
var raycast_leg_lenght: float #la distancia del raycast desde la altura del rootbone
var left_leg_pole: Node3D
var right_leg_pole: Node3D
var left_leg_next_target: Node3D
var right_leg_next_target: Node3D
var left_leg_current_target: Node3D
var right_leg_current_target: Node3D
var left_leg_raycast: RayCast3D
var right_leg_raycast: RayCast3D

#Tamaños de huesos
var head_size: Vector3
var neck_size: Vector3
var chest_size: Vector3
var upper_spine_size: Vector3
var middle_spine_size: Vector3
var lower_spine_size: Vector3 #this is the root
var upper_leg_size: Vector3
var lower_leg_size: Vector3
var upper_feet_size: Vector3
var lower_feet_size: Vector3
var upper_arm_size: Vector3
var lower_arm_size: Vector3
var shoulder_width: Vector3
var hip_width: Vector3

# Huesos
var lower_spine : CustomBone
var middle_spine : CustomBone
var upper_spine : CustomBone
var chest : CustomBone
var left_hip : CustomBone
var right_hip : CustomBone
var left_upper_leg : CustomBone
var left_lower_leg : CustomBone
var right_upper_leg : CustomBone
var right_lower_leg : CustomBone
var right_upper_feet : CustomBone
var left_upper_feet : CustomBone
var neck : CustomBone
var head : CustomBone
var left_shoulder : CustomBone
var right_shoulder : CustomBone
var right_upper_arm : CustomBone
var right_lower_arm : CustomBone
var left_upper_arm : CustomBone
var left_lower_arm : CustomBone

func update_sizes() -> void:
	# Evitar división por cero
	var total := legs_to_feet_proportion + chest_to_low_spine_proportion + neck_to_head_proportion
	if total == 0.0:
		total = 1.0

	# Calcular proporciones relativas
	var leg_ratio := legs_to_feet_proportion / total
	var torso_ratio := chest_to_low_spine_proportion / total
	var head_ratio := neck_to_head_proportion / total

	# Calcular alturas absolutas
	var leg_height := feet_to_head_height * leg_ratio
	var torso_height := feet_to_head_height * torso_ratio
	var head_height := feet_to_head_height * head_ratio

	# --------- PIERNAS ---------
	upper_leg_size = Vector3(0.1, leg_height * 0.55, 0.1)
	lower_leg_size = Vector3(0.1, leg_height * 0.45, 0.1)

	# Separar el pie de la pierna
	upper_feet_size = Vector3(0.1, leg_height * 0.28, 0.1)
	lower_feet_size = Vector3(0.1, leg_height * 0.02, 0.1)

	# --------- TORSO ---------
	# Proporciones ajustadas internamente para coherencia anatómica
	lower_spine_size = Vector3(0.1, torso_height * 0.1, 0.1)
	middle_spine_size = Vector3(0.1, torso_height * 0.2, 0.1)
	upper_spine_size = Vector3(0.1, torso_height * 0.3, 0.1)
	chest_size = Vector3(0.2, torso_height * 0.4, 0.2)

	# Anchuras laterales
	hip_width = Vector3( 0.1,hips_width_proportion * feet_to_head_height, 0.1)
	shoulder_width = Vector3( 0.1,shoulder_width_proportion * feet_to_head_height, 0.1)

	# --------- CABEZA Y CUELLO ---------
	if has_neck:
		neck_size = Vector3(0.1, head_height * 0.8, 0.1)
		head_size = Vector3(0.3, head_height * 1.0, 0.3)
	else:
		neck_size = Vector3.ZERO
		head_size = Vector3(0.3, head_height, 0.3)

	# --------- BRAZOS ---------
	var arm_total := torso_height * arms_proportion
	upper_arm_size = Vector3(0.1, arm_total * 0.55, 0.1)
	lower_arm_size = Vector3(0.1, arm_total * 0.45, 0.1)
	raycast_leg_lenght = leg_height 
	distance_from_ground = leg_height * (1- distance_from_ground_factor)



func _ready() -> void:
	initialize_skeleton()

func initialize_skeleton() -> void:
	for bone in get_children():
		bone.queue_free()
	for target in ik_targets.get_children():
		target.queue_free()

	update_sizes()

	# Hueso raíz
	lower_spine = CustomBone.create(lower_spine_size, Vector3.ZERO, Color.WHITE_SMOKE)
	add_child(lower_spine)

	# Chest and spine
	middle_spine = CustomBone.createFromToUp(lower_spine, middle_spine_size, 0.0,0.0, Color.SKY_BLUE, true)
	upper_spine = CustomBone.createFromToUp(middle_spine, upper_spine_size, 0.0,0.0, Color.BURLYWOOD , true)
	chest = CustomBone.createFromToUp(upper_spine, chest_size, 0.0,0.0, Color.BURLYWOOD , true)
	left_hip = CustomBone.createFromToLeft(lower_spine, hip_width, 0.0,0.0, Color.ROYAL_BLUE , false)
	right_hip = CustomBone.createFromToRight(lower_spine, hip_width, 0.0,0.0, Color.ROYAL_BLUE , false)

	# Legs
	left_upper_leg = CustomBone.createFromToDown(left_hip, upper_leg_size, 0.0,0.0, Color.YELLOW , true)
	left_lower_leg = CustomBone.createFromToDown(left_upper_leg, lower_leg_size, 0.0,0.0, Color.ORANGE , true)
	right_upper_leg = CustomBone.createFromToDown(right_hip, upper_leg_size, 0.0,0.0, Color.YELLOW , true)
	right_lower_leg = CustomBone.createFromToDown(right_upper_leg, lower_leg_size, 0.0,0.0, Color.ORANGE , true)
	right_upper_feet = CustomBone.createFromToForward(right_lower_leg, upper_feet_size, 0.0,0.0, Color.ORANGE , true)
	left_upper_feet = CustomBone.createFromToForward(left_lower_leg, upper_feet_size, 0.0,0.0, Color.ORANGE , true)
	
	# Head
	if has_neck:
		neck = CustomBone.createFromToUp(chest, neck_size, 0.0,0.0, Color.RED , true)
	head = CustomBone.createFromToUp(neck if neck else chest, head_size, 0.0,0.0, Color.GREEN , true)
	
	# Shoulders
	left_shoulder = CustomBone.createFromToLeft(chest, shoulder_width, 0.0,0.3, Color.CHOCOLATE , true)
	right_shoulder = CustomBone.createFromToRight(chest, shoulder_width, 0.0,-0.3, Color.GREEN , true)

	# Arms
	right_upper_arm = CustomBone.createFromToDown(right_shoulder, upper_arm_size, 0.0,0.0, Color.VIOLET , true)
	right_lower_arm = CustomBone.createFromToDown(right_upper_arm, lower_arm_size, 0.0,0.0, Color.RED , true)
	left_upper_arm = CustomBone.createFromToDown(left_shoulder, upper_arm_size, 0.0,0.0, Color.VIOLET , true)
	left_lower_arm = CustomBone.createFromToDown(left_upper_arm, lower_arm_size, 0.0,0.0, Color.RED , true)
	
	create_ik_controls()
	translate(Vector3(0,-distance_from_ground,0))

func create_ik_controls() -> void:	
	left_leg_raycast = RayCast3D.new()
	left_leg_raycast.target_position = Vector3(0,-raycast_leg_lenght,0)
	left_leg_raycast.add_child(DebugUtil.create_debug_line(raycast_color, raycast_leg_lenght))
	left_leg_raycast.translate(Vector3(-hip_width.y,0,0))
	add_child(left_leg_raycast)
	right_leg_raycast = RayCast3D.new()
	right_leg_raycast.target_position = Vector3(0,-raycast_leg_lenght,0)
	right_leg_raycast.add_child(DebugUtil.create_debug_line(raycast_color, raycast_leg_lenght))
	right_leg_raycast.translate(Vector3(hip_width.y,0,0))
	add_child(right_leg_raycast)
	
	# === LEFT POLE ===
	left_leg_pole = Node3D.new()
	add_child(left_leg_pole)
	left_leg_pole.global_position = left_lower_leg.global_position + left_lower_leg.global_transform.basis.z * pole_distance
	left_leg_pole.add_child(DebugUtil.create_debug_sphere(left_color))

	# === RIGHT POLE ===
	right_leg_pole = Node3D.new()
	add_child(right_leg_pole)
	right_leg_pole.global_position = right_lower_leg.global_position + right_lower_leg.global_transform.basis.z * pole_distance
	right_leg_pole.add_child(DebugUtil.create_debug_sphere(right_color))

	# === IK TARGETS ===
	left_leg_next_target = Node3D.new()
	add_child(left_leg_next_target)
	left_leg_next_target.position = Vector3(-hip_width.y,-raycast_leg_lenght,0)
	left_leg_next_target.add_child(DebugUtil.create_debug_sphere(left_color))

	right_leg_next_target = Node3D.new()
	add_child(right_leg_next_target)
	right_leg_next_target.position = Vector3(hip_width.y,-raycast_leg_lenght,0)
	right_leg_next_target.add_child(DebugUtil.create_debug_sphere(right_color))
	
	#var lef := create_ik_target(left_color, step_radius_walk, step_radius_turn)
	#ik_targets.add_child(current_target)

	left_leg_current_target = create_ik_target(left_color)
	ik_targets.add_child(left_leg_current_target)
	right_leg_current_target = create_ik_target(right_color)
	ik_targets.add_child(right_leg_current_target)
   
func _physics_process(_delta: float) -> void:
	left_leg_current_target = update_ik_raycast(left_leg_raycast,left_leg_next_target,left_leg_current_target,left_upper_leg,left_lower_leg,left_leg_pole)
	right_leg_current_target = update_ik_raycast(right_leg_raycast,right_leg_next_target,right_leg_current_target,right_upper_leg,right_lower_leg,right_leg_pole)

func create_ik_target(color: Color) -> Node3D:
	var _ik_target = Node3D.new()
	_ik_target.add_child(DebugUtil.create_debug_cube(color))
	_ik_target.add_child(DebugUtil.create_debug_ring(color,step_radius_walk))
	_ik_target.add_child(DebugUtil.create_debug_ring(color,step_radius_turn))
	return _ik_target

func solve_leg_ik(
	upper_bone: CustomBone,
	lower_bone: CustomBone,
	ik_target: Vector3,
	pole_target: Vector3
) -> void:
	var root_pos  : Vector3 = upper_bone.global_position
	var target_pos: Vector3 = ik_target
	var upper_len : float   = upper_bone.length
	var lower_len : float   = lower_bone.length

	# ---- Direction & reach ----
	var root_to_target = target_pos - root_pos
	var total_len = root_to_target.length()
	var clamped_len = clamp(total_len, 0.001, upper_len + lower_len)
	var dir_to_target = root_to_target.normalized()

	# ---- Bend plane using pole ----
	var raw_pole = (pole_target - root_pos).normalized()
	var right_vec = dir_to_target.cross(raw_pole)
	if right_vec.length() < 1e-6:
		right_vec = dir_to_target.orthogonal()
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

	# ---- Build world bases directly from REST -> POSE mapping ----
	var upper_rest = Basis.from_euler(upper_bone.rest_rotation)
	var lower_rest = Basis.from_euler(lower_bone.rest_rotation)

	upper_bone.global_transform.basis = _pose_from_rest_to(upper_dir, pole_on_plane, upper_rest)
	lower_bone.global_transform.basis = _pose_from_rest_to(lower_dir, pole_on_plane, lower_rest)

func _pose_from_rest_to(dir: Vector3, pole: Vector3, rest_basis: Basis) -> Basis:
	var y = dir.normalized()

	# 1) Shortest-arc rotation that moves REST +Y onto desired direction
	var rest_y = rest_basis.y.normalized()
	var c = clamp(rest_y.dot(y), -1.0, 1.0)
	var align: Basis
	if c > 0.999999:
		align = Basis() # already aligned
	elif c < -0.999999:
		var axis = rest_y.cross(Vector3.RIGHT)
		if axis.length_squared() < 0.0001:
			axis = rest_y.cross(Vector3.UP)
			axis = axis.normalized()
			align = Basis(axis, PI) # 180° flip
	else:
		var axis = rest_y.cross(y).normalized()
		var angle = acos(c)
		align = Basis(axis, angle)

	# 2) Twist around the direction so REST X matches the pole projection
	var projected_pole = (pole - y * pole.dot(y)).normalized()
	if projected_pole.length() < 1e-6:
		projected_pole = y.orthogonal().normalized()

# NEW: make the leg's local -Z align with the pole direction on the bend plane
	var ref_axis = (align * rest_basis).z.normalized()  # treat -Z as "forward"
	var s = ref_axis.cross(projected_pole).dot(y)
	var t = ref_axis.dot(projected_pole)
	var twist_angle = atan2(s, t)
	var twist = Basis(y, twist_angle)

	# Final world basis
	return twist * align * rest_basis


func update_ik_raycast(raycast: RayCast3D,next_target: Node3D,current_target: Node3D,upper_leg: CustomBone,lower_leg: CustomBone,pole: Node3D) -> Node3D:
	raycast.force_raycast_update()
	var want_step := false
	var target_point := current_target.global_position

	if raycast.is_colliding():
		target_point = raycast.get_collision_point()
		next_target.global_position = target_point

		# Compare XZ-only distance against your threshold
		var dxz := Vector2(target_point.x, target_point.z) - Vector2(current_target.global_position.x, current_target.global_position.z)
		# If `step_radius_walk` is a radius (not squared), compare to its square:
		# if dxz.length_squared() > step_radius_walk * step_radius_walk:
		if dxz.length_squared() > step_radius_walk:
			want_step = true
	else:
		# No ground hit — move toward where we think the next target is
		target_point = next_target.global_position
		# Only step if there's actually some distance to cover
		want_step = current_target.global_position.distance_to(target_point) > 0.001

	# Trigger tween only when we actually want a step
	if want_step:
		var dist : float = current_target.global_position.distance_to(target_point)
		# Convert distance to time; clamp so tiny/huge steps still feel good
		var duration : float = clamp(dist / STEP_SPEED_MPS, 0.06, 0.25)
		_tween_foot_to(current_target, current_target.global_position, target_point, duration, STEP_HEIGHT)
	solve_leg_ik(upper_leg, lower_leg, current_target.global_position, pole.global_position)
	return current_target


# Adjustable step settings
const STEP_SPEED_MPS  := 6.0      # how fast the foot travels toward its new spot
const STEP_HEIGHT     := 0.4     # how high the foot lifts during the step

func _tween_foot_to(node: Node3D, from_pos: Vector3, to_pos: Vector3, duration: float, height: float = STEP_HEIGHT) -> void:
	# Stop an in-flight tween for this node (if any)
	if node.has_meta("ik_tween"):
		var old: Tween = node.get_meta("ik_tween")
		if old and old.is_running():
			old.kill()

	var tween := get_tree().create_tween()
	# If this runs from _physics_process, keep the tween in physics for stability
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	node.set_meta("ik_tween", tween)

	# Tween with a small vertical arc using tween_method
	var from := from_pos
	var to   := to_pos

	tween.tween_method(
		func(p: float) -> void:
			# p goes 0..1 — lerp on XZ and add a soft arc on Y
			var pos := from.lerp(to, p)
			pos.y += sin(p * PI) * height
			node.global_position = pos
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Cleanup meta when finished (optional)
	tween.finished.connect(func(): node.set_meta("ik_tween", null))
