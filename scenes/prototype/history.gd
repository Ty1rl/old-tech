extends RefCounted

const MAX_SECONDS: float = 5.0
const SAMPLE_RATE: float = 20.0
const SAMPLE_INTERVAL: float = 1.0 / SAMPLE_RATE
const MAX_SNAPSHOTS: int = 100
const MAX_PAYLOAD_BYTES: int = 65536

var inspecting: bool = false
var selected_seconds_ago: float = 0.0
var encoded_bytes: int = 0
var rejected_count: int = 0
var last_diagnostic: String = ""

var available_seconds: float:
	get:
		if inspecting:
			if _entries.size() <= 1:
				return 0.0
			return minf(MAX_SECONDS, maxf(0.0, _inspection_time - float(_entries[0]["time"])))
		if _entries.is_empty():
			return 0.0
		return minf(MAX_SECONDS, maxf(0.0, _current_time - float(_entries[0]["time"])))

var snapshot_count: int:
	get:
		return _entries.size()

var _entries: Array[Dictionary] = []
var _pre_inspection_entries: Array[Dictionary] = []
var _current_time: float = 0.0
var _last_sample_time: float = 0.0
var _sample_accumulator: float = 0.0
var _inspection_time: float = 0.0
var _selected_index: int = -1
var _pre_inspection_time: float = 0.0
var _pre_inspection_last_sample_time: float = 0.0
var _pre_inspection_accumulator: float = 0.0


func record(delta: float, capture: Callable) -> void:
	if inspecting:
		return
	if is_nan(delta) or is_inf(delta) or delta <= 0.0:
		return
	var dt: float = minf(delta, MAX_SECONDS)
	_current_time += dt
	_sample_accumulator += dt
	if _sample_accumulator + 0.000001 < SAMPLE_INTERVAL:
		_evict_expired(_current_time)
		return
	if dt >= SAMPLE_INTERVAL:
		_sample_accumulator = 0.0
	else:
		_sample_accumulator = fmod(_sample_accumulator, SAMPLE_INTERVAL)
		if is_equal_approx(_sample_accumulator, SAMPLE_INTERVAL):
			_sample_accumulator = 0.0

	var sample_start: float = _last_sample_time
	var sample_end: float = _current_time - _sample_accumulator
	_last_sample_time = sample_end

	if not capture.is_valid():
		_record_diagnostic("Rejected snapshot: capture Callable is invalid")
		_evict_expired(_current_time)
		return

	var raw_state: Variant = capture.call()
	var payload: PackedByteArray = _encode_validated(raw_state)
	if not payload.is_empty():
		var stamp: float = sample_start
		if not _entries.is_empty() and stamp <= float(_entries[-1]["time"]) + 0.000001:
			stamp = float(_entries[-1]["time"]) + SAMPLE_INTERVAL
		_entries.append({
			"time": stamp,
			"end_time": sample_end,
			"payload": payload,
			"size": payload.size(),
		})
		encoded_bytes += payload.size()
	_evict_expired(_current_time)
	_evict_overflow()


func begin_inspection(present: Dictionary) -> void:
	var payload: PackedByteArray = _encode_validated(present)
	if payload.is_empty():
		return
	if inspecting:
		_entries = _pre_inspection_entries.duplicate()
		_current_time = _pre_inspection_time
		_last_sample_time = _pre_inspection_last_sample_time
		_sample_accumulator = _pre_inspection_accumulator
		_recalculate_bytes()

	_pre_inspection_entries = _entries.duplicate()
	_pre_inspection_time = _current_time
	_pre_inspection_last_sample_time = _last_sample_time
	_pre_inspection_accumulator = _sample_accumulator

	var present_time: float = _current_time
	if not _entries.is_empty() and present_time <= float(_entries[-1]["time"]) + 0.000001:
		present_time = float(_entries[-1]["time"]) + SAMPLE_INTERVAL
		_current_time = present_time

	_inspection_time = present_time
	_entries.append({
		"time": present_time,
		"end_time": present_time,
		"payload": payload,
		"size": payload.size(),
	})
	encoded_bytes += payload.size()
	_evict_expired(_inspection_time)
	_evict_overflow()

	inspecting = true
	_selected_index = _entries.size() - 1
	selected_seconds_ago = 0.0


func seek(seconds_ago: float) -> Dictionary:
	if not inspecting or _entries.is_empty():
		return {}
	var requested: float = 0.0 if (is_nan(seconds_ago) or is_inf(seconds_ago) or seconds_ago < 0.0) else seconds_ago
	var max_age: float = available_seconds
	var clamped: float = clampf(requested, 0.0, max_age)
	if clamped <= 0.000001 or _entries.size() == 1:
		_selected_index = _entries.size() - 1
		selected_seconds_ago = 0.0
		return _decode_payload(_entries[_selected_index]["payload"])

	var best_index: int = _entries.size() - 1
	var best_diff: float = INF
	for i in range(_entries.size()):
		var age: float = maxf(0.0, _inspection_time - float(_entries[i]["time"]))
		var diff: float = absf(age - clamped)
		if diff < best_diff - 0.000001:
			best_diff = diff
			best_index = i

	_selected_index = best_index
	if _selected_index == _entries.size() - 1:
		selected_seconds_ago = 0.0
	else:
		selected_seconds_ago = maxf(0.0, _inspection_time - float(_entries[_selected_index]["time"]))
	return _decode_payload(_entries[_selected_index]["payload"])


func commit_inspection() -> Dictionary:
	if not inspecting or _entries.is_empty():
		inspecting = false
		selected_seconds_ago = 0.0
		_selected_index = -1
		return {}

	var idx: int = clampi(_selected_index, 0, _entries.size() - 1)
	var chosen: Dictionary = _decode_payload(_entries[idx]["payload"])
	if idx == _entries.size() - 1:
		# At NOW (original present), resume without jumping or discarding history.
		_entries = _pre_inspection_entries.duplicate()
		_current_time = _pre_inspection_time
		_last_sample_time = _pre_inspection_last_sample_time
		_sample_accumulator = _pre_inspection_accumulator
	else:
		# Jump to past snapshot: truncate future and rebase recorder to selected moment.
		var selected_time: float = float(_entries[idx]["time"])
		var rebased_time: float = float(_entries[idx]["end_time"])
		var retained: Array[Dictionary] = []
		for entry in _pre_inspection_entries:
			if float(entry["time"]) <= selected_time + 0.000001:
				retained.append(entry)
		_entries = retained
		_current_time = rebased_time
		_last_sample_time = rebased_time
		_sample_accumulator = 0.0
		_recalculate_bytes()
		_evict_expired(_current_time)
		_evict_overflow()

	_pre_inspection_entries.clear()
	inspecting = false
	selected_seconds_ago = 0.0
	_selected_index = -1
	_recalculate_bytes()
	return chosen


func cancel_inspection() -> Dictionary:
	if not inspecting or _entries.is_empty():
		inspecting = false
		selected_seconds_ago = 0.0
		_selected_index = -1
		return {}

	var original_present: Dictionary = _decode_payload(_entries[-1]["payload"])
	_entries = _pre_inspection_entries.duplicate()
	_current_time = _pre_inspection_time
	_last_sample_time = _pre_inspection_last_sample_time
	_sample_accumulator = _pre_inspection_accumulator
	_pre_inspection_entries.clear()
	inspecting = false
	selected_seconds_ago = 0.0
	_selected_index = -1
	_recalculate_bytes()
	return original_present


func clear() -> void:
	_entries.clear()
	_pre_inspection_entries.clear()
	inspecting = false
	selected_seconds_ago = 0.0
	encoded_bytes = 0
	_current_time = 0.0
	_last_sample_time = 0.0
	_sample_accumulator = 0.0
	_inspection_time = 0.0
	_selected_index = -1
	_pre_inspection_time = 0.0
	_pre_inspection_last_sample_time = 0.0
	_pre_inspection_accumulator = 0.0


func _evict_expired(reference_time: float) -> void:
	while not _entries.is_empty() and (reference_time - float(_entries[0]["time"])) > MAX_SECONDS + 0.000001:
		var removed: Dictionary = _entries.pop_front()
		encoded_bytes = maxi(0, encoded_bytes - int(removed["size"]))


func _evict_overflow() -> void:
	while _entries.size() > MAX_SNAPSHOTS:
		var removed: Dictionary = _entries.pop_front()
		encoded_bytes = maxi(0, encoded_bytes - int(removed["size"]))


func _recalculate_bytes() -> void:
	var total: int = 0
	for entry in _entries:
		total += int(entry["size"])
	encoded_bytes = total


func _encode_validated(state: Variant) -> PackedByteArray:
	if typeof(state) != TYPE_DICTIONARY:
		_record_diagnostic("Rejected snapshot: root payload must be a Dictionary")
		return PackedByteArray()
	var dict_state: Dictionary = state
	var invalid_reason: String = _find_invalid_type(dict_state, 0)
	if not invalid_reason.is_empty():
		_record_diagnostic("Rejected snapshot: " + invalid_reason)
		return PackedByteArray()
	var bytes: PackedByteArray = var_to_bytes(dict_state)
	if bytes.is_empty():
		_record_diagnostic("Rejected snapshot: serialization produced empty payload")
		return PackedByteArray()
	if bytes.size() > MAX_PAYLOAD_BYTES:
		_record_diagnostic("Rejected snapshot: payload size %d B exceeds %d B cap" % [bytes.size(), MAX_PAYLOAD_BYTES])
		return PackedByteArray()
	return bytes


func _decode_payload(payload: PackedByteArray) -> Dictionary:
	if payload.is_empty():
		return {}
	var restored: Variant = bytes_to_var(payload)
	if typeof(restored) == TYPE_DICTIONARY:
		return restored
	return {}


func _find_invalid_type(value: Variant, depth: int) -> String:
	if depth > 32:
		return "nesting depth exceeds 32"
	var t: int = typeof(value)
	if t == TYPE_OBJECT or t == TYPE_CALLABLE or t == TYPE_SIGNAL or t == TYPE_RID:
		return "contains disallowed reference type (%s)" % type_string(t)
	if t == TYPE_DICTIONARY:
		var d: Dictionary = value
		for k in d:
			var key_err: String = _find_invalid_type(k, depth + 1)
			if not key_err.is_empty():
				return key_err
			var val_err: String = _find_invalid_type(d[k], depth + 1)
			if not val_err.is_empty():
				return val_err
	elif t == TYPE_ARRAY:
		var arr: Array = value
		for item in arr:
			var item_err: String = _find_invalid_type(item, depth + 1)
			if not item_err.is_empty():
				return item_err
	return ""


func _record_diagnostic(message: String) -> void:
	rejected_count += 1
	last_diagnostic = message
	push_warning(message)
