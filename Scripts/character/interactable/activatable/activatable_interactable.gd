class_name ActivatableInteractable
extends Interactable

signal activated()

func get_prompt() -> String:
	return "[E] to interact"

func activate() -> void:
	activated.emit()
