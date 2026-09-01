class_name PassiveAnimations
extends Node

## ANIMACIONES PASIVAS: las que corren cuando el personaje NO está haciendo nada.
##
## Van en un archivo aparte de `animations.gd` por responsabilidad, no por mecanismo: usan el MISMO
## `ProceduralBoneAnimator`, que ya es una capa aditiva sobre un reset por frame. Registrar acá se
## suma a la marcha sin pelearse y se propaga por la cadena de huesos solo.
##
## ── EL CONTRATO ───────────────────────────────────────────────────────────────────────────────────
## Una animación es PASIVA si cumple las cuatro:
##
##   1. **Tiene reloj propio** — no depende del ciclo de paso. Sigue cuando el personaje está quieto.
##   2. **La maneja el ESTADO** del personaje (esfuerzo, temblor), no la locomoción.
##   3. **No escribe nada que el juego lea** — ni alcance, ni cápsula, ni targets de IK.
##   4. **Se deriva local en cada máquina.** Cero bytes en el cable.
##
## Si algo no cumple las cuatro, va en `animations.gd`.
##
## ── LO QUE NO HACE: RAGDOLL ───────────────────────────────────────────────────────────────────────
## Durante el ragdoll los CustomBone quedan congelados y el espejo lee los `RigidBody3D`, así que todo
## lo registrado acá deja de verse. Es una limitación conocida, no un olvido.
##
## Para respirar tirado en el piso hay que escribir DESPUÉS del sync, y ahí aparece otra restricción:
## `SkinnedBodyUtil._detach_children_of_stretched()` aplana la jerarquía, así que una rotación local
## sobre `chest` no arrastraría al cuello ni a los brazos. La salida limpia sería un shape key
## `breath_max` — una caja torácica inflada es una FORMA, no un ángulo, y una key no sabe de poses.
## Ver technical/character-appearance-system.md.

var bi: BoneInstantiator


func _ready() -> void:
	bi = get_parent() as BoneInstantiator


func register_all() -> void:
	var st := bi.passive_state
	if st == null:
		return
	_register_breathing(st)
	_register_tremor(st)


## ── RESPIRACIÓN ───────────────────────────────────────────────────────────────────────────────────
## El pecho se abre hacia atrás al inhalar y el cuello compensa para que la cabeza no cabecee. Esa
## compensación es lo que separa "respira" de "asiente": en una respiración tranquila la cabeza
## prácticamente no se mueve.
##
## El torso también sube unos milímetros. Es poco y se nota: sin eso el pecho se abre pero el cuerpo
## queda plantado y se lee como una bisagra.
##
## Los pesos son la amplitud EN REPOSO; `breath_amplitude()` la multiplica hasta ~2.8× jadeando, o sea
## que el pecho llega a ~12° en el pico del jadeo.
##
## El peso del cuello se mueve JUNTO con los otros dos: es la compensación para que la cabeza quede
## quieta, así que si subís el pecho y no el cuello, el personaje empieza a asentir.
func _register_breathing(st: PassiveState) -> void:
	var PA := ProceduralBoneAnimator
	var pa := bi.procedural_animator
	var cb := bi.custom_bones_util
	var breath := func() -> float: return st.breath() * st.breath_amplitude()

	pa.register_formula(cb.chest,        PA.Axis.ROT_X, breath,  0.075)
	pa.register_formula(cb.higher_spine, PA.Axis.ROT_X, breath,  0.034)
	if is_instance_valid(cb.neck):
		pa.register_formula(cb.neck,     PA.Axis.ROT_X, breath, -0.084)
	pa.register_formula(cb.lower_spine,  PA.Axis.POS_Y, breath,  0.012)


## ── TEMBLOR ───────────────────────────────────────────────────────────────────────────────────────
## Cuatro decisiones, todas por la misma razón — que se lea como un cuerpo y no como ruido:
##
##   - **Cuasi-periódico, no aleatorio.** Ver PassiveState.tremor.
##   - **En las piernas, solo el POLE.** Rotar un hueso de pierna pelea con el planteo del pie, pero el
##     pole es el único grado de libertad que NO lo mueve: el pie y la cadera quedan donde están y la
##     rodilla bambolea sobre el eje que las une. Es como se ve un temblor de piernas de verdad.
##   - **Crece hacia la punta de la cadena.** La mano tiembla más que el hombro, porque el temblor se
##     amplifica a lo largo del brazo. Sale solo registrando pesos distintos por hueso.
##   - **Desfasados MUY POCO entre sí.** Un temblor sale de una sola oscilación nerviosa: el cuerpo
##     tiembla casi en fase, con un retardo chico entre articulaciones. Los offsets están en SEGUNDOS y
##     a 5 Hz un valor grande da vuelta el ciclo entero y quedás en fase pseudo-aleatoria — que se lee
##     como que cada parte tiembla por su cuenta. 0.018 s son ~32° de retardo: se nota que no están
##     clavados, pero pertenecen al mismo cuerpo.
func _register_tremor(st: PassiveState) -> void:
	var amount: float = bi.entity_instantiation.arch_final.tremor
	if is_zero_approx(amount):
		return
	var PA := ProceduralBoneAnimator
	var pa := bi.procedural_animator
	var cb := bi.custom_bones_util

	var left  := func() -> float: return st.tremor(0.000)
	var right := func() -> float: return st.tremor(0.018)
	var core  := func() -> float: return st.tremor(0.009)

	pa.register_formula(cb.left_lower_arm,  PA.Axis.ROT_X, left,  amount * 0.030)
	pa.register_formula(cb.left_lower_arm,  PA.Axis.ROT_Z, left,  amount * 0.022)
	pa.register_formula(cb.right_lower_arm, PA.Axis.ROT_X, right, amount * 0.030)
	pa.register_formula(cb.right_lower_arm, PA.Axis.ROT_Z, right, amount * 0.022)

	pa.register_formula(cb.left_upper_arm,  PA.Axis.ROT_X, left,  amount * 0.010)
	pa.register_formula(cb.right_upper_arm, PA.Axis.ROT_X, right, amount * 0.010)

	if is_instance_valid(cb.head):
		pa.register_formula(cb.head,  PA.Axis.ROT_X, core, amount * 0.008)
		pa.register_formula(cb.head,  PA.Axis.ROT_Z, core, amount * 0.006)
	pa.register_formula(cb.chest,     PA.Axis.ROT_Z, core, amount * 0.004)

	# Rodillas: se mueve el POLE, no el hueso. Sobre RIGHT, o sea de costado.
	#
	# El pole se coloca en `(offset_lateral, 0, −pole_distance)`, o sea MAYORMENTE ADELANTE de la
	# pierna. Correrlo en Z solo lo acerca o lo aleja sobre su propio eje y casi no gira la rodilla;
	# el que la hace bambolear sobre el eje cadera→pie es el movimiento lateral.
	#
	# ⚠ EL PESO ES GRANDE Y TIENE QUE SERLO, al revés de lo que sugiere la intuición. `pole_distance`
	# es el largo de la pierna entera (~0.92 m), y un brazo de palanca largo da MENOS ángulo por
	# milímetro, no más. La cuenta es `desplazamiento = pole_distance · tan(ángulo)`:
	#
	#   0.006 m → 0.4° (invisible)      0.02 m → 1.25°      0.05 m → 3.1° (demasiado)
	#
	# El peso es el desplazamiento en metros en el pico del temblor.
	#
	# ⚠ HAY UN TECHO, y no es de gusto. El pole define el ROLL de la tibia, y el hueso `foot` cuelga
	# rígido de ella: al mover el pole, **el pie se tuerce**. Además la rodilla barre `muslo · sin(θ)`
	# —24 mm a 3.1°— y con el pie clavado el ojo lee eso como que patina.
	#
	# Las dos cosas escalan con la amplitud, así que ~1.25° es donde el temblor se ve y el artefacto no.
	# Para pasar de ahí habría que darle al pie una orientación propia en vez de heredar la de la tibia,
	# que es otro trabajo.
	var ik := bi.ik_util
	if is_instance_valid(ik):
		if is_instance_valid(ik.left_leg_pole):
			pa.register_node_formula(ik.left_leg_pole,  Vector3.RIGHT, left,  amount * 0.02)
		if is_instance_valid(ik.right_leg_pole):
			pa.register_node_formula(ik.right_leg_pole, Vector3.RIGHT, right, amount * 0.02)
