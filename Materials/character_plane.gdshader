shader_type spatial;
render_mode specular_disabled, cull_back, depth_draw_opaque;

// PLANOS DE FEATURE — cejas, ojos, boca, arrugas, pelos.
//
// Variante del shader de personaje para las tiras con textura que se apoyan sobre el cuerpo. Tres
// diferencias con `character.gdshader`, y las tres tienen una razón:
//
// 1. RECORTE POR ALPHA TEST, no alpha blend. Se escribe `ALPHA` **y** `ALPHA_SCISSOR_THRESHOLD`:
//    con las dos, Godot lo deja en el pase OPACO, así que escribe depth y se ordena solo. Con
//    `ALPHA` a secas se va al pase transparente, que no escribe depth y ordena por objeto — y una
//    docena de planos superpuestos en un personaje en movimiento saltan de adelante hacia atrás.
//
// 2. SE EMPUJA POR LA NORMAL. El plano está apoyado sobre la malla que decora, o sea en el mismo
//    plano de profundidad: sin separarlo hay z-fighting. Se empuja por la normal y NO se usa además
//    depth bias — con los dos, a ángulos rasantes el plano se despega visiblemente.
//
// 3. CASI SIN SOMBRA. La cara lleva las features DIBUJADAS, y una sombra fuerte se las come. Es lo
//    que hace legible el estilo (Animal Crossing hace exactamente esto).
//
// El COLOR sigue viniendo por `instance uniform`, así que una arruga se tiñe con el color de piel del
// personaje y un pelo con el de pelo — una textura compartida por toda la ciudad, un color por cada
// uno. Por eso las texturas se exportan en BLANCO o escala de grises: el tinte multiplica, y negro
// por cualquier cosa sigue siendo negro.

instance uniform vec4 tint : source_color = vec4(1.0);

uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
// Separación del plano respecto de la superficie que decora, en metros.
uniform float normal_offset : hint_range(0.0, 0.01) = 0.0008;
// Mismo modelo de sombra que character.gdshader, pero apenas aplicado: la cara lleva las features
// dibujadas y una sombra fuerte se las come.
uniform float shadow_value : hint_range(0.0, 1.0) = 0.7;
uniform float shadow_saturation : hint_range(0.0, 2.0) = 1.2;
uniform vec4 shadow_hue : source_color = vec4(0.45, 0.52, 0.80, 1.0);
uniform float shadow_hue_amount : hint_range(0.0, 1.0) = 0.2;
uniform int steps : hint_range(1, 4) = 1;
uniform float softness : hint_range(0.01, 1.0) = 0.35;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 shadow_of(vec3 base) {
	vec3 c = base * shadow_value;
	c = mix(vec3(dot(c, LUMA)), c, shadow_saturation);
	c *= mix(vec3(1.0), shadow_hue.rgb, shadow_hue_amount);
	return max(c, vec3(0.0));
}

void vertex() {
	VERTEX += NORMAL * normal_offset;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	ALBEDO = tex.rgb * tint.rgb;
	ALPHA = tex.a * tint.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_threshold;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	float ndotl = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float n = float(steps);
	float scaled = ndotl * n;
	float lower = floor(scaled);
	float t = (lower + smoothstep(0.5 - softness * 0.5, 0.5 + softness * 0.5, fract(scaled))) / n;
	DIFFUSE_LIGHT += mix(shadow_of(ALBEDO), ALBEDO, t * ATTENUATION) * LIGHT_COLOR;
}
