extends SceneTree
# Round O Wave A arena-level checks (jam-8): authored camera + explicit zoom, held
# slow_time through real input events, capability gates, emergency wheel stepping,
# intentional weapon-condition rollback, repeated recoveries, pause/focus/scene exit.
# Requires the Round O A public APIs from jam-7 (SceneManager.get_popup) and jam-3
# (WeaponRepair.show_message / has_active_session); run after integration.
# The arena is loaded at runtime and kept untyped: the main check script is compiled
# before autoloads exist, so it must not depend on arena.gd at parse time.

const ARENA_SCENE := "res://scenes/prototype/arena.tscn"
const EPS := 0.0001

var checks := 0
var failures: Array[String] = []
var gs: Node


func _initialize() -> void:
	call_deferred("run")


func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func near(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = Vector2(640, 400)
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func frames(count: int) -> void:
	for i in range(count):
		await physics_frame


func run() -> void:
	gs = root.get_node("GameState")
	var arena: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(arena)
	current_scene = arena
	await frames(3)
	var t: TimeController = arena.time_controller
	check_camera(arena)
	await check_held_slow(arena, t)
	await check_capabilities(arena, t)
	await check_emergency_flow(arena, t)
	await check_scene_exit(arena, t)
	print(JSON.stringify({"status": "passed" if failures.is_empty() else "failed", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func check_camera(arena: Node) -> void:
	var cam: Camera3D = arena.player.camera
	expect(cam.projection == Camera3D.PROJECTION_PERSPECTIVE and near(cam.fov, 52.0), "Arena keeps the authored camera projection/fov")
	expect(cam.position.is_equal_approx(Vector3(0, 20, 14)) and near(arena.zoom, 22.0), "Authored framing is zoom 22")
	cam.fov = 40.0 # an inspector edit must survive zoom changes
	arena._unhandled_input(_pressed_key(KEY_EQUAL))
	expect(near(arena.zoom, 20.0) and cam.position.is_equal_approx(Vector3(0, 20, 14) * (20.0 / 22.0)), "Plus zooms in by scaling the authored offset")
	expect(near(cam.fov, 40.0), "Zoom never overwrites the inspector fov")
	arena._unhandled_input(_pressed_key(KEY_MINUS))
	arena._unhandled_input(_pressed_key(KEY_MINUS))
	expect(near(arena.zoom, 24.0), "Minus zooms out")
	for i in range(10):
		arena._unhandled_input(_pressed_key(KEY_MINUS))
	expect(near(arena.zoom, 32.0), "Zoom is clamped")
	arena.reset_arena()
	expect(near(arena.zoom, 22.0) and cam.position.is_equal_approx(Vector3(0, 20, 14)), "Reset restores the authored framing")
	cam.fov = 52.0


func _pressed_key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func check_held_slow(arena: Node, t: TimeController) -> void:
	key(KEY_SPACE, true)
	await frames(1)
	expect(t.slow_active and near(t.world_scale, 0.18), "Physical Space slows on the next physics tick")
	key(KEY_SPACE, false)
	await frames(1)
	expect(not t.slow_active and near(t.world_scale, 1.0), "Release stops slow on the next tick")
	t.try_spend(t.meter - 5.0)
	key(KEY_SPACE, true)
	await frames(1)
	expect(t.slow_active, "A fresh press with only 5 units still acts immediately")
	key(KEY_SPACE, false)
	await frames(1)
	t.begin_attempt()
	key(KEY_SPACE, true)
	await frames(1)
	key(KEY_2, true)
	key(KEY_2, false)
	await frames(1)
	expect(arena.weapons.selected_tool == 2 and t.slow_active, "Slow survives a tool switch while held")
	arena.equipment.spend(&"beam", 10.0)
	key(KEY_E, true)
	key(KEY_E, false)
	await frames(1)
	expect(popup_open(&"Repair") and t.slow_active, "Opening repair keeps the held slow (repair never forces slow on/off)")
	key(KEY_E, true)
	key(KEY_E, false)
	await frames(1)
	expect(not popup_open(&"Repair"), "E toggles repair closed")
	gs.pause()
	key(KEY_SPACE, false) # released while the tree is paused
	gs.resume()
	await frames(1)
	expect(not t.slow_active, "Release during pause is honoured after resume")
	key(KEY_SPACE, true)
	await frames(1)
	arena._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	expect(gs.is_paused() and not t.slow_requested, "Focus loss pauses and drops the held slow")
	gs.resume()
	await frames(1)
	expect(not t.slow_active and not Input.is_action_pressed(&"slow_time"), "No stuck slow after focus returns")


func popup_open(key_name: StringName) -> bool:
	return root.get_node("SceneManager").has_popup(key_name)


func check_capabilities(arena: Node, t: TimeController) -> void:
	t.set_capabilities(false, true)
	key(KEY_SPACE, true)
	await frames(2)
	expect(not t.slow_active and near(t.world_scale, 1.0), "Locked slow ignores the held key in the arena")
	key(KEY_SPACE, false)
	t.set_capabilities(true, false)
	var charges := t.charges_remaining
	arena.player.take_damage(10000.0)
	await frames(1)
	expect(t.exhausted and not arena.emergency_rewind.active and t.charges_remaining == charges, "Locked rewind: depletion is a retry, no hidden charge or recovery view")
	arena.reset_arena()
	expect(not t.exhausted and not t.rewind_unlocked and t.slow_unlocked, "Retry keeps capabilities (campaign owns unlocks)")
	t.set_capabilities(true, true)


func check_emergency_flow(arena: Node, t: TimeController) -> void:
	arena.reset_arena()
	await frames(45) # 1.5 world seconds of history
	var eq: WeaponEquipment = arena.equipment
	eq.spend(&"beam", eq.capacity(&"beam") * 0.6)
	await frames(30)
	var worn := eq.remaining(&"beam")
	var session := eq.begin_repair(&"beam")
	t.try_spend_repair_checkpoint()
	eq.complete_step(&"beam", session)
	eq.end_repair(session)
	var repaired := eq.remaining(&"beam")
	await frames(12)
	arena.player.take_damage(10000.0)
	await frames(1)
	expect(arena.emergency_rewind.active and t.charges_remaining == 2, "Depletion opens recovery with one charge spent")
	for i in range(3):
		mouse(MOUSE_BUTTON_WHEEL_DOWN, true)
	expect(arena.emergency_rewind.selected_index == 3, "Each wheel-down notch selects one older moment")
	mouse(MOUSE_BUTTON_WHEEL_UP, true)
	expect(arena.emergency_rewind.selected_index == 2, "Wheel up selects one newer moment")
	var guard := 0
	while arena.emergency_rewind.choice_age(arena.emergency_rewind.selected_index) < 0.8 and guard < 40:
		mouse(MOUSE_BUTTON_WHEEL_DOWN, true)
		guard += 1
	expect(arena.emergency_rewind.choice_age(arena.emergency_rewind.selected_index) < 1.3, "Chosen moment is between the wear and the repair")
	mouse(MOUSE_BUTTON_LEFT, true)
	mouse(MOUSE_BUTTON_LEFT, false)
	await frames(1)
	expect(not arena.emergency_rewind.active and t.meter >= 40.0 and t.meter < 41.0 and t.protected, "Click confirms; recovery floor and grace apply (%.2f)" % t.meter)
	expect(near(eq.remaining(&"beam"), worn) and repaired > worn, "Weapon condition rolls back to the chosen moment (decision: repairs/wear rewind)")
	expect(t.charges_remaining == 2, "Confirm never refunds the charge")
	await frames(60)
	arena.player.take_damage(10000.0)
	await frames(1)
	key(KEY_ENTER, true)
	key(KEY_ENTER, false)
	await frames(1)
	expect(t.meter >= 40.0 and t.meter < 41.0 and t.protected and t.charges_remaining == 1, "Second recovery: same floor and grace, one fewer charge (%.2f)" % t.meter)


func check_scene_exit(arena: Node, t: TimeController) -> void:
	await frames(60)
	arena.player.take_damage(10000.0)
	await frames(1)
	expect(gs.is_in_emergency(), "Third emergency is open before the scene exit")
	arena.queue_free()
	await frames(2)
	var fresh: Node = (load(ARENA_SCENE) as PackedScene).instantiate()
	root.add_child(fresh)
	current_scene = fresh
	await frames(2)
	expect(not gs.is_in_emergency() and gs.is_playing(), "A new arena after exiting mid-emergency starts clean")
	expect(fresh.time_controller.charges_remaining == 3 and not fresh.emergency_rewind.active, "New scene has a fresh attempt")
	fresh.queue_free()
	await frames(1)
