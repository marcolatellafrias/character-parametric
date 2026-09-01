class_name EntitySpecie

enum Specie {human, alien, robot}

# BASE STATS
var strenght_multiplier : float = 1.0
var speed_forw_multiplier : float = 1.0
var speed_back_multiplier : float = 1.0
var speed_side_multiplier : float = 1.0
var side_swing_multiplier: float = 1.0
var acceleration_multiplier : float = 1.0
var forward_stability_multiplier : float = 1.0
var backwards_stability_multiplier : float = 1.0
var sideways_stability_multiplier : float = 1.0
var stability_spring_multiplier : float = 1.0
var stability_damp_multiplier : float = 1.0

# REACH/ARMS
var throw_strenght_multiplier : float = 1.0
var reach_multiplier : float = 1.0

# JUMP
## OJO: hoy no lo aplica nadie — el salto sale solo del archetype (jump_height).
var jump_height_multiplier : float = 1.0

# ANIMATIONS
var shoulder_swing_multiplier : float = 1.0
var hip_swing_multiplier : float = 1.0
var root_bounciness_multiplier  : float = 1.0
var step_height_multiplier : float = 1.0
var stride_multiplier : float = 1.0
var leg_cripple_chance_multiplier : float = 1.0

## Paletas de color por specie. El seed elige UNA de cada una, y de ahí salen los `instance uniform`
## que pinta CharacterAppearance. Son listas y no rangos continuos a propósito: un color elegido de
## una paleta autorada siempre queda bien, y un color aleatorio en HSV no.
var skin_colors : Array
var cloth_colors : Array
var hair_colors : Array
var leather_colors : Array


static func human_specie() -> EntitySpecie:
	var specie = EntitySpecie.new()
	specie.strenght_multiplier = 1.0
	specie.speed_forw_multiplier = 1.0
	specie.speed_back_multiplier = 1.0
	specie.speed_side_multiplier = 1.0
	specie.acceleration_multiplier = 1.0
	specie.forward_stability_multiplier = 1.0
	specie.backwards_stability_multiplier = 1.0
	specie.sideways_stability_multiplier = 1.0
	specie.stability_spring_multiplier = 1.0
	specie.stability_damp_multiplier = 1.0
	specie.throw_strenght_multiplier = 1.0
	specie.reach_multiplier = 1.0
	specie.jump_height_multiplier = 1.2
	specie.shoulder_swing_multiplier = 1.0
	specie.hip_swing_multiplier = 1.0
	specie.root_bounciness_multiplier = 1.0
	specie.step_height_multiplier = 1.0
	specie.stride_multiplier = 1.0
	specie.leg_cripple_chance_multiplier = 1.0
	specie.side_swing_multiplier = 1.0
	specie.skin_colors = [
		Color(1.0, 0.85, 0.7),
		Color(0.9, 0.7, 0.5),
		Color(0.75, 0.55, 0.35),
		Color(0.5, 0.35, 0.2),
		Color(0.3, 0.2, 0.12),
	]
	# Paleta de época: lanas y tweeds apagados de 1900-1920, nada saturado. Nuevos Aires no tiene
	# tintes sintéticos brillantes todavía.
	specie.cloth_colors = [
		Color(0.28, 0.30, 0.36),  # azul pizarra
		Color(0.34, 0.31, 0.26),  # tweed marrón
		Color(0.22, 0.24, 0.23),  # verde carbón
		Color(0.45, 0.42, 0.36),  # lino sucio
		Color(0.31, 0.22, 0.22),  # bordó apagado
		Color(0.19, 0.20, 0.24),  # casi negro
	]
	specie.hair_colors = [
		Color(0.09, 0.07, 0.06),  # negro
		Color(0.20, 0.13, 0.09),  # castaño oscuro
		Color(0.36, 0.24, 0.14),  # castaño
		Color(0.55, 0.42, 0.24),  # rubio oscuro
		Color(0.45, 0.24, 0.12),  # rojizo
		Color(0.62, 0.60, 0.57),  # canoso
	]
	specie.leather_colors = [
		Color(0.16, 0.12, 0.10),
		Color(0.28, 0.19, 0.13),
		Color(0.38, 0.28, 0.18),
	]
	return specie

static func alien_specie() -> EntitySpecie:
	var specie = EntitySpecie.new()
	specie.strenght_multiplier = 0.7
	specie.speed_forw_multiplier = 1.0
	specie.speed_back_multiplier = 1.0
	specie.speed_side_multiplier = 1.0
	specie.acceleration_multiplier = 1.0
	specie.forward_stability_multiplier = 1.0
	specie.backwards_stability_multiplier = 1.0
	specie.sideways_stability_multiplier = 1.0
	specie.stability_spring_multiplier = 1.0
	specie.stability_damp_multiplier = 1.0
	specie.throw_strenght_multiplier = 1.0
	specie.reach_multiplier = 1.5
	specie.jump_height_multiplier = 1.0
	specie.shoulder_swing_multiplier = 1.0
	specie.hip_swing_multiplier = 1.0
	specie.root_bounciness_multiplier = 1.0
	specie.step_height_multiplier = 1.0
	specie.stride_multiplier = 1.0
	specie.side_swing_multiplier = 1.0
	specie.leg_cripple_chance_multiplier = 0.0
	specie.skin_colors = [
		Color(0.3, 0.8, 0.4),
		Color(0.4, 0.6, 0.9),
		Color(0.7, 0.3, 0.8),
		Color(0.2, 0.7, 0.7),
	]
	return specie

static func robot_specie() -> EntitySpecie:
	var specie = EntitySpecie.new()
	specie.strenght_multiplier = 1.5
	specie.speed_forw_multiplier = 0.7
	specie.speed_back_multiplier = 0.4
	specie.speed_side_multiplier = 0.5
	specie.acceleration_multiplier = 0.7
	specie.forward_stability_multiplier = 0.9
	specie.backwards_stability_multiplier = 0.6
	specie.sideways_stability_multiplier = 0.3
	specie.stability_spring_multiplier = 1.0
	specie.stability_damp_multiplier = 1.0
	specie.throw_strenght_multiplier = 1.0
	specie.reach_multiplier = 1.0
	specie.jump_height_multiplier = 1.0
	specie.shoulder_swing_multiplier = 1.0
	specie.hip_swing_multiplier = 1.0
	specie.root_bounciness_multiplier = 1.0
	specie.step_height_multiplier = 0.5
	specie.stride_multiplier = 0.6
	specie.side_swing_multiplier = 1.0
	specie.leg_cripple_chance_multiplier = 0.0
	specie.skin_colors = [
		Color(0.75, 0.75, 0.75),
		Color(0.4, 0.4, 0.4),
		Color(0.8, 0.6, 0.2),
		Color(0.3, 0.5, 0.7),
	]
	return specie
