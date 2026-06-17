shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D color_ramp : hint_default_white, filter_linear;

void fragment() {
	ALBEDO = albedo.rgb;
}

void light() {
	// NdotL: 1 = mirando a la luz, -1 = mirando al lado opuesto
	float NdotL = dot(NORMAL, LIGHT);
	// Remap de [-1, 1] a [0, 1] para usarlo como coordenada UV
	float ramp_uv = clamp(NdotL * 0.5 + 0.5, 0.0, 1.0);

	// Sampleamos el gradient: izquierda = sombra, derecha = luz
	vec3 ramp_color = texture(color_ramp, vec2(ramp_uv, 0.5)).rgb;

	DIFFUSE_LIGHT += ALBEDO * ramp_color * LIGHT_COLOR.rgb * ATTENUATION;
}