class_name ControlDefinition
extends Resource

enum ControlType { TOUCH, ONE_AXIS, TWO_AXIS, ROTATING }

@export var label:       String      = ""
@export var type:        ControlType = ControlType.TOUCH
@export var grid_size:   Vector2i    = Vector2i(1, 1)
@export var custom_mesh: Mesh        = null

@export_group("Shared")
@export var auto_return:   bool         = false
@export var default_value: float        = 0.0
@export var positions:     Array[float] = []

@export_group("OneAxis / TwoAxis")
@export var sensitivity:         float   = 0.005
@export var max_angle_degrees:   float   = 45.0
@export var rotation_axis_local: Vector3 = Vector3.RIGHT
@export var rest_rotation_deg:   Vector3 = Vector3.ZERO

@export_group("Touch")
@export var is_toggle: bool = false

@export_group("Rotating")
@export var rotate_sensitivity: float = 0.05
@export var height_offset:      float = 0.0
