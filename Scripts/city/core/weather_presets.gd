class_name WeatherPresets
extends RefCounted

## LOS CLIMAS — la tabla de colores del mundo, copiada de `timecyc.dat` de GTA San Andreas.
##
## La estructura es de San Andreas y vale la pena entender por qué, porque resuelve de raíz la pelea que
## tuvimos con la niebla y las siluetas:
##
##   · EL COLOR DE LA NIEBLA ES EL COLOR DE ABAJO DEL CIELO. En el timecyc son la misma columna (`Sky bot`):
##     allá la niebla no tiene color propio, ES el horizonte, y por construcción una pieza saturada queda
##     pintada de lo que tiene detrás, sin silueta posible. Los ocho presets de San Andreas conservan esa
##     regla —su `fog_color` es igual a su `sky_horizon`—, pero ACÁ NO ES LEY DEL SISTEMA: `fog_color` es
##     un campo propio, y el preset `original` lo usa para tener cielo stock con niebla azul, que es lo
##     que el juego busca. Ahí la silueta sí existe, y de ella se ocupa el fundido de entrada.
##   · EL CLIMA CAMBIA EL COLOR, NO EL ALCANCE. En las ocho entradas que copié, `FarClp` vale 2000 en TODAS.
##     San Andreas nunca te encierra más cuando hay niebla: te tiñe más. Por eso acá los presets no traen
##     distancias — esas viven en WorldSettings y son las mismas para todos los climas—.
##   · DOS CAPAS DE TINTE A PANTALLA COMPLETA (`Alpha1 RGB1`, `Alpha2 RGB2`), con alpha 195 de 255 en todas
##     las filas que vi. Es un lavado fortísimo, y es donde vive buena parte del "estilo" del juego.
##
## Los valores son los de `timecyc.dat` pasados de 0-255 a 0-1. Lo que NO es copia literal está marcado:
## el ambiente de Godot no funciona como el de RenderWare (allá `Amb` es para el mapa y `Amb_Obj` para
## peatones y autos), así que de esas dos columnas salió un color y una energía a ojo.
##
## Las entradas de atardecer y amanecer vienen de filas cuyo final no pude leer, así que su TINTE está
## tomado prestado del mediodía de su misma ciudad. Si algún día se consigue la fila completa, se corrige.
##
## EL SOL VA EN DOS LUCES, y conviene saber por qué: en Godot `light_angular_distance` controla a la vez
## el TAMAÑO DEL DISCO que dibuja el cielo y la BLANDURA DE LA SOMBRA (simula el tamaño angular del sol,
## que en la realidad es 0,53°). Con un disco grande y lindo las sombras entre edificios se difuminan
## hasta desaparecer. Por eso `sun_size` (el disco) y `shadow_softness` (la sombra) son campos separados,
## y CityFog usa una luz para cada cosa.
##
## `sun_core` y `sun_size` sí salen del timecyc (columnas `SunCore` y `SunSz`), y traen un detalle
## que vale la pena copiar: en LLUVIA y TORMENTA DE ARENA el tamaño es **0**, o sea que San Andreas
## directamente no dibuja el sol —sigue habiendo luz direccional, pero no hay disco—. En cambio la
## POSICIÓN del sol (`sun_elevation`, `sun_azimuth`) NO está en el timecyc: allá se calcula de la hora.
## Acá va a mano, y es lo que hace que el amanecer y el atardecer tengan sombras largas de verdad.

const PRESETS := {
	"original": {
		"name": "Original (build del 25/6)",
		"shadow_softness": 0.2,
		# El cielo de fábrica de Godot, sin tocar, y una niebla AZUL que no sale de él. Los valores son los
		# que tenía `Scenes/world_settings.tscn` en el commit deec477 (25/6/2026).
		"sky_top": Color(0.385, 0.454, 0.55),
		"sky_horizon": Color(0.804, 0.816, 0.843),
		"fog_color": Color(0.389, 0.499, 0.952),
		"sky_curve": 0.15,
		"ambient": Color(0.556, 0.632, 0.811),
		"ambient_energy": 0.35,
		# Sin filtro de pantalla: en esa build no existía.
		"tint1": Color(0.5, 0.5, 0.5),
		"tint1_alpha": 0.0,
		"tint2": Color(0.5, 0.5, 0.5),
		"tint2_alpha": 0.0,
		"sun_core": Color(1.0, 0.957, 0.902),
		"sun_size": 3.0,
		"sun_glow": 30.0,
		"sun_elevation": 62.0,
		"sun_azimuth": 35.0,
		"sun_energy": 1.35,
	},
	"despejado": {
		"sun_core": Color(1.0, 1.0, 0.98),
		"sun_size": 3.2,
		"sun_glow": 30.0,
		"sun_elevation": 62.0,
		"sun_azimuth": 35.0,
		"sun_energy": 1.35,
		"name": "Despejado (EXTRASUNNY_LA, mediodía)",
		"shadow_softness": 0.2,
		"sky_top": Color(0.286, 0.416, 0.549),
		"sky_horizon": Color(0.624, 0.651, 0.710),
		"fog_color": Color(0.624, 0.651, 0.710),
		"ambient": Color(0.667, 0.667, 0.667),
		"ambient_energy": 0.35,
		"tint1": Color(0.627, 0.627, 0.627),
		"tint1_alpha": 0.765,
		"tint2": Color(0.490, 0.537, 0.584),
		"tint2_alpha": 0.765,
		"sky_curve": 0.15,
	},
	"smog_atardecer": {
		"sun_core": Color(1.0, 0.76, 0.35),
		"sun_size": 4.0,
		"sun_glow": 45.0,
		"sun_elevation": 6.0,
		"sun_azimuth": 250.0,
		"sun_energy": 1.10,
		"name": "Smog al atardecer (SUNNY_SMOG_LA, 19h)",
		"shadow_softness": 0.6,
		"sky_top": Color(0.231, 0.294, 0.384),
		"sky_horizon": Color(0.714, 0.573, 0.376),
		"fog_color": Color(0.714, 0.573, 0.376),
		"ambient": Color(0.667, 0.667, 0.667),
		"ambient_energy": 0.30,
		"tint1": Color(0.745, 0.745, 0.745),
		"tint1_alpha": 0.765,
		"tint2": Color(0.439, 0.494, 0.557),
		"tint2_alpha": 0.765,
		"sky_curve": 0.25,
	},
	"atardecer": {
		"sun_core": Color(1.0, 0.70, 0.45),
		"sun_size": 4.5,
		"sun_glow": 50.0,
		"sun_elevation": 2.5,
		"sun_azimuth": 265.0,
		"sun_energy": 0.90,
		"name": "Atardecer (EXTRASUNNY_LA, 20h)",
		"shadow_softness": 0.6,
		"sky_top": Color(0.671, 0.404, 0.588),
		"sky_horizon": Color(0.706, 0.596, 0.443),
		"fog_color": Color(0.706, 0.596, 0.443),
		"ambient": Color(0.588, 0.588, 0.588),
		"ambient_energy": 0.28,
		"tint1": Color(0.627, 0.627, 0.627),
		"tint1_alpha": 0.765,
		"tint2": Color(0.490, 0.537, 0.584),
		"tint2_alpha": 0.765,
		"sky_curve": 0.30,
	},
	"amanecer": {
		"sun_core": Color(1.0, 0.85, 0.70),
		"sun_size": 4.0,
		"sun_glow": 40.0,
		"sun_elevation": 5.0,
		"sun_azimuth": 85.0,
		"sun_energy": 1.00,
		"name": "Amanecer (EXTRASUNNY_LA, 6h)",
		"shadow_softness": 0.5,
		"sky_top": Color(0.651, 0.608, 0.529),
		"sky_horizon": Color(0.722, 0.620, 0.514),
		"fog_color": Color(0.722, 0.620, 0.514),
		"ambient": Color(0.667, 0.667, 0.667),
		"ambient_energy": 0.30,
		"tint1": Color(0.627, 0.627, 0.627),
		"tint1_alpha": 0.765,
		"tint2": Color(0.490, 0.537, 0.584),
		"tint2_alpha": 0.765,
		"sky_curve": 0.30,
	},
	"noche": {
		"sun_core": Color(0.70, 0.78, 1.0),
		"sun_size": 0.0,
		"sun_glow": 20.0,
		"sun_elevation": 35.0,
		"sun_azimuth": 200.0,
		"sun_energy": 0.35,
		"name": "Noche (EXTRASUNNY_LA, medianoche)",
		"shadow_softness": 1.0,
		"sky_top": Color(0.216, 0.235, 0.259),
		"sky_horizon": Color(0.263, 0.286, 0.314),
		"fog_color": Color(0.263, 0.286, 0.314),
		"ambient": Color(0.471, 0.471, 0.471),
		"ambient_energy": 0.22,
		"tint1": Color(0.392, 0.420, 0.482),
		"tint1_alpha": 0.765,
		"tint2": Color(0.412, 0.447, 0.525),
		"tint2_alpha": 0.765,
		"sky_curve": 0.15,
	},
	"lluvia": {
		"sun_core": Color(1.0, 1.0, 1.0),
		"sun_size": 0.0,
		"sun_glow": 20.0,
		"sun_elevation": 55.0,
		"sun_azimuth": 120.0,
		"sun_energy": 0.90,
		"name": "Lluvia (RAINY_SF, mediodía)",
		"shadow_softness": 2.5,
		"sky_top": Color(0.251, 0.251, 0.243),
		"sky_horizon": Color(0.514, 0.510, 0.502),
		"fog_color": Color(0.514, 0.510, 0.502),
		"ambient": Color(0.667, 0.667, 0.667),
		"ambient_energy": 0.30,
		"tint1": Color(0.549, 0.549, 0.549),
		"tint1_alpha": 0.765,
		"tint2": Color(0.667, 0.667, 0.667),
		"tint2_alpha": 0.765,
		"sky_curve": 0.15,
	},
	"niebla": {
		"sun_core": Color(1.0, 1.0, 1.0),
		"sun_size": 0.5,
		"sun_glow": 20.0,
		"sun_elevation": 40.0,
		"sun_azimuth": 150.0,
		"sun_energy": 0.80,
		"name": "Niebla espesa (FOGGY_SF, mediodía)",
		"shadow_softness": 2.5,
		"sky_top": Color(0.439, 0.439, 0.439),
		"sky_horizon": Color(0.510, 0.510, 0.510),
		"fog_color": Color(0.510, 0.510, 0.510),
		"ambient": Color(0.667, 0.667, 0.667),
		"ambient_energy": 0.32,
		"tint1": Color(0.549, 0.549, 0.549),
		"tint1_alpha": 0.765,
		"tint2": Color(0.667, 0.667, 0.667),
		"tint2_alpha": 0.765,
		"sky_curve": 0.15,
	},
	"tormenta_arena": {
		"sun_core": Color(1.0, 0.92, 0.78),
		"sun_size": 0.0,
		"sun_glow": 20.0,
		"sun_elevation": 50.0,
		"sun_azimuth": 300.0,
		"sun_energy": 1.00,
		"name": "Tormenta de arena (SANDSTORM_DESERT, mediodía)",
		"shadow_softness": 2.0,
		"sky_top": Color(0.604, 0.565, 0.490),
		"sky_horizon": Color(0.671, 0.663, 0.643),
		"fog_color": Color(0.671, 0.663, 0.643),
		"ambient": Color(0.667, 0.667, 0.667),
		"ambient_energy": 0.30,
		"tint1": Color(0.784, 0.643, 0.486),
		"tint1_alpha": 0.765,
		"tint2": Color(0.694, 0.635, 0.522),
		"tint2_alpha": 0.765,
		"sky_curve": 0.40,
	},
}

## El orden en que F5 los recorre.
const ORDER: Array[String] = [
	"original",
	"lluvia",
	"despejado",
	"niebla",
	"amanecer",
	"atardecer",
	"smog_atardecer",
	"tormenta_arena",
	"noche",
]


## Un preset por id, con el default si no existe.
static func get_preset(id: String) -> Dictionary:
	return PRESETS.get(id, PRESETS[default_id()])


## Con cuál arranca el juego: el look que tenía la build del 25/6 —cielo stock y niebla azul oscura—, que
## es el que quedó elegido después de probar los de San Andreas.
static func default_id() -> String:
	return "original"


## Los ids que existen de verdad, en el orden de `ORDER` (saltea los que la tabla no tenga).
static func ids() -> Array[String]:
	var out: Array[String] = []
	for id in ORDER:
		if PRESETS.has(id):
			out.append(id)
	return out


## El siguiente en la rueda, volviendo al principio.
static func next_id(current: String) -> String:
	var all := ids()
	if all.is_empty():
		return default_id()
	var index := all.find(current)
	return all[(index + 1) % all.size()]
