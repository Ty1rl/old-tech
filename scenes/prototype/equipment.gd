extends RefCounted

const Tuning = preload("res://scenes/prototype/tuning.gd")
var repairing: StringName = &""
var _remaining: Dictionary = {}
var _stages: Dictionary = {}
var _repair_session: int = 0


func _init() -> void:
	reset_state()


func reset_state() -> void:
	_repair_session += 1
	repairing = &""
	for tool in Tuning.GEAR:
		_remaining[tool] = capacity(tool)
		_stages[tool] = 0


func capacity(tool: StringName) -> float:
	return float(Tuning.GEAR[String(tool)].capacity)


func remaining(tool: StringName) -> float:
	return float(_remaining[String(tool)])


func can_use(tool: StringName, amount: float = 0.000001) -> bool:
	return repairing != tool and amount > 0.0 and remaining(tool) + 0.0000001 >= amount


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


func stage(tool: StringName) -> int:
	return int(_stages[String(tool)])


# One completed puzzle section restores one quarter of a full service interval.
# Closing a panel never touches capacity or stage; unfinished gestures are UI-only.
func complete_step(tool: StringName) -> float:
	if repairing != tool:
		return 0.0
	var restored := minf(capacity(tool) - remaining(tool), capacity(tool) / Tuning.REPAIR_STEPS)
	if restored <= 0.0:
		return 0.0
	_remaining[String(tool)] = remaining(tool) + restored
	_stages[String(tool)] = (stage(tool) + 1) % Tuning.REPAIR_STEPS
	if is_equal_approx(remaining(tool), capacity(tool)):
		_stages[String(tool)] = 0
	return restored


func status_text() -> String:
	return "Service: ring %.0f launches | flash %.0f shots | cone %.1fs | clock %.1fs" % [
		remaining(&"ring"), remaining(&"beam"), remaining(&"cone"), remaining(&"clock")]
