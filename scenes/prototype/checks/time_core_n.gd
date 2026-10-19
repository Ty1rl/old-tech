extends SceneTree
# Round N Wave1 focused checks for the isolated time core:
# TimeSettings, TimeController, ReplayHistory, EmergencyRewind and the
# editor-visible scenes/time/time_core.tscn composition.

const CORE_SCENE := preload("res://scenes/time/time_core.tscn")
const SETTINGS_PATH := "res://scripts/time/time_settings.tres"
const EPS := 0.0001

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func near(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps


func settings_values(s: TimeSettings) -> Dictionary:
	var values := {}
	for property in s.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			values[property.name] = s.get(property.name)
	return values


func new_core() -> Node:
	var core: Node = CORE_SCENE.instantiate()
	root.add_child(core)
	var controller: TimeController = core.get_node("TimeController")
	controller.set_physics_process(false) # Deterministic manual advance below.
	return core


func run() -> void:
	check_global_classes()
	var shared: TimeSettings = load(SETTINGS_PATH)
	var before := settings_values(shared)
	check_scene_composition()
	check_hits_and_recharge()
	check_multiplier_without_shared_mutation()
	check_slow()
	check_voluntary_spending()
	check_depletion_and_recovery()
	check_exhaustion_and_retry()
	check_history()
	check_emergency_choices()
	check_empty_history_fallbacks()
	await check_native_pause()
	expect(settings_values(shared) == before, "Shared TimeSettings resource is never mutated at runtime")
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func check_global_classes() -> void:
	var found := {}
	for entry in ProjectSettings.get_global_class_list():
		found[String(entry["class"])] = entry
	var expected := {
		"TimeSettings": ["Resource", "res://scripts/time/time_settings.gd"],
		"TimeController": ["Node", "res://scripts/time/time_controller.gd"],
		"EmergencyRewind": ["Node", "res://scripts/time/emergency_rewind.gd"],
		"ReplayHistory": ["RefCounted", "res://scripts/time/replay_history.gd"],
	}
	for name: String in expected:
		expect(found.has(name), "Global class %s discovered after import" % name)
		if found.has(name):
			expect(String(found[name]["base"]) == expected[name][0], "%s extends %s" % [name, expected[name][0]])
			expect(String(found[name]["path"]) == expected[name][1], "%s lives at %s" % [name, expected[name][1]])


func check_scene_composition() -> void:
	var core: Node = CORE_SCENE.instantiate()
	root.add_child(core)
	var controller := core.get_node("TimeController") as TimeController
	var emergency := core.get_node("EmergencyRewind") as EmergencyRewind
	expect(controller != null and emergency != null, "time_core.tscn composes typed TimeController + EmergencyRewind")
	expect(controller.settings == load(SETTINGS_PATH), "Scene uses the shared settings resource")
	expect(emergency.time_controller == controller, "EmergencyRewind references its controller through an exported typed field")
	expect(emergency.process_mode == Node.PROCESS_MODE_ALWAYS, "Emergency logic keeps processing while the world is paused")
	expect(controller.is_physics_processing() and controller.process_physics_priority < 0, "Controller self-advances before gameplay nodes")
	expect(near(controller.meter, 100.0) and controller.charges_remaining == 3, "Fresh attempt has full meter and three charges")
	expect(near(controller.world_scale, 1.0) and not controller.emergency_active, "Fresh attempt runs at normal world time")
	core.free()


func check_hits_and_recharge() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var costs: Array[float] = []
	var meter_events := [0]
	t.hit_taken.connect(func(cost: float) -> void: costs.append(cost))
	t.meter_changed.connect(func(_m: float, _c: float) -> void: meter_events[0] += 1)
	expect(near(t.apply_hit(10.0), 10.0) and near(t.meter, 90.0), "Hit spends its base amount from the meter")
	expect(costs == [10.0], "hit_taken reports the spent cost")
	t.advance(1.0)
	expect(near(t.meter, 90.0), "No recharge during the post-hit delay")
	t.advance(1.0)
	expect(near(t.meter, 96.0), "Recharge resumes for the remainder after the delay (12/s * 0.5s)")
	var events_before: int = meter_events[0]
	t.advance(10.0)
	expect(near(t.meter, 100.0), "Recharge clamps at capacity")
	t.advance(1.0)
	expect(meter_events[0] == events_before + 1, "meter_changed is not emitted when nothing changes")
	expect(near(t.apply_hit(-5.0), 0.0) and near(t.apply_hit(NAN), 0.0) and near(t.meter, 100.0), "Invalid hit amounts are ignored")
	core.free()


func check_multiplier_without_shared_mutation() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var custom := TimeSettings.new()
	custom.hit_multiplier = 2.0
	t.settings = custom
	t.begin_attempt()
	expect(near(t.apply_hit(10.0), 20.0) and near(t.meter, 80.0), "hit_multiplier scales the caller's base amount")
	core.free()


func check_slow() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var slow_events: Array[bool] = []
	t.slow_changed.connect(func(active: bool) -> void: slow_events.append(active))
	t.slow_requested = true
	t.advance(1.0)
	expect(t.slow_active and near(t.world_scale, 0.18) and near(t.meter, 92.0), "Held slow drains 8/s and scales world time to 0.18")
	t.advance(11.0)
	expect(near(t.meter, 4.0) and t.slow_active, "Slow keeps draining without recharge")
	t.advance(1.0)
	expect(near(t.meter, 0.0) and not t.slow_active, "Slow stops at zero")
	expect(near(t.world_scale, lerpf(1.0, 0.18, 0.5)), "Tick that runs out averages slowed and normal time")
	expect(not t.emergency_active and t.charges_remaining == 3, "Voluntary slow to zero never starts an emergency or spends a charge")
	t.advance(1.0)
	expect(near(t.meter, 12.0) and not t.slow_active and near(t.world_scale, 1.0), "Held Space at zero lets the meter recharge (below start threshold)")
	t.advance(0.5)
	expect(near(t.meter, 18.0) and not t.slow_active, "Slow does not restart below slow_min_to_start")
	t.advance(0.5)
	expect(t.slow_active and near(t.meter, 14.0), "Slow resumes once the start threshold is reached")
	t.slow_requested = false
	t.advance(0.5)
	expect(not t.slow_active and near(t.meter, 20.0), "Releasing slow restores recharge immediately")
	expect(slow_events == [true, false, true, false], "slow_changed fires only on transitions")
	core.free()


func check_voluntary_spending() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	expect(t.try_spend_repair_checkpoint() and near(t.meter, 94.0), "Repair checkpoint pays its configured cost")
	expect(t.try_spend(89.0) and near(t.meter, 5.0), "Atomic voluntary spend")
	expect(not t.try_spend_repair_checkpoint() and near(t.meter, 5.0), "Unaffordable checkpoint changes nothing")
	t.set_repair_gesture_active(true)
	t.advance(2.0)
	expect(near(t.meter, 5.0), "Active repair gesture suppresses recharge")
	t.set_repair_gesture_active(false)
	t.advance(1.0)
	expect(near(t.meter, 17.0), "Idle repair panel does not block recharge")
	expect(t.try_spend(t.meter) and near(t.meter, 0.0) and not t.emergency_active, "Voluntary spending to zero is not a depletion")
	expect(not t.try_spend(-1.0), "Negative spend is rejected")
	t.apply_hit(1.0)
	expect(t.emergency_active and t.charges_remaining == 2, "Any hit at zero time is hit-driven depletion")
	core.free()


func check_depletion_and_recovery() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	var history := ReplayHistory.new(12.0, 20.0, 240)
	e.history = history
	for i in range(10):
		history.record(0.05, func() -> Dictionary: return {"tick": i})
	var started := [0]
	t.emergency_started.connect(func(_left: int) -> void: started[0] += 1)
	e.capture_present = func() -> Dictionary: return {"tick": "present"}
	t.slow_requested = true
	t.advance(0.1)
	t.apply_hit(150.0)
	expect(t.emergency_active and near(t.meter, 0.0) and t.charges_remaining == 2, "Depleting hit spends exactly one charge immediately")
	expect(started[0] == 1 and e.active and e.choice_count == 11, "Emergency auto-begins with NOW plus recorded moments")
	expect(not t.slow_active and near(t.world_scale, 0.0), "Emergency freezes world time and cancels slow")
	expect(near(t.apply_hit(30.0), 0.0) and t.charges_remaining == 2 and started[0] == 1, "Repeated hits during an emergency cannot deplete again")
	t.advance(5.0)
	expect(near(t.meter, 0.0) and near(t.world_scale, 0.0), "No recharge or drain while frozen")
	e.step_selection(3)
	expect(t.charges_remaining == 2, "Preview never refunds a charge")
	e.confirm()
	expect(not t.emergency_active and near(t.meter, 40.0) and t.protected, "Confirm grants the recovery floor and grace")
	expect(t.charges_remaining == 2, "Commit never refunds a charge")
	expect(near(t.apply_hit(25.0), 0.0) and near(t.meter, 40.0), "Recovery grace absorbs the same incoming hit")
	t.advance(1.6)
	expect(not t.protected and near(t.apply_hit(10.0), 10.0), "Hits cost time again after grace")
	core.free()


func check_exhaustion_and_retry() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	e.history = ReplayHistory.new()
	var exhausted := [0]
	t.attempt_exhausted.connect(func() -> void: exhausted[0] += 1)
	for round_index in range(3):
		t.advance(2.0)
		t.apply_hit(500.0)
		expect(e.active, "Emergency %d opens" % (round_index + 1))
		e.confirm()
	expect(t.charges_remaining == 0 and exhausted[0] == 0, "Three recoveries consume the three charges")
	t.advance(2.0)
	t.apply_hit(500.0)
	expect(t.exhausted and not t.emergency_active and exhausted[0] == 1, "Depletion with no charge ends the attempt once")
	expect(not e.active and near(t.world_scale, 1.0), "Exhaustion does not open an emergency or freeze the world")
	t.apply_hit(500.0)
	t.advance(3.0)
	expect(exhausted[0] == 1 and near(t.meter, 0.0), "Exhausted attempt ignores further hits and recharge")
	t.begin_attempt()
	expect(not t.exhausted and t.charges_remaining == 3 and near(t.meter, 100.0), "Retry starts a fresh attempt budget")
	t.apply_hit(500.0)
	e.abandon()
	expect(not e.active and t.emergency_active, "Abandon ends the session without restoring or refunding")
	t.begin_attempt()
	expect(not t.emergency_active and t.charges_remaining == 3, "begin_attempt clears an abandoned emergency")
	t.apply_hit(500.0)
	expect(e.active, "Emergency open before retry")
	t.begin_attempt()
	expect(not e.active and not t.emergency_active and t.charges_remaining == 3, "Room retry during an emergency closes the session without restore")
	core.free()
	# Code-built composition: the setter wires signals even after both nodes are ready.
	var controller := TimeController.new()
	var emergency := EmergencyRewind.new()
	root.add_child(controller)
	root.add_child(emergency)
	controller.set_physics_process(false)
	emergency.time_controller = controller
	controller.apply_hit(500.0)
	expect(emergency.active, "Code-assigned time_controller connects emergency_started")
	emergency.abandon()
	emergency.time_controller = null
	controller.begin_attempt()
	controller.apply_hit(500.0)
	expect(not emergency.active and controller.emergency_active, "Clearing the reference disconnects the old controller")
	controller.free()
	emergency.free()


func check_history() -> void:
	var settings: TimeSettings = load(SETTINGS_PATH)
	var h := ReplayHistory.from_settings(settings)
	expect(near(h.window_seconds, 18.0) and near(h.sample_interval, 1.0 / 12.0) and h.max_snapshots == 240, "History sizes come from TimeSettings")
	var stored := 0
	for i in range(600): # 20 recorded seconds at 30 Hz
		if h.record(1.0 / 30.0, func() -> Dictionary: return {"i": i}):
			stored += 1
	expect(stored >= 239 and stored <= 241, "Samples at ~12 Hz of recorded time (%d)" % stored)
	expect(h.snapshot_count <= 240 and h.age_of(0) <= 18.0 + EPS, "Window and count stay bounded")
	expect(int(h.state_at(h.snapshot_count - 1)["i"]) >= 598, "Newest snapshot is the latest capture")
	var count := h.snapshot_count
	expect(not h.record(0.0, func() -> Dictionary: return {}) and h.snapshot_count == count, "Zero delta (frozen world) records nothing")
	var target := count - 13
	var target_age := h.age_of(target)
	var state := h.rewind_to(target)
	expect(h.snapshot_count == target + 1 and near(h.age_of(target), 0.0), "rewind_to trims newer snapshots and rebases time")
	expect(target_age > 0.9 and target_age < 1.2 and state.has("i"), "Rewound state is the selected value snapshot")
	expect(not h.push([1, 2]) and h.rejected_count == 1, "Non-dictionary snapshot rejected")
	h.validate_snapshots = true
	expect(not h.push({"node": RefCounted.new()}), "Validation rejects object references")
	expect(not h.push({"callable": func() -> void: pass}), "Validation rejects callables")
	h.validate_snapshots = false
	var big := PackedByteArray()
	big.resize(ReplayHistory.MAX_PAYLOAD_BYTES + 16)
	expect(not h.push({"big": big}), "Oversized payload rejected without validation")
	expect(h.seed_checkpoint({"room": "start"}) and h.has_checkpoint, "Checkpoint seeded")
	h.clear()
	expect(h.snapshot_count == 0 and h.has_checkpoint and h.checkpoint_state() == {"room": "start"}, "clear keeps the checkpoint")


func check_emergency_choices() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	var h := ReplayHistory.new(12.0, 20.0, 240)
	e.history = h
	for i in range(40):
		h.record(0.05, func() -> Dictionary: return {"i": i})
	var previews: Array[int] = []
	var confirmed: Array[Dictionary] = []
	e.selection_changed.connect(func(index: int, _age: float, _s: Dictionary) -> void: previews.append(index))
	e.confirmed.connect(func(_age: float, s: Dictionary) -> void: confirmed.append(s))
	t.apply_hit(500.0)
	expect(e.active and e.choice_count == 41 and previews == [0], "Choices: NOW plus every recorded moment, NOW previewed first")
	expect(e.choice_state(0) == {} and near(e.choice_age(0), 0.0), "NOW without a capture callable is an empty present (consumer must supply capture)")
	e.step_selection(1)
	expect(near(e.choice_age(e.selected_index), 1.0, 0.06), "Step 1 selects ~1 world second back by timestamp")
	e.step_selection(100)
	expect(e.selected_index == 40 and int(e.choice_state(40)["i"]) == 0, "Selection clamps at the oldest moment")
	e.select(10)
	expect(e.selected_index == 10 and previews.size() == 4, "Wheel steps and direct select preview each change once")
	var age := e.choice_age(10)
	e.confirm()
	expect(confirmed.size() == 1 and int(confirmed[0]["i"]) == 30, "Confirm restores the selected moment")
	expect(h.snapshot_count == 31 and near(age, 0.45, 0.001), "Newer history discarded; ages are recorded seconds")
	expect(not e.active and not t.emergency_active, "Session and emergency end together")
	e.confirm()
	e.step_selection(1)
	expect(confirmed.size() == 1, "Confirm/select after the session are no-ops")
	core.free()


func check_empty_history_fallbacks() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	var h := ReplayHistory.new()
	e.history = h
	e.capture_present = func() -> Dictionary: return {"where": "now"}
	h.seed_checkpoint({"where": "room start"})
	var confirmed: Array[Dictionary] = []
	e.confirmed.connect(func(_age: float, s: Dictionary) -> void: confirmed.append(s))
	t.apply_hit(500.0)
	expect(e.choice_count == 2 and near(e.choice_age(1), EmergencyRewind.CHECKPOINT_AGE), "Empty history offers NOW plus the seeded checkpoint")
	e.select(1)
	e.confirm()
	expect(confirmed.size() == 1 and confirmed[0] == {"where": "room start"}, "Checkpoint choice restores the safe fallback")
	h.clear_checkpoint()
	t.advance(2.0)
	t.apply_hit(500.0)
	expect(e.active and e.choice_count == 1, "No history and no checkpoint still offers NOW (never softlocks)")
	e.confirm()
	expect(confirmed.size() == 2 and confirmed[1] == {"where": "now"} and not t.emergency_active, "NOW recovery resumes in place with floor/grace")
	var no_history := EmergencyRewind.new()
	root.add_child(no_history)
	expect(no_history.begin({"x": 1}) and no_history.choice_count == 1, "Emergency without any history object still works")
	no_history.free()
	core.free()


func check_native_pause() -> void:
	var core: Node = CORE_SCENE.instantiate()
	root.add_child(core)
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	t.slow_requested = true
	await physics_frame
	await physics_frame
	var drained := t.meter
	expect(drained < 100.0 and t.slow_active, "Auto-advance runs from the native physics tick")
	paused = true
	await physics_frame
	await physics_frame
	expect(near(t.meter, drained) and not t.can_process() and e.can_process(), "Tree pause stops the meter; emergency logic still processes")
	paused = false
	core.free()
