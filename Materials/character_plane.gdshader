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
// El COLOR viene por `instance uniform`, así que una arruga se tiñe con el color de piel del personaje
// y un pelo con el de pelo — una textura compartida por toda la ciudad, un color por cada uno.
//
// ── DOS FAMILIAS DE COLOR EN LA MISMA TEXTURA ─────────────────────────────────────────────────────
// Un mismo plano necesita las dos cosas: el ojo lleva líneas que se tiñen con la piel y una esclerótica
// que tiene que quedarse blanca pase lo que pase. La regla que las separa es:
//
//   • **NEUTRO (R = G = B) → SE TIÑE.** Blanco puro, negros y toda la escala de grises. Blanco = tinte
//     a full, gris = tinte atenuado, negro = negro.
//   • **CON COLOR → LITERAL.** Sale tal cual. Para un blanco de ojo se usa **#FFFFEE**.
//
// Se decide por CROMA y no comparando contra un color exacto, y eso importa: un color exacto no
// sobrevive la conversión sRGB→lineal del sampler. La neutralidad sí, porque la conversión es la misma
// función en los tres canales.
//
// ⚠ EXIGE QUE EL ARTE ESTÉ SEPARADO EN CAPAS. Si una línea blanca se dibuja PEGADA a un relleno de
// color, el rasterizador promedia el borde y esos píxeles quedan con croma — o sea del lado literal, y
// la línea se lee sin teñir. Pasó con la boca. Sobre fondo transparente no ocurre: ahí el antialiasing
// se va al canal alpha y el píxel sigue siendo blanco puro.

instance uniform vec4 tint : source_color = vec4(1.0);

// 1.0 = espeja la textura en X. Es POR INSTANCIA y no un uniform común porque los dos ojos comparten
// material (se cachea por textura), así que un uniform normal los voltearía a los dos.
//
// Existe porque los planos de ojo son geometría ESPEJADA en Blender con el MISMO mapeo UV (medido: las
// dos superficies tienen idéntico signo de área en UV). Misma textura sobre malla reflejada = dibujo
// dado vuelta. Voltear el UV de uno cancela el espejado de la malla.
instance uniform float uv_flip_x = 0.0;

// 1.0 = decodificar sRGB a mano. Lo necesitan las texturas que vienen de Rive: son render targets, no
// traen la marca de sRGB que sí trae un PNG importado, así que el `source_color` de abajo no las
// convierte y la imagen sale lavada. Un PNG normal va en 0.0 y no se toca nada.
instance uniform float srgb_decode = 0.0;

uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float alpha_threshold : hint_range(0.0, 1.0) = 0.5;
// Separación del plano respecto de la superficie que decora, en metros.
uniform float normal_offset : hint_range(0.0, 0.01) = 0.0008;
// Mismo modelo de sombra que character.gdshader, pero apenas aplicado: la cara lleva las features
// dibujadas y una sombra fuerte se las come.
// Debajo de esto un píxel se considera NEUTRO (gris) y se tiñe; por encima sale literal.
uniform float literal_threshold : hint_range(0.0, 0.5) = 0.03;
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
	vec2 uv = vec2(mix(UV.x, 1.0 - UV.x, uv_flip_x), UV.y);
	vec4 tex = texture(albedo_texture, uv);
	tex.rgb = mix(tex.rgb, pow(tex.rgb, vec3(2.2)), srgb_decode);
	// Croma = cuánto se aparta el píxel del gris. Ver el bloque de arriba.
	float chroma = max(tex.r, max(tex.g, tex.b)) - min(tex.r, min(tex.g, tex.b));
	ALBEDO = mix(tex.rgb * tint.rgb, tex.rgb, step(literal_threshold, chroma));
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
