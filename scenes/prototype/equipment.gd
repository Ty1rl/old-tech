extends RefCounted

signal repaired(tool: StringName, restored: float)

const Tuning = preload("res://scenes/prototype/tuning.gd")
const EPS := 0.000001

var repairing: StringName = &""
var _remaining: Dictionary = {}
var _repair_session: int = 0


func _init() -> void:
	reset_state()


func reset_state() -> void:
	_repair_session += 1
	repairing = &""
	for tool in Tuning.GEAR:
		_remaining[String(tool)] = capacity(StringName(tool))


func capacity(tool: StringName) -> float:
	return float(Tuning.GEAR[String(tool)].capacity)


func remaining(tool: StringName) -> float:
	return float(_remaining[String(tool)])


func condition(tool: StringName) -> float:
	var cap := capacity(tool)
	return clampf(remaining(tool) / cap, 0.0, 1.0) if cap > 0.0 else 1.0


func is_full(tool: StringName) -> bool:
	return remaining(tool) >= capacity(tool) - EPS


func can_use(tool: StringName, amount: float = EPS) -> bool:
	return repairing != tool and amount > 0.0 and remaining(tool) > 0.0 and remaining(tool) + EPS >= amount


# Returns actual capacity spent. Discrete shots must first call can_use(tool, 1).
# Continuous tools use the returned fraction for damage/time on their final tick.
func spend(tool: StringName, amount: float) -> float:
	if repairing == tool or amount <= 0.0:
		return 0.0
	var spent := minf(remaining(tool), amount)
	_remaining[String(tool)] = maxf(0.0, remaining(tool) - spent)
	return spent


func begin_repair(tool: StringName) -> int:
	_repair_session += 1
	repairing = tool
	return _repair_session


func end_repair(session: int = -1) -> void:
	# A closing old panel must not cancel a newer repair session.
	if session == -1 or session == _repair_session:
		repairing = &""
		_repair_session += 1


func is_session_active(session: int, tool: StringName = &"") -> bool:
	if repairing == &"" or session != _repair_session:
		return false
	return tool == &"" or repairing == tool


# Derived from condition: 0..3 intact quarters while worn, 0 when full.
func stage(tool: StringName) -> int:
	if is_full(tool):
		return 0
	var step_size := capacity(tool) / float(Tuning.REPAIR_STEPS)
	if step_size <= 0.0:
		return 0
	return clampi(int(floor((remaining(tool) + EPS) / step_size)), 0, Tuning.REPAIR_STEPS - 1)


func next_checkpoint_capacity(tool: StringName) -> float:
	if is_full(tool):
		return capacity(tool)
	return capacity(tool) * float(stage(tool) + 1) / float(Tuning.REPAIR_STEPS)


# One completed section restores capacity up to the next quarter boundary.
# Closing a panel never touches capacity; unfinished gestures are UI-only.
func complete_step(tool: StringName, session: int = -1) -> float:
	if repairing != tool or (session != -1 and session != _repair_session) or is_full(tool):
		return 0.0
	var before := remaining(tool)
	var target := next_checkpoint_capacity(tool)
	var restored := maxf(0.0, minf(capacity(tool), target) - before)
	if restored <= 0.0:
		return 0.0
	if target >= capacity(tool) - EPS:
		_remaining[String(tool)] = capacity(tool)
	else:
		_remaining[String(tool)] = minf(capacity(tool), before + restored)
	repaired.emit(tool, restored)
	return restored


func capture_state() -> Dictionary:
	var saved := {}
	for tool in Tuning.GEAR:
		var key := String(tool)
		saved[key] = remaining(StringName(key))
	return {"remaining": saved}


func restore_state(data: Dictionary) -> void:
	_repair_session += 1
	repairing = &""
	var source: Dictionary = data.get("remaining", data) if data.get("remaining") is Dictionary else data
	for tool in Tuning.GEAR:
		var key := String(tool)
		var cap := capacity(StringName(key))
		var raw: Variant = source.get(key, source.get(StringName(key), data.get(key, data.get(StringName(key), cap))))
		_remaining[key] = clampf(float(raw), 0.0, cap)


func status_text() -> String:
	return "Service: ring %.0f launches | flash %.0f shots | cone %.1fs | clock %.1fs" % [
		remaining(&"ring"), remaining(&"beam"), remaining(&"cone"), remaining(&"clock")]
