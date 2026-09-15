shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;

// LA CAJA DE UNA REGIÓN COLOCADA (ver CityIndex.add_region): un cubo unitario por instancia de MultiMesh,
// llevado al mundo con la MISMA bilineal que el placer usó para la pieza. El marco de la región va en la
// transformación de la instancia (origen y derivadas en x, y, z) y el término cruzado en
// INSTANCE_CUSTOM.xyz. No es una caja afín parecida: es la región exacta, con la curvatura de su grilla.
//
// Una grilla puede espejar un eje, y entonces el cubo sale con las caras al revés: se dibujan las dos y en
// el fragment se descarta la que mira hacia adentro, según el signo del determinante de la instancia.

uniform vec4 tint : source_color = vec4(1.0, 0.0, 0.0, 0.12);

varying float mirrored;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + INSTANCE_CUSTOM.xyz * (VERTEX.x * VERTEX.z);
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
	mirrored = determinant(mat3(MODEL_MATRIX)) < 0.0 ? 1.0 : 0.0;
}

void fragment() {
	if (FRONT_FACING == (mirrored > 0.5)) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
