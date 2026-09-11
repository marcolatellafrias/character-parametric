shader_type spatial;
// Vidrio del domo de la nave (ver DomeHull).
//
// Los brillos son los del shader de vidrio del foro de Godot
// (forum.godotengine.org/t/how-do-i-create-a-transparent-glass-shader/47651/9): un especular muy
// concentrado que además sube el alfa, así el brillo se ve aunque el vidrio sea casi transparente.
//
// Aquel usa mezcla ADITIVA con alfa cero: solo puede aclarar. Acá la mezcla es la normal, para poder
// además teñir el vidrio y oscurecerlo hacia arriba con un gradiente marcado —abajo, por donde se mira
// hacia afuera y se ve el piso al aterrizar, queda cristalino; arriba, oscuro y casi opaco—.
//
// De las dos caras: el vidrio es un plano solo. Las dos se iluminan con la normal de AFUERA, la del vidrio
// de verdad (ver fragment()).
render_mode blend_mix, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Color y opacidad abajo y arriba del gradiente.
uniform vec4 bottom_tint : source_color = vec4(0.8, 0.9, 1.0, 0.15);
uniform vec4 top_tint : source_color = vec4(0.14, 0.17, 0.21, 0.75);
// Entre qué alturas —en el espacio de la nave— va el gradiente: el vidrio de abajo y el de arriba.
uniform float gradient_bottom = 1.0;
uniform float gradient_top = 5.0;
// Qué tan concentrado es el brillo: más alto, más chico.
uniform float shininess = 200.0;

varying float height;

void vertex() {
	height = VERTEX.y;
}

void fragment() {
	// Godot le da a la cara de atrás la normal dada vuelta —hacia adentro—, y como hacia adentro casi ninguna
	// cara mira al sol, desde adentro el domo se veía parejo y desde afuera facetado. Con la de afuera en las
	// dos, se ve igual de los dos lados. El frente es la cara de afuera: las esquinas se ordenan así.
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
	vec4 tint = mix(bottom_tint, top_tint, smoothstep(gradient_bottom, gradient_top, height));
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}

void light() {
	// La luz difusa de siempre (Lambert), para que el tinte se ilumine como el resto de la nave.
	DIFFUSE_LIGHT += clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION * LIGHT_COLOR / PI;

	// El brillo del shader del foro.
	vec3 half_vec = normalize(VIEW + LIGHT);
	float n_dot_half = max(0.0, dot(NORMAL, half_vec));
	float pf = pow(n_dot_half, shininess * SPECULAR_AMOUNT);
	SPECULAR_LIGHT += pf * ATTENUATION;
	ALPHA += pf * ATTENUATION;
}
