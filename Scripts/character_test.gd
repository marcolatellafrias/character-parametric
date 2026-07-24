extends CharacterBody3D

@export var enabled: bool = true:
	set(value):
		enabled = value
		_apply_enabled()

@export var speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var fly_speed: float = 8.0
@export var fly_sprint_speed: float = 16.0
@export var mouse_sensitivity: float = 0.003

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var creative_mode: bool = false

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_apply_enabled()

func _apply_enabled() -> void:
	set_physics_process(enabled)
	set_process_unhandled_input(enabled)
	if camera:
		camera.current = enabled
	# El mouse_mode lo maneja UIState (technical/ui.md), no este freecam de debug.

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x, -PI / 2.0, PI / 2.0)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		creative_mode = not creative_mode
		velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	var input_dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): input_dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S): input_dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1.0

	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var sprinting := Input.is_physical_key_pressed(KEY_SHIFT)

	if creative_mode:
		var current_speed := fly_sprint_speed if sprinting else fly_speed
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed

		var vertical := 0.0
		if Input.is_physical_key_pressed(KEY_SPACE): vertical += 1.0
		if Input.is_physical_key_pressed(KEY_CTRL): vertical -= 1.0
		velocity.y = vertical * current_speed
	else:
		if not is_on_floor():
			velocity.y -= gravity * delta

		if Input.is_physical_key_pressed(KEY_SPACE) and is_on_floor():
			velocity.y = jump_velocity

		var current_speed := sprint_speed if sprinting else speed
		if direction:
			velocity.x = direction.x * current_speed
			velocity.z = direction.z * current_speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, current_speed)
			velocity.z = move_toward(velocity.z, 0.0, current_speed)

	move_and_slide()
