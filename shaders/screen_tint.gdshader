shader_type canvas_item;

// EL TINTE DE PANTALLA — las dos capas de corrección de color que San Andreas aplica sobre el cuadro
// terminado (`Alpha1 RGB1` y `Alpha2 RGB2` del timecyc, con alpha 195 de 255 en todas las filas que miré).
// Es un lavado fuerte y deliberado, y es donde vive buena parte de lo que uno recuerda como "el estilo".
//
// ⚠ ES UNA APROXIMACIÓN. La implementación real de Rockstar difiere entre PS2, PC y mobile —SkyGfx tiene un
// `COLORFILTER_PS2` y un `COLORFILTER_PC` distintos justamente por eso—, y no pude leer su código: el sitio
// del mod está caído. Así que acá hay dos capas con una convención razonable, no una copia fiel:
//
//   · CAPA 1, MULTIPLICATIVA (modulate 2x). Un gris 0.5 deja la imagen igual, más claro la levanta, más
//     oscuro la apaga. Es la que tiñe.
//   · CAPA 2, LAVADO. Mezcla plano hacia un color, que es lo que aplana el contraste y da el aire de
//     película vieja.
uniform vec4 tint1 : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float tint1_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint2 : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float tint2_strength : hint_range(0.0, 1.0) = 0.0;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	col *= mix(vec3(1.0), tint1.rgb * 2.0, tint1_strength);
	col = mix(col, tint2.rgb, tint2_strength);
	COLOR = vec4(col, 1.0);
}
