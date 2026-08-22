class_name PrecisionProbe

## Diagnóstico de una sospecha concreta: que los huesos se separen lejos del origen por pérdida de
## precisión en float de 32 bits, y no por un error de lógica.
##
## Mide dos cosas y las compara:
##   · LOCAL  — `hijo.position.length()`, el offset guardado respecto del padre. Es un número chico y
##              exacto: un fémur mide lo mismo esté donde esté el personaje.
##   · MUNDO  — la distancia entre las posiciones globales de padre e hijo.
##
## En matemática exacta son idénticos. La diferencia entre ambos ES el error de precisión, y sube con
## la distancia al origen porque el espaciado entre floats representables crece con la magnitud.
##
## Lo importante es dónde aparece la diferencia: si el LOCAL está sano y solo el MUNDO se degrada, el
## rig lógico está bien y el daño lo introducen las conversiones a espacio mundial (el espejo, la IK).
## Ese caso tiene arreglo barato y contenido. Si el local también se degrada, el problema es más hondo.

## Se escribe acá además de imprimirse. `user://` en Windows es %APPDATA%/Godot/app_userdata/<proyecto>/.
const REPORT_PATH := "user://precision_probe.txt"

static func run(bi: BoneInstantiator) -> String:
	if not is_instance_valid(bi) or bi.custom_bones_util == null:
		return "PrecisionProbe: no hay esqueleto."

	var origin_dist := bi.char_rigidbody.global_position.length()
	# Espaciado entre floats representables a esta magnitud: M · 2^-23.
	var ulp := origin_dist * pow(2.0, -23.0)

	var lines: Array[String] = []
	lines.append("── PRECISION PROBE ─────────────────────────────────")
	lines.append("distancia al origen : %.1f m" % origin_dist)
	lines.append("resolución fp32 acá : %.4f mm  (1 ulp)" % (ulp * 1000.0))
	lines.append("")
	lines.append("%-24s %9s %9s %9s" % ["hueso (padre→hijo)", "local", "mundo", "Δ mm"])

	var worst := 0.0
	var worst_name := "-"
	for bone in bi.custom_bones_util.get_all_bones():
		if not is_instance_valid(bone):
			continue
		var parent := bone.get_parent() as CustomBone
		if parent == null:
			continue
		var local_len := bone.position.length()
		var world_len := parent.global_position.distance_to(bone.global_position)
		var delta_mm: float = absf(world_len - local_len) * 1000.0
		if delta_mm > worst:
			worst = delta_mm
			worst_name = bone.name
		lines.append("%-24s %9.5f %9.5f %9.4f" % [_short(parent, bone), local_len, world_len, delta_mm])

	lines.append("")
	lines.append("PEOR separación de junta: %.4f mm  (%s)" % [worst, worst_name])
	lines.append("")

	# Segundo frente: cuánto se desvía la malla skinneada del rig lógico. Es la conversión a mundo que
	# hace el espejo cada frame, y es la que rompería la geometría visible aunque el rig esté sano.
	if is_instance_valid(bi.skinned_body):
		var drift := bi.skinned_body.measure_drift()
		lines.append("espejo (CustomBone vs Skeleton3D): peor %.4f mm  (%s)" % [drift[0], drift[1]])
	else:
		lines.append("espejo: no hay modelo skinneado.")

	lines.append("")
	lines.append("Lectura: si Δ crece con la distancia al origen y está en el orden de 1 ulp,")
	lines.append("es precisión fp32. Si son centímetros, es un bug de lógica y hay que buscar otra cosa.")
	lines.append("────────────────────────────────────────────────────")
	return "\n".join(lines)

static func _short(parent: CustomBone, child: CustomBone) -> String:
	return "%s→%s" % [str(parent.name).substr(0, 10), str(child.name).substr(0, 12)]
