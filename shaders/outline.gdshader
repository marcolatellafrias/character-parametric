shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix;

// CONTORNO DE HOVER — casco invertido, recortado por stencil.
//
// `cull_front` + empujar el vértice por su normal dibuja una copia inflada del objeto vista desde
// adentro: lo que asoma por los bordes es el contorno.
//
// `compare_not_equal, 1` es lo que lo vuelve una silueta ÚNICA: `outline_mask.gdshader` ya marcó con 1
// todos los píxeles del objeto, así que el casco de una malla queda descartado donde lo tapa otra malla
// del mismo objeto. Las costuras internas —brazo con torso, zapato con pierna, cada plano de ceja y de
// ojo— desaparecen solas, sin tener que elegir a mano qué mallas contornear.
//
// El grosor está en METROS, así que un objeto chico y uno grande no se ven igual. Es la limitación que
// queda de esta técnica; pasarlo a píxeles constantes se hace escalando por la distancia a cámara.

stencil_mode read, compare_not_equal, 1;

uniform float outline_thickness = 0.003;
uniform vec4 color : source_color = vec4(1.0, 1.0, 0.0, 1.0);

void vertex() {
	// `normalize` porque el .glb puede traer normales sin normalizar y ahí el grosor sale desparejo.
	VERTEX += normalize(NORMAL) * outline_thickness;
}

void fragment() {
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
