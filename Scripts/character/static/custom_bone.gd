class_name CustomBone
extends Node3D

## Un hueso del rig LÓGICO. Es solo un Node3D con un largo: no dibuja nada.
##
## Lo visible es la malla skinneada del modelo de Blender, que sigue a estos huesos vía
## SkinnedBodyUtil. Antes cada hueso instanciaba su propio `bone.glb` deformado por blend shapes —
## veinte mallas por personaje que hoy estarían siempre ocultas. Ver
## technical/skinned-character-migration.md.
##
## `capsule_dimensions` sobrevive con x/z = radio, y = largo: el largo lo lee todo el sistema de
## animación, y los radios ya solo dan forma a las cápsulas de colisión del ragdoll.

var capsule_dimensions: Vector3
## Rotación de reposo GLOBAL. La provee ReferenceRig desde el modelo de Blender; `create` la convierte
## a local contra el padre. También es la referencia de torsión que usa `pose_from_rest_to`.
var rest_rotation: Vector3

var length: float = capsule_dimensions.y:
	get:  return capsule_dimensions.y
	set(val): capsule_dimensions.y = val


static func create(new_capsule_dimensions: Vector3, new_rest_rotation: Vector3,
		father_bone: CustomBone = null, use_father_end: bool = true) -> CustomBone:
	var bone := CustomBone.new()
	bone.capsule_dimensions = new_capsule_dimensions
	bone.rest_rotation = new_rest_rotation

	if father_bone:
		bone.position = father_bone.get_end_position() if use_father_end else Vector3.ZERO
		father_bone.add_child(bone)
		# rest_rotation es global: se la baja a local contra la rotación acumulada del padre.
		var parent_global := _get_accumulated_rotation(father_bone)
		bone.rotation = (parent_global.inverse() * Basis.from_euler(new_rest_rotation)).get_euler()
	else:
		bone.rotation = new_rest_rotation
	return bone


func get_end_position() -> Vector3:
	return Vector3(0, capsule_dimensions.y, 0)


func set_length(new_y: float) -> void:
	capsule_dimensions.y = new_y


## Base que apunta el eje de reposo del hueso a lo largo de `dir`, resolviendo la torsión con `pole`.
## Es la primitiva que usa la IK.
##
## OJO con la degeneración: si `dir` viene de una cadena a extensión total, el codo/rodilla queda
## colineal, `pole` cae casi paralelo a `dir` y la torsión sale arbitraria. Por eso los targets de
## reposo se clampean (SkeletonSizesUtil.ARM_REST_EXTENSION).
func pose_from_rest_to(dir: Vector3, pole: Vector3) -> Basis:
	var rest_basis := Basis.from_euler(rest_rotation)
	var y := dir.normalized()
	var rest_y := rest_basis.y.normalized()
	var c := clampf(rest_y.dot(y), -1.0, 1.0)
	var align := Basis()
	if c > 0.999999:
		align = Basis()
	elif c < -0.999999:
		var axis := rest_y.cross(Vector3.RIGHT)
		if axis.length_squared() < 0.0001:
			axis = rest_y.cross(Vector3.UP)
		align = Basis(axis.normalized(), PI)
	else:
		align = Basis(rest_y.cross(y).normalized(), acos(c))

	var projected_pole := (pole - y * pole.dot(y)).normalized()
	if projected_pole.length() < 1e-6:
		projected_pole = IkUtil.get_orthogonal(y).normalized()
	var ref_axis := (align * rest_basis).z.normalized()
	var twist := Basis(y, atan2(ref_axis.cross(projected_pole).dot(y), ref_axis.dot(projected_pole)))
	return twist * align * rest_basis


static func _get_accumulated_rotation(bone: CustomBone) -> Basis:
	var accumulated := Basis.from_euler(bone.rotation)
	var current := bone.get_parent()
	while current != null and current is CustomBone:
		accumulated = Basis.from_euler(current.rotation) * accumulated
		current = current.get_parent()
	return accumulated
