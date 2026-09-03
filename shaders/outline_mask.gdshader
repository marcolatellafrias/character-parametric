shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, blend_mix, cull_disabled;

// MÁSCARA DEL CONTORNO — no dibuja nada, solo marca el stencil.
//
// Es la mitad invisible del contorno de hover. Marca en el buffer de stencil todos los píxeles que
// ocupa el objeto, y el pase de contorno (`outline.gdshader`, encadenado en `next_pass`) dibuja el
// casco inflado SOLO donde esta marca no está. Resultado: **una sola silueta del modelo entero** en vez
// de una por malla.
//
// Sin esto, cada malla se contorneaba sola: el casco de un brazo asoma por delante del torso en la
// costura, pasa el test de profundidad, y se ve una línea en medio del personaje. Ese era el efecto de
// "contornea cada mesh" — no un bug, sino lo que hace la técnica del casco invertido.
//
// Tres decisiones que parecen raras y no lo son:
//
// 1. `depth_test_disabled`. Este pase dibuja LA MISMA geometría que ya se dibujó opaca, o sea a
//    profundidad idéntica. El test por defecto es MENOR, así que a profundidad igual **falla** y no se
//    escribiría ni un píxel de stencil. Apagarlo es lo que hace que la marca exista.
//    No abre el contorno a través de las paredes: el que decide eso es el pase de contorno, que sí
//    tiene test de profundidad.
//
// 2. `ALPHA = 0.0` con `blend_mix`. Es cómo se escribe stencil sin escribir color: el fragmento se
//    procesa igual, la operación de stencil ocurre, y la mezcla no cambia nada.
//
// 3. Va al pase TRANSPARENTE (por eso escribe ALPHA), y no por gusto. `render_priority` solo ordena
//    transparentes; en opaco Godot ordena por profundidad y no hay forma de garantizar que TODAS las
//    máscaras se dibujen antes que TODOS los contornos. Con las dos en transparente y prioridades
//    distintas, el orden queda garantizado entre mallas.
stencil_mode write, compare_always, 1;

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
