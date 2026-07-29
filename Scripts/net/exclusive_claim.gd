class_name ExclusiveClaim
extends Node
## Propiedad exclusiva de un recurso compartido, arbitrada por el host: un solo peer puede ser dueño
## a la vez. Se cuelga como hijo con nombre estable ("Claim") del interactuable, así el path coincide
## en todas las máquinas y los RPC rutean.
##
## Encapsula UNA sola vez, acá, el patrón host-authoritative de "pedir → conceder/negar → difundir",
## incluido el gotcha de que `rpc_id(propio_id)` NO se invoca localmente (el host se auto-despacha).
## Los interactuables lo usan por SEÑALES y no re-implementan arbitraje: el asiento, los controles del
## dashboard, y a futuro las estaciones de la nave. La propiedad (esto) y el ESTADO que cada
## interactuable sincroniza (valor del control, pose sentado) son capas separadas.
## Ver Scripts/city/docs/conceptual/multiplayer.md.

signal granted(peer: int)  ## El recurso pasó a ser de `peer` (se emite en todas las máquinas).
signal released()          ## El recurso quedó libre (se emite en todas las máquinas).
signal revoked()           ## Pediste el recurso pero no te lo dieron (solo en el que pidió).

## Peer dueño del recurso (0 = libre). Host-authoritative.
var owner_peer: int = 0
## Pediste soltar antes de que llegara la concesión (p.ej. un tap muy rápido): se suelta apenas llega.
var _wants_release: bool = false

func is_free() -> bool:
	return owner_peer == 0

## True si el dueño soy yo (offline: si está ocupado, soy yo — hay un solo jugador).
func is_mine() -> bool:
	if owner_peer == 0:
		return false
	if not multiplayer.has_multiplayer_peer():
		return true
	return owner_peer == multiplayer.get_unique_id()

# ── API pública ────────────────────────────────────────────────────────────────

## Pedir la propiedad. Offline: concedida al toque. Online: arbitra el host (self-dispatch seguro).
func request() -> void:
	_wants_release = false
	if not multiplayer.has_multiplayer_peer():
		owner_peer = 1
		granted.emit(1)
		return
	if multiplayer.is_server():
		_host_request(multiplayer.get_unique_id())  # el host se auto-despacha (rpc_id a sí mismo no invoca)
	else:
		_request.rpc_id(1)

## Liberar. Si la concesión todavía está en vuelo (tap rápido), lo marca para soltar al llegar.
func release() -> void:
	if not multiplayer.has_multiplayer_peer():
		if owner_peer != 0:
			owner_peer = 0
			released.emit()
		return
	if not is_mine():
		_wants_release = true  # aún no me la concedieron: soltar apenas llegue (ver _set_owner)
		return
	if multiplayer.is_server():
		_host_release(multiplayer.get_unique_id())
	else:
		_release.rpc_id(1)

# ── Arbitración (host-authoritative) ──────────────────────────────────────────

@rpc("any_peer", "reliable")
func _request() -> void:
	if multiplayer.is_server():
		_host_request(multiplayer.get_remote_sender_id())

@rpc("any_peer", "reliable")
func _release() -> void:
	if multiplayer.is_server():
		_host_release(multiplayer.get_remote_sender_id())

func _host_request(requester: int) -> void:
	if owner_peer == 0:
		_set_owner.rpc(requester)
	elif owner_peer != requester:
		if requester == multiplayer.get_unique_id():
			revoked.emit()          # el propio host perdió: rpc_id a sí mismo no invoca, avisar acá
		else:
			_revoke.rpc_id(requester)

func _host_release(requester: int) -> void:
	if owner_peer == requester:
		_set_owner.rpc(0)

## Host → todos (call_local, así el host también aplica): fija el dueño y emite la señal.
@rpc("authority", "reliable", "call_local")
func _set_owner(peer: int) -> void:
	owner_peer = peer
	if peer == 0:
		released.emit()
	else:
		granted.emit(peer)
		if is_mine() and _wants_release:  # pedí soltar antes de que me la concedieran → soltar ya
			_wants_release = false
			release()

## Host → al que perdió la carrera: no obtuviste el recurso.
@rpc("authority", "reliable", "call_remote")
func _revoke() -> void:
	revoked.emit()
