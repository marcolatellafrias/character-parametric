shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 0.0, 1.0); // Amarillo
uniform float intensity : hint_range(0.0, 5.0) = 2.0;

void fragment() {
    ALBEDO = shine_color.rgb;
    // Esto crea el efecto de borde suave
    float fresnel = pow(1.0 - dot(NORMAL, VIEW), 3.0); 
    ALPHA = fresnel * shine_color.a * intensity;
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
