class_name DashboardPreset
extends Resource

# fixed_slots are placed first in order; conflicts are skipped silently.
# If fill_remaining_random = true, leftover cells are filled with the seeded RNG.
@export var fixed_slots:           Array[DashboardSlot] = []
@export var fill_remaining_random: bool                  = true
