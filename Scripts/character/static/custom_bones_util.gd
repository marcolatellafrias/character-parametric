class_name CustomBonesUtil

var lower_spine : CustomBone
var middle_spine : CustomBone
var higher_spine : CustomBone
var chest : CustomBone
var left_hip : CustomBone
var right_hip : CustomBone
var left_higher_leg : CustomBone
var left_lower_leg : CustomBone
var right_higher_leg : CustomBone
var right_lower_leg : CustomBone
var right_foot : CustomBone
var left_foot : CustomBone
var neck : CustomBone
var head : CustomBone
var left_shoulder : CustomBone
var right_shoulder : CustomBone
var right_upper_arm : CustomBone
var right_lower_arm : CustomBone
var left_upper_arm : CustomBone
var left_lower_arm : CustomBone

## Todos los huesos, para lo que necesite recorrerlos enteros (visibilidad, debug). `neck` puede ser
## null si el arquetipo no tiene cuello, así que el que la use tiene que chequear validez.
func get_all_bones() -> Array[CustomBone]:
	return [
		lower_spine, middle_spine, higher_spine, chest,
		left_hip, right_hip,
		left_higher_leg, left_lower_leg, right_higher_leg, right_lower_leg,
		left_foot, right_foot,
		left_shoulder, right_shoulder,
		left_upper_arm, left_lower_arm, right_upper_arm, right_lower_arm,
		neck, head,
	]

## Arma la jerarquía. Las ROTACIONES DE REPOSO salen del modelo de Blender (ReferenceRig), no de
## convenciones hardcodeadas: antes había cinco helpers (`createFromToUp/Down/Left/Right/Forward`) que
## aproximaban a mano lo que el modelo ya dice exacto, y esa diferencia era la que hacía que el
## personaje se viera distinto en Blender y en el juego.
##
## Lo único que se le suma encima es la POSTURA del arquetipo — hoy solo `slouch`, y como offset
## relativo a lo que dice el modelo. Con `slouch = 0` el reposo es exactamente el esculpido.
static func create(sizes: SkeletonSizesUtil, inst: EntityInstantiation) -> CustomBonesUtil:
	var u := CustomBonesUtil.new()
	var stats := inst.arch_final
	var rig := ReferenceRig.get_rig()

	u.lower_spine  = _bone(rig, "lower_spine", sizes.lower_spine_size)
	u.middle_spine = _bone(rig, "middle_spine", sizes.middle_spine_size, u.lower_spine,  true,  sizes.slouchiness_center_spine)
	u.higher_spine = _bone(rig, "higher_spine", sizes.higher_spine_size, u.middle_spine, true)
	u.chest        = _bone(rig, "chest", sizes.chest_size, u.higher_spine, true, -sizes.slouchiness_chest)

	# Las caderas cuelgan de la BASE del lower_spine, no de su punta (use_parent_end = false).
	u.left_hip  = _bone(rig, "left_hip", sizes.hip_size, u.lower_spine, false)
	u.right_hip = _bone(rig, "right_hip", sizes.hip_size, u.lower_spine, false)

	u.left_higher_leg  = _bone(rig, "left_higher_leg", sizes.higher_leg_size, u.left_hip,         true)
	u.left_lower_leg   = _bone(rig, "left_lower_leg", sizes.lower_leg_size, u.left_higher_leg,  true)
	u.left_foot        = _bone(rig, "left_foot", sizes.foot_size, u.left_lower_leg,   true)
	u.right_higher_leg = _bone(rig, "right_higher_leg", sizes.higher_leg_size, u.right_hip,        true)
	u.right_lower_leg  = _bone(rig, "right_lower_leg", sizes.lower_leg_size, u.right_higher_leg, true)
	u.right_foot       = _bone(rig, "right_foot", sizes.foot_size, u.right_lower_leg,  true)

	if stats.has_neck:
		u.neck = _bone(rig, "neck", sizes.neck_size, u.chest, true, -sizes.slouchiness_neck)
	u.head = _bone(rig, "head", sizes.head_size, u.neck if u.neck else u.chest, true)

	u.left_shoulder   = _bone(rig, "left_shoulder", sizes.shoulder_width, u.chest, true)
	u.right_shoulder  = _bone(rig, "right_shoulder", sizes.shoulder_width, u.chest, true)
	u.left_upper_arm  = _bone(rig, "left_upper_arm", sizes.upper_arm_size, u.left_shoulder,   true)
	u.left_lower_arm  = _bone(rig, "left_lower_arm", sizes.lower_arm_size, u.left_upper_arm,  true)
	u.right_upper_arm = _bone(rig, "right_upper_arm", sizes.upper_arm_size, u.right_shoulder,  true)
	u.right_lower_arm = _bone(rig, "right_lower_arm", sizes.lower_arm_size, u.right_upper_arm, true)

	return u

## `pitch` es la postura del arquetipo, aplicada como rotación LOCAL sobre la base del modelo (no
## sumada al euler): así se dobla sobre el eje propio de la articulación, que es lo anatómicamente
## correcto y lo que hace que sea un offset relativo y no un valor absoluto.
static func _bone(rig: ReferenceRig, field: String, dims: Vector3,
		parent: CustomBone = null, use_parent_end: bool = true, pitch: float = 0.0) -> CustomBone:
	var basis: Basis = rig.bases.get(field, Basis.IDENTITY)
	if not is_zero_approx(pitch):
		basis = basis * Basis(Vector3.RIGHT, pitch)
	return CustomBone.create(dims, basis.get_euler(), parent, use_parent_end)
