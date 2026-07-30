class_name CharacterGrabbable
extends GrabbableInteractable
## El grabbable que cuelga de la cápsula de un personaje (empujar/agarrar a un compañero). Se apaga
## mientras ese personaje está ragdolleando o recuperándose: no se puede agarrar, empujar ni tirar a
## un jugador caído (ni sus huesos, que no son interactuables). Como el throw/push eligen objetivo
## por can_interact(), esto también bloquea empujarlo. Ver conceptual/multiplayer.md.

var owner_bi: BoneInstantiator = null

func can_interact() -> bool:
	if is_instance_valid(owner_bi) and is_instance_valid(owner_bi.ragdoll_util):
		var rd := owner_bi.ragdoll_util
		if rd.is_active or rd.is_recovering:
			return false
	return super.can_interact()
