class_name TestSounds

## SONIDOS DE PRUEBA — generados por código, sin archivos, y rudimentarios a propósito. Sirven para
## comprobar que las cosas suenan donde y cuando tienen que sonar hasta que haya sonidos de verdad; ese
## día se borra este archivo junto con sus usos (TouchComponent.start_control, Ship y CarManager).
##
## NO hay FMOD en el proyecto —no está entre los addons y su GDExtension necesita el SDK propietario—, así
## que el motor de los autos se sintetiza acá como los otros dos. Hubo también un zumbido de fondo de
## ciudad; se saco porque molestaba.

const MIX_RATE := 22050

static var _click: AudioStreamWAV = null
static var _hum: AudioStreamWAV = null
static var _engine: AudioStreamWAV = null


## Un clic corto en la posición de `at`. El reproductor se borra solo al terminar.
static func click(at: Node3D) -> void:
	if not at.is_inside_tree():
		return
	if _click == null:
		_click = _make_click()
	var player := AudioStreamPlayer3D.new()
	player.stream = _click
	player.volume_db = -6.0
	at.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Zumbido grave en loop, para algo prendido. Lo prende y lo apaga quien lo agrega.
static func hum_player() -> AudioStreamPlayer3D:
	if _hum == null:
		_hum = _make_hum()
	var player := AudioStreamPlayer3D.new()
	player.name = "hum"
	player.stream = _hum
	player.volume_db = -12.0
	return player


## EL MOTOR DE UN AUTO, rudimentario y por ahora igual para todos. Posicional y de alcance corto: hay
## decenas sonando a la vez dentro del radio de dibujado.
static func engine_player() -> AudioStreamPlayer3D:
	if _engine == null:
		_engine = _make_engine()
	var player := AudioStreamPlayer3D.new()
	player.name = "engine"
	player.stream = _engine
	player.volume_db = -10.0
	player.unit_size = 20.0
	player.max_distance = 260.0
	return player


## 25 ms de un tono de 1.8 kHz que se apaga enseguida: suena a tecla.
static func _make_click() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(int(MIX_RATE * 0.025))
	for i in samples.size():
		var t := float(i) / MIX_RATE
		samples[i] = sin(TAU * 1800.0 * t) * exp(-t * 250.0)
	return _wav(samples, false)


## Un segundo de 110 Hz con dos armónicos. Frecuencias enteras en un segundo exacto: el final empalma con
## el principio y el loop no chasquea.
static func _make_hum() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(MIX_RATE)
	for i in samples.size():
		var t := float(i) / MIX_RATE
		samples[i] = 0.5 * sin(TAU * 110.0 * t) + 0.25 * sin(TAU * 220.0 * t) + 0.12 * sin(TAU * 330.0 * t)
	return _wav(samples, true)


## Un segundo de motor rudimentario. La fundamental es de 92 Hz y no de 55 porque a 55 el sonido se lo come
## el parlante —uno de notebook no baja de ~150 Hz— y lo único que llega son los armónicos. Diente de sierra —armónicos
## con peso 1/h— porque es lo que suena a explosión y no a flauta, y un golpeteo de 23 Hz encima, como una
## combustión despareja. 92 y 23 son enteros: el segundo cierra justo y el loop no chasquea.
static func _make_engine() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(MIX_RATE)
	for i in samples.size():
		var t := float(i) / MIX_RATE
		var value := 0.0
		for harmonic in range(1, 9):
			value += sin(TAU * 92.0 * float(harmonic) * t) / float(harmonic)
		samples[i] = value * 0.32 * (0.75 + 0.25 * sin(TAU * 23.0 * t))
	return _wav(samples, true)


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# UNA MENOS que el tamaño: `loop_end` es un ÍNDICE de muestra, no una cantidad. Apuntando a
		# `size()` el mezclador lee una muestra fuera del buffer en cada vuelta, y eso es un CLIC
		# periódico —el "tac, tac" que se escuchaba en los tres sonidos, el zumbido de la nave incluido—.
		wav.loop_end = samples.size() - 1
	return wav
