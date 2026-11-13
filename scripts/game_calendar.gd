extends RefCounted
class_name GameCalendar

## Deterministic clock, suitable for a future authoritative simulation worker.
## A 30-day game month equals exactly 86400 real seconds.
const REAL_SECONDS_PER_GAME_MONTH := 86400
const GAME_DAYS_PER_MONTH := 30
const REAL_SECONDS_PER_GAME_DAY := 2880
const MONTHS_PER_YEAR := 12
const MAX_OFFLINE_DAYS_PER_LOGIN := 90

static func date_for_day(day: int) -> Dictionary:
	var normalized: int = maxi(0, day)
	return {"year": 1 + int(normalized / 360), "month": 1 + int(normalized / 30) % 12, "day": 1 + normalized % 30}

static func label(day: int) -> String:
	var date: Dictionary = date_for_day(day)
	return "%02d.%02d.%04d" % [date["day"], date["month"], date["year"]]

static func due_days(last_tick_unix: int, now_unix: int, limit: int = MAX_OFFLINE_DAYS_PER_LOGIN) -> int:
	if last_tick_unix <= 0 or now_unix <= last_tick_unix:
		return 0
	return mini(maxi(0, limit), int((now_unix - last_tick_unix) / REAL_SECONDS_PER_GAME_DAY))

static func remaining_seconds(last_tick_unix: int, now_unix: int) -> int:
	if last_tick_unix <= 0:
		return REAL_SECONDS_PER_GAME_DAY
	var elapsed: int = maxi(0, now_unix - last_tick_unix)
	return REAL_SECONDS_PER_GAME_DAY - elapsed % REAL_SECONDS_PER_GAME_DAY

static func simulation_command(world_id: String, actor_id: String, tick: int, command_id: String, kind: String, payload: Dictionary) -> Dictionary:
	# Data-only envelope; no network calls and no trusted client-side economy.
	return {"protocol_version": 1, "world_id": world_id, "actor_id": actor_id, "tick": tick, "command_id": command_id, "type": kind, "payload": payload.duplicate(true)}
