class_name SandboxEntity
extends CharacterBody3D

## EL ENTE DEL DESIGN SANDBOX: una cápsula con cámara que camina sin inercia, salta sin carga y con V
## vuela (creative), sin fricción ni nada del personaje del juego. Lo único que comparte con él es la
## interacción con controllables —el mismo `InteractionController` y su detector, sin brazos, sin
## animación ni fuerza de agarre: acá no se agarra ni se sienta nadie—, así una palanca de nave responde
## igual en los dos mundos. La velocidad de vuelo es menor que la del creative del juego: el sandbox es
## otra escala.

const WALK_SPEED := 4.5
const SPRINT_MULTIPLIER := 1.8
const FLY_SPEED := 6.0
const JUMP_SPEED := 5.0
const GRAVITY := 18.0
const MOUSE_SENSITIVITY := 0.002
const EYE_HEIGHT := 1.6
const REACH_M := 3.0

var flying := false
var _yaw := 0.0
var _pitch := 0.0
var _camera: Camera3D = null
var _interaction: InteractionController = null


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	_camera.current = true
	add_child(_camera)

	_interaction = InteractionController.new()
	add_child(_interaction)
	_interaction.setup(self, _camera, null, null, REACH_M, null)


func _input(event: InputEvent) -> void:
	if not UIState.gameplay_active():
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var sensitivity := MOUSE_SENSITIVITY * _interaction.get_camera_sensitivity_factor()
		_yaw -= motion.relative.x * sensitivity
		_pitch = clampf(_pitch - motion.relative.y * sensitivity, -1.4, 1.4)
		rotation.y = _yaw
		_camera.rotation.x = _pitch
		_interaction.apply_controlled_motion(motion.relative)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					_interaction.try_interact()
				else:
					_interaction.release_interact()
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_interaction.adjust_distance(-1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_interaction.adjust_distance(1.0)
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.keycode == KEY_V:
			flying = not flying
			velocity = Vector3.ZERO


func _physics_process(delta: float) -> void:
	_interaction.update(delta)
	var input := Vector2.ZERO
	if UIState.gameplay_active():
		if Input.is_physical_key_pressed(KEY_A):
			input.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D):
			input.x += 1.0
		if Input.is_physical_key_pressed(KEY_W):
			input.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S):
			input.y += 1.0
	input = input.limit_length(1.0)
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var sprint := SPRINT_MULTIPLIER if Input.is_physical_key_pressed(KEY_SHIFT) and not flying else 1.0

	if flying:
		# Sin gravedad: la dirección es la de la cámara, arriba con espacio, abajo con shift.
		var look := -_camera.global_transform.basis.z
		var move := (look * -input.y + right * input.x)
		var vertical := 0.0
		if Input.is_physical_key_pressed(KEY_SPACE):
			vertical += 1.0
		if Input.is_physical_key_pressed(KEY_SHIFT):
			vertical -= 1.0
		velocity = (move + Vector3.UP * vertical).limit_length(1.0) * FLY_SPEED
	else:
		var planar := (forward * -input.y + right * input.x) * WALK_SPEED * sprint
		velocity.x = planar.x
		velocity.z = planar.z
		if is_on_floor():
			velocity.y = JUMP_SPEED if Input.is_physical_key_pressed(KEY_SPACE) else 0.0
		else:
			velocity.y -= GRAVITY * delta
	move_and_slide()
