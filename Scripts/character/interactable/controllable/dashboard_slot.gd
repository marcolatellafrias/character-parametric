class_name DashboardSlot
extends Resource

# cell: position in the grid (col, row)
# definition null → intentional empty cell (marked occupied, nothing placed)
@export var cell:       Vector2i          = Vector2i(0, 0)
@export var definition: ControlDefinition = null


# ─────────────────────────────────────────────────────────────────────────────
