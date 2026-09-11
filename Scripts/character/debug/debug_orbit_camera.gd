class_name DebugOrbitCamera
extends Camera3D

## Tercera persona SOLO para debug: mirar desde afuera las animaciones y los agarres del personaje.
##
## Es puramente visual — el rayo de interacción sigue saliendo de la cámara de primera persona — y se
## maneja entera con el numpad, así el mouse queda con el personaje: se puede agarrar una palanca y
## moverla con una mano mientras la otra rodea al personaje.
##
##   5            primera ↔ tercera persona (lo maneja PlayerController)
##   4 / 6        rodear (sostenido)
##   8 / 2        subir / bajar la cámara (sostenido)
##   + / −        acercar / alejar (sostenido)
##   1 / 3 / 7    frente / derecha / arriba
##   9            el lado opuesto al actual
##   0            atrás, el ángulo por defecto
##
## Cualquiera de estas teclas pasa a tercera persona. El ángulo es de MUNDO, no relativo al personaje:
## si él gira, la cámara no se va con él y el encuadre del agarre se mantiene. Las vistas 0/1/3/7 se
## toman respecto de hacia dónde mira el personaje al apretarlas.
##
## Un punto marca dónde pega la mira del personaje (o la punta del rayo, si no pega en nada), dibujado
## por encima de todo: desde afuera no hay otra forma de saber qué tiene en la mira.

const ORBIT_SPEED   := PI * 0.5   # rad/s
const PITCH_SPEED   := PI / 3.0   # rad/s
const PITCH_MIN     := -PI / 3.0  # desde abajo, para ver manos y pies
const PITCH_MAX     := PI * 0.5   # cenital
const DEFAULT_PITCH := PI / 12.0
## El zoom es ADIMENSIONAL: multiplica la distancia a la que el personaje entra justo en cuadro. 1.0 =
## encuadrado exacto, no se acerca más. Al ser un múltiplo vale igual para cualquier altura.
const ZOOM_SPEED    := 2.0
const ZOOM_MAX      := 8.0
## Aire alrededor del personaje con el zoom al mínimo, para que no quede pegado a los bordes.
const FRAME_MARGIN  := 1.15
## Diámetro del punto de mira como fracción de su distancia a la cámara: tamaño constante en pantalla.
const MARKER_SIZE   := 0.012

const KEYS: Array[Key] = [KEY_KP_0, KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_6, KEY_KP_7,
		KEY_KP_8, KEY_KP_9, KEY_KP_ADD, KEY_KP_SUBTRACT]

var yaw   := 0.0
var pitch := DEFAULT_PITCH
var zoom  := 2.5
var _has_view := false
var _marker: MeshInstance3D


func _init() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Sin test de profundidad y en el pase transparente (que va después de lo opaco): se ve a través
	# de la cabeza y de las paredes.
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.albedo_color  = Color(0.1, 0.9, 1.0)
	_marker = MeshInstance3D.new()
	_marker.mesh              = sphere
	_marker.material_override = mat
	_marker.cast_shadow       = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.top_level         = true
	_marker.visible           = false
	add_child(_marker)


func set_active(on: bool) -> void:
	current = on
	_marker.visible = on


## La primera vez que se entra a tercera persona, la cámara arranca atrás del personaje.
func ensure_view(character_yaw: float) -> void:
	if not _has_view:
		_set_view(character_yaw, DEFAULT_PITCH)


## Tecla apretada (las sostenidas se leen en `follow`). true si es de esta cámara.
func handle_key(key: Key, character_yaw: float) -> bool:
	if key not in KEYS:
		return false
	ensure_view(character_yaw)
	match key:
		KEY_KP_0: _set_view(character_yaw, DEFAULT_PITCH)
		KEY_KP_1: _set_view(character_yaw + PI, 0.0)
		KEY_KP_3: _set_view(character_yaw + PI * 0.5, 0.0)
		KEY_KP_7: _set_view(character_yaw, PITCH_MAX)
		KEY_KP_9: _set_view(yaw + PI, pitch)
	return true


## Cada frame en tercera persona. `center` es el centro del personaje y `height` su altura: la distancia
## mínima es la que lo hace entrar justo en cuadro (trigonometría del FOV).
func follow(delta: float, center: Vector3, height: float, aim_point: Vector3) -> void:
	yaw  += _axis(KEY_KP_6, KEY_KP_4) * ORBIT_SPEED * delta
	pitch = clampf(pitch + _axis(KEY_KP_8, KEY_KP_2) * PITCH_SPEED * delta, PITCH_MIN, PITCH_MAX)
	zoom  = clampf(zoom + _axis(KEY_KP_SUBTRACT, KEY_KP_ADD) * ZOOM_SPEED * delta, 1.0, ZOOM_MAX)

	# Armada con la base y no con look_at: así la vista cenital no se degenera.
	var fit := (height * 0.5 * FRAME_MARGIN) / tan(deg_to_rad(fov) * 0.5)
	var b   := Basis.from_euler(Vector3(-pitch, yaw, 0.0))
	global_transform = Transform3D(b, center + b.z * fit * zoom)

	_marker.global_position = aim_point
	_marker.scale = Vector3.ONE * global_position.distance_to(aim_point) * MARKER_SIZE


func _set_view(new_yaw: float, new_pitch: float) -> void:
	yaw       = new_yaw
	pitch     = new_pitch
	_has_view = true


static func _axis(positive: Key, negative: Key) -> float:
	return float(Input.is_key_pressed(positive)) - float(Input.is_key_pressed(negative))
