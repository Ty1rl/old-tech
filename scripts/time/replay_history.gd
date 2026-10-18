class_name ReplayHistory
extends RefCounted
## Bounded, value-only world snapshots used by EmergencyRewind.
##
## Callers pass the world delta (real delta * TimeController.world_scale) to
## record(), so the window covers recorded world seconds and sampling stops
## while the world is frozen. Snapshots must be plain values (no Objects,
## Callables or RIDs); deep validation runs only when validate_snapshots is set
## (checks enable it) to keep the hot path cheap. TimeController state is never
## stored here. A separate checkpoint (e.g. room start) is kept outside the
## rolling window so a recovery always has a safe target.

const MAX_PAYLOAD_BYTES := 65536
const MAX_DEPTH := 32

var window_seconds: float
var sample_interval: float
var max_snapshots: int
## Deep type validation of every snapshot. Off in play; checks turn it on.
var validate_snapshots := false
var rejected_count := 0
var last_diagnostic := ""

## Number of rolling snapshots (excludes the checkpoint).
var snapshot_count: int:
	get: return _payloads.size()
var has_checkpoint: bool:
	get: return not _checkpoint.is_empty()
## Recorded time of the newest record() call.
var clock: float:
	get: return _clock

var _times: Array[float] = []
var _payloads: Array[PackedByteArray] = []
var _checkpoint := PackedByteArray()
var _clock := 0.0
var _accumulator := 0.0


func _init(seconds: float = 18.0, rate: float = 12.0, snapshots: int = 240) -> void:
	window_seconds = maxf(0.1, seconds)
	sample_interval = 1.0 / maxf(0.1, rate)
	max_snapshots = maxi(1, snapshots)


static func from_settings(time_settings: TimeSettings) -> ReplayHistory:
	return ReplayHistory.new(time_settings.history_seconds, time_settings.history_sample_rate,
		time_settings.history_max_snapshots)


## Advances recorded time and stores capture.call() once per sample interval.
## Returns true when a snapshot was stored.
func record(world_delta: float, capture: Callable) -> bool:
	if not (world_delta > 0.0) or is_inf(world_delta):
		return false
	_clock += world_delta
	_accumulator += world_delta
	if _accumulator + 0.000001 < sample_interval:
		return false
	# Subtract instead of fmod: fmod(0.05, 0.05) can return ~0.05 and sample every tick.
	# Large deltas store one snapshot, never a catch-up burst.
	_accumulator -= sample_interval
	if _accumulator >= sample_interval or _accumulator < 0.0:
		_accumulator = 0.0
	return push(capture.call())


## Stores a snapshot at the current recorded time. Returns false when rejected.
func push(state: Variant) -> bool:
	var payload := _encode(state)
	if payload.is_empty():
		return false
	_times.append(_clock)
	_payloads.append(payload)
	_evict()
	return true


## Keeps one safe fallback state outside the rolling window (e.g. room start).
func seed_checkpoint(state: Variant) -> bool:
	var payload := _encode(state)
	if payload.is_empty():
		return false
	_checkpoint = payload
	return true


func clear_checkpoint() -> void:
	_checkpoint = PackedByteArray()


## Drops rolling snapshots and resets recorded time. The checkpoint is kept.
func clear() -> void:
	_times.clear()
	_payloads.clear()
	_clock = 0.0
	_accumulator = 0.0


## Recorded seconds between snapshot `index` (0 = oldest) and now.
func age_of(index: int) -> float:
	return maxf(0.0, _clock - _times[index])


func state_at(index: int) -> Dictionary:
	return _decode(_payloads[index])


func checkpoint_state() -> Dictionary:
	return _decode(_checkpoint)


## Returns snapshot `index` and discards every newer snapshot. Recorded time is
## rebased to that snapshot so later ages stay consistent.
func rewind_to(index: int) -> Dictionary:
	var state := state_at(index)
	_clock = _times[index]
	_accumulator = 0.0
	_times.resize(index + 1)
	_payloads.resize(index + 1)
	return state


func _evict() -> void:
	var drop := 0
	while drop < _times.size() and _clock - _times[drop] > window_seconds + 0.000001:
		drop += 1
	drop = maxi(drop, _times.size() - max_snapshots)
	if drop > 0:
		_times = _times.slice(drop)
		_payloads = _payloads.slice(drop)


func _encode(state: Variant) -> PackedByteArray:
	if typeof(state) != TYPE_DICTIONARY:
		return _reject("snapshot root must be a Dictionary")
	if validate_snapshots:
		var reason := _find_invalid(state, 0)
		if not reason.is_empty():
			return _reject(reason)
	var bytes := var_to_bytes(state)
	if bytes.is_empty() or bytes.size() > MAX_PAYLOAD_BYTES:
		return _reject("payload size %d outside 1..%d bytes" % [bytes.size(), MAX_PAYLOAD_BYTES])
	return bytes


func _decode(payload: PackedByteArray) -> Dictionary:
	if payload.is_empty():
		return {}
	var value: Variant = bytes_to_var(payload)
	return value if value is Dictionary else {}


func _reject(reason: String) -> PackedByteArray:
	rejected_count += 1
	last_diagnostic = "Rejected snapshot: " + reason
	push_warning(last_diagnostic)
	return PackedByteArray()


func _find_invalid(value: Variant, depth: int) -> String:
	if depth > MAX_DEPTH:
		return "nesting deeper than %d" % MAX_DEPTH
	match typeof(value):
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return "contains %s" % type_string(typeof(value))
		TYPE_DICTIONARY:
			for key: Variant in value:
				var reason := _find_invalid(key, depth + 1)
				if reason.is_empty():
					reason = _find_invalid(value[key], depth + 1)
				if not reason.is_empty():
					return reason
		TYPE_ARRAY:
			for item: Variant in value:
				var reason := _find_invalid(item, depth + 1)
				if not reason.is_empty():
					return reason
	return ""
