shader_type spatial;
render_mode specular_disabled, cull_back, depth_draw_opaque;

// SHADER DE PERSONAJE.
//
// La idea de fondo: **la sombra es el color del personaje, no negro.** Un personaje rojo tiene sombra
// roja oscura. Eso mantiene la lectura de volumen sin generar el contraste que se comería las
// features DIBUJADAS de la cara, que es de lo que depende todo el estilo.
//
// La sombra NO se calcula multiplicando por un factor y ya. Multiplicar conserva el tono pero apaga
// la saturación, y la sombra sale gris sucia. Acá se hacen tres cosas por separado, que son las que
// hace un pintor:
//
//   1. OSCURECER  (shadow_value)
//   2. SATURAR    (shadow_saturation > 1) — que un rojo dé rojo intenso, no bordó apagado
//   3. SESGAR EL TONO (shadow_hue) — hacia el azul del cielo, que es de donde viene la luz que
//      realmente ilumina una sombra. En 0 queda "su propio color, más oscuro" y nada más.
//
// El COLOR BASE viene por `instance uniform`, así que toda la ciudad comparte UN material y cada
// personaje tiene su piel, su traje y su pelo. Ver technical/character-appearance-system.md.
//
// ⚠ NO ESCRIBIR `ALPHA` acá. Alcanza con tocarlo una vez para que el material entero pase al pase
// transparente, que no escribe depth y ordena por objeto — y las mallas se dibujan una encima de otra
// ignorando la profundidad, a veces sí y a veces no. El personaje es OPACO; el recorte vive en
// character_plane.gdshader.

instance uniform vec4 tint : source_color = vec4(1.0);

uniform sampler2D albedo_texture : source_color, hint_default_white;

// ── Sombra ────────────────────────────────────────────────────────────────────────────────────────
//
// EL PERSONAJE SE ILUMINA COMO CUALQUIER MALLA. El ambient de la escena entra normal y este shader
// solo le da forma a la luz DIRECTA — el escalón del terminador y el color de la sombra.
//
// Hubo una versión con `ambient_light_disabled` para que la sombra no se aplastara contra el piso que
// pone el cielo. Salió mal: sin ambient este shader pasaba a ser TODO el modelo de iluminación, y
// como la luz directa a energía 1 da exactamente el albedo, el personaje no podía ser más brillante
// que su color base y quedaba negro. Necesitó un multiplicador de ganancia para compensar, o sea dos
// parches encima de una decisión equivocada. Si la sombra queda lavada, se corrige con
// `shadow_value`, no apagando el ambient.
// Brillo de la sombra como fracción de la luz. 1.0 = sin sombra. La cara quiere valores ALTOS.
uniform float shadow_value : hint_range(0.0, 1.0) = 0.4;
// >1 satura la sombra. Es la perilla que separa "sombra pintada" de "sombra apagada".
uniform float shadow_saturation : hint_range(0.0, 2.0) = 1.25;
// Tono hacia el que se sesga la sombra, y cuánto. En 0 la sombra es puro color propio más oscuro.
uniform vec4 shadow_hue : source_color = vec4(0.45, 0.52, 0.80, 1.0);
uniform float shadow_hue_amount : hint_range(0.0, 1.0) = 0.2;

// ── Terminador ────────────────────────────────────────────────────────────────────────────────────
// Escalones entre luz y sombra. 1 = un solo borde (lo más limpio en low poly, donde los escalones
// caen sobre caras planas enteras y el personaje se ve parcheado).
uniform int steps : hint_range(1, 4) = 1;
// 0 = borde de tinta, 1 = degradé suave.
uniform float softness : hint_range(0.01, 1.0) = 0.25;
// Corre el borde. Positivo = más iluminado.
uniform float light_bias : hint_range(-0.5, 0.5) = 0.0;

// ── Rim ───────────────────────────────────────────────────────────────────────────────────────────
// Separa la silueta del fondo sin outlines, que en low poly se rompen.
uniform float rim_strength : hint_range(0.0, 2.0) = 0.2;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 shadow_of(vec3 base) {
	vec3 c = base * shadow_value;
	// Saturar respecto de su propia luminancia: >1 aleja del gris sin cambiar el tono.
	c = mix(vec3(dot(c, LUMA)), c, shadow_saturation);
	// El sesgo va MULTIPLICATIVO para que la identidad del color base sobreviva: teñir por mezcla
	// arrastraría todo hacia el mismo azul y un personaje rojo dejaría de tener sombra roja.
	c *= mix(vec3(1.0), shadow_hue.rgb, shadow_hue_amount);
	return max(c, vec3(0.0));
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * tint.rgb;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	float ndotl = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5 + light_bias, 0.0, 1.0);

	// Cuantizar y suavizar el escalón. Sin el smoothstep el borde aliasea feo en un personaje chico
	// en pantalla, que es como se lo ve casi todo el tiempo.
	float n = float(steps);
	float scaled = ndotl * n;
	float lower = floor(scaled);
	float t = (lower + smoothstep(0.5 - softness * 0.5, 0.5 + softness * 0.5, fract(scaled))) / n;

	float lit = t * ATTENUATION;
	DIFFUSE_LIGHT += mix(shadow_of(ALBEDO), ALBEDO, lit) * LIGHT_COLOR;

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	DIFFUSE_LIGHT += rim * rim_strength * ALBEDO * LIGHT_COLOR * ATTENUATION;
}
