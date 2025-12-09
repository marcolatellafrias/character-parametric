class_name Building extends RefCounted

# Vértices del quad [BL, BR, TR, TL]
var vertices: Array[Vector3]

# Tipos de edges [north, east, south, west]
var edge_types: Array[int]


func _init(
	p_vertices: Array[Vector3],
	p_edge_types: Array[int]
) -> void:
	vertices = p_vertices
	edge_types = p_edge_types


func get_vertex(index: int) -> Vector3:
	if index < 0 or index >= vertices.size():
		return Vector3.ZERO
	return vertices[index]


func get_edge_type(side: String) -> int:
	match side:
		"north":
			return edge_types[0]
		"east":
			return edge_types[1]
		"south":
			return edge_types[2]
		"west":
			return edge_types[3]
		_:
			return DistortedGrid.CellType.NORMAL
