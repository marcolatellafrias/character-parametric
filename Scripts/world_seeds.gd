class_name WorldSeeds
extends RefCounted

# Universal world seeds, derived deterministically from the real Buenos Aires date.
# They are the SAME for every player worldwide on the same day/week — no networking
# needed — and the player cannot change them (they come from the calendar).
# See conceptual/world.md. Daily → climate/events/packages/HQ; weekly → city generation.

const BA_UTC_OFFSET_SECONDS := -3 * 3600  # America/Argentina/Buenos_Aires (UTC-3, no DST)

static func _ba_unix() -> int:
	return int(Time.get_unix_time_from_system()) + BA_UTC_OFFSET_SECONDS

static func ba_date() -> Dictionary:
	return Time.get_datetime_dict_from_unix_time(_ba_unix())

static func day_index() -> int:
	return int(floor(float(_ba_unix()) / 86400.0))

static func week_index() -> int:
	return int(floor(float(day_index()) / 7.0))

## Changes every day (BA time). Drives climate, world events, packages, HQ placement.
static func daily_seed() -> int:
	return _hash_int(day_index() * 2 + 1)

## Changes every week (BA time). Drives city generation.
static func weekly_seed() -> int:
	return _hash_int(week_index() * 2)

## Deterministic child seed from a base + salt, for sub-systems that need their own stream.
static func derive(base: int, salt: int) -> int:
	return _hash_int(base ^ ((salt + 1) * 0x9E3779B9))

# FNV-1a-style hash over the 8 bytes of n. Deterministic across machines for a given
# engine build (all players run the same version), which is all we need for shared seeds.
static func _hash_int(n: int) -> int:
	var h := 1469598103934665603
	for i in range(8):
		var b := (n >> (i * 8)) & 0xFF
		h = (h ^ b) * 1099511628211
	return h & 0x7FFFFFFFFFFFFFFF
