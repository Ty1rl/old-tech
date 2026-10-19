class_name ProtagonistVoice
extends RefCounted
## Choose a few relevant reactions across a run, rather than the busiest event.

const NORMAL_INTERVAL := 150.0
const EXTENDED_INTERVAL := 300.0
const EARLY_REPAIR_RESERVATION := 120.0
const IDLE_DELAY := 300.0
const RUN_TARGET := 4
const FAMILIES := {
	&"protagonist.repair_started": &"repair",
	&"protagonist.repair_completed": &"repair",
	&"protagonist.under_pressure": &"combat",
	&"protagonist.enemy_exposed": &"combat",
	&"protagonist.multi_kill": &"combat",
	&"protagonist.rewind_recovered": &"recovery",
	&"protagonist.room_cleared": &"milestone",
	&"protagonist.boss_defeated": &"milestone",
}
const PRIORITIES := {
	&"protagonist.boss_defeated": 60,
	&"protagonist.rewind_recovered": 50,
	&"protagonist.repair_started": 40,
	&"protagonist.repair_completed": 35,
	&"protagonist.room_cleared": 30,
	&"protagonist.enemy_exposed": 20,
	&"protagonist.multi_kill": 10,
	&"protagonist.under_pressure": 0,
}

var total := 0
var event_counts: Dictionary = {}
var family_counts: Dictionary = {}
var elapsed := 0.0
var _last_spoken := -EXTENDED_INTERVAL
var _idle_elapsed := 0.0
var _active := false
var _repairing := false
var _pending: Dictionary = {}


func reset() -> void:
	total = 0
	event_counts.clear()
	family_counts.clear()
	elapsed = 0.0
	_last_spoken = -EXTENDED_INTERVAL
	_idle_elapsed = 0.0
	_active = false
	_repairing = false
	clear_pending()


func clear_pending() -> void:
	_pending.clear()


func offer(event: StringName) -> void:
	if FAMILIES.has(event):
		# Remember only recent opportunities, never dialogue to deliver much later.
		_pending[event] = {"event": event, "expires": elapsed + 6.0, "variant": -1}


func step(delta: float, active: bool, repairing: bool, idle: bool) -> void:
	_active = active
	_repairing = repairing
	if not active:
		_idle_elapsed = 0.0
		clear_pending()
		return
	elapsed += maxf(0.0, delta)
	for event in _pending.keys():
		if float(_pending[event].expires) < elapsed:
			_pending.erase(event)
	if repairing:
		offer(&"protagonist.repair_started")
	_idle_elapsed = _idle_elapsed + maxf(0.0, delta) if idle else 0.0
	if not idle and int(_pending.get(&"protagonist.room_cleared", {}).get("variant", -1)) == 1:
		_pending.erase(&"protagonist.room_cleared")
	if _idle_elapsed >= IDLE_DELAY and not _pending.has(&"protagonist.room_cleared"):
		# Only "Let's keep moving" fits inactivity. Do not invent a new recording.
		_pending[&"protagonist.room_cleared"] = {
			"event": &"protagonist.room_cleared", "expires": elapsed + 1.0, "variant": 1,
		}


func choose() -> Dictionary:
	if not _active or (total >= RUN_TARGET and elapsed - _last_spoken < EXTENDED_INTERVAL):
		return {}
	var best: Dictionary = {}
	var best_score := -100000
	for event: StringName in _pending:
		var family: StringName = FAMILIES[event]
		if event == &"protagonist.repair_started" and not _repairing:
			continue
		if family == &"combat":
			if not family_counts.has(&"repair") and elapsed < EARLY_REPAIR_RESERVATION:
				continue
			# Common combat can fill a long session, but cannot monopolize a run.
			if family_counts.has(family) and elapsed - _last_spoken < EXTENDED_INTERVAL:
				continue
		var score := int(PRIORITIES[event]) - int(family_counts.get(family, 0)) * 20
		if not family_counts.has(family): score += 200
		if not event_counts.has(event): score += 50
		if score > best_score:
			best = _pending[event]
			best_score = score
	return best


func played(event: StringName) -> void:
	if not FAMILIES.has(event): return
	var family: StringName = FAMILIES[event]
	event_counts[event] = int(event_counts.get(event, 0)) + 1
	family_counts[family] = int(family_counts.get(family, 0)) + 1
	total += 1
	_last_spoken = elapsed
	_idle_elapsed = 0.0
	clear_pending()


func interval() -> float:
	return EXTENDED_INTERVAL if total >= RUN_TARGET else NORMAL_INTERVAL
