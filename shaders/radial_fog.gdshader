shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled;

uniform vec3 player_pos;
uniform float inner_radius = 100.0;
uniform float outer_radius = 150.0;
uniform vec4 fog_color : source_color = vec4(0.5, 0.55, 0.6, 1.0);
uniform sampler2D depth_texture : hint_depth_texture;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth_raw = texture(depth_texture, SCREEN_UV).x;

	if (depth_raw <= 0.0001) {
		discard;
	}

	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view_coords = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 view_pos = view_coords.xyz / view_coords.w;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view_pos, 1.0)).xyz;

	float dist_xz = length(world_pos.xz - player_pos.xz);
	float fog_amount = smoothstep(inner_radius, outer_radius, dist_xz);

	ALBEDO = fog_color.rgb;
	ALPHA = fog_amount;
}
