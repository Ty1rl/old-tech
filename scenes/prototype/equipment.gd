class_name WeaponEquipment
extends RefCounted

signal repaired(tool: StringName, restored: float)

const DEFAULT_SETTINGS: WeaponConditionSettings = preload("res://scenes/weapons/settings/weapon_condition.tres")
const TOOLS: Array[StringName] = [&"ring", &"beam", &"cone"]
var settings: WeaponConditionSettings
var wear_scale := 1.0
var repair_steps: int:
	get: return clampi(settings.repair_steps, 1, 8)
const EPS := 0.000001

var repairing: StringName = &""
var training_protection: Array[StringName] = []
var _remaining: Dictionary = {}
var _repair_session: int = 0


func _init(p_settings: WeaponConditionSettings = DEFAULT_SETTINGS) -> void:
	settings = p_settings if p_settings != null else DEFAULT_SETTINGS
	reset_state()


func reset_state() -> void:
	_repair_session += 1
	repairing = &""
	_remaining.clear()
	for tool in TOOLS:
		_remaining[String(tool)] = capacity(StringName(tool))


func set_training_protection(tools: Array) -> void:
	training_protection.clear()
	for item in tools:
		var tool := StringName(item)
		if tool in TOOLS and not (tool in training_protection):
			training_protection.append(tool)


func is_training_protected(tool: StringName) -> bool:
	return tool in training_protection


func restore_tool(tool: StringName, fraction: float = 1.0) -> void:
	var key := String(tool)
	if not tool in TOOLS:
		return
	_remaining[key] = maxf(remaining(tool), capacity(tool) * clampf(fraction, 0.0, 1.0))


func capacity(tool: StringName) -> float:
	match tool:
		&"ring": return maxf(0.001, settings.ring_capacity)
		&"beam": return maxf(0.001, settings.beam_capacity)
		&"cone": return maxf(0.001, settings.cone_capacity)
	return 0.0


func remaining(tool: StringName) -> float:
	return float(_remaining.get(String(tool), 0.0))


func condition(tool: StringName) -> float:
	var cap := capacity(tool)
	return clampf(remaining(tool) / cap, 0.0, 1.0) if cap > 0.0 else 0.0


func is_full(tool: StringName) -> bool:
	return tool in TOOLS and remaining(tool) >= capacity(tool) - EPS


func can_use(tool: StringName, amount: float = EPS) -> bool:
	return tool in TOOLS and repairing != tool and amount > 0.0 and remaining(tool) > 0.0 and remaining(tool) + EPS >= amount * _wear_multiplier(tool)


# Returns usable shots/seconds, before difficulty wear. Continuous tools use
# this fraction for damage on their final tick; faster wear must not boost damage.
# Discrete shots must first call can_use(tool, 1).
# Tools listed in training_protection accept positive spend without reducing remaining.
func spend(tool: StringName, amount: float) -> float:
	if tool not in TOOLS or repairing == tool or amount <= 0.0:
		return 0.0
	var scale := _wear_multiplier(tool)
	var used := minf(remaining(tool) / scale, amount)
	if not (tool in training_protection):
		_remaining[String(tool)] = maxf(0.0, remaining(tool) - used * scale)
	return used


func _wear_multiplier(tool: StringName) -> float:
	return 1.0 if tool in training_protection else maxf(.01, wear_scale)


func begin_repair(tool: StringName) -> int:
	if tool not in TOOLS: return -1
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
	var step_size := capacity(tool) / float(repair_steps)
	if step_size <= 0.0:
		return 0
	return clampi(int(floor((remaining(tool) + EPS) / step_size)), 0, repair_steps - 1)


func next_checkpoint_capacity(tool: StringName) -> float:
	if is_full(tool):
		return capacity(tool)
	return capacity(tool) * float(stage(tool) + 1) / float(repair_steps)


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
	for tool in TOOLS:
		var key := String(tool)
		saved[key] = remaining(StringName(key))
	return {"remaining": saved}


func restore_state(data: Dictionary) -> void:
	_repair_session += 1
	repairing = &""
	var source: Dictionary = data.get("remaining", data) if data.get("remaining") is Dictionary else data
	for tool in TOOLS:
		var key := String(tool)
		var cap := capacity(StringName(key))
		var raw: Variant = source.get(key, source.get(StringName(key), data.get(key, data.get(StringName(key), cap))))
		_remaining[key] = clampf(float(raw), 0.0, cap)


func status_text() -> String:
	return "Service: ring %.0f launches | flash %.0f shots | bellows %.1fs" % [remaining(&"ring"), remaining(&"beam"), remaining(&"cone")]
