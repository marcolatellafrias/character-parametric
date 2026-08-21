extends Node

signal settings_changed

@export_group("Fog")
@export var fog_start_distance: float = 140.0:
	set(value):
		fog_start_distance = value
		settings_changed.emit()

@export var render_distance: float = 350.0:
	set(value):
		render_distance = value
		settings_changed.emit()

@export var fog_color: Color = Color(0.46, 0.56, 0.96):
	set(value):
		fog_color = value
		settings_changed.emit()

@export_group("Spawning")
@export var spawn_buffer: float = 150.0:
	set(value):
		spawn_buffer = value
		settings_changed.emit()

@export var max_cars: int = 100:
	set(value):
		max_cars = value
		settings_changed.emit()

var spawn_radius: float:
	get: return render_distance + spawn_buffer
