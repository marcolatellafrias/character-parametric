class_name Weather
extends Resource

## EL CLIMA — un solo juego de valores: niebla, cielo, luz ambiente, sol y tinte de pantalla.
##
## LA V1 TIENE UN CLIMA FIJO, y por eso esto es un Resource con defaults y no una tabla. Hubo nueve
## presets copiados del `timecyc.dat` de GTA San Andreas (`weather_presets.gd`) y una lista en F5 para
## alternarlos; se eligio uno y el resto quedo en el historial de git. Lo que sobrevivio de esa lectura
## son las tres decisiones de abajo, que siguen siendo estructurales.
##
## Los defaults de este archivo SON el clima del juego: el afinador (F6) los toca en vivo y su boton de
## copiar escupe exactamente estas lineas para pegarlas aca. No hay estado en disco ni overrides.
##
## ── 1. EL COLOR DE LA NIEBLA NO ES EL DEL CIELO, salvo que se pida ──
## En el timecyc niebla y horizonte son UNA sola columna (`Sky bot`). Con eso la silueta es imposible:
## una pieza saturada de niebla queda pintada del color que tiene detras. Es elegante, pero ata el color
## de la ciudad lejana al del cielo, y eso no gusto. `fog_from_sky` es esa disputa hecha interruptor:
## prendido copia el horizonte (regla San Andreas), apagado usa `fog_color` propio —el default, cielo
## stock con niebla azul—. Con el interruptor apagado la silueta existe, y de ella se ocupa el fundido
## de entrada (`City._fade_into_fog`).
##
## ── 2. EL CLIMA ES COLOR, NO ALCANCE ──
## En las nueve filas de timecyc que se leyeron, el far clip vale 2000 en TODAS. Por eso aca no hay
## distancias: viven en `WorldSettings`, porque ademas mandan el corte por distancia de la ciudad y el
## radio de spawn de autos. Cambiar el clima nunca puede achicar el mundo.
##
## ── 3. EL SOL SON DOS LUCES ──
## `DirectionalLight3D.light_angular_distance` es a la vez el TAMAÑO DEL DISCO que dibuja el cielo y el
## ancho de la PENUMBRA de la sombra (el sol real mide 0,53°). Un disco lindo borra las sombras entre
## edificios. Por eso `sun_size` y `shadow_softness` son campos separados y `CityFog` usa una luz para
## cada cosa. Con `sun_size` en 0 no hay disco y sigue habiendo sol, que es lo que San Andreas hace en
## lluvia y en tormenta de arena.

@export_group("Niebla")
## El color propio de la niebla. Solo se usa con `fog_from_sky` apagado.
@export var fog_color := Color(0.389, 0.499, 0.952)
## Prendido, la niebla toma el color del horizonte del cielo y la silueta se vuelve imposible (ver arriba).
@export var fog_from_sky := true
## Como se reparte la densidad entre las dos distancias: >1 la empuja al fondo y deja el medio campo
## limpio. En 1.0 sube lineal desde `fog_start_distance` y la ciudad se siente encerrada.
@export_range(0.1, 8.0, 0.05) var fog_curve := 1.05
## Cuanto se aclara la niebla mirando hacia el sol.
@export_range(0.0, 1.0, 0.01) var fog_sun_scatter := 0.13

@export_group("Nubes")
## Si las nubes volumétricas (Sunshine Clouds 2) se calculan. Apagadas por defecto: cuestan FPS y se están
## afinando; lo demás de las nubes se afina en el recurso (ver CityFog.clouds).
@export var clouds_enabled := false

@export_group("Cielo")
@export var sky_top := Color(0.16529846, 0.34908625, 0.61328125)
@export var sky_horizon := Color(0.3916626, 0.5430558, 0.7265625)
@export_range(0.0, 1.0, 0.01) var sky_curve := 0.17

@export_group("Luz ambiente")
@export var ambient := Color(0.20040894, 0.36905152, 0.77734375)
@export_range(0.0, 1.2, 0.01) var ambient_energy := 0.25

@export_group("Sol")
@export var sun_core := Color(1, 0.957, 0.902)
@export_range(0.0, 4.0, 0.05) var sun_energy := 1.1
## Altura sobre el horizonte, en grados: 0 es el horizonte, 90 el cenit.
@export_range(-10.0, 90.0, 1.0) var sun_elevation := 62.0
@export_range(0.0, 360.0, 1.0) var sun_azimuth := 35.0
## El disco que se ve en el cielo. En 0 no hay disco, pero sigue habiendo luz.
@export_range(0.0, 12.0, 0.1) var sun_size := 5.0
## El ancho de la penumbra. En 0 la sombra es dura.
@export_range(0.0, 4.0, 0.05) var shadow_softness := 0.3
## El brillo del disco y su halo. Va aparte de `sun_energy` porque son dos luces: subir la luz del
## mundo hasta donde se ve bien no tiene por que ser el mismo numero que hace que el sol se vea.
@export_range(0.0, 8.0, 0.05) var sun_disc_energy := 0.95
## El radio del halo alrededor del disco, en grados. Grande reparte el mismo brillo sobre medio cielo
## y el sol queda como un degrade lavado.
@export_range(0.0, 90.0, 1.0) var sun_glow := 56.0
## Como cae el halo del borde del disco hacia afuera. Chico lo pega contra el disco.
@export_range(0.01, 1.0, 0.01) var sun_curve := 0.15

@export_group("Filtro de pantalla")
## Dos capas sobre el cuadro terminado (ver Shaders/screen_tint.gdshader): la 1 multiplica —gris 0.5 no
## hace nada— y la 2 lava hacia un color. Es la perilla de "que tan pelicula vieja" se ve el juego. En
## San Andreas van con alpha 195/255; aca arrancan en 0 porque el tonemapping no es el de RenderWare y a
## esa fuerza se come el contraste.
@export var tint1 := Color(0.94117653, 0.5110294, 0.41176474)
@export_range(0.0, 1.0, 0.01) var tint1_strength := 0.0
@export var tint2 := Color(0.94921875, 0.5020709, 0.10752869)
@export_range(0.0, 1.0, 0.01) var tint2_strength := 0.0
