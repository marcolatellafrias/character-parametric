extends CharacterBody3D

@export var speed: float = 5.0
@export var acceleration: float = 8.0
@export var jump_force: float = 4.5
@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var mouse_sensitivity: float = 0.3

var input_dir: Vector3
var velocity_y: float = 0.0

@onready var camera: Camera3D = $Camera3D

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# NEW: handle Esc even when UI is in focus
func _input(event):
	if event.is_action_pressed("ui_cancel"): # Esc by default
		_toggle_mouse_capture()

func _unhandled_input(event):
	# Only rotate when mouse is captured
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_rotate_camera(event.relative)

func _physics_process(delta: float):
	_handle_movement(delta)
	_apply_gravity(delta)
	move_and_slide()

func _handle_movement(delta: float):
	var input_vec = Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_forward") - Input.get_action_strength("move_backward")
	).normalized()

	var forward = -camera.global_transform.basis.z
	var right = camera.global_transform.basis.x
	input_dir = (forward * input_vec.y + right * input_vec.x).normalized()

	var target_velocity = input_dir * speed
	var horizontal_velocity = velocity
	horizontal_velocity.y = 0.0

	horizontal_velocity = horizontal_velocity.lerp(target_velocity, acceleration * delta)
	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z

	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_force

func _apply_gravity(delta: float):
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

func _rotate_camera(relative: Vector2):
	rotate_y(deg_to_rad(-relative.x * mouse_sensitivity))
	camera.rotate_x(deg_to_rad(-relative.y * mouse_sensitivity))
	camera.rotation_degrees.x = clamp(camera.rotation_degrees.x, -80, 80)

# NEW: toggle between captured (hidden) and visible cursor
func _toggle_mouse_capture():
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)   # show cursor → can click UI
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)  # hide cursor → FPS look
