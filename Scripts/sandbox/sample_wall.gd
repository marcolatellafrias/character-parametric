class_name SampleWall
extends RefCounted

## UN TABIQUE DE MUESTRA para ver una pieza de fachada sola: un bloque de pared con la pieza colocada en su
## frente POR EL MISMO CAMINO que en un edificio —la matriz rígida del quad de la cara
## (`RigidMatrix.from_quad`), el placer (`GridPlacer.place`) y la abertura cortada en la piel con su espesor,
## derrames y arco (`BuildingSkin.add_opening`)—, así lo que se ve en el sandbox es lo que la ciudad hace,
## y no una copia hecha a mano. El hueco atraviesa el tabique: el frente lleva los derrames y la cara de
## atrás solo el corte.

const WIDTH := 4.0
const HEIGHT := 3.6
const THICKNESS := 0.3
const WALL_COLOR := Color(0.6, 0.58, 0.55)


## La pared con `piece` colocada: `size_m` es (a lo largo, hacia afuera, hacia arriba) y `sill_m` a qué
## altura del piso arranca. La raíz queda centrada en el origen de `parent`, apoyada en y = 0, con el
## frente hacia -Z.
static func build(parent: Node3D, piece: UnitMesh, size_m: Vector3, sill_m: float, kind: int,
		arch_height_m: float, arch_segments: int) -> Node3D:
	var root := Node3D.new()
	root.name = "SampleWall"
	parent.add_child(root)

	# El tabique como piel: cinco caras (la de abajo apoya en el piso), el frente con la abertura.
	var hw := WIDTH * 0.5
	var zf := -THICKNESS * 0.5
	var zb := THICKNESS * 0.5
	var front: Array[Vector3] = [Vector3(-hw, 0.0, zf), Vector3(hw, 0.0, zf), Vector3(hw, HEIGHT, zf), Vector3(-hw, HEIGHT, zf)]
	var back: Array[Vector3] = [Vector3(hw, 0.0, zb), Vector3(-hw, 0.0, zb), Vector3(-hw, HEIGHT, zb), Vector3(hw, HEIGHT, zb)]
	var left: Array[Vector3] = [Vector3(-hw, 0.0, zb), Vector3(-hw, 0.0, zf), Vector3(-hw, HEIGHT, zf), Vector3(-hw, HEIGHT, zb)]
	var right: Array[Vector3] = [Vector3(hw, 0.0, zf), Vector3(hw, 0.0, zb), Vector3(hw, HEIGHT, zb), Vector3(hw, HEIGHT, zf)]
	var top: Array[Vector3] = [Vector3(-hw, HEIGHT, zf), Vector3(hw, HEIGHT, zf), Vector3(hw, HEIGHT, zb), Vector3(-hw, HEIGHT, zb)]
	var skin := BuildingSkin.new(WALL_COLOR)
	skin.wall_thickness = THICKNESS
	skin.add_wall(front, Vector3.FORWARD)
	skin.add_wall(back, Vector3.BACK)
	skin.add_wall(left, Vector3.LEFT)
	skin.add_wall(right, Vector3.RIGHT)
	skin.add_wall(top, Vector3.UP)

	# La superficie del frente y la pieza, hundida en la pared como en un edificio.
	var surface := RigidMatrix.from_quad(front, RigidMatrix.WALL_DEPTH_M, Vector3.FORWARD)
	var size := surface.cells_for(size_m.x, size_m.y, size_m.z)
	var lo := Vector3i(maxi((surface.count.x - size.x) / 2, 0), 0,
		clampi(roundi(sill_m / surface.cell.z), 0, maxi(surface.count.z - size.z, 0)))
	var buffer := GridPlacer.new_buffer()
	var placer := GridPlacer.new(CityIndex.new(), 0, 0, buffer)
	var sink := floori(THICKNESS / surface.cell.y)
	if placer.place(surface, lo, size, piece, kind, 0, 0, 0, 0, sink):
		var hole := opening_quad(surface, lo, size)
		skin.add_opening(hole, Vector3.FORWARD, arch_height_m, arch_segments)
		var through: Array[Vector3] = []
		for p in hole:
			through.append(p + Vector3(0.0, 0.0, THICKNESS))
		skin.add_opening(through, Vector3.BACK, arch_height_m, arch_segments, false)
	else:
		push_warning("[SampleWall] la pieza no entra en el tabique: %s celdas en %s" % [size, surface.count])

	var wall := MeshInstance3D.new()
	wall.mesh = skin.build()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	wall.material_override = material
	root.add_child(wall)
	root.add_child(GridPlacer.bake_mesh(buffer))
	return root


## Las cuatro esquinas, en el mundo, de la cara de una región sobre su superficie: la abertura que deja.
static func opening_quad(surface: RigidMatrix, lo: Vector3i, size: Vector3i) -> Array[Vector3]:
	return [
		surface.cell_to_world(Vector3(lo.x, 0.0, lo.z)),
		surface.cell_to_world(Vector3(lo.x + size.x, 0.0, lo.z)),
		surface.cell_to_world(Vector3(lo.x + size.x, 0.0, lo.z + size.z)),
		surface.cell_to_world(Vector3(lo.x, 0.0, lo.z + size.z)),
	]
