class_name AnimationInputs
extends RefCounted
## Entrada explícita del pipeline de animación: todo lo que la pose necesita saber del estado del
## personaje, en un solo lugar. Un "productor" (BoneInstantiator._update_animation_inputs) lo llena
## cada frame — hoy desde la cápsula física; a futuro desde la red + raycasts locales en un proxy.
## Los módulos de animación LEEN de acá en vez de meter mano en char_rigidbody/controllers.
##
## Refactor de desacople (etapa 1: locomotion_signals). Ver technical/character-animation.md.

# ── Transform / movimiento ──
var velocity: Vector3 = Vector3.ZERO       # velocidad de movimiento (world) → pasos, lean
var basis: Basis = Basis()                 # orientación del cuerpo (yaw)
var origin: Vector3 = Vector3.ZERO         # posición del cuerpo
var grounded: bool = true                  # pies plantados vs recogidos
var ground_point: Vector3 = Vector3.ZERO   # punto de contacto con el piso

# ── Impacto (stagger) ──
var impact_y: float = 0.0
var impact_xz: Vector2 = Vector2.ZERO

# ── Pose de cuerpo ──
var crouch_t: float = 0.0
var jump_squat_t: float = 0.0
## Pitch de mirada (cabeza/columna, mirar arriba/abajo), ya clampeado. Local: cámara; proxy: red.
var head_pitch: float = 0.0

# ── Agarre ──
## El interactuable cuyos handle/grab points alcanzan los brazos: un GrabbableInteractable agarrado o
## un ControllableInteractable que se maneja (o null). El resto (handles, grab point, origen del
## pecho) se deriva local. En un proxy lo llena la red (CharacterNetSync); local, su InteractionController.
var grab_target: Node = null
