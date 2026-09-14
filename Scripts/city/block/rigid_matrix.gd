class_name RigidMatrix
extends PlacementGrid

## LA GRILLA RÍGIDA DE UNA SUPERFICIE — donde viven los objetos que casi no se deforman: ventanas, puertas,
## tanques, balcones. Es una PlacementGrid como el módulo; lo único propio es CÓMO ELIGE SUS CELDAS.
##
## Se construye SOLO a partir de la superficie: el cuadrilátero es la superficie misma, `axis_n` su normal
## orientada hacia afuera, y la cantidad de celdas la que haga que midan lo más cerca posible de
## `TARGET_CELL_M`. La profundidad se proyecta hacia afuera con el mismo tamaño de celda. Nada de esto depende
## de los objetos: la grilla existe desde el inicio, y lo único que los objetos deformables le cambian es qué
## celdas quedan DISPONIBLES (ver `mark_world_hexahedron`).
##
## ⚠ NO HAY UMBRAL DE DISTORSIÓN. Una superficie angosta o corta da pocas celdas, o ninguna, y el objeto que
## necesita más de las que hay no entra. Ese es todo el filtro.
##
## Lo que va acá SÍ SE DEFORMA, apenas: es la bilineal de la superficie, igual que en el módulo, solo que
## sobre un cuadrilátero casi plano y casi paralelogramo. Una fachada es un paralelogramo exacto —cada piso es
## el de abajo subido—, así que sus celdas son paralelogramos con los lados verticales y el piso inclinado como
## el terreno, y una ventana sale con ese mismo cizallamiento: paralela a la arista del módulo Y a la línea de
## piso, como el edificio. Antes tenía un marco propio ortonormal y salía torcida respecto de una de las dos
## (medido: 1,5° de mediana, 7,4° en el peor caso). Una azotea es una silla de montar de centímetros, y la
## base de lo que se apoya la copia.
##
## En el marco de la grilla `y` SALE DE LA SUPERFICIE: arriba en una azotea, hacia la calle en una fachada,
## donde es `z` la que sube (el quad de `BuildingModule.get_facade_quad` va de abajo hacia arriba en `z`).

const TARGET_CELL_M := 0.25


## La grilla de una superficie `quad` `[c0, c1, c2, c3]` en el mundo, recorrida en orden: `x` va de c0 a c1
## y `z` de c0 a c3. `depth_m` es cuánto se proyecta hacia afuera; `outward` dice de qué lado está afuera.
static func from_quad(quad: Array[Vector3], depth_m: float, outward: Vector3) -> RigidMatrix:
	var m := RigidMatrix.new()
	if quad.size() != 4:
		return m
	var normal := (quad[2] - quad[0]).cross(quad[3] - quad[1])
	if normal.length_squared() <= 0.0:
		return m
	normal = normal.normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	var along_x := (quad[0].distance_to(quad[1]) + quad[3].distance_to(quad[2])) * 0.5
	var along_z := (quad[0].distance_to(quad[3]) + quad[1].distance_to(quad[2])) * 0.5
	# Un lado más corto que media celda da cero, y la grilla queda vacía a propósito.
	var n_x := roundi(along_x / TARGET_CELL_M)
	var n_z := roundi(along_z / TARGET_CELL_M)
	if n_x <= 0 or n_z <= 0:
		return m
	var cell_n := (along_x / float(n_x) + along_z / float(n_z)) * 0.5
	var n_n := maxi(1, ceili(depth_m / cell_n))
	m._setup(quad.duplicate(), normal, cell_n, Vector3i(n_x, n_n, n_z))
	return m


## LA MISMA GRILLA CORRIDA `offset` en el mundo, sin ocupación. Es cómo sale la fachada de un piso a partir de
## la del piso 0: cada piso es el de abajo subido en Y, así que `from_quad` daría exactamente estas celdas
## corridas. Copiar es mucho más barato que recalcular, y se hace una vez por fachada de cada piso.
func translated(offset: Vector3) -> RigidMatrix:
	var m := RigidMatrix.new()
	if not is_valid():
		return m
	var moved: Array[Vector3] = []
	for c: Vector3 in corners:
		moved.append(c + offset)
	m._setup(moved, axis_n, cell.y, count)
	return m
