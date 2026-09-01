class_name SkeletonSizesUtil

var leg_height : float
var torso_height : float
var head_height : float
var hips_width : float
var shoulders_width : float
## Largo de la cadena del brazo (hombro→muñeca) en metros. Reemplaza a `EntityArchetype.reach`, que
## ya no existe: el largo del brazo sale del rango del modelo, no de un número autorado.
var arm_reach : float
## Hasta dónde llega a agarrar, en metros: `arm_reach × arm_stretch × 0.97`. Reemplaza a
## `reach × reach_multiplier` con la misma división de responsabilidades — largo del brazo y cuánto
## estira son DOS variables de arquetipo independientes. Ver "The arm reach problem" en el doc.
var interaction_reach : float
## Cuánto estira el brazo este personaje al agarrar, en múltiplos de su reposo. Sale del arquetipo,
## ya clampeado al rango que se esculpió en Blender.
var arm_stretch : float
## Altura total del personaje, en metros. Es un RESULTADO (pierna + torso + cabeza), no una entrada.
var total_height : float

var head_size: Vector3
var neck_size: Vector3
var chest_size: Vector3
var higher_spine_size: Vector3
var lower_spine_size: Vector3
var higher_leg_size: Vector3
var lower_leg_size: Vector3
var foot_size: Vector3
var lower_feet_size: Vector3
var upper_arm_size: Vector3
var lower_arm_size: Vector3
var shoulder_width: Vector3
var hip_size: Vector3
var raycast_stance_offset: float

# ── MARCHA ────────────────────────────────────────────────────────────────────────────────────────
# Todo esto se deriva del knob `stride` del arquetipo. Ver technical/character-animation.md.

## Extensión máxima de la cadena de la pierna, en fracción de su largo. Es el TECHO de la IK: pasado
## esto, `BoneInstantiator._update_pelvis_drop` considera que el pie no llega y baja la pelvis.
##
## ⚠ TIENE QUE SER ≥ STAND_EXTENSION_STRAIGHT, o la pose de reposo es inalcanzable por definición.
## Estuvo en 0.95 contra un reposo de 0.99, y el efecto era el opuesto al buscado: **parado y quieto**
## el déficit daba 3.8 cm, la pelvis bajaba sola, y `root_bounciness` lo exageraba hasta 4.9 cm. O
## sea que todo lo que `leg_bentness` pidiera por encima de 0.95 se descartaba, y el arquetipo que
## pedía la pierna MÁS RECTA terminaba siendo el más flexionado, por generar el mayor déficit.
##
## Esa es la razón de que sea 0.99 y no un número "cómodo": el margen para terreno irregular ya lo da
## la caída de pelvis, que existe justo para eso. Este techo no tiene que aportar margen, tiene que
## dejar que el reposo se cumpla.
const MAX_EXTENSION := 0.99
## Extensión de la pierna PARADO, en fracción de su largo. NO es un margen de seguridad (la pelvis ya
## baja sola cuando no llega): es la GARANTÍA de que la pierna alcanza el piso estando parado. Subirlo
## hacia 1.0 endereza la pierna y acerca el reposo al modelo, a cambio de trabar antes en terreno
## irregular.
## Cuánto de su largo usa la pierna estando parada. Es lo que fija la FLEXIÓN DE RODILLA en reposo, y
## el arquetipo elige dónde cae dentro de esta banda con `leg_bentness`.
##
##   0.99 → ~16° de rodilla      0.985 → 20°      0.97 → 28°      0.95 → 37°      0.90 → ~52°
##
## ⚠ El techo NO puede acercarse a 1.0, y no es un margen de seguridad: es **la garantía de que la
## pierna llega al piso estando parada**. Con la pierna estirada al 100% el objetivo de la IK queda
## justo en el límite del alcance, cualquier irregularidad del terreno lo deja fuera, y el pie se pliega
## hacia su objetivo aéreo — el personaje flota y no da un paso. Ver technical/character-animation.md.
const STAND_EXTENSION_STRAIGHT := 0.99
const STAND_EXTENSION_BENT := 0.90

## Excursión máxima del pie desde la cadera, en fracción del largo de pierna, mapeada desde `stride`.
## Ya NO se deriva de la altura de pelvis: es al revés — se elige la zancada y la pelvis baja lo que
## haga falta (ver BoneInstantiator._update_pelvis_drop). El tope existe para que la bajada no se
## vaya de rango, no por geometría.
const FOOT_REACH_MIN := 0.20
const FOOT_REACH_MAX := 0.55
## Duty factor: fracción del ciclo que el pie pasa APOYADO. Caminando >0.5 (siempre hay un pie en el
## piso, y hay doble apoyo); corriendo <0.5 (hay fase de vuelo con los dos pies en el aire).
const DUTY_WALK := 0.62
const DUTY_RUN  := 0.40

## Excursión máxima del pie desde la cadera, en metros. Es una ELECCIÓN (sale de `stride`), no una
## consecuencia de la altura de pelvis: la pelvis se acomoda para que el pie llegue.
var foot_reach: float
## EXCURSIÓN del pie de este frame (A, metros): cuánto se adelanta/atrasa el pie respecto de la
## cadera. El pie pisa en +A y despega en −A, así que su recorrido en el marco del cuerpo es 2A.
var current_excursion: float
## ZANCADA de este frame (S, metros): lo que avanza el cuerpo en un ciclo completo de un pie.
## Durante el apoyo (fracción D del ciclo) el pie está fijo en el mundo, o sea que en el marco del
## cuerpo retrocede D·S; y ese recorrido tiene que ser exactamente 2A ⇒ **S = 2A/D**. De ahí sale la
## cadencia: f = v/S. No es un parámetro libre — se deriva de la geometría y del duty.
var current_stride: float
var current_duty: float

var step_height: float
## Altura del TOBILLO sobre el piso, o sea el grosor de pie/zapato. Sale del modelo (en Blender la
## planta apoya en 0). Es lo que separa "el pie apoya" de "el tobillo toca el piso".
var ankle_height: float
## Altura de la pelvis parado, en metros sobre el piso. Sale del modelo (ReferenceRig).
var standing_pelvis_height: float
var distance_from_ground: float
var raycast_leg_lenght: float
var pole_distance: float
var axis_weight_lateral:  float = 0.6
var axis_weight_forward:  float = 0.8
var axis_weight_backward: float = 1.0

## ── SLOUCH: SOLO HACIA ADELANTE ───────────────────────────────────────────────────────────────────
## El encorvado es `chest` y `neck` inclinándose hacia adelante, y nada más.
##
## Antes era una **S**: `higher_spine` se arqueaba hacia ATRÁS (+0.6 rad) y `chest`/`neck` hacia
## adelante (−0.6), así que los hombros quedaban casi en su lugar y lo único que se veía encorvado era
## la cabeza. Mucha maquinaria para poca lectura, y difícil de tunear porque los dos términos se
## cancelaban entre sí. Ahora los grados que se piden son los grados que se ven.
##
## Los máximos bajaron al sacar el contra-arqueo: sin nada que compense, el 0.6 del pecho inclinaba el
## torso entero 34°. `chest` 0.35 (20°) + `neck` 0.45 (26°) acumulan 46° en la cabeza, que es un
## encorvado marcado sin doblar al personaje al medio.
##
## LOS DOS ARRANCAN EN CERO. El cuello tenía un piso de 0.2 rad que compensaba el reposo del modelo
## viejo; el esqueleto se re-posicionó para que **derecho sea la postura natural**, así que ese piso
## dejó de tener sentido y además ensuciaría un futuro parámetro de largo de cuello.
var slouchiness_chest: float
var slouchiness_neck: float
## ── POSTURA DE HOMBRO, en radianes ────────────────────────────────────────────────────────────────
## Salen de sus propios knobs de arquetipo (`shoulders_forward` / `shoulders_drop`), NO del slouch.
##
## Los dos son giros sobre ejes del MUNDO y van espejados entre lados, así que las dos articulaciones
## se mueven juntas en vez de rotar el torso: `forward` sobre la vertical, `drop` sobre el eje frontal.
##
## Los topes son chicos a propósito. Los hombros no "se cierran" mucho aunque la espalda esté vencida,
## y pasarse acá se lee como brazos cruzados y no como postura.
##
## ⚠ NO pasan por `lerp_range`, que clampea a 0..1: acá el knob es un factor CON SIGNO. Negativo es una
## postura tan válida como positiva —hombros atrás y pecho abierto, o hombros levantados— y clamparla
## a cero las perdía sin avisar.
const SHOULDER_FORWARD_MAX := 0.12
const SHOULDER_DROP_MAX := 0.10
var shoulder_forward: float
var shoulder_drop: float

var arm_openness_angle: float
var arm_bentness: float
## Hacia dónde apunta el codo, 0..1 (0 = adentro, 0.5 = atrás, 1 = afuera). Constante por ahora:
## era por arquetipo y se simplificó mientras se cierra el personaje genérico.
const ELBOW_POLE_DIRECTION := 0.7
var left_arm_tip_rest_local: Vector3
var right_arm_tip_rest_local: Vector3
var left_arm_pole_rest_local: Vector3
var right_arm_pole_rest_local: Vector3

var left_arm_shoulder_rest_local: Vector3
var right_arm_shoulder_rest_local: Vector3


var raycast_start_y_offset: float = 0.0

const CONST_HEAD_HEIGHT    := 0.378
const CONST_HEAD_RADIUS_XZ := 0.19

# ── LARGOS DE HUESO: EL MODELO DE BLENDER MANDA ───────────────────────────────────────────────────
# Todos los largos salen de rangos medidos del modelo, NO de `height` × proporciones. El arquetipo
# solo aporta un 0..1 por cadena (legs_length / arms_length / torso_length) y acá se convierte a
# metros. Consecuencia buscada: `height` deja de ser una entrada y pasa a ser un RESULTADO — ver
# `total_height`. Si un arquetipo quisiera un largo fuera del rango, gana el rango.
#
# SOLO QUEDA EL TORSO ACÁ. El brazo y la pierna ya tienen sus dos extremos autorados en Blender y
# pasan por `authored_chain`: para ellos el modelo es el 0.0 y el 1.0 es el modelo × factor.
#
# Para el torso el esquema sigue siendo provisorio: el largo esculpido es el 0.5 y los extremos son
# factores sobre él, hasta que estén modelados. El largo esculpido se LEE DEL RIG — no se transcribe.
# Antes eran constantes copiadas de un volcado, y quedaban viejas en silencio en cuanto se re-exportaba
# el modelo: el rig lógico seguía pidiendo las proporciones de la versión anterior y el espejo estiraba
# la malla para cumplirlas. Ver technical/character-blender-length-variable.md.
const LENGTH_MIN_FACTOR := 0.65
const LENGTH_MAX_FACTOR := 1.30

## ── BRAZO: LA BANDA DEL ARQUETIPO DENTRO DEL RANGO DE BLENDER ─────────────────────────────────────
## El brazo ya NO usa el esquema provisorio de arriba: tiene sus dos extremos autorados, el 0.0 es el
## modelo tal cual viene y el 1.0 es ese modelo × ARM_MODEL_FACTOR.
##
## Pero `arms_length` del arquetipo NO mapea a 0..1 completo, y no es un descuido: en Blender el 1.0
## es "brazo totalmente extendido alcanzando", no "personaje de brazos largos" — son cosas distintas.
## Con factor ×4 la distinción deja de ser teórica: un personaje parado con el brazo en 1.0 mediría
## 1.49 m de hombro a muñeca. Así que el arquetipo elige PROPORCIÓN DE CUERPO dentro de esta banda, y
## el agarre es lo único que empuja por encima de ella.
##
## Calibrada contra hombro→PUNTA DE LOS DEDOS, no contra hombro→muñeca. La mano son 0.158 m más allá
## de la muñeca y es lo que se ve; medir solo la cadena daba un brazo que en pantalla llegaba casi a
## la rodilla.
##
## EL PISO ES 0.00 y es el brazo tal cual se esculpió en Blender: no hay nada más corto. Ahí vive
## `kid`, y para eso se acortó la base del brazo en Blender (0.471 → 0.330). Antes de ese re-baseo el
## chico tenía los brazos proporcionalmente MÁS LARGOS que cualquiera, y no había número acá que lo
## arreglara.
##
## EL TECHO NO ES A OJO, SE DERIVA. El brazo más largo, estirado al máximo por el agarre, tiene que
## caer JUSTO en el máximo autorado en Blender — ni más (el correctivo se clampea y la malla se ve de
## goma) ni mucho menos (se desperdicia rango esculpido). Eso es:
##
##     cadena(ext) · stretch = cadena_modelo · F        ⇒  ext = (F/stretch − 1) / (F − 1)
##
## Con F = 4 y stretch = 2 da exactamente 1/3, o sea que el arquetipo más largo tiene el DOBLE del
## brazo del modelo y estirado llega al ×4 justo. Antes esto era un número puesto a mano (0.09, después
## 0.15) y `tall_lanky` se pasaba un 3%.
##
## ⚠ SUBIR EL TECHO ALARGA A TODOS, porque `arms_length` es una fracción de la banda. Cada vez que se
## mueve hay que re-pinchar el `arms_length` de los arquetipos para que solo cambie el que se quiere
## cambiar. Con el techo en 1/3 la cuenta es directa: `k = largo_deseado / cadena_modelo − 1`.
##
## ⚠ Estos números dependen de `rig.arm_chain`, que sale del .glb. Si se remodela el brazo en Blender,
## HAY QUE REVISAR ESTA BANDA: ya pasó — la cadena creció de 0.372 a 0.471 en un remodelado y un
## recorte del 12%% acá terminó dando un brazo más largo que antes.
##
## Calibrada contra hombro→PUNTA DE LOS DEDOS: la mano son 0.180 m más allá de la muñeca y es lo que
## se ve.
const ARM_EXT_MIN := 0.00
## El estirón para el que se dimensiona la banda. Es el `arm_stretch` que usan todos los arquetipos;
## `MAX_ARM_STRETCH` es aparte y es solo un tope de seguridad.
const DESIGN_ARM_STRETCH := 2.0
const ARM_EXT_MAX := (ReferenceRig.ARM_MODEL_FACTOR / DESIGN_ARM_STRETCH - 1.0) / (ReferenceRig.ARM_MODEL_FACTOR - 1.0)



## Extensión máxima del brazo en reposo, en fracción de su cadena.
##
## NUNCA 1.0: a extensión total el codo queda colineal, el plano de flexión se indefine y la torsión de
## la mano sale arbitraria — resuelta por una cuenta en espacio mundo, o sea distinta según hacia dónde
## mire el personaje. Fue el bug de las manos dadas vuelta.
##
## Es el PISO de la flexión: con `arm_bentness = 0` el codo se queda con lo que este tope deje.
##   0.97 → 28°     0.985 → 20°     0.99 → 16°     1.0 → 0° y roto
## En 0.985 el codo sigue claramente fuera del eje, así que el pole tiene plano definido y sobra
## margen. Si alguna vez vuelven a aparecer manos dadas vuelta, este es el primer sospechoso.
const ARM_REST_EXTENSION := 0.99

## Techo ABSOLUTO del estiramiento, en múltiplos del largo en reposo. Es una red de seguridad, no la
## perilla: quien elige cuánto estira cada personaje es `EntityArchetype.arm_stretch`. Esto solo
## impide que un arquetipo pida un brazo fuera del rango que se esculpió en Blender, donde el shape
## key ya no tiene con qué corregir la silueta y la malla sí se ve de goma.
##
## 2.5 sobre el genérico (escala 1.54) da 0.98 del rango autorado — o sea justo el borde del ×4.
const MAX_ARM_STRETCH := 2.5

static func create(inst: EntityInstantiation) -> SkeletonSizesUtil:
	var skelSizes = SkeletonSizesUtil.new()
	var entityStats := inst.arch_final
	var rig := ReferenceRig.get_rig()

	# Las tres cadenas paramétricas: 0..1 del arquetipo → metros, dentro del rango del modelo.
	var new_leg_height   := leg_chain_for(rig, entityStats.legs_length)
	var new_torso_height := torso_chain_for(rig, entityStats.torso_length)
	var new_arm_length   := arm_chain_for(rig, lerp_range(ARM_EXT_MIN, ARM_EXT_MAX, entityStats.arms_length))
	# Cuánto se aparta esta pierna de la del modelo: escala lo que se lee del rig (estancia, tobillo).
	var leg_scale: float = new_leg_height / rig.leg_chain if rig.leg_chain > 0.0 else 1.0
	# Todavía sin parametrizar (fase 3): quedan en el largo esculpido.
	# Todavía sin parametrizar (fase 3): quedan en el largo esculpido, leído del rig.
	var new_head_height       := rig.neck_len + rig.head_len
	# EL ANCHO DEL FRAME SALE DE LA MASA, no de un knob propio. El hueso de hombro y el de cadera están
	# horizontales en el modelo, así que alargarlos mueve el brazo y la pierna hacia AFUERA sin bajarlos
	# — `upper.arm` y `higher.leg` son hijos y los siguen gratis (con `Inherit Scale = None`, para que se
	# corran sin engordarse).
	var new_hips_width        := authored_chain(rig.hip_len, ReferenceRig.HIPS_MODEL_FACTOR, entityStats.fat)
	var new_shoulders_width   := authored_chain(rig.shoulder_len, ReferenceRig.FRAME_MODEL_FACTOR, entityStats.muscle)

	skelSizes.arm_reach = new_arm_length
	# Alcance de interacción: hasta dónde puede agarrar, derivado del brazo y no autorado. El 0.97 es
	# el GRAB_MIN_BEND_FACTOR de ArmsController — con ese techo el brazo nunca se estira más de
	# MAX_ARM_STRETCH veces su largo esculpido.
	# El estirón nunca puede pedir más brazo del que se esculpió: pasado `cadena_modelo × F` el
	# correctivo se clampea en 1 y la malla se estira sin nada que corrija la silueta — se ve de goma.
	# El tope sale del MODELO, no de una constante, así que no puede quedar viejo cuando se re-esculpe.
	# Con la banda derivada de arriba esto no llega a activarse; está para que no pueda volver a pasar.
	var authored_max := rig.arm_chain * ReferenceRig.ARM_MODEL_FACTOR
	skelSizes.arm_stretch = minf(minf(entityStats.arm_stretch, MAX_ARM_STRETCH),
		authored_max / maxf(new_arm_length, 0.001))
	skelSizes.interaction_reach = new_arm_length * skelSizes.arm_stretch * 0.97
	# `height` ya no es una entrada: es esto. Lo lee la cápsula, la cámara y el panel de debug.
	skelSizes.total_height = new_leg_height + new_torso_height + new_head_height

	skelSizes.leg_height      = new_leg_height
	skelSizes.torso_height    = new_torso_height
	skelSizes.head_height     = new_head_height
	skelSizes.hips_width      = new_hips_width
	# La estancia sale del MODELO, no del ancho de cadera. Si el pie en reposo no cae donde el modelo lo
	# tiene, la tibia queda girada respecto de él y el pie —que cuelga rígido de la tibia— hereda ese
	# giro: eran los pies apuntando para adentro. `stance_width` queda como multiplicador encima.
	# LA ESTANCIA ES EL ANCHO DE CADERA, literalmente. En el modelo la pierna es vertical —la punta de
	# `hip.L` y `foot.L` comparten X exacto—, así que el pie cae justo debajo de la articulación y no hay
	# nada más que calcular.
	#
	# Antes era `foot_rest_x * leg_scale`, de cuando la pierna venía inclinada en el modelo y el pie no
	# caía bajo la cadera. Ese `leg_scale` hacía que **alargar la pierna separara los pies**: el genérico,
	# con la pierna a 1.59×, se paraba con 0.411 m entre pies contra los 0.2585 del modelo.
	skelSizes.raycast_stance_offset = new_hips_width * inst.arch_final.stance_width
	skelSizes.shoulders_width = new_shoulders_width

	if entityStats.has_neck:
		var neck_radius := lerp_range(0.05, 0.12, entityStats.muscularity)
		skelSizes.neck_size = Vector3(neck_radius, new_head_height * entityStats.head_neck_ratio, neck_radius)
		skelSizes.head_size = Vector3(CONST_HEAD_RADIUS_XZ, new_head_height * (1.0 - entityStats.head_neck_ratio), CONST_HEAD_RADIUS_XZ * 0.75)
	else:
		skelSizes.neck_size = Vector3.ZERO
		skelSizes.head_size = Vector3(CONST_HEAD_RADIUS_XZ, new_head_height, CONST_HEAD_RADIUS_XZ * 0.85)

	var chest_u_radius : float = lerp_range(0.16, 0.45, entityStats.muscularity)
	var chest_l_radius : float = lerp_range(0.16, 0.45, entityStats.muscularity)
	skelSizes.chest_size = Vector3(chest_u_radius, new_torso_height * 0.3, chest_l_radius)

	var higher_spine_u_radius : float = lerp_range(0.1, 0.3, entityStats.fatness)
	var higher_spine_l_radius : float = lerp_range(0.1, 0.3, entityStats.fatness)
	skelSizes.higher_spine_size = Vector3(higher_spine_u_radius, new_torso_height * 0.25, higher_spine_l_radius)


	var lower_spine_u_radius : float = lerp_range(0.1, 0.35, entityStats.fatness)
	var lower_spine_l_radius : float = lerp_range(0.1, 0.35, entityStats.fatness)
	skelSizes.lower_spine_size = Vector3(lower_spine_u_radius, new_torso_height * 0.2, lower_spine_l_radius)

	var shoulder_u_radius : float = lerp_range(0.08, 0.2, entityStats.muscularity)
	var shoulder_l_radius : float = lerp_range(0.08, 0.25, entityStats.muscularity)
	skelSizes.shoulder_width = Vector3(shoulder_u_radius, new_shoulders_width, shoulder_l_radius)

	var arm_total := new_arm_length
	var upper_arm_u_radius : float = lerp_range(0.06, 0.2, entityStats.muscularity)
	var upper_arm_l_radius : float = lerp_range(0.06, 0.23, entityStats.muscularity)
	skelSizes.upper_arm_size = Vector3(upper_arm_u_radius, arm_total * 0.45, upper_arm_l_radius)
	var lower_arm_u_radius : float = lerp_range(0.06, 0.13, entityStats.muscularity)
	var lower_arm_l_radius : float = lerp_range(0.06, 0.18, entityStats.muscularity)
	skelSizes.lower_arm_size = Vector3(lower_arm_u_radius, arm_total * 0.55, lower_arm_l_radius)

	var higher_leg_u_radius : float = lerp_range(0.06, 0.2, entityStats.fatness)
	var higher_leg_l_radius : float = lerp_range(0.06, 0.23, entityStats.fatness)
	skelSizes.higher_leg_size = Vector3(higher_leg_u_radius, new_leg_height * 0.45, higher_leg_l_radius)
	var lower_leg_u_radius : float = lerp_range(0.06, 0.2, entityStats.fatness)
	var lower_leg_l_radius : float = lerp_range(0.06, 0.23, entityStats.fatness)
	skelSizes.lower_leg_size = Vector3(lower_leg_u_radius, new_leg_height * 0.55, lower_leg_l_radius)
	skelSizes.foot_size = Vector3(0.1, new_leg_height * 0.2, 0.1)
	skelSizes.lower_feet_size = Vector3(0.1, new_leg_height * 0.02, 0.1)
	var hip_u_radius : float = lerp_range(0.1, 0.2, entityStats.fatness)
	var hip_l_radius : float = lerp_range(0.1, 0.2, entityStats.fatness)
	skelSizes.hip_size = Vector3(hip_u_radius, new_hips_width, hip_l_radius)

	# Largo de cada hueso: la cadena repartida en las proporciones del MODELO, leídas del rig. Va DESPUÉS del bloque que
	# arma los tamaños (que fija los radios) y ANTES de todo lo derivado (marcha, poles, targets de
	# reposo de brazos), que lee estos campos.
	# Los radios (.x/.z) NO se tocan: son la forma de la cápsula del CustomBone, que ya no se dibuja.
	# Hueso hoja = no estira malla, así que `foot_size` se queda con su fórmula derivada.
	skelSizes.lower_spine_size.y  = _share(rig, "lower_spine",  new_torso_height, rig.torso_chain)
	skelSizes.higher_spine_size.y = _share(rig, "higher_spine", new_torso_height, rig.torso_chain)
	skelSizes.chest_size.y        = _share(rig, "chest",        new_torso_height, rig.torso_chain)
	skelSizes.neck_size.y         = rig.neck_len if entityStats.has_neck else 0.0
	skelSizes.head_size.y         = rig.head_len if entityStats.has_neck else new_head_height
	skelSizes.shoulder_width.y    = rig.shoulder_len
	skelSizes.upper_arm_size.y    = _share(rig, "left_upper_arm",  new_arm_length, rig.arm_chain)
	skelSizes.lower_arm_size.y    = _share(rig, "left_lower_arm",  new_arm_length, rig.arm_chain)
	skelSizes.hip_size.y          = new_hips_width
	skelSizes.higher_leg_size.y   = _share(rig, "left_higher_leg", new_leg_height, rig.leg_chain)
	skelSizes.lower_leg_size.y    = _share(rig, "left_lower_leg",  new_leg_height, rig.leg_chain)

	skelSizes.raycast_leg_lenght = new_leg_height

	# ── Marcha: de la zancada deseada sale la altura de pelvis, y de ahí el alcance ───────────────
	# La cadena de la pierna (fémur 0.45 + tibia 0.55) mide exactamente new_leg_height. Con la cadera
	# INVERTIDO respecto de como era: antes se elegía la altura de pelvis y de ahí salía el alcance del
	# pie. Ahora se elige el alcance (la zancada) y la pelvis BAJA lo que haga falta, frame a frame,
	# midiendo si las piernas llegan (BoneInstantiator._update_pelvis_drop).
	#
	# Y la altura PARADO sale del modelo, no de una fracción del largo de pierna: en Blender la planta
	# está en 0, así que la Y del hueso raíz es literalmente a qué altura se para el personaje. Con eso
	# el reposo del juego coincide con Blender por construcción, incluida la flexión que hayas modelado
	# y el grosor de pie/zapato (que no se deduce del esqueleto, pero se mide porque el modelo apoya en
	# 0). Se escala con el largo de pierna para que un arquetipo de piernas cortas baje proporcional.
	#
	# Antes había además un margen de seguridad (STAND_EXTENSION) para que un pie en un escalón no
	# trabara la rodilla. Quedó redundante: la pelvis ya baja sola cuando las piernas no llegan, así que
	# el margen estático solo agachaba al personaje de gratis, siempre.
	# La pelvis parada se DERIVA, no se copia del modelo. Copiarla fue el error anterior: el modelo la
	# tiene a 0.8885 sobre una cadena de 0.863, o sea que la pierna no llegaba al piso ni estirada del
	# todo — el personaje flotaba y nunca daba un paso. Del modelo sale solo la altura de TOBILLO (el
	# grosor de pie/zapato, que ningún hueso puede decir), y encima va lo que la pierna alcanza.
	# ALTURA DEL TOBILLO SOBRE EL PISO: es el grosor del zapato, y NO escala con nada.
	#
	# ⚠ Este número tiene que coincidir con lo que hace la MALLA, no con lo que sería ideal. `foot` no
	# está en ninguna cadena de STRETCH_CHAINS y `_detach_children_of_stretched` lo desprende de la
	# tibia, así que `shoes_mesh` es RÍGIDO: mide 3 cm en todos los personajes.
	#
	# Estaba multiplicado por `leg_scale`, o sea asumiendo que el pie crecía con la pierna. El resultado
	# era que la IK plantaba el tobillo más arriba de lo que la suela baja y **todos los personajes
	# flotaban**: 18 mm el genérico, 25 el tall_lanky, proporcional al estirado de su pierna.
	#
	# Si algún día el pie escala (entra a una cadena, o se le da su propio factor), este número tiene
	# que volver a escalar CON ÉL.
	skelSizes.ankle_height = rig.ankle_rest_height
	var stand_extension := lerp_range(STAND_EXTENSION_STRAIGHT, STAND_EXTENSION_BENT, entityStats.leg_bentness)
	skelSizes.standing_pelvis_height = skelSizes.ankle_height + new_leg_height * stand_extension
	skelSizes.distance_from_ground = new_leg_height - skelSizes.standing_pelvis_height
	skelSizes.foot_reach = new_leg_height * lerp_range(FOOT_REACH_MIN, FOOT_REACH_MAX, inst.stride)
	skelSizes.current_duty = DUTY_WALK
	skelSizes.current_excursion = 0.0
	skelSizes.current_stride = 0.0

	skelSizes.step_height = new_leg_height * inst.step_height
	skelSizes.pole_distance = new_leg_height
	skelSizes.raycast_start_y_offset = new_leg_height * 0.35

	skelSizes.slouchiness_chest        = lerp_range(0.0, 0.35, entityStats.slouch)
	skelSizes.slouchiness_neck         = lerp_range(0.0, 0.45, entityStats.slouch)
	skelSizes.shoulder_forward         = clampf(entityStats.shoulders_forward, -1.0, 1.0) * SHOULDER_FORWARD_MAX
	skelSizes.shoulder_drop            = clampf(entityStats.shoulders_drop, -1.0, 1.0) * SHOULDER_DROP_MAX

	skelSizes.arm_openness_angle   = lerp_range(0.0, -PI * 0.25, entityStats.arm_openness)
	skelSizes.arm_bentness         = entityStats.arm_bentness

	skelSizes.left_arm_tip_rest_local   = _compute_arm_tip_local(true,  skelSizes)
	skelSizes.right_arm_tip_rest_local  = _compute_arm_tip_local(false, skelSizes)
	skelSizes.left_arm_pole_rest_local  = _compute_arm_pole_local(true,  skelSizes)
	skelSizes.right_arm_pole_rest_local = _compute_arm_pole_local(false, skelSizes)

	skelSizes.left_arm_shoulder_rest_local  = _compute_arm_shoulder_local(true,  skelSizes)
	skelSizes.right_arm_shoulder_rest_local = _compute_arm_shoulder_local(false, skelSizes)

	return skelSizes


static func _compute_arm_shoulder_local(left: bool, s: SkeletonSizesUtil) -> Vector3:
	var pos := Vector3.ZERO
	pos += Vector3(0, s.lower_spine_size.y, 0)
	pos += Vector3(0, s.higher_spine_size.y, 0)
	var b := Basis.from_euler(Vector3(-s.slouchiness_chest, 0, 0))
	pos += b * Vector3(0, s.chest_size.y, 0)
	if left:
		b = Basis.from_euler(Vector3(0, 0, deg_to_rad(90)))
	else:
		b = Basis.from_euler(Vector3(0, 0, deg_to_rad(-90)))
	pos += b * Vector3(0, s.shoulder_width.y, 0)
	return pos

static func _compute_arm_tip_local(left: bool, s: SkeletonSizesUtil) -> Vector3:
	var sign_x := -1.0 if left else 1.0
	var shoulder := _compute_arm_shoulder_local(left, s)
	# El techo es la CADENA por ARM_REST_EXTENSION, nunca la cadena entera: a extensión total el codo
	# queda colineal, el plano de flexión se indefine y la torsión sale arbitraria — o sea la mano dada
	# vuelta, distinta según hacia dónde mire el personaje. La constante existía y estaba documentada,
	# pero no la leía nadie.
	#
	# Y los radios de cápsula (.x/.z) que se sumaban acá ya no van: eran del sistema viejo, donde el
	# brazo eran dos cápsulas dibujadas y la punta caía sobre la superficie de la última. Con la malla
	# de Blender no representan nada, y sumaban ~0.10 m a un target que la cadena tiene que poder
	# alcanzar: con el brazo corto pedían MÁS que el largo del brazo, y lo dejaban colineal siempre.
	var arm_length := (s.upper_arm_size.y + s.lower_arm_size.y) * ARM_REST_EXTENSION
	var actual_distance: float = lerp(arm_length, 0.0, s.arm_bentness)
	var arm_dir := Basis(Vector3.FORWARD, s.arm_openness_angle * sign_x) * Vector3.DOWN
	return shoulder + arm_dir * actual_distance

static func _compute_arm_pole_local(left: bool, s: SkeletonSizesUtil) -> Vector3:
	var sign_x := -1.0 if left else 1.0
	var shoulder := _compute_arm_shoulder_local(left, s)
	var arm_dir := Basis(Vector3.FORWARD, s.arm_openness_angle * sign_x) * Vector3.DOWN
	var elbow := shoulder + arm_dir * s.upper_arm_size.y

	var backward := Vector3(0, 0, 1)
	var outward  := Vector3(sign_x, 0, 0)
	var pole_dir: Vector3
	if ELBOW_POLE_DIRECTION >= 0.5:
		pole_dir = backward.lerp(outward,  (ELBOW_POLE_DIRECTION - 0.5) * 2.0).normalized()
	else:
		pole_dir = backward.lerp(-outward, (0.5 - ELBOW_POLE_DIRECTION) * 2.0).normalized()

	return elbow + pole_dir * s.upper_arm_size.y * 0.8 + Vector3(0, 0, 0.5)


func update(delta: float, inputs: AnimationInputs, inst: EntityInstantiation, ik_util: IkUtil) -> void:
	_update_gait(inputs, inst.arch_final)
	ik_util.advance_gait(delta, self, inputs)

## Excursión, duty y zancada de este frame, en función de la velocidad. La excursión crece con la
## velocidad (pasos más largos al correr) pero SIEMPRE acotada por foot_reach, que ya viene del
## alcance real de la pierna — así nunca se le pide al pie un punto al que la IK no llega. El duty
## baja de caminata a carrera: >0.5 hay doble apoyo, <0.5 hay fase de vuelo. La zancada (y con ella
## la cadencia) es consecuencia de los otros dos, no un parámetro.
func _update_gait(inputs: AnimationInputs, entity_stats: EntityArchetype) -> void:
	var instant_speed := Vector2(inputs.velocity.x, inputs.velocity.z).length()
	var max_speed: float = entity_stats.speed * entity_stats.sprint_multiplier * CharacterRigidBody3D.SPEED_SCALE
	var t: float = clamp(instant_speed / max(max_speed, 0.01), 0.0, 1.0)
	current_duty      = lerp_range(DUTY_WALK, DUTY_RUN, t)
	# √t, no un lerp con piso: la excursión tiene que llegar a CERO parado. Con un piso (antes 0.35)
	# el pie apuntaba a un objetivo adelantado incluso a velocidad ~0 — la dirección está normalizada,
	# así que a 0.001 m/s la colocación seguía siendo la excursión entera. El paso de asentamiento
	# apuntaba ahí, aterrizaba fuera de su propio umbral y volvía a dispararse: pasitos infinitos.
	# La raíz además sube rápido al arrancar, así que caminar despacio no queda en pasitos ínfimos
	# (con `t` lineal la cadencia sale constante; con √t crece con la velocidad, que es lo real).
	current_excursion = foot_reach * sqrt(t)
	current_stride    = 2.0 * current_excursion / max(current_duty, 0.05)

static func lerp_range(min_val: float, max_val: float, t: float) -> float:
	return min_val + (max_val - min_val) * clamp(t, 0.0, 1.0)

## Interpolación en DOS TRAMOS sobre tres valores autorales: 0.0 → 0.5 → 1.0.
##
## No es un lerp de dos puntos porque **el 0.5 no es el punto medio**: es el personaje genérico tal
## como fue esculpido, y los extremos se modelan a mano sin obligación de quedar simétricos. Esa
## asimetría ES el control artístico — con un lerp de dos extremos, el genérico saldría del promedio
## en vez de salir del modelo.
## Largo de una cadena CON LOS DOS EXTREMOS AUTORADOS EN BLENDER: el modelo es el 0.0 y el 1.0 es ese
## modelo × factor. Es la MISMA cuenta que hace el driver de Blender — si las dos se separan, el
## preview de Blender miente. Su inversa la usa el agarre para despejar cuánto puede estirar el brazo.
static func authored_chain(model_len: float, factor: float, t: float) -> float:
	return model_len * (1.0 + (factor - 1.0) * t)

static func arm_chain_for(rig: ReferenceRig, ext: float) -> float:
	return authored_chain(rig.arm_chain, ReferenceRig.ARM_MODEL_FACTOR, ext)

static func leg_chain_for(rig: ReferenceRig, t: float) -> float:
	return authored_chain(rig.leg_chain, ReferenceRig.LEGS_MODEL_FACTOR, t)

static func torso_chain_for(rig: ReferenceRig, t: float) -> float:
	return authored_chain(rig.torso_chain, ReferenceRig.TORSO_MODEL_FACTOR, t)

## Largo de una cadena TODAVÍA SIN AUTORAR (solo el torso): el esculpido es el 0.5 y los extremos son
## factores provisorios sobre él. Brazo y pierna ya no pasan por acá — ver authored_chain.
static func _chain(sculpted: float, t: float) -> float:
	return lerp_three(sculpted * LENGTH_MIN_FACTOR, sculpted, sculpted * LENGTH_MAX_FACTOR, t)

## Largo de UN hueso dentro de una cadena ya escalada: la cadena repartida en la misma proporción que
## tiene en el modelo. Se lee del rig en runtime por la misma razón que las cadenas — transcribirlo
## fue exactamente el bug: el muslo estaba al 0.4592 de la pierna cuando el modelo lo tiene al 0.3810,
## así que la rodilla quedaba 7 cm fuera de lugar y el pie no caía donde la IK lo mandaba.
static func _share(rig: ReferenceRig, field: String, chain: float, rig_chain: float) -> float:
	if rig_chain <= 0.0:
		return 0.0
	return chain * float(rig.lengths.get(field, 0.0)) / rig_chain

static func lerp_three(lo: float, mid: float, hi: float, t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	if c <= 0.5:
		return lo + (mid - lo) * (c * 2.0)
	return mid + (hi - mid) * ((c - 0.5) * 2.0)

## La inversa de lerp_three: dado un largo en metros, qué valor 0..1 lo produce. La usa el agarre
## para despejar "necesito un brazo de tanto, ¿qué arms_length es eso?" y clampear en 1.0.
static func inverse_lerp_three(lo: float, mid: float, hi: float, value: float) -> float:
	if value <= mid:
		if absf(mid - lo) < 0.0001:
			return 0.5
		return clampf(0.5 * (value - lo) / (mid - lo), 0.0, 1.0)
	if absf(hi - mid) < 0.0001:
		return 0.5
	return clampf(0.5 + 0.5 * (value - mid) / (hi - mid), 0.0, 1.0)
