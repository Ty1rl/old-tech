extends SceneTree
# Round O Wave A: time capabilities, slow input reliability, recovery consistency,
# 18 s / 12 Hz history and the authored slow_time action. Core-level; runs without
# the arena so it is valid on the standalone branch.

const CORE_SCENE := preload("res://scenes/time/time_core.tscn")
const SETTINGS: TimeSettings = preload("res://scripts/time/time_settings.tres")
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


func new_core() -> Node:
	var core: Node = CORE_SCENE.instantiate()
	root.add_child(core)
	(core.get_node("TimeController") as TimeController).set_physics_process(false)
	return core


func run() -> void:
	check_authored_input()
	check_capability_defaults_and_slow_gate()
	check_rewind_lock()
	check_fresh_press_and_release()
	check_consistent_recoveries()
	check_history_window()
	check_full_window_choices()
	check_payload_cap_fallback()
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func check_authored_input() -> void:
	expect(InputMap.has_action(&"slow_time"), "slow_time is authored in project.godot (no arena needed)")
	var events := InputMap.action_get_events(&"slow_time")
	expect(events.size() == 1, "slow_time has exactly one binding (no aliases)")
	if events.size() == 1:
		var key := events[0] as InputEventKey
		expect(key != null and key.physical_keycode == KEY_SPACE and key.keycode == KEY_NONE, "slow_time binds PHYSICAL Space")
	for alias in [&"time_slow", &"slow"]:
		expect(not InputMap.has_action(alias), "No legacy alias action '%s'" % alias)
	var press := InputEventKey.new()
	press.physical_keycode = KEY_SPACE
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	expect(Input.is_action_pressed(&"slow_time"), "Physical Space press drives the native action state")
	var release := InputEventKey.new()
	release.physical_keycode = KEY_SPACE
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	expect(not Input.is_action_pressed(&"slow_time"), "Release clears the native action state")


func check_capability_defaults_and_slow_gate() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var changes: Array = []
	t.capabilities_changed.connect(func(s: bool, r: bool) -> void: changes.append([s, r]))
	expect(t.slow_unlocked and t.rewind_unlocked, "Sandbox defaults: slow and rewind unlocked")
	t.set_capabilities(false, false)
	t.set_capabilities(false, false)
	expect(changes == [[false, false]], "capabilities_changed fires once per actual change")
	t.slow_requested = true
	t.advance(1.0 / 30.0)
	expect(not t.slow_active and near(t.world_scale, 1.0) and near(t.meter, 100.0), "Locked slow: holding the key does nothing")
	t.begin_attempt()
	expect(not t.slow_unlocked and not t.rewind_unlocked, "Capabilities survive begin_attempt")
	t.set_capabilities(true, false)
	t.advance(1.0 / 30.0)
	expect(t.slow_active and near(t.world_scale, 0.18), "Unlocking slow while held takes effect on the next tick")
	t.set_capabilities(false, false)
	expect(not t.slow_active, "Re-locking slow stops an active slow immediately")
	t.advance(1.0 / 30.0)
	expect(near(t.world_scale, 1.0), "Locked slow keeps world time normal")
	core.free()


func check_rewind_lock() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	e.history = ReplayHistory.new()
	var exhausted := [0]
	var emergencies := [0]
	t.attempt_exhausted.connect(func() -> void: exhausted[0] += 1)
	t.emergency_started.connect(func(_left: int) -> void: emergencies[0] += 1)
	t.set_capabilities(true, false)
	t.apply_hit(500.0)
	expect(t.exhausted and exhausted[0] == 1 and emergencies[0] == 0, "Locked rewind: depletion requests room retry, no emergency")
	expect(t.charges_remaining == 3 and not e.active, "Locked rewind spends no hidden charge")
	t.apply_hit(500.0)
	expect(exhausted[0] == 1, "Further hits after exhaustion are ignored")
	t.begin_attempt()
	expect(not t.force_depletion() or (t.exhausted and t.charges_remaining == 3 and emergencies[0] == 0), "force_depletion while locked also retries without a charge")
	t.begin_attempt()
	t.set_capabilities(true, true)
	t.apply_hit(500.0)
	expect(t.emergency_active and e.active and t.charges_remaining == 2 and emergencies[0] == 1, "Unlocked rewind: depletion opens a real emergency and spends one charge")
	t.set_capabilities(true, false)
	expect(t.emergency_active and e.active, "Locking rewind does not cancel an emergency already open")
	e.confirm()
	expect(not t.emergency_active, "Open emergency still confirms after locking")
	core.free()


func check_fresh_press_and_release() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var dt := 1.0 / 30.0
	t.try_spend(95.0) # 5 units: below the held-resume threshold
	t.slow_requested = true
	t.advance(dt)
	expect(t.slow_active and near(t.world_scale, 0.18), "Fresh press with 5 units starts slow on the very next tick")
	t.slow_requested = false
	t.advance(dt)
	expect(not t.slow_active and near(t.world_scale, 1.0), "Release stops slow on the next tick")
	t.slow_requested = true
	var ticks := 0
	while ticks < 120 and (t.slow_active or ticks == 0):
		t.advance(dt)
		ticks += 1
	expect(near(t.meter, 0.0) and not t.slow_active, "Held slow runs the meter to zero and stops")
	var flickered := false
	for i in range(30): # one second still held, meter recharging to 12
		t.advance(dt)
		flickered = flickered or t.slow_active
	expect(not flickered and t.meter > 11.0 and t.meter < 15.0, "Still-held key does not flicker slow on below the resume threshold")
	t.slow_requested = false
	t.slow_requested = true
	t.advance(dt)
	expect(t.slow_active, "Release + fresh press restarts slow with any time left")
	t.slow_requested = false
	t.advance(dt)
	t.try_spend(t.meter)
	t.slow_requested = true
	t.advance(dt)
	expect(not t.slow_active and near(t.world_scale, 1.0), "Fresh press with zero time does nothing")
	var waited := 0.0
	while not t.slow_active and waited < 3.0:
		t.advance(dt)
		waited += dt
	expect(t.slow_active and waited > 1.1 and waited < 1.4, "Held key resumes slow once the meter reaches 15 (%.2fs)" % waited)
	t.slow_requested = false
	t.advance(dt)
	expect(not t.slow_active, "Release always stops slow")
	core.free()


func check_consistent_recoveries() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	var h := ReplayHistory.from_settings(t.settings)
	e.history = h
	var after: Array = []
	var cases := ["hit while slowing", "hit near empty", "teaching depletion"]
	for i in range(cases.size()):
		for k in range(24):
			h.record(1.0 / 12.0, func() -> Dictionary: return {"k": k})
		if i == 0:
			t.slow_requested = true
			t.advance(0.5)
			t.apply_hit(500.0)
			t.slow_requested = false
		elif i == 1:
			t.try_spend(t.meter - 2.0)
			t.apply_hit(30.0)
		else:
			t.force_depletion()
		e.step_selection(6)
		e.confirm()
		var meter_now := t.meter
		var protected_now := t.protected
		t.apply_hit(10.0)
		var absorbed := near(t.meter, meter_now)
		t.advance(t.settings.recovery_grace_seconds + 0.1)
		after.append([meter_now, protected_now, absorbed, snappedf(t.meter, 0.001), t.charges_remaining])
	expect(after[0][0] == after[1][0] and after[1][0] == after[2][0] and near(after[0][0], 40.0), "Every recovery restores the same floor (%s)" % str(after))
	expect(after.all(func(row: Array) -> bool: return row[1] and row[2]), "Every recovery grants the same grace")
	expect(after[0][3] == after[1][3] and after[1][3] == after[2][3], "Recharge after grace is identical each time (no accumulated delay)")
	expect(after.map(func(row: Array) -> int: return row[4]) == [2, 1, 0], "Charges only go down: 2, 1, 0")
	t.advance(5.0)
	t.apply_hit(500.0)
	expect(t.exhausted and not e.active, "Fourth depletion exhausts the attempt; no charge refunded")
	core.free()


func check_history_window() -> void:
	expect(near(SETTINGS.history_seconds, 18.0) and near(SETTINGS.history_sample_rate, 12.0) and SETTINGS.history_max_snapshots == 240, "Default history is 18 world s at 12 Hz, cap 240")
	var h := ReplayHistory.from_settings(SETTINGS)
	var stored := 0
	for i in range(900): # 30 world seconds at 30 Hz
		if h.record(1.0 / 30.0, func() -> Dictionary: return {"i": i}):
			stored += 1
	expect(stored >= 358 and stored <= 362, "Samples at 12 Hz of world time (%d over 30 s)" % stored)
	expect(h.snapshot_count >= 215 and h.snapshot_count <= 217, "18 s window keeps ~216 snapshots (%d)" % h.snapshot_count)
	expect(h.age_of(0) <= 18.0 + EPS and h.age_of(0) >= 17.8, "Oldest snapshot is ~18 world seconds old (%.2f)" % h.age_of(0))
	expect(h.snapshot_count <= 240, "Never exceeds the 240 snapshot cap")
	var dense := ReplayHistory.new(30.0, 30.0, 240)
	for i in range(1200):
		dense.record(1.0 / 30.0, func() -> Dictionary: return {"i": i})
	expect(dense.snapshot_count == 240, "Cap bounds memory even when window * rate exceeds it")
	var slowed := ReplayHistory.from_settings(SETTINGS)
	for i in range(300): # 10 real seconds at 0.18 world scale
		slowed.record((1.0 / 30.0) * 0.18, func() -> Dictionary: return {"i": i})
	expect(slowed.snapshot_count >= 20 and slowed.snapshot_count <= 22, "Slowed play records world time, not real time (%d)" % slowed.snapshot_count)


func check_full_window_choices() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	var h := ReplayHistory.from_settings(t.settings)
	e.history = h
	for i in range(216):
		h.record(1.0 / 12.0, func() -> Dictionary: return {"i": i})
	t.apply_hit(500.0)
	expect(e.choice_count == 217, "Full buffer offers NOW + 216 recorded moments")
	e.step_selection(1)
	expect(near(e.choice_age(1), 0.0, 0.001), "One notch is the newest recorded moment")
	e.step_selection(1000)
	expect(e.selected_index == 216 and e.choice_age(216) > 17.8, "Oldest choice is ~18 world seconds back (%.2f)" % e.choice_age(216))
	e.step_selection(-1)
	var chosen := e.choice_state(e.selected_index)
	var confirmed: Array[Dictionary] = []
	e.confirmed.connect(func(_a: float, s: Dictionary) -> void: confirmed.append(s))
	e.confirm()
	expect(confirmed.size() == 1 and confirmed[0] == chosen, "Confirm restores exactly the previewed snapshot")
	expect(h.snapshot_count == 2, "History newer than the chosen moment is discarded")
	core.free()


func check_payload_cap_fallback() -> void:
	var core := new_core()
	var t := core.get_node("TimeController") as TimeController
	var e := core.get_node("EmergencyRewind") as EmergencyRewind
	var h := ReplayHistory.from_settings(t.settings)
	e.history = h
	var big := PackedByteArray()
	big.resize(ReplayHistory.MAX_PAYLOAD_BYTES)
	expect(not h.push({"blob": big}) and h.snapshot_count == 0 and h.rejected_count == 1, "Over-cap snapshot is rejected, never stored")
	h.seed_checkpoint({"room": "start"})
	e.capture_present = func() -> Dictionary: return {"now": true}
	t.apply_hit(500.0)
	expect(e.active and e.choice_count == 2, "Empty buffer after rejection still offers NOW + checkpoint")
	e.step_selection(1)
	expect(e.selected_index == 1 and near(e.choice_age(1), EmergencyRewind.CHECKPOINT_AGE), "A wheel notch reaches the checkpoint")
	var restored: Array[Dictionary] = []
	e.confirmed.connect(func(_a: float, s: Dictionary) -> void: restored.append(s))
	e.confirm()
	expect(restored.size() == 1 and restored[0] == {"room": "start"}, "Checkpoint fallback restores the room start")
	core.free()
