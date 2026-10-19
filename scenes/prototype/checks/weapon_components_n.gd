extends SceneTree
const Harness = preload("res://scenes/weapons/checks/harness.gd")
const Pattern = preload("res://scenes/prototype/pattern_enemy.gd")
const RingScene = preload("res://scenes/weapons/ring_cutter.tscn")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func mouse(down: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	return e
func values_only(v: Variant) -> bool:
	if v is Object or v is Callable or v is Signal: return false
	if v is Array:
		for item in v:
			if not values_only(item): return false
	if v is Dictionary:
		for key in v:
			if not values_only(key) or not values_only(v[key]): return false
	return true
func launch(w: WeaponController, player: Node3D) -> void:
	w.select_tool(1)
	w.handle_event(mouse(true), player, Vector3(-3, 0, -5))
	var move := InputEventMouseMotion.new()
	w.handle_event(move, player, Vector3(3, 0, -5))
	w.handle_event(mouse(false), player, Vector3(3, 0, -5))
func run() -> void:
	var harness := Harness.new()
	root.add_child(harness)
	if harness.weapons == null:
		expect(false, "Weapon scene failed to load")
		finish()
		return
	var w: WeaponController = harness.weapons
	expect(w.ring is RingCutter and w.flash is FocusedFlash and w.bellows is HeatBellows and w.equipment is WeaponEquipment, "Concrete named controller/equipment and three real child components")
	expect(w.get_child_count() == 4 and w.get_node("Presentation") is WeaponPresentation, "Scene provides stable editor-visible composition")
	expect(w.ring.settings is RingCutterSettings and w.flash.settings is FocusedFlashSettings and w.bellows.settings is HeatBellowsSettings, "Individual exported tuning Resources")
	expect(not "health" in harness.player and not "slow_charge" in harness.player, "Weapon lifecycle runs without player health/clock aliases")
	var second := Harness.new()
	root.add_child(second)
	launch(w, harness.player)
	expect(w.ring.flight_points.size() > 2 and second.weapons.ring.flight_points.is_empty() and second.equipment.is_full(&"ring"), "Mutable flight/condition state is instance local")
	expect(w.ring.stroke.mesh != second.weapons.ring.stroke.mesh and w.presentation.batch != second.weapons.presentation.batch, "Procedural mesh state is instance local")
	w.reset_state()
	w.set_loadout([2, 4, 2, 0, 3], 4)
	expect(w.available_tools == [2, 3] and w.selected_tool == 2, "Loadout retains owned three-tool order and rejects duplicates/clock")
	w.select_tool(4)
	expect(w.selected_tool == 2, "Invalid fourth slot cannot equip")
	w.restore_state({"selected_tool":1})
	expect(w.selected_tool == 2 and w.available_tools == [2, 3], "Replay cannot grant an unacquired weapon")
	w.set_loadout([1, 2, 3])
	launch(w, harness.player)
	w.step(.1, harness.player, Vector3(3, 0, -5), [], .1)
	w.select_tool(2)
	w.handle_event(mouse(true), harness.player, Vector3(0, 0, -15))
	w.step(1, harness.player, Vector3(0, 0, -15), [], 0)
	w.handle_event(mouse(false), harness.player, Vector3(0, 0, -15))
	var snapshot := w.capture_state()
	expect(values_only(snapshot) and not snapshot.has("available_tools") and not snapshot.has("equipment") and not snapshot.has("time"), "Weapon snapshots contain only transient world values")
	var held := w.capture_state()
	held.ring.points.clear()
	held.flash.pulses[0].pos = Vector3(100, 0, 100)
	expect(w.ring.flight_points.size() > 0 and w.flash.pulses[0].pos != Vector3(100, 0, 100), "Captured arrays/dictionaries do not alias live state")
	w.restore_state(snapshot)
	expect(w.capture_state().ring == snapshot.ring and w.capture_state().flash == snapshot.flash, "Transient flight/pulse state round-trips exactly")
	expect(not w.flash.charging and not w.ring.drawing and not w.bellows.active and w.require_fresh_press, "Restore never resumes held gestures")
	var time: TimeController = TimeController.new()
	time.auto_advance = false
	root.add_child(time)
	time.begin_attempt()
	w.time_controller = time
	var meter := time.meter
	var charges := time.charges_remaining
	w.step(.05, harness.player, Vector3(0, 0, -15), [], .05)
	expect(time.meter == meter and time.charges_remaining == charges, "Weapon step never ticks or mirrors the time authority")
	time.slow_requested = true
	time.advance(.01)
	var phase_before := w.presentation.phase
	w.step(.1, harness.player, Vector3(0, 0, -15), [])
	expect(is_equal_approx(w.presentation.phase - phase_before, .1 * time.world_scale), "Default world delta also reads the bound authority, without a second slow model")
	time.slow_requested = false
	time.advance(.01)
	time.try_spend(time.meter)
	expect(not time.emergency_active, "Voluntary zero does not invent a weapon death path")
	w.flash.cooldown = 0
	w.handle_event(mouse(true), harness.player, Vector3(0, 0, -15))
	expect(w.flash.charging, "Voluntary zero still permits ordinary weapon input")
	time.apply_hit(1)
	expect(not w.flash.charging and not w.bellows.active and not w.ring.drawing, "Emergency signal cancels held actions even when arena never calls weapon step")
	var before := w.capture_state()
	w.handle_event(mouse(true), harness.player, Vector3(0, 0, -15))
	w.step(1, harness.player, Vector3(0, 0, -15), [], 1)
	expect(w.capture_state().ring == before.ring and w.capture_state().flash == before.flash, "Emergency freezes flight/cooldowns even if caller supplies positive deltas")
	expect(not w.flash.charging and not w.bellows.active and not w.ring.drawing, "Emergency ignores attack input")
	w.restore_state(snapshot)
	expect(time.charges_remaining == charges - 1 and time.meter == 0 and time.emergency_active, "World restore cannot refund a charge or meter")
	time.finish_emergency()
	w.reset_state()
	harness.equipment.reset_state()
	# A resource edit changes the actual selected behavior, not a mirrored tuning table.
	var slow: RingCutterSettings = w.ring.settings.duplicate()
	slow.stroke_speed = 19
	w.ring.settings = slow
	launch(w, harness.player)
	w.ring.flight_phase = "stroke"
	w.ring.head = w.ring.flight_points[0]
	w.ring.stroke_index = 0
	w.ring.step(.02, harness.player.position, [])
	expect(is_equal_approx(w.ring.head.x - w.ring.flight_points[0].x, .38), "Inspector ring stroke_speed changes real flight distance")
	expect(second.weapons.ring.settings.stroke_speed == 38 and w.flash.settings == second.weapons.flash.settings, "Editing one weapon Resource leaves other behaviors/settings intact")
	# A concrete component is independently usable; no controller dispatch required.
	var independent: RingCutter = RingScene.instantiate()
	root.add_child(independent)
	independent.bind(WeaponEquipment.new(), harness.cover)
	independent.press(Vector3.ZERO, Vector3(-2, 0, -4))
	independent.sample(Vector3(2, 0, -4), Vector3.ZERO)
	independent.release(Vector3.ZERO, Vector3(2, 0, -4), Vector3(0, 1.5, -.5))
	independent.step(.1, Vector3.ZERO, [])
	expect(independent.flight_phase == "outbound" and independent.head.y > 0, "Standalone RingCutter scene owns a real launch and arc")
	independent.free()
	w.time_controller = null
	w.ring.settings = second.weapons.ring.settings
	# Preserve mechanism inspection after the body's one-hit-per-launch ledger fills.
	w.reset_state(); harness.equipment.reset_state()
	var pattern := Pattern.new()
	root.add_child(pattern)
	pattern.configure(&"loop", Vector3(0, 0, -5), 81)
	var circle: Array[Vector3] = []
	for i in range(33): circle.append(pattern.position + Vector3(cos(i * TAU / 32), 0, sin(i * TAU / 32)) * 1.9)
	w.select_tool(1)
	w.handle_event(mouse(true), harness.player, circle[0])
	for point in circle:
		var motion := InputEventMouseMotion.new()
		w.handle_event(motion, harness.player, point)
	w.handle_event(mouse(false), harness.player, circle[-1])
	for frame in range(120): w.step(1.0/60, harness.player, circle[-1], [pattern], 1.0/60)
	expect(pattern.pattern_open and pattern.health > 0, "Raw cutter segments continue completing all pattern links after first body contact")
	w.select_tool(2)
	var core: Vector3 = pattern.core_world_position()
	w.handle_event(mouse(true), harness.player, core)
	w.step(1, harness.player, core, [pattern], 0)
	w.handle_event(mouse(false), harness.player, core)
	w.step(.4, harness.player, core, [pattern], .4)
	expect(pattern.health == 0, "Real charged component pulse finishes the actually opened loop core")
	pattern.configure(&"pair", Vector3(0, 0, -5), 82)
	w.reset_state()
	w.select_tool(2)
	for i in range(2):
		var valve: Vector3 = pattern.valve_world_position(i)
		w.handle_event(mouse(true), harness.player, valve)
		w.handle_event(mouse(false), harness.player, valve)
		w.step(.35, harness.player, valve, [pattern], .35)
		pattern.step_enemy(.35, null)
	expect(pattern.health == 0 and pattern.pair_progress == 2, "Actual quick A/B shots retain pattern contact behavior after extraction")
	# Malformed snapshots still respect history ledger and projectile bounds.
	var oversized: Array[Dictionary] = []
	for i in range(20): oversized.append({"pos":Vector3.ZERO, "hit_ids":range(1, 90)})
	w.flash.restore_state({"pulses":oversized})
	expect(w.flash.pulses.size() == 8 and w.flash.pulses[0].hit_ids.size() == 32, "Pulse/ledger restore bounds retained")
	w.ring.flight_points.clear()
	for i in range(w.ring.settings.max_samples): w.ring.flight_points.append(Vector3(i * .01, 0, -5))
	for i in range(1, 33): w.ring.hit_ids[i] = true
	var bounded := w.capture_state()
	expect(values_only(bounded) and var_to_bytes(bounded).size() < 16384, "Worst bounded weapon state leaves most of the 64KiB history budget for actors")
	pattern.free(); time.free(); second.free(); harness.free()
	finish()
func finish() -> void:
	print(JSON.stringify({"status":"passed" if failures.is_empty() else "failed","checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
