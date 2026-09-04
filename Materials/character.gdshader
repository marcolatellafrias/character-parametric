shader_type spatial;
render_mode specular_disabled, cull_back, depth_draw_opaque;

// SHADER DE PERSONAJE.
//
// ── LA BASE ES LA ILUMINACIÓN ESTÁNDAR, NO EL TOON ────────────────────────────────────────────────
// Con todo en neutro este shader da EXACTAMENTE `ALBEDO × ndotl`, o sea lo mismo que un material sin
// shader. No es una aproximación: es la fórmula, y se puede verificar leyéndola.
//
//   light_wrap 0 · band_amount 0 · rim_strength 0
//   shadow_value 0 · shadow_saturation 1 · shadow_hue_amount 0   → la sombra es negra
//   light_value 1  · light_saturation 1  · light_hue_amount 0    → la luz es el albedo
//
// Eso importa porque el punto de partida del estilo ES el look sin shader, y desde ahí se va tocando:
// "la sombra está muy negra, la llevo al color base", "la saturo un poco más". Cada perilla se mueve
// desde un neutro conocido en vez de desde un preset que ya decidió cosas por vos.
//
// ── LA IDEA DE FONDO ──────────────────────────────────────────────────────────────────────────────
// **La sombra es el color del personaje, no negro.** Un personaje rojo tiene sombra roja oscura. Eso
// mantiene la lectura de volumen sin generar el contraste que se comería las features DIBUJADAS de la
// cara, que es de lo que depende todo el estilo.
//
// Y no se hace multiplicando por un factor: multiplicar conserva el tono pero apaga la saturación y la
// sombra sale gris sucia. Se hacen tres cosas por separado, que son las que hace un pintor —oscurecer,
// saturar, sesgar el tono— y las mismas tres están disponibles para el lado ILUMINADO.
//
// ⚠ NO ESCRIBIR `ALPHA` acá. Alcanza con tocarlo una vez para que el material entero pase al pase
// transparente, que no escribe depth y ordena por objeto. El personaje es OPACO; el recorte vive en
// character_plane.gdshader.

instance uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white;

// ── Terminador ────────────────────────────────────────────────────────────────────────────────────
// 0 = Lambert (max(N·L, 0)), igual que un material estándar. 1 = half-lambert (N·L·0.5 + 0.5), que
// nunca llega a cero y suaviza el lado oscuro. Es el knob que decide si esto se parece al estándar.
uniform float light_wrap : hint_range(0.0, 1.0) = 0.0;
// Corre el borde. Positivo = más iluminado.
uniform float light_bias : hint_range(-0.5, 0.5) = 0.0;

// ── Bandas (opcional) ─────────────────────────────────────────────────────────────────────────────
// En 0 la rampa es continua y no hay nada de toon. Es un EXTRA, no la base.
uniform float band_amount : hint_range(0.0, 1.0) = 0.0;
uniform int band_count : hint_range(1, 4) = 1;
// 0 = borde de tinta, 1 = degradé suave.
uniform float band_softness : hint_range(0.01, 1.0) = 0.25;

// ── Color de la sombra ────────────────────────────────────────────────────────────────────────────
// Brillo de la sombra como fracción del albedo. **0 = negro = iluminación estándar.**
uniform float shadow_value : hint_range(0.0, 1.0) = 0.0;
// >1 satura. Es la perilla que separa "sombra pintada" de "sombra apagada".
uniform float shadow_saturation : hint_range(0.0, 2.0) = 1.0;
uniform vec4 shadow_hue : source_color = vec4(0.45, 0.52, 0.80, 1.0);
uniform float shadow_hue_amount : hint_range(0.0, 1.0) = 0.0;

// ── Color de la luz ───────────────────────────────────────────────────────────────────────────────
// Los mismos tres controles del lado iluminado. **1 / 1 / 0 = el albedo tal cual.**
uniform float light_value : hint_range(0.0, 2.0) = 1.0;
uniform float light_saturation : hint_range(0.0, 2.0) = 1.0;
uniform vec4 light_hue : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float light_hue_amount : hint_range(0.0, 1.0) = 0.0;

// ── Ruido ─────────────────────────────────────────────────────────────────────────────────────────
// Grano procedural sobre el brillo del albedo, como reemplazo provisorio de las texturas. Modifica el
// color ANTES de la luz, así que la sombra lo oscurece y la luz lo ilumina — se lee como que el
// material tiene textura, no como un filtro encima.
//
// ── DÓNDE SE MUESTREA, que es lo que decide si queda ANCLADO ──────────────────────────────────────
// `noise_space` 0 = UV, 1 = posición de modelo.
//
// **UV es el que está anclado de verdad**, y es el default. Un UV es una coordenada fija del vértice:
// no cambia con la pose, con el estirado de huesos ni con nada. Es exactamente cómo se pega una
// textura, que es lo que este ruido reemplaza mientras tanto.
//
// La posición de modelo NO sirve para anclar, aunque suene a que sí: Godot aplica el SKINNING antes de
// `vertex()`, así que lo que se lee ahí ya viene deformado por la pose. Al caminar, esa posición se
// mueve y el grano se desliza sobre la piel. Queda como opción porque no depende del layout de UV, y
// para una malla con UV sucios puede ser el mal menor.
//
// `noise_scale` son celdas por unidad: en UV, a lo largo de todo el layout; en modelo, por metro.
uniform float noise_space : hint_range(0.0, 1.0) = 0.0;
uniform float noise_scale : hint_range(1.0, 300.0) = 60.0;
// Cuánto varía el BRILLO y cuánto la SATURACIÓN. Son perillas separadas porque hacen cosas distintas:
// solo brillo se lee como grano de superficie; solo saturación, como variación de tintura en la tela.
// La saturación usa el mismo truco que la sombra —extrapolar respecto de la luminancia— así que puede
// pasar de 1 y saturar de más, no solo desaturar.
uniform float noise_amount : hint_range(0.0, 1.0) = 0.0;
uniform float noise_saturation : hint_range(0.0, 2.0) = 0.0;

// ESTIRA EL GRANO. Multiplican la coordenada de muestreo, así que más alto = más fino EN ESE EJE.
// Con los dos iguales el grano es parejo; desbalanceados se convierte en vetas, que es lo que hace que
// una tela se lea como tejida y no como ruido.
uniform float noise_scale_x : hint_range(0.05, 20.0) = 1.0;
uniform float noise_scale_y : hint_range(0.05, 20.0) = 1.0;

// ── Ambiente ──────────────────────────────────────────────────────────────────────────────────────
// Cuánta luz de ambiente recibe el material. 1 = la que pone el Environment; 0 = ninguna.
//
// ⚠ ES LA PERILLA QUE DECIDE SI LA SOMBRA PUEDE LLEGAR A NEGRO, y no es obvio que sea esta.
// `shadow_value`, `shadow_saturation` y el tono solo le dan forma a la luz DIRECTA. El ambiente se
// suma por fuera, sin escalón, así que por más que pongas la sombra en negro puro el lado oscuro
// queda encendido por el cielo. Bajar esto es lo que abre el rango.
//
// Hubo una versión del shader con `ambient_light_disabled`, o sea esto clavado en 0, y salió mal
// porque no había con qué compensar el brillo perdido y el personaje quedaba negro. Ahora sí lo hay:
// `light_value` llega a 2. Un ambiente bajo con la luz subida es una combinación legítima.
//
// El otro camino es bajar el ambiente del Environment, pero eso es global y afecta a la ciudad entera.
// Esto es por material.
uniform float ambient_amount : hint_range(0.0, 1.0) = 1.0;

// ── Rim (opcional) ────────────────────────────────────────────────────────────────────────────────
// Separa la silueta del fondo sin outlines. Apagado por default: es un extra.
uniform float rim_strength : hint_range(0.0, 2.0) = 0.0;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;

// ── Máscaras de vertex paint ──────────────────────────────────────────────────────────────────────
// Vienen empaquetadas en el color de vértice por Tools/blender/pack_vertex_masks.py:
//
//   R = mask_shadow_grad    degradé general
//   G = mask_shadow_paint   sombras autorales
//   B = tinte 1             mask_flush en piel, mask_stain en ropa
//   A = tinte 2             mask_fade en ropa
//
// Las dos de sombra están SEPARADAS a propósito: son decisiones artísticas distintas y se quieren
// dosificar por separado. El día que la proporción esté encontrada se pueden fusionar y liberar G.
//
// B y A son genéricos —"llevá el color hacia este otro"— y por eso el mismo shader sirve para piel y
// para ropa: lo único que cambia es qué color se le pone a cada rol.
uniform float mask_shadow_grad : hint_range(0.0, 1.0) = 0.0;
uniform float mask_shadow_paint : hint_range(0.0, 1.0) = 0.0;
// Cuánto DESATURA la sombra de máscara, además de apagar luz. Una sombra pintada no es solo menos
// luz: el color pierde croma. Es la segunda mitad del efecto y va sobre el albedo, no sobre la luz.
uniform float mask_shadow_desat : hint_range(0.0, 1.0) = 0.0;
uniform vec4 mask_b_color : source_color = vec4(1.0, 0.45, 0.35, 1.0);
uniform float mask_b_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 mask_a_color : source_color = vec4(0.85, 0.85, 0.82, 1.0);
uniform float mask_a_amount : hint_range(0.0, 1.0) = 0.0;

// 0 = normal. 1..4 = mostrar UNA máscara sola en escala de grises, para autorar en Blender sabiendo
// qué está viendo el juego. Lo maneja el panel de estilo.
uniform int debug_mask : hint_range(0, 4) = 0;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

// El color de vértice llega con la curva sRGB→lineal ya aplicada: está MEDIDO que lo que se pinta como
// hex 808080 llega en 0.216 y no en 0.5. Deshacerla acá hace que la máscara responda como se pintó,
// que es lo único intuitivo al autorar.
vec3 lin_to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

// Oscurecer + saturar + sesgar el tono. Es la primitiva que usan la sombra y la luz.
//
// El sesgo va MULTIPLICATIVO para que la identidad del color base sobreviva: teñir por mezcla
// arrastraría todo hacia el mismo tono y un personaje rojo dejaría de tener sombra roja.
vec3 recolor(vec3 base, float value, float saturation, vec3 hue, float hue_amount) {
	vec3 c = base * value;
	c = mix(vec3(dot(c, LUMA)), c, saturation);
	c *= mix(vec3(1.0), hue, hue_amount);
	return max(c, vec3(0.0));
}

// Ruido de valor 3D, sin textura. Devuelve 0..1.
//
// Es de VALOR y no ruido blanco por vértice ni `fract(sin())` puro: interpola suave entre celdas, así
// que tiene grano con forma en vez de puntos sueltos, y el tamaño se controla con una sola escala.
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash13(i + vec3(0.0, 0.0, 0.0)), hash13(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 0.0)), hash13(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash13(i + vec3(0.0, 0.0, 1.0)), hash13(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash13(i + vec3(0.0, 1.0, 1.0)), hash13(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

varying vec4 masks;
/// Posición de modelo, solo para el modo alternativo del ruido (`noise_space` = 1).
///
/// NO queda anclada: Godot aplica el skinning antes de `vertex()`, así que esto ya viene deformado por
/// la pose y el grano se desliza sobre la superficie al animar. El modo anclado usa UV. Se mantiene
/// porque no depende del layout de UV.
varying vec3 noise_pos;

// Cuánta luz apagan las dos máscaras de sombra, combinadas.
//
// Se combinan en SCREEN y no sumando: dos sombras del 50% no dejan 0% de luz, dejan 25%. Nunca satura
// y pintar de más siempre hace algo.
float shadow_occlusion() {
	float sg = masks.r * mask_shadow_grad;
	float sp = masks.g * mask_shadow_paint;
	return 1.0 - (1.0 - sg) * (1.0 - sp);
}

void vertex() {
	masks = vec4(lin_to_srgb(COLOR.rgb), lin_to_srgb(vec3(COLOR.a)).r);
	noise_pos = VERTEX;
}

void fragment() {
	vec3 base = texture(albedo_texture, UV).rgb * tint.rgb;
	float occ = shadow_occlusion();

	// ⚠ LA MÁSCARA TIENE QUE APAGAR EL AMBIENTE TAMBIÉN, o nunca llega a negro.
	//
	// `light()` solo le da forma a la luz DIRECTA. El ambiente del Environment —que acá viene del
	// cielo y es claro— se suma por fuera, así que con la máscara al 100% la zona igual quedaba
	// iluminada y se sentía que el efecto "no llegaba". `AO` es el canal por el que se atenúa.
	//
	// `AO_LIGHT_AFFECT = 0` porque la luz directa ya la apaga `light()` con el mismo factor: si lo
	// subiéramos, se descontaría dos veces.
	//
	// `ambient_amount` va por el mismo canal: es una atenuación del ambiente igual que la máscara, solo
	// que pareja en toda la superficie en vez de pintada.
	AO = (1.0 - occ) * ambient_amount;
	AO_LIGHT_AFFECT = 0.0;

	// La otra mitad del efecto: la sombra pintada también DESATURA. Va sobre el albedo porque es una
	// propiedad del color, no de la luz que lo toca.
	base = mix(base, vec3(dot(base, LUMA)), occ * mask_shadow_desat);

	// Grano. `d` va de −1 a 1, centrado en 0 para que aclare y oscurezca por igual: sin el −0.5 subiría
	// el brillo medio del material y cambiar la intensidad se sentiría como cambiar la exposición.
	if (noise_amount > 0.0 || noise_saturation > 0.0) {
		vec3 np = (noise_space < 0.5) ? vec3(UV, 0.0) : noise_pos;
		np *= vec3(noise_scale_x, noise_scale_y, 1.0) * noise_scale;
		float d = (value_noise(np) - 0.5) * 2.0;
		base *= 1.0 + d * noise_amount;
		base = mix(vec3(dot(base, LUMA)), base, 1.0 + d * noise_saturation);
		base = max(base, vec3(0.0));
	}

	// Los dos tintes de máscara se aplican al ALBEDO, ANTES de la luz: son propiedades de la
	// superficie (una mancha, el rubor de la piel), no de cómo la ilumina el sol.
	base = mix(base, mask_b_color.rgb, masks.b * mask_b_amount);
	base = mix(base, mask_a_color.rgb, masks.a * mask_a_amount);

	if (debug_mask > 0) {
		float m = masks.a;
		if (debug_mask == 1) { m = masks.r; }
		else if (debug_mask == 2) { m = masks.g; }
		else if (debug_mask == 3) { m = masks.b; }
		base = vec3(m);
	}

	ALBEDO = base;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
}

void light() {
	float raw = dot(NORMAL, LIGHT);
	float ndotl = clamp(mix(max(raw, 0.0), raw * 0.5 + 0.5, light_wrap) + light_bias, 0.0, 1.0);

	// Cuantizar es OPCIONAL y se mezcla contra la rampa continua. El smoothstep está para que el borde
	// no aliasee en un personaje chico en pantalla, que es como se lo ve casi todo el tiempo.
	float n = float(band_count);
	float scaled = ndotl * n;
	float banded = (floor(scaled)
		+ smoothstep(0.5 - band_softness * 0.5, 0.5 + band_softness * 0.5, fract(scaled))) / n;
	float ramp = mix(ndotl, banded, band_amount);

	// El mismo factor que atenúa el ambiente vía `AO` en fragment(), acá aplicado a la luz directa.
	float lit = ramp * (1.0 - shadow_occlusion()) * ATTENUATION;

	vec3 shade = recolor(ALBEDO, shadow_value, shadow_saturation, shadow_hue.rgb, shadow_hue_amount);
	vec3 lite = recolor(ALBEDO, light_value, light_saturation, light_hue.rgb, light_hue_amount);
	DIFFUSE_LIGHT += mix(shade, lite, lit) * LIGHT_COLOR;

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	DIFFUSE_LIGHT += rim * rim_strength * ALBEDO * LIGHT_COLOR * ATTENUATION;
}
