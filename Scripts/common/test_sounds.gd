class_name TestSounds

## SONIDOS DE PRUEBA — generados por código, sin archivos, y rudimentarios a propósito. Sirven para
## comprobar que las cosas suenan donde y cuando tienen que sonar hasta que haya sonidos de verdad; ese
## día se borra este archivo junto con sus dos usos (TouchComponent.start_control y Ship).

const MIX_RATE := 22050

static var _click: AudioStreamWAV = null
static var _hum: AudioStreamWAV = null


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
		wav.loop_end = samples.size()
	return wav
