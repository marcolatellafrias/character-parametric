class_name DashboardPreset
extends Resource

# fixed_slots are placed first in order; conflicts are skipped silently.
# If fill_remaining_random = true, leftover cells are filled with the seeded RNG.
@export var fixed_slots:           Array[DashboardSlot] = []
@export var fill_remaining_random: bool                  = true


## Un tablero de un solo control, `definition` en `cell`, y nada más: los botones de la compuerta y del
## portón, el atril del sandbox.
static func single(definition: ControlDefinition, cell := Vector2i.ZERO) -> DashboardPreset:
	var slot := DashboardSlot.new()
	slot.cell = cell
	slot.definition = definition
	var preset := DashboardPreset.new()
	preset.fill_remaining_random = false
	var slots: Array[DashboardSlot] = [slot]
	preset.fixed_slots = slots
	return preset
