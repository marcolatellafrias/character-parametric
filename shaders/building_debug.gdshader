shader_type spatial;
render_mode cull_back, diffuse_lambert;

// LA MALLA DEBUG DE EDIFICIOS: el color por vértice (barrio, sombreado por piso y por módulo) y, si se pide,
// una de las dos grillas encima —cada celda con un tinte distinto según su posición, translúcido, para que
// el color y el sombreado de abajo se sigan leyendo—.
//
// Las coordenadas de grilla vienen por vértice (ver BuildingShell): UV es (x, z) en celdas del módulo —la
// deformable—, UV2 es (x, z) en celdas de la matriz rígida de la superficie, CUSTOM0.x la altura en celdas
// del módulo. En las paredes se interpolan exactas. En las tapas (CUSTOM0.y = 1) no: son cuadriláteros
// generales, y la interpolación lineal se desvía de la bilineal de la grilla; traen la bilineal del núcleo
// en XZ (CUSTOM1, CUSTOM2) y cuánto cambian las coordenadas por unidad de sus parámetros (CUSTOM3), y acá se
// invierte por Newton desde la (p, q) interpolada (CUSTOM0.zw): la misma cuenta que
// PlacementGrid.world_to_cell, proyectando en vertical.

// 0 ninguna, 1 deformable (el módulo), 2 rígida (la superficie).
uniform int grid_mode : hint_range(0, 2) = 0;
uniform vec3 grid_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float grid_strength : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_pos;
varying vec2 module_xz;
varying vec2 rigid_xz;
varying vec4 face;
varying flat vec4 quad_a;
varying flat vec4 quad_b;
varying flat vec4 jacobian;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	module_xz = UV;
	rigid_xz = UV2;
	face = CUSTOM0;
	quad_a = CUSTOM1;
	quad_b = CUSTOM2;
	jacobian = CUSTOM3;
}

// Un tinte por celda a partir de la paridad de cada coordenada: vecinas distintas en cualquier dirección,
// también en diagonal (un chaflán cruza las celdas del módulo en diagonal).
float cell_level(float a, float b, float c) {
	float pa = mod(floor(a), 2.0);
	float pb = mod(floor(b), 2.0);
	float pc = mod(floor(c), 2.0);
	return (pa * 4.0 + pb * 2.0 + pc) / 7.0;
}

void fragment() {
	vec2 m = module_xz;
	vec2 r = rigid_xz;
	if (face.y > 0.5) {
		vec2 c0 = quad_a.xy;
		vec2 e1 = quad_a.zw;
		vec2 e3 = quad_b.xy;
		vec2 e13 = quad_b.zw;
		vec2 pq = face.zw;
		for (int i = 0; i < 4; i++) {
			vec2 f = c0 + e1 * pq.x + e3 * pq.y + e13 * (pq.x * pq.y) - world_pos.xz;
			vec2 jp = e1 + e13 * pq.y;
			vec2 jq = e3 + e13 * pq.x;
			float det = jp.x * jq.y - jp.y * jq.x;
			if (abs(det) < 0.000000001) {
				break;
			}
			pq -= vec2(jq.y * f.x - jq.x * f.y, jp.x * f.y - jp.y * f.x) / det;
		}
		vec2 d = pq - face.zw;
		m += jacobian.xy * d;
		r += jacobian.zw * d;
	}

	vec3 albedo = COLOR.rgb;
	if (grid_mode > 0) {
		float level;
		float per_pixel;
		if (grid_mode == 1) {
			level = cell_level(m.x, face.x, m.y);
			per_pixel = max(max(fwidth(m.x), fwidth(m.y)), fwidth(face.x));
		} else {
			level = cell_level(r.x, r.y, 0.0);
			per_pixel = max(fwidth(r.x), fwidth(r.y));
		}
		// De lejos, cuando una celda mide menos de un par de píxeles, el patrón se funde en su promedio en
		// vez de hervir.
		level = mix(level, 0.5, smoothstep(0.25, 0.75, per_pixel));
		albedo = mix(albedo, grid_tint, level * grid_strength);
	}
	ALBEDO = albedo;
}
